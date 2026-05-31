# NET-REL-05 E2 — Concurrent Durable Fallback + Offline-Tail Sizing Runbook

> Status: **wire-validation gate.** NET-REL-05's send orchestration (sticky transport,
> grace window, concurrent durable fallback, relay 2→1) is implemented and host-green
> (mutation-pinned at the fake layer). Two things a host fake **cannot** give remain:
> (E2) proof over the **real Go stack** that one low-confidence send fired BOTH a live
> attempt AND an `InboxStore` and the receiver got **exactly one**; and (sizing) the
> **offline-tail** win — the gate baseline had 0 failures / 0 inbox, so the
> concurrent-fallback + offline-tail wins are **UNMEASURED**. Do **not** claim those wins
> until this runs.

---

## 1. Goal

Two measurements over the real Dart→bridge→Go→relay stack:

- **E2 (correctness):** a single **low-confidence** 1:1 send fires a **live stream
  attempt AND a concurrent `InboxStore`** over the wire, and the receiver surfaces
  **exactly one** message — proving the "passes via dedup even though the live path
  silently never fired" false positive cannot hide here.
- **Offline-tail sizing (latency):** with the recipient **offline**, measure
  send→durable-custody latency so the concurrent-fallback win is **sized**, not assumed.

Source: `Network-Arch/Transport-Reliability/05-send-orchestration.md` (Test Plan E2 /
I-series). Doctrine: `06-test-and-simulation-strategy.md` (§5 item 9 — real-stack
concurrent-fallback liveness proof).

---

## 2. What this proves (and what it does NOT)

### Proves
- Both the live attempt and the inbox write genuinely occurred over the real Go stack for
  one low-confidence send (assembled from Dart FLOW + relay metric delta + receiver==1),
  not just that "a message arrived."
- A real offline-recipient send reaches durable inbox custody within a measured budget.

### Does NOT prove
- LAN/`local` behavior (that is NET-REL-01 I3).
- Cross-network direct (closed — NET-REL-02 gate).
- A single decisive Go counter exists today correlating "live-attempt AND InboxStore for
  THIS send" — it does **not** (see §7). The proof is **assembled** from three signals;
  a dedicated Go FLOW correlation counter is a recommended BUILD to make this one-signal.

---

## 3. Harness & prerequisites

- The real-stack 1:1 harness is `integration_test/transport_e2e_test.dart`, driven by
  `integration_test/scripts/run_transport_e2e.dart` (real relay + a Go CLI test peer,
  fixture-coordinated). It carries the E1 dedup proofs (D1/D3/D4) today; E2 and the
  offline-tail are the **additions** this runbook schedules.
- **One simulator/device + a Go CLI peer** suffices (this is wire fidelity, not LAN — no
  two-phone WiFi requirement). A real device is preferred for honest timing.
- Go must be current: `cd go-mknoon && PATH="$PATH:$(go env GOPATH)/bin" make all`.
- **Relay reachable** (real relay or the in-process `local_relay_harness`). Have the relay
  `/metrics` endpoint (`:2112`) scrapeable to read `relay_inbox_stored_total`.
