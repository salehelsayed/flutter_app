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

**E2-A (per send, all N) — correlated by the same messageId (requires the id-tag in §7):**
- Live attempt fired (`CHAT_MSG_SEND_RELAY_PROBE_CONNECTED`, id-tagged) **AND** inbox store
  wire-acked (`CHAT_MSG_SEND_CONCURRENT_INBOX_CUSTODY`, id-tagged) **AND** receiver surfaced
  **exactly 1** message for that id; with `relay_inbox_stored_total` delta **== +1** as
  corroboration. All required — any missing → fail (that is the false-positive this gate
  exists to catch). *Until the id-tag lands,* fall back to per-launch ordering at low N and
  flag the run as **id-unverified**.

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

- **Per-id correlation needs a tiny Dart id-tag — NOT a Go signal** (revised 2026-05-31
  after reading the send path). The live-attempt and inbox signals already exist on the
  **Dart** side — `CHAT_MSG_SEND_CONCURRENT_INBOX_BEGIN` (inbox arm fired),
  `CHAT_MSG_SEND_CONCURRENT_INBOX_CUSTODY` (inbox store wire-acked = relay accepted it),
  and `CHAT_MSG_SEND_RELAY_PROBE_CONNECTED` (live relay circuit connected) — but **none of
  the three carries the messageId** in its payload (`send_chat_message_use_case.dart:557,
  :875, :1391` carry `{targetPeerId}`, `{reason}`, `{}` respectively), so they cannot be
  cleanly correlated by id from logs under concurrency at N≥30. **Cheapest fix (recommended
  over a Go signal):** add `'id': resolvedMessageId.substring(0, 8)` to those three events'
  `details` — a ~3-line **additive Dart** change, no Go production change, mutation-testable.
  Then E2-A asserts, for the **same** id: CONCURRENT_INBOX_CUSTODY (store wire-acked) AND
  RELAY_PROBE_CONNECTED (live attempt) AND receiver==1, with `relay_inbox_stored_total`
  delta as corroboration. A dedicated Go correlation FLOW is heavier (Go production +
  de-confliction) and only marginally better — **defer** it unless E2-A proves ambiguous on
  hardware. **NOTE:** `send_chat_message_use_case.dart` is the cross-session de-confliction
  hotspot (NET-REL-01 P1 + NET-REL-05 both edit it) — the id-tag must be made by, or
  sequenced with, its owner.
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