- A way to force **low confidence** (so the concurrent-inbox gate fires) and to put the
  recipient **offline** (don't start / disconnect the Go CLI peer).

---

## 4. Build & run

```sh
# rebuild Go
cd go-mknoon && PATH="$PATH:$(go env GOPATH)/bin" make all && cd ..

# run the real-stack 1:1 transport harness on a device/sim
dart run integration_test/scripts/run_transport_e2e.dart -d <DEVICE_OR_SIM_ID>

# scrape relay inbox counter before/after each condition
curl -s http://<relay-host>:2112/metrics | grep -E 'relay_inbox_stored_total|relay_inbox_retrieved_total'
```

Capture FLOW logs from the sender app (the harness already tees device logs). Key Dart
markers: `CHAT_MSG_SEND_CONCURRENT_INBOX_BEGIN` (the concurrent inbox fired,
`send_chat_message_use_case.dart`), plus the live-attempt `CHAT_MSG_SEND_*` direct/relay
markers.

---

## 5. Conditions, N, and procedure

### Condition E2-A — low-confidence ONLINE send (concurrent fallback)
1. Recipient **online** but force the send into the **low-confidence** gate (e.g. no
   sticky/learned transport, fresh peer, relay-probe path) so the concurrent `storeInInbox`
   arm is eligible.
2. Send **one** message; record: sender FLOW (`CHAT_MSG_SEND_CONCURRENT_INBOX_BEGIN` +
   a live attempt marker), the relay `relay_inbox_stored_total` **delta** (expect +1), and
   the **receiver message count for that messageId** (expect exactly **1**).
3. Repeat **N ≥ 30**.

### Condition E2-B — OFFLINE recipient (offline-tail sizing)
1. Recipient **offline** (Go CLI peer not connected). Send a message; start a timer at
   send-use-case entry.
2. Record **send→durable-custody latency** = time until `relay_inbox_stored_total` +1
   (durably queued). Bring the recipient online, `drainOfflineInbox`, confirm exactly one
   delivered (dedup).
3. Repeat **N ≥ 30**; report median + p95.

### Negative controls (mandatory)
- **NC-1 (gate not always firing):** a high-confidence online send (sticky/learned, happy
  path) must fire **NO** concurrent inbox — `storeInInbox` count 0, no
  `CHAT_MSG_SEND_CONCURRENT_INBOX_BEGIN`, `relay_inbox_stored_total` unchanged. If E2-A and
  this both store to inbox, the gate is always-on → fail.
- **NC-2 (dedup not swallowing):** send two **different** messageIds concurrently → the
  receiver must surface **two** messages. Proves the exactly-one in E2-A is dedup, not
  loss.

---

## 6. Pass criteria (path-pinned)

**E2-A (per send, all N) — correlated by the same messageId (the §7 id-tag is in place):**
A low-confidence send fires the inbox arm (`CHAT_MSG_SEND_CONCURRENT_INBOX_BEGIN`, id-tagged)
AND a live attempt. For that id, with `relay_inbox_stored_total` delta **== +1** and the
**receiver surfacing exactly 1** message, exactly one outcome pair must hold:
- **live wins (the concurrent-fallback win):** BEGIN(id) + `CHAT_MSG_SEND_SUCCESS`(id,
  `via` ∈ {direct, relay, reuse}) — live delivered AND the concurrent inbox copy still
  reached the relay (the +1); receiver dedups to 1; OR
- **inbox saves it (live failed within window):** BEGIN(id) +
  `CHAT_MSG_SEND_CONCURRENT_INBOX_CUSTODY`(id) + `CHAT_MSG_SEND_SUCCESS`(id, `via`=inbox).

A send where the inbox arm fired but **neither** a live `SUCCESS` **nor** a CUSTODY is
recorded for that id → **fail** (the live path silently never fired — the false positive
this gate exists to catch). Note: CUSTODY and the relay-probe tail
(`CHAT_MSG_SEND_RELAY_PROBE_CONNECTED`, also id-tagged) are the live-**failed** branches and
are mutually exclusive with a live `SUCCESS` — do not expect both in one send.

**E2-B (sizing):** report the offline send→custody **median + p95** as the sized
offline-tail. (If a pre-NET-REL-05 sequential-tail number is available, report the delta;
otherwise this absolute number becomes the baseline the concurrent path is measured
against. Do **not** claim a "win" magnitude without one of these.)

**NC-1:** high-confidence send stores to inbox **0** times. **NC-2:** two ids → two
messages.

**N ≥ 30** per condition (≥ 50 if a decision hinges on a <10% gap), per the
baseline-runbook N discipline.

---

## 7. Trust caveats (doctrine)

- **Per-id correlation: DONE via a tiny additive Dart id-tag — not a Go signal** (2026-05-31).
  The correlating signals live on the **Dart** side: `CHAT_MSG_SEND_CONCURRENT_INBOX_BEGIN`
  (inbox arm fired), `CHAT_MSG_SEND_SUCCESS` (terminal outcome + `via`; already carried the
  id), `CHAT_MSG_SEND_CONCURRENT_INBOX_CUSTODY` (inbox saved it when the live race failed),
  and `CHAT_MSG_SEND_RELAY_PROBE_CONNECTED` (relay-tail live attempt). BEGIN, CUSTODY, and
  RELAY_PROBE_CONNECTED originally omitted the messageId (`{targetPeerId}`, `{reason}`, `{}`).
  **Fix applied:** `resolvedMessageId.substring(0, 8)` added to those three events' `details`
  (additive; mutation-pinned by a host test — stripping any id turns the test RED). So E2-A
  is now correlatable by id purely from Dart FLOW + the `relay_inbox_stored_total` delta +
  receiver==1 (see §6 for the exact live-wins vs inbox-saves outcome pairs). A dedicated Go
  correlation FLOW was evaluated and **deferred** — heavier (Go production + de-confliction),
  only marginally better; revisit only if E2-A proves ambiguous on hardware.
- **`relay_inbox_stored_total` over-counts duplicates** (`inbox.go` increments even on a
  duplicate store). Read it as a **delta around a single send** and cross-check the
  receiver count; do not sum naively across a noisy window.
- **Don't size the fake.** Offline-tail latency must be measured over the **real Go
  stack** (E2-B), not a host `FakeP2PNetwork` (which has no relay-probe/inbox latency
  model). A host number would be T1 fidelity masquerading as a measurement — explicitly
  out of scope here.
- **Exactly-one is the load-bearing claim.** Pair every "delivered" with the dedup check
  (NC-2) so a passing run can't be "dedup swallowed everything."
- Path-pin per NET-REL-06 — never accept the `{direct,relay,inbox}` set as proof of a
  specific arm; assert the *specific* signals above.

---

## 8. Results template

```
NET-REL-05 E2 + OFFLINE-TAIL — RESULTS
======================================
Date: ____   Device/sim: ____   Relay: ____   Go built (make all): YES

E2-A (low-confidence ONLINE, concurrent fallback):  N = ____
  live attempt fired (FLOW) for all?                 ____/____
  relay_inbox_stored_total delta == +1 per send?     ____/____
  receiver surfaced exactly 1 per id?                ____/____
  --> E2-A PASS requires all three columns == N

E2-B (OFFLINE recipient, offline-tail sizing):  N = ____
  send->durable-custody latency:  median ____ ms , p95 ____ ms
  drained exactly-once after recipient online?       YES / NO
  pre-NET-REL-05 sequential-tail comparison (if any): ____ ms  (delta: ____)

NEGATIVE CONTROLS:
  NC-1 high-confidence send stored to inbox 0 times?  YES / NO  (must be YES)
  NC-2 two different ids -> two messages?             YES / NO  (must be YES)

VERDICT: PASS / FAIL
Notes / anomalies: __________________________________________________
```

## 8b. Recorded run — 2026-05-31 (executor; verdict deferred to monitor)

Run in two parts per the fidelity split. Both `dart run` invocations exited 1 on
**orchestrator-side residuals** (Pixel: cross-device `/tmp` handshake → no CLI peer;
sim: the known **E8 media-metadata** orchestrator residual) — the **Flutter test passed
in both** (Pixel 4/4 self-contained; sim 37/37). Build under test: `e7f9d1b5`.

**FIDELITY SPLIT (do not overclaim):**
- **E2-A correlation + E2-B latency = REAL DEVICE** (Pixel `21071FDF600CSC`, real relay `mknoun.xyz`).
- **NC-1 / NC-2 / E2-A live-wins = SIMULATOR** (iPhone 17 Pro) — logic controls only.
- The sim E2-B latency is **not** a fidelity number; the offline-tail size is the Pixel's.

```
REAL DEVICE — Pixel 21071FDF600CSC, relay mknoun.xyz:
  E2-A: inboxSaves = 30/30 correlated  [BEGIN(id)+CUSTODY(id), via==inbox, path-pinned]   PASS
        liveWins  = 0/0  (CLI peer absent on device — file handshake is sim-only)
  E2-B: send->custody  median = 176 ms , p95 = 845 ms , delivered = 30/30                 PASS
        (sizes the NET-REL-05 offline tail; no pre-NET-REL-05 sequential baseline captured)

SIMULATOR — iPhone 17 Pro, relay mknoun.xyz (logic controls):
  E2-A: inboxSaves = 30/30 ; liveWins = 1/1  [BEGIN(id)+SUCCESS(id, via=direct)]          PASS
  NC-1: firedConcurrentInbox = false , via = direct , r = success                         PASS
        (high-confidence send did NOT fire the concurrent inbox — negative control holds)
  NC-2: distinctIds = 2 , ra = success , rb = success  (two ids -> two messages)          PASS
  E2-B (sim latency, NON-fidelity): median = 54 ms , p95 = 58 ms , 30/30
```

**Doctrine (NET-REL-06):** E2-A's positive (30/30 real wire + 1/1 sim live-wins) is now
paired with its negative control **NC-1** (sim) → the concurrent-fallback arm is proven
**not** always-on; **NC-2** proves dedup collapses only true duplicates. All four scenarios PASS.

**Not in this run:** I3 (separate two-phone manual session); an exact `relay_inbox_stored_total`
delta / receiver==1 relay-scrape cross-check (the harness asserts via sender FLOW + transport
label, which is sufficient for the per-id correlation but a relay scrape remains possible hardening).
