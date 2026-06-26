# FDC-03 — Generalize the concurrent durable inbox safety net  (Modification)

Status: awaiting-review
Spec: Network-Arch/Fast-Direct-Connection-Architecture-Proposal.md (§6.2(b) "Durable inbox — always, in parallel, a *separate tier*"; recommendation **P0-2** §8; pseudocode §7 "UNKNOWN: full race + concurrent inbox"; honesty note §6.2 "recipient cost rises"; durability-ordering hazard §9.3 / FDC-00)

---

## Source Of Truth

- **Proposal** §6.2(b), §7 send pseudocode, recommendation P0-2 (§8 table), §6.3 presence states, §9.3 durability-ordering hazard.
- **Roadmap** `FDC-00-roadmap.md` — FDC-03 row, the **COLLISION MAP** (same file as FDC-01/02/04, run **sequentially**, FDC-03 lands **third** after FDC-01→FDC-02), and the **DURABILITY-ORDERING hazard** (FDC-03 raises inbox volume → pull FDC-10 Redis earlier).
- **`scripts/run_test_gates.sh` wins over prose.** Home gate = `1to1`; floor = `baseline`. The two test files this plan edits are **already registered** in the `1to1` array (`send_chat_message_use_case_test.dart` line 36; `offline_inbox_roundtrip_test.dart` lines 11/19).
- Where this plan and the proposal disagree on a number, the proposal's verified file:line anchors and the green gate win.
- **FDC-S5 true-parallel confirmed (gating spike).** This plan fires `storeInInbox` **concurrently** with the live race and depends on that concurrency being real over the single Go bridge — otherwise the durable copy would land *after* the race (a serial ladder) instead of alongside it, defeating "always, in parallel, a separate tier" (§6.2b). [FDC-S5](FDC-S5-go-bridge-concurrency-design-note.md) confirms it by source read (Go `nodeMu` pointer-read-only `bridge.go:1027-1029`; node `n.mu` RWMutex read-concurrent `node.go:1417-1419`) **and** by the host microbench `TestConcurrentSendDialNoSerialize` (`go-mknoon/node/benchmark_bridge_concurrency_test.go`, `-race`): a real send completes in <1 ms while 8 concurrent dials each block ~0.6 s. So `Future.wait([race, storeInInbox])` is genuine concurrency and the durability tier truly runs in parallel.

---

## Session Classification

**implementation-ready** — pure-Dart edit of one use-case file; every behavior change is host-observable through the existing `FakeP2PService` / `FakeMessageRepository` / `captureFlowEvents` harness already in `send_chat_message_use_case_test.dart`. No relay/Go deploy, no migration, no device dependency for *closure of the host contract*. (Device/sim proof is still required for the live-wins claim — see Device/Relay Proof Profile — but the FDC-03 *change itself* is fully host-testable.)

---

## Exact Problem Statement

**What's broken / missing.** The durable inbox deposit — the proposal's *delivery guarantee tier* (§6.2b, "the part the transport systems don't give you") — is fired **concurrently** with the live race **only for "low confidence" sends**: peers where the *most recent prior outgoing message* terminally failed or was inbox-delivered within the last 30 s (`send_chat_message_use_case.dart:597-660`, gated by `kLowConfidenceWindow = 30s` at `:67`). For the **common cold / unknown-presence send** — a first-ever message, or any send whose prior attempt succeeded live — the inbox copy is **not** fired in parallel. Instead, on a race failure the code pays a **serial** relay-probe→inbox tail (`:1021-1062` probe, then `:1064-1099` store), so durable custody lands *seconds* after the race budget is spent rather than concurrently. This is proposal root cause **R6** (§4: "the durable inbox safety net is gated behind 'low confidence' only … 'will deliver' custody is several seconds late on the open-send-close path; the user watches a long 'sending…'").

**Who feels it.** The reported "open app → send one message → close" user on a cold notif-tap / fresh-conversation send: their first message to a peer is *never* low-confidence (no prior failed attempt exists), so it gets the slow serial tail, not concurrent custody.

**What must improve.** For **all unknown-presence sends** (not already connected, not LAN-local, no live peer connection), fire `storeInInbox` **concurrently** with the live race as a strictly separate durability tier — independent of any prior-attempt recency. Commit on the first live ack; if all live legs fail, the concurrent inbox copy already holds custody → `delivered(inbox)` + push-to-wake (server-side on store). Drop the **serial relay-probe→inbox tail** as the carrier of last resort.

**What must stay unchanged → preserved sentinels.**
- **Not a blanket dual-write of EVERY send.** A live-connected (`reuse`) send and a LAN-local (`isLocalPeer`) send must **still** be single-path — they have their own delivery confirmation (the wire ack / the LAN nonce ack), so they must **not** fire the concurrent inbox. (Preserves the §6.2 honesty note "recipient cost rises" by not paying it where a confirmed path exists.)
- **Exactly one relay write per message.** A send must never produce **two** `storeInInbox` calls (concurrent + serial). The existing R1 guard (`:1006-1019`, `:1819-1837`) must be preserved and generalized.
- **`messageId` dedup is the correctness backstop** (receiver-side, already enforced server-side — proposal Appendix `inbox_store.go:7,14`). The parallel copy is harmless because the receiver dedups; this plan does **not** add or change dedup.
- **Inbox acceptance is CUSTODY, not delivery** (doc 115): the row persists non-terminal `'inboxed'` with the wire envelope **retained** so the custody sweep / delivery-receipt flip still work (`persistInboxAccepted` `:907-956`).

---

## Root Cause (verify→refute confirmed)

**Mechanism (verified by Read, branch `new-orbit`):**

1. **The gate** — `:597-629`. `lowConfidence` is set true **only** when `!isAlreadyConnected && !isLocalPeer && !isConnectedToPeer` **AND** `messageRepo.getLatestMessageForContact(targetPeerId)` returns a prior **outgoing** row that is `status=='failed' || transport=='inbox'` **AND** whose `createdAt` age `< kLowConfidenceWindow (30s)` (`:608-628`).
2. **The concurrent arm fires only under that gate** — `:639-660`. `concurrentInbox` stays **null** for a high-confidence send, so `storeInInbox` is never started in parallel.
3. **The serial tail** — on race failure, `:1006-1019` short-circuits to custody *only if* `concurrentInbox != null` and it succeeded; otherwise `:1021-1062` runs a **serial** `_tryRelayProbeSend` (relay probe → dial → one post-probe send), and `:1064-1099` runs a final **serial** `storeInInbox`. For a high-confidence offline peer this is the *only* path to custody, and it is sequential after the full race budget.
4. **The unacked branch** — `_persistOutgoingSendResult:1812-1837` likewise only skips the serial handoff when `concurrentInbox != null`; a high-confidence unacked live write pays the serial `:1844-1865` store.

**Confirmed, not refuted:** the gate's three structural guards (`!isAlreadyConnected`, `!isLocalPeer`, `!isConnectedToPeer`) are correct and must be **kept** — they exclude the cases that already have a confirmed path. The *only* over-restriction is the **`getLatestMessageForContact` recency/terminal requirement** (`:613-628`), which makes the concurrent deposit conditional on a *prior failure*. That requirement is what FDC-03 removes.

**Do-NOT-re-introduce (refuted as the fix):**
- Do **not** keep the 30 s recency lookup as the gate — it is exactly the over-restriction (R6). After FDC-03 the `getLatestMessageForContact` read is removed from the gate (one fewer DB await on the hot path); `kLowConfidenceWindow` becomes dead **in the send path**. ⚠️ **Correction (review):** the constant is **not** referenced only by this gate — `test/core/services/p2p_service_fault_injection_test.dart:603` also consumes it (`.subtract(kLowConfidenceWindow + …)` to backdate a prior delivery out of the window). Removing the constant therefore breaks that file's compile, and that file is **not** one of the two test files this plan originally named (see *Files To Inspect Next* / *Existing Tests* / *Step 5b* / *Scope Guard*).
- Do **not** fire the concurrent inbox for `reuse`/`isLocalPeer` sends (blanket dual-write — violates the §6.2 cost honesty note and breaks the preserved single-path sentinels).
- Do **not** rely on cancelling the live legs (proposal §6.2: "Cancel the losing legs is mostly aspirational" — Dart Futures aren't cancellable, `message:send` is one-shot). Correctness leans on **receiver `messageId` dedup**, present.

---

## Real Scope

**In scope (FDC-03):**
- Generalize the gate at `:597-660`: fire the concurrent `storeInInbox` for **all unknown-presence sends** (`!isAlreadyConnected && !isLocalPeer && !isConnectedToPeer`), dropping the `getLatestMessageForContact` recency/terminal requirement. Rename the renamed concept from `lowConfidence` → `unknownPresence` (or `concurrentInboxEligible`).
- Drop the **serial relay-probe→inbox tail** as carrier: remove the `if (raceResult.relayProbeEligible) { _tryRelayProbeSend … }` block (`:1021-1062`). Keep a **single** sequential `storeInInbox` fallback (`:1064-1099`) reachable **only** when `concurrentInbox` was null (the connected/local edge that fell through) **or** the concurrent copy returned false — preserving the "exactly one relay write" invariant via the existing `:1006-1019` skip.
- Generalize the unacked-branch concurrent-custody skip (`:1819-1837`) so it applies to all unknown-presence sends, not only low-confidence ones.

**Out of scope → owning FDC-xx:**
- **Presence-based emphasis** (reachable→lazy inbox / unreachable→inbox-first; §6.3) → **FDC-08** (gated by FDC-S3). Until then **everything non-connected/non-local is treated as UNKNOWN → concurrent inbox**, per §7 pseudocode. This is the deliberate FDC-03 simplification.
- **The ranked race body + per-leg budgets** (§6.2a) → **FDC-02** (lands *before* FDC-03; relay becomes an in-race leg, which is *why* the serial probe tail is safe to drop here).
- **`direct_timeout`→probe-eligibility correctness** (§4.1) → **FDC-01** (lands first; its `relayProbeEligible` change is rendered vestigial by FDC-03 dropping the probe consumer — see Dependency Impact).
- **Durable Redis backend + relay pool** (the inbox-volume durability half of the §9.3 hazard) → **FDC-10** (pull earlier; FDC-03 raises inbox volume).
- **`warmPeer`, lifecycle, cold-start** → FDC-04/05/06/07.

---

## Files To Inspect Next

**Production (entry / use-case):**
- `lib/features/conversation/application/send_chat_message_use_case.dart` — **the only edited file.** Specifically: constants `kLowConfidenceWindow :67`, `interactiveInboxBudget :27`; the gate `:597-660`; the race-fail tail `:1006-1099`; `persistInboxAccepted :907-956`, `persistInboxRejectedFull :958-996`; `_tryRelayProbeSend :1534`; `_completeSuccessfulSend :1700-1729`; `_persistOutgoingSendResult :1790-1837`.
- `lib/core/services/p2p_service.dart` — `storeInInbox`, `isConnectedToPeer`, `isLocalPeer`, `lastKnownGoodTransport` contracts (dependency-only; **not edited**).

**Models / repos (dependency-only, not edited):**
- `lib/features/conversation/domain/repositories/message_repository.dart` — `getLatestMessageForContact` (the read FDC-03 removes from the gate), `saveMessage`, `updateWireEnvelope`.
- `lib/core/services/inbox_store_outcome.dart` — `InboxStoreOutcome` / `InboxStoreStatus.rejectedFull` (the retained single serial fallback still surfaces INBOX_FULL).

**Direct tests:**
- `test/features/conversation/application/send_chat_message_use_case_test.dart` — fakes at `:34-440`, `captureFlowEvents :547`, the existing U3/U-N3/U4 concurrent-inbox block `:3246-3470`, the E2 correlation block `:3292-3385`, the **Phase-3 relay-probe block `:2030-2212`** (whose probe-tail behavior this plan removes), and the preserved-single-path tests at `:2883-2906` and `:3699-3715`.

**Integration tests:**
- `test/features/conversation/integration/offline_inbox_roundtrip_test.dart` — shared `FakeP2PNetwork`/`TestUser` harness (`:1-50`), offline→inbox→resume-drain roundtrip.
- `test/features/conversation/integration/concurrent_durable_fallback_roundtrip_test.dart` — the integration suite **named for this feature** (real `FakeP2PNetwork` + `storeInInboxCallCount`). **⚠️ review finding: not in the plan's original scope, but its negative controls invert** — see the *Affected existing tests* callout below.

**⚠️ Affected existing tests beyond the original two-file scope (review finding — the plan originally claimed only `send_chat_message_use_case_test.dart` + `offline_inbox_roundtrip_test.dart` are touched, but the `core-host-all` / `feature-host-all` acceptance gates run these too):**
- `test/core/services/p2p_service_fault_injection_test.dart` (**`core-host-all` gate**) — (a) **uses `kLowConfidenceWindow`** at `:603` → constant removal breaks compile; (b) 3 tests assert `probeRelayCallCount == 1` (`:564`, `:638`, `:679`) → the dropped serial probe tail makes them `0`; (c) the Phase-4 recovery test (`:578`) backdates a prior delivery out of the 30 s window to force a high-confidence single-path and asserts `storeInInboxCallCount == 0` (`:640`) → FDC-03 makes that send fire the concurrent inbox (`1`). **Must be migrated** (compile + behavior).
- `test/features/conversation/integration/concurrent_durable_fallback_roundtrip_test.dart` (**`feature-host-all` gate**) — `N-online` (`:122`) asserts `storeInInboxCallCount == 0` for a high-confidence **online** send ("P4 is low-confidence-only") → **inverts to `1`** (direct analog of the named `slow relay` / `live acked` 0→1 migrations, but in an unnamed file); `I1` (`:60`) "first high-confidence send stored once via the sequential tail" now stores via the concurrent path (audit its event/path assertions); `N-no-double-write` (`:148`) is robust (`lessThanOrEqualTo(2)`) → stays green.
- `test/features/conversation/application/retry_failed_messages_use_case_test.dart` / `retry_unacked_messages_use_case_test.dart` (**`feature-host-all` / `1to1`**) — reference the concurrent-fallback row shape but exercise the **retrier's row-filter** (seed rows, assert the retrier does/does not re-send); their `storeInInboxCallCount == 0` cases are "no send happened," robust to the gate change. **Audit to confirm, likely no edit.**
- `test/performance/benchmark_routing_paths_test.dart` — references `relayProbeEligible` / the probe path; **excluded from the host gates** (`test/performance/**` is not in `host-all`), so not gate-blocking, but audit for staleness once the probe tail is gone.

**Dependency-only context:**
- `go-relay-server/inbox_store.go:7,14`, `backend_memory.go:121-142`, `backend_redis.go:272-295` — store-side `messageId` dedup (already correct; **do not touch**, FDC-10 owns durability).

---

## Existing Tests Covering This Area

All in `send_chat_message_use_case_test.dart` unless noted; the file is registered in the **`1to1`** gate array (line 36) and auto-globs into `feature-host-all`.

| Test (file::name) | Exists? | Gate array | FDC-03 disposition |
|---|---|---|---|
| `::U3 concurrent: low-confidence send fires inbox AND live in parallel` (`:3251`) | exists | 1to1 | **Stays green** — low-confidence is a *subset* of unknown-presence; still fires. |
| `::U-N3 concurrent neg: high-confidence send does NOT fire inbox` (`:3391`) | exists | 1to1 | **MUST CHANGE (inverted)** — a high-confidence unknown-presence send now **DOES** fire the concurrent inbox. Rewritten as FDC-03-01. |
| `::U-N3 concurrent neg: stale prior failure stays high-confidence` (`:3416`) | exists | 1to1 | **MUST CHANGE (inverted)** — staleness no longer matters; unknown-presence fires. Folded into FDC-03-01 / removed (recency gate deleted). |
| `::E2 BEGIN + CUSTODY carry the id` (`:3319`) | exists | 1to1 | **Stays green** — uses a low-confidence prior; BEGIN/CUSTODY still fire. |
| `::E2 RELAY_PROBE_CONNECTED carries the id` (`:3354`) | exists | 1to1 | **MUST CHANGE** — the relay-probe tail is removed; this `peer_not_found` send now takes concurrent-inbox custody, not a probe. Rewritten/retired (see Step 4). |
| Phase-3 relay-probe block `:2030-2212` (`discover miss then relay probe connected…`, `…noReservation falls to inbox`, `…probe error…`, `probe-connected lost ACK…`, `…attempts exactly once (P5)`) | exists | 1to1 | **MUST CHANGE** — these assert `probeRelayCallCount==1` / the serial probe→inbox tail. With the probe tail dropped, the live-recovery is FDC-02's in-race relay leg and custody is the concurrent inbox. Audited + rewritten in Step 4. |
| `::slow relay does not block P2P path` (`:2883`, asserts `storeInInboxCallCount,0` `:2904`) | exists | 1to1 | **MUST CHANGE** — default `FakeP2PService` is unknown-presence + live-success → now fires one concurrent inbox (count `1`). Timing assertion (`<3s`) preserved. |
| `::live acked send still persists delivered` (`:3699`, asserts `storeInInboxCallCount,0` `:3714`) | exists | 1to1 | **MUST CHANGE** — same: unknown-presence live-success now fires one concurrent inbox (count `1`); `status=='delivered'`, `transport=='direct'` preserved. |
| `::U-N3 high-confidence` reuse / `::existing connected peer is used…` (`:2239`+) and `isLocalPeer`/`U4 dedup local` (`:3452`) | exists | 1to1 | **Stays green** — reuse/local are excluded by the kept structural guards (preserved sentinels FDC-03-P1/P2). |
| `offline_inbox_roundtrip_test.dart` roundtrip suite | exists | 1to1 | Extended with FDC-03-06 (concurrent first-ever-offline deposit + resume drain). |
| **`concurrent_durable_fallback_roundtrip_test.dart`** N-online (`:122`) / I1 (`:60`) / N-no-double-write (`:148`) | exists | feature-host-all | **MUST CHANGE (review finding)** — N-online `storeInInboxCallCount==0`→`1` (high-conf online now fires the concurrent inbox); I1 stores via the concurrent path; N-no-double-write stays green (`≤2`). **Not in the plan's original two-file scope.** |
| **`p2p_service_fault_injection_test.dart`** Phase-4 recovery (`:578`) + 2 relay-probe tests (`:532` / `:652`) | exists | core-host-all | **MUST CHANGE (review finding)** — uses `kLowConfidenceWindow` (`:603`, compile); `probeRelayCallCount==1`→`0` (probe tail dropped); high-conf recovery `storeInInboxCallCount==0`→`1`. **Not in the plan's original two-file scope.** |

**No test currently asserts a high-confidence unknown-presence send fires the concurrent inbox** — that is the central gap (FDC-03-01/02). **No test asserts the probe tail is *absent*** — gap FDC-03-03.

---

## RED Test Catalog  (BEFORE any prod code)

> Tiers: **unit/application** = `send_chat_message_use_case_test.dart` (drives `sendChatMessage` directly through `FakeP2PService`/`FakeMessageRepository`); **integration** = `offline_inbox_roundtrip_test.dart` (`FakeP2PNetwork` two-user roundtrip). Lowest tier that still fails for the real reason is unit/application for the gate/tail changes; the integration tier locks the end-to-end roundtrip + concurrency under the shared network fake.
>
> **Distinct-event discriminator (required by the brief):** where a live-success send and a serial-tail send both end "delivered," the tests assert the **`CHAT_MSG_SEND_CONCURRENT_INBOX_BEGIN`** flow-event fired (the deposit ran **concurrently**, not on the serial unhappy path) — captured via `captureFlowEvents`.

### FDC-03-01 — unknown-presence live-success fires the concurrent inbox (the core)
- **file::name:** `send_chat_message_use_case_test.dart::FDC-03-01 unknown-presence live-success ALSO deposits one concurrent inbox copy`
- **Tier:** unit/application.
- **Shape/setup:** `p2pService = FakeP2PService()` (default: not connected, not local, `discoverPeerResult` set, `sendMessageResult=true`, acked). `messageRepo.latestMessageForContact == null` (no prior attempt → **high confidence on HEAD**). Send a fresh message.
- **RED-on-HEAD-because:** the gate (`:609-628`) requires a prior failed/inbox attempt; with none, `lowConfidence=false` → `concurrentInbox` stays null → `storeInInboxCallCount == 0`. (Identical to the current assertion at `:3714`.)
- **GREEN-asserts:** `result==success`; `message.status=='delivered'`; `message.transport=='direct'`; **`p2pService.storeInInboxCallCount == 1`** (concurrent deposit fired); exactly one saved row.
- **Mutation-that-re-reds:** re-add the recency requirement (wrap the concurrent arm back in `if (lowConfidence)` / restore the `getLatestMessageForContact` gate) → count back to 0 → RED.
- **Distinct-event discriminator:** asserts (with FDC-03-02) that the deposit was concurrent, not the serial tail (which never runs on a live-success).

### FDC-03-02 — the concurrent BEGIN flow-event fires on the live-success path (discriminator)
- **file::name:** `send_chat_message_use_case_test.dart::FDC-03-02 CONCURRENT_INBOX_BEGIN fires for an unknown-presence send whose live leg WINS`
- **Tier:** unit/application.
- **Shape/setup:** default `FakeP2PService()` (live success), no prior attempt; wrap the send in `captureFlowEvents`.
- **RED-on-HEAD-because:** `CHAT_MSG_SEND_CONCURRENT_INBOX_BEGIN` is emitted only inside the `if (lowConfidence)` block (`:641-648`); a high-confidence send never emits it.
- **GREEN-asserts:** the captured events contain `CHAT_MSG_SEND_CONCURRENT_INBOX_BEGIN` with `details['id'] == message.id.substring(0,8)`, AND the terminal event is `CHAT_MSG_SEND_SUCCESS` with `via=='direct'` (proves the inbox fired **in parallel with** a winning live leg, not on a serial fallback).
- **Mutation-that-re-reds:** move the BEGIN emit back behind the recency gate → event absent → RED.
- **Discriminator role:** this *is* the "inbox-deposit flow-event fires concurrently (not only on the serial unhappy path)" assertion.

### FDC-03-03 — race-all-fail takes concurrent-inbox custody; the serial relay-probe tail does NOT run
- **file::name:** `send_chat_message_use_case_test.dart::FDC-03-03 race failure for an unknown-presence peer commits inbox custody WITHOUT the relay probe`
- **Tier:** unit/application.
- **Shape/setup:** `FakeP2PService(useNullDiscover: true, storeInInboxResult: true)` (direct leg misses → `peer_not_found`, which on HEAD sets `relayProbeEligible`), `probeRelayResult = RelayProbeResult.connected`, **no prior attempt**.
- **RED-on-HEAD-because:** high-confidence → `concurrentInbox` null → on race-fail the `relayProbeEligible` block runs `_tryRelayProbeSend` → `probeRelayCallCount == 1` and the message is delivered live via probe (`transport=='direct'`).
- **GREEN-asserts:** `result==success`; `message.status=='inboxed'`; `message.transport=='inbox'`; `message.wireEnvelope != null` (custody retained); **`p2pService.probeRelayCallCount == 0`** (probe tail removed); `p2pService.storeInInboxCallCount == 1` (the concurrent copy is the carrier); flow-events contain `CHAT_MSG_SEND_CONCURRENT_INBOX_BEGIN` + `CHAT_MSG_SEND_CONCURRENT_INBOX_CUSTODY`, and **no** `CHAT_MSG_SEND_RELAY_PROBE_CONNECTED`.
- **Mutation-that-re-reds:** restore the `if (raceResult.relayProbeEligible) { _tryRelayProbeSend(...) }` block → `probeRelayCallCount==1` → RED.
- **Distinct-event discriminator:** asserts presence of `CONCURRENT_INBOX_*` and **absence** of `RELAY_PROBE_CONNECTED`.

### FDC-03-04 — exactly one relay write on the custody path (no concurrent + serial double-write)
- **file::name:** `send_chat_message_use_case_test.dart::FDC-03-04 concurrent custody writes storeInInbox EXACTLY once`
- **Tier:** unit/application.
- **Shape/setup:** `FakeP2PService(sendMessageResult: false, storeInInboxResult: true)` (live race fails to land, concurrent inbox succeeds), no prior attempt.
- **RED-on-HEAD-because:** high-confidence → no concurrent arm → race-fail runs the serial tail → on HEAD this path also stores once, **but** `CHAT_MSG_SEND_CONCURRENT_INBOX_BEGIN` is absent (the deposit was serial). The test asserts BOTH `storeInInboxCallCount==1` **and** the concurrent BEGIN event — the BEGIN absence makes it RED on HEAD.
- **GREEN-asserts:** `storeInInboxCallCount == 1`; `message.status=='inboxed'`; events contain `CONCURRENT_INBOX_BEGIN` **and** `CONCURRENT_INBOX_CUSTODY`; events do **not** contain a second store marker (`CHAT_MSG_SEND_RACE_ALL_FAILED` may appear once but no `INBOX_FULL`/second `recordAttempt`).
- **Mutation-that-re-reds:** remove the `:1006-1019` "skip serial store when concurrent custody succeeded" short-circuit → the serial `storeInInbox` runs after the concurrent one → `storeInInboxCallCount==2` → RED.

### FDC-03-05 — unacked live write + concurrent custody settles 'inboxed' without a second store (generalized)
- **file::name:** `send_chat_message_use_case_test.dart::FDC-03-05 unacked live write for an unknown-presence peer settles inboxed via the concurrent copy`
- **Tier:** unit/application.
- **Shape/setup:** `FakeP2PService(sendMessageReply: null /* live write returns sent but unacked */, storeInInboxResult: true)`, no prior attempt (so HEAD = high confidence → no concurrent arm).
- **RED-on-HEAD-because:** `_persistOutgoingSendResult` only consults `concurrentInbox` when non-null (`:1819`); high-confidence → null → it pays the serial `:1844` handoff and emits `CHAT_MSG_SEND_UNACKED_INBOX_HANDOFF_BEGIN`, not `..._UNACKED_CONCURRENT_INBOX_CUSTODY`.
- **GREEN-asserts:** `message.status=='inboxed'`, `transport=='inbox'`, `wireEnvelope!=null`; `storeInInboxCallCount == 1`; events contain `CHAT_MSG_SEND_UNACKED_CONCURRENT_INBOX_CUSTODY`; events do **not** contain `CHAT_MSG_SEND_UNACKED_INBOX_HANDOFF_BEGIN`.
- **Mutation-that-re-reds:** re-gate the unacked concurrent-custody branch behind the old low-confidence flag → falls to the serial handoff → `HANDOFF_BEGIN` event reappears → RED.

### FDC-03-06 — (integration) first-ever send to an offline peer deposits concurrently and round-trips on resume
- **file::name:** `offline_inbox_roundtrip_test.dart::FDC-03-06 first-ever offline send deposits a concurrent inbox copy that drains on resume`
- **Tier:** integration (`FakeP2PNetwork` two-user).
- **Shape/setup:** fresh `alice`→`bob` with **no prior message history** (high-confidence on HEAD); `bob.setOnline(false)`; Alice sends one message; capture flow events; then `bob.setOnline(true)` and drain.
- **RED-on-HEAD-because:** with no prior attempt the send is high-confidence → the inbox copy is fired **serially** after the race, so `CHAT_MSG_SEND_CONCURRENT_INBOX_BEGIN` never appears; the assertion on that event fails on HEAD even though Bob *eventually* receives (delivery already passes — the RED is specifically about the **concurrent** deposit, not the end state).
- **GREEN-asserts:** Alice's message persists `status=='inboxed'`/`transport=='inbox'`; flow-events contain `CHAT_MSG_SEND_CONCURRENT_INBOX_BEGIN`; after `bob.setOnline(true)` + drain, Bob's conversation contains exactly one copy of the message (receiver `messageId` dedup → no duplicate).
- **Mutation-that-re-reds:** re-gate the concurrent arm behind the recency lookup → BEGIN absent for a first-ever send → RED.
- **Distinct-event discriminator:** the BEGIN event proves the deposit was concurrent under the real two-user network fake.

### Preserved (green-on-HEAD, must STAY green — locked, not RED)
- **FDC-03-P1** `::reuse send does NOT fire the concurrent inbox` — `FakeP2PService(currentState: NodeState(isStarted:true, connections:[ConnectionState(peerId:'target-peer', …)]))`; assert `storeInInboxCallCount==0`, `transport=='reuse'`/`'direct'`. (Reuse returns before the gate `:451-512`.)
- **FDC-03-P2** `::LAN-local send does NOT fire the concurrent inbox` — `DurableLanFakeP2PService()..localPeers.add('target-peer')`; assert `storeInInboxCallCount==0`, `transport=='local'`. (Kept `!isLocalPeer` guard.)
- **FDC-03-P3** `::downgrade-blocked send fires no inbox` — the EF-2 gate (`:3731`) returns `invalidMessage` before the race; assert `storeInInboxCallCount==0`, `sendCallCount==0`. (Gate runs before the concurrent arm.)
- **FDC-03-P4** `::U3 low-confidence still fires (subset)` — the existing `:3251` test must remain green (low-confidence ⊂ unknown-presence).

---

## Test Coverage Matrix

| Spec case | Behavior props | Tier | Test file::name | RED reason on HEAD | Mutation revert | Acceptance gate cmd | Harness registration |
|---|---|---|---|---|---|---|---|
| Unknown-presence live-success fires concurrent inbox (P0-2 core, R6) | high-conf send → `storeInInboxCallCount==1`, `transport=='direct'` | unit/app | `send_chat_message_use_case_test.dart::FDC-03-01` | gate requires prior failure → count 0 | re-add recency gate | `./scripts/run_test_gates.sh 1to1` | already in `1to1` array (line 36); auto-globs `feature-host-all` |
| Deposit is **concurrent**, not serial (discriminator) | `CONCURRENT_INBOX_BEGIN` fires with winning live leg | unit/app | `…::FDC-03-02` | BEGIN emitted only under low-conf gate | move BEGIN behind recency gate | `./scripts/run_test_gates.sh 1to1` | same file |
| Serial relay-probe tail dropped; custody via concurrent inbox | `probeRelayCallCount==0`, `status=='inboxed'`, no `RELAY_PROBE_CONNECTED` | unit/app | `…::FDC-03-03` | `relayProbeEligible` block runs probe → count 1 | restore `_tryRelayProbeSend` block | `./scripts/run_test_gates.sh 1to1` | same file |
| Exactly one relay write (no double-write) | `storeInInboxCallCount==1` + BEGIN+CUSTODY | unit/app | `…::FDC-03-04` | BEGIN absent (serial path) | remove `:1006-1019` skip → count 2 | `./scripts/run_test_gates.sh 1to1` | same file |
| Unacked live + concurrent custody → 'inboxed', one store | `UNACKED_CONCURRENT_INBOX_CUSTODY`, no `…HANDOFF_BEGIN`, count 1 | unit/app | `…::FDC-03-05` | unacked branch only checks non-null concurrent | re-gate unacked branch behind low-conf | `./scripts/run_test_gates.sh 1to1` | same file |
| First-ever offline send deposits concurrently + round-trips | `inboxed`, `CONCURRENT_INBOX_BEGIN`, one copy after drain | integration | `offline_inbox_roundtrip_test.dart::FDC-03-06` | high-conf → serial deposit, BEGIN absent | re-gate concurrent arm behind recency | `./scripts/run_test_gates.sh 1to1` | already in `1to1` array (lines 11/19) |
| **PRESERVE** reuse send single-path | `storeInInboxCallCount==0` | unit/app | `…::FDC-03-P1` | n/a (green) — locks "not blanket dual-write" | drop `!isAlreadyConnected`/reuse-return guard → count 1 | `./scripts/run_test_gates.sh 1to1` | same file |
| **PRESERVE** LAN-local send single-path | `storeInInboxCallCount==0`, `transport=='local'` | unit/app | `…::FDC-03-P2` | n/a (green) | drop `!isLocalPeer` guard → count 1 | `./scripts/run_test_gates.sh 1to1` | same file |
| **PRESERVE** EF-2 downgrade-blocked: no inbox | `storeInInboxCallCount==0`, `sendCallCount==0` | unit/app | `…::FDC-03-P3` | n/a (green) | move gate after concurrent arm | `./scripts/run_test_gates.sh 1to1` | same file |
| **PRESERVE** low-confidence still fires (subset) | existing U3 stays green | unit/app | `…::FDC-03-P4` (existing `:3251`) | n/a (green) | n/a | `./scripts/run_test_gates.sh 1to1` | same file |
| **Regression floor** (no 1:1 / feed / groups / baseline breakage) | full gates green | gate | (all of the above + existing suites) | n/a | n/a | `./scripts/run_test_gates.sh baseline` · `feed` · `groups` · `./scripts/run_host_test_gates.sh feature-host-all` | n/a |

No empty cells.

---

## Blind-Spot Sweep

- **Lifecycle / derived-state durability.** The concurrent inbox now fires on *every* unknown-presence send → **inbox volume rises materially** (proposal §9.3 / FDC-00 DURABILITY-ORDERING hazard). The new copies land in the **in-memory relay backend by default**, which is wiped on a relay bounce. **Row:** documented as a cross-plan durability hazard (Risks); the *mitigation owner is FDC-10* (Redis) and FDC-00 mandates pulling FDC-10 earlier. FDC-03's host tests cannot observe a relay bounce — flagged, not silently accepted. No new persistent client state is introduced by FDC-03 itself.
- **Sibling-surface consistency (group send).** The group send path fires the durable inbox concurrently *already* (the 1:1 low-confidence gate was modeled on it — the `:63` doc-comment "as the group path does"). FDC-03 brings 1:1 into parity for unknown presence; **no group-path edit.** **Row:** `./scripts/run_test_gates.sh groups` is a regression floor to prove no group breakage (group path untouched).
- **Destructive-action side-effects.** None added. The change is additive within the send path; `persistInboxAccepted` keeps the envelope (custody, not delivery) so the custody sweep / receipt-flip invariants (doc 115) are unchanged. **Row:** FDC-03-03/05 assert `wireEnvelope!=null` on the inbox-custody rows.
- **Invariant re-verification under the new transition.** The "exactly one relay write per message" invariant (R1) is the one most at risk under "concurrent arm now always fires" — re-locked by FDC-03-04 (`==1`, mutation → 2). The "not a blanket dual-write" invariant is re-locked by the preserved FDC-03-P1/P2 (reuse/local stay 0). **Row:** both covered.
- **Edit/retry path.** `editChatMessage` (`:1155`) and UI retry route through `sendChatMessage`, so they inherit the generalized gate. An edit to an unknown-presence peer now also deposits concurrently — acceptable (same id → receiver dedup). **Row:** no separate test required; covered transitively by FDC-03-01 (the edit path is the same function); EF-2 preserved by FDC-03-P3.
- **Bridge serialization (§10).** The extra `storeInInbox` funnels through the single Go bridge alongside the live send → could head-of-line the live leg. FDC-03 fires the inbox **fire-and-forget** (it does not `await` before the race, matching HEAD `:649-660`), so it does not block the race start. **Row:** FDC-03-02 asserts the live leg still wins (BEGIN + `via=='direct'`), proving the concurrent deposit did not stall the live path in the fake. Real-bridge contention is a device-proof concern (Device/Relay Proof Profile), flagged — not host-provable.

---

## Invariants (locked by tests)

1. **Unknown presence ⇒ concurrent inbox.** Any send that is not already-connected, not LAN-local, and has no live peer connection fires `storeInInbox` concurrently with the live race — independent of prior-attempt recency. (FDC-03-01/02; integration FDC-03-06.)
2. **Confirmed-path ⇒ single-path.** A `reuse`/connected send and an `isLocalPeer` send never fire the concurrent inbox. (FDC-03-P1/P2.)
3. **Exactly one relay write per message.** Concurrent custody success suppresses the serial store; no message produces two `storeInInbox` calls. (FDC-03-04.)
4. **No serial relay-probe carrier.** Race failure for an unknown-presence peer takes concurrent-inbox custody; `_tryRelayProbeSend` does not run. (FDC-03-03.)
5. **Custody, not delivery.** Inbox acceptance persists non-terminal `'inboxed'` with the wire envelope retained. (FDC-03-03/05.)
6. **Concurrency is observable.** `CHAT_MSG_SEND_CONCURRENT_INBOX_BEGIN` fires even when the live leg wins (deposit was parallel, not serial). (FDC-03-02, the distinct-event discriminator.)

---

## Step-By-Step Implementation Plan  (RED first)

> **Stop-if (blocker):** FDC-03 lands **third** in the Phase-0 sequence — **after FDC-01 and FDC-02 are merged and the `1to1` gate is green** (FDC-00 collision map). FDC-02 must already have folded the relay leg into the in-race ranked race; otherwise dropping the serial probe tail removes the *only* relay-live path. **Do not start FDC-03 against a tree where FDC-02 has not landed.** Re-capture the green `1to1` baseline count immediately before starting (TODO — record it).

1. **RED — author the catalog first.** Add FDC-03-01..05 to `send_chat_message_use_case_test.dart` and FDC-03-06 to `offline_inbox_roundtrip_test.dart`. Add/keep the preserved FDC-03-P1..P4. Run `./scripts/run_test_gates.sh 1to1` and confirm 01-06 are RED for the stated reasons (and P1-P4 green). **Seam:** existing `FakeP2PService`/`FakeMessageRepository`/`captureFlowEvents` — no new fakes.
2. **GREEN step A — generalize the gate** (`:597-660`). Replace the `lowConfidence` computation: keep the three structural guards (`!isAlreadyConnected && !isLocalPeer && !p2pService.isConnectedToPeer(targetPeerId)`); **delete** the `getLatestMessageForContact` recency/terminal block (`:613-628`). Set `unknownPresence = <the three guards>`; fire the concurrent `storeInInbox` arm (`:639-660`) when `unknownPresence`. Rename the constant comment block; `kLowConfidenceWindow` (`:67`) becomes dead → remove it and its doc, or leave with a `// retired by FDC-03` note (prefer remove). **Seam:** the gate block only; the fire-and-forget `.then(recordAttempt).catchError` structure is unchanged. Makes FDC-03-01/02 green.
3. **GREEN step B — generalize the unacked-branch skip** (`_persistOutgoingSendResult :1819-1837`). No code change needed *if* `concurrentInbox` is now non-null for unknown presence (it already keys off non-null). Verify FDC-03-05 green; the existing `CHAT_MSG_SEND_UNACKED_CONCURRENT_INBOX_CUSTODY` emit now fires for the generalized set. **Seam:** confirm the `concurrentInbox` future is threaded into `_completeSuccessfulSend` on the live-win path (`:889`) and the unacked branch — already wired; no edit expected.
4. **GREEN step C — drop the serial relay-probe tail** (`:1021-1062`). Remove the `if (raceResult.relayProbeEligible) { final relayProbeResult = await _tryRelayProbeSend(...) ... }` block. Keep the `:1006-1019` concurrent-custody short-circuit (unchanged) and the **single** final `storeInInbox` fallback (`:1064-1099`) as the carrier **only** for the `concurrentInbox==null` edge (connected/local fall-through) or `concurrent==false` retry. **Seam:** delete the probe block; leave the final inbox block intact. Makes FDC-03-03 green and removes the probe consumer. Audit `_tryRelayProbeSend` (`:1534`) for now-dead references; leave the helper if FDC-02 still references it in-race, else mark dead-code for a follow-up cleanup (do not delete cross-plan symbols speculatively).
5. **GREEN step D — migrate the inverted/affected existing tests.** Rewrite `U-N3` (`:3391`) and `U-N3 stale` (`:3416`) to the new contract (now they fire — fold into FDC-03-01 or re-purpose as "reuse/local still don't fire"). Update `::slow relay does not block` (`:2904`) and `::live acked send still persists delivered` (`:3714`) `storeInInboxCallCount` `0→1`. Audit + rewrite the Phase-3 relay-probe block (`:2030-2212`) and `E2 RELAY_PROBE_CONNECTED` (`:3354`) to the post-probe-tail behavior (custody via concurrent inbox; relay live-recovery is FDC-02's in-race leg). **Seam:** test file only; each rewrite must keep its original *intent* (it is a behavior change, documented in the test's comment with a `// FDC-03:` note).

   **5b — migrate the affected tests OUTSIDE `send_chat_message_use_case_test.dart` (review finding; these are NOT in the plan's original two-file scope but the `core-host-all` / `feature-host-all` gates run them, so they WILL fail otherwise):**
   - `concurrent_durable_fallback_roundtrip_test.dart`: flip `N-online` (`:139`) `storeInInboxCallCount` `0→1` (high-conf online now fires the concurrent inbox) and update its reason string; re-check `I1` (`:73-93`) — it now takes custody via the concurrent path; leave `N-no-double-write` (robust `≤2`).
   - `p2p_service_fault_injection_test.dart`: replace the `kLowConfidenceWindow` reference (`:603`) — drop the backdating premise; rewrite the Phase-4 recovery test (`:578`) and the two relay-probe tests (`:532` / `:652`) to the post-probe-tail contract (`probeRelayCallCount==0`; custody via the concurrent inbox).
   - Audit (likely no edit): `retry_failed_messages_use_case_test.dart` / `retry_unacked_messages_use_case_test.dart` (retrier-filter tests, no send-gate invocation) and `benchmark_routing_paths_test.dart` (perf, ungated).
6. **Re-run the full gate set + hygiene.** `1to1`, `baseline`, `feed`, `groups`, `feature-host-all`, `flutter analyze`, `git diff --check`. Re-run each FDC-03 mutation to confirm re-RED.

---

## Risks And Edge Cases

| Risk / edge | Pinned by |
|---|---|
| **Inbox-volume ramp before durable backend** (§9.3 hazard): FDC-03 deposits on every unknown-presence send into the restart-losable in-memory relay backend. | Cross-plan: **FDC-10 (Redis) must land alongside/before FDC-03** (FDC-00 DURABILITY-ORDERING hazard). FDC-03 host tests cannot observe a relay bounce — documented, not waived. |
| **Double-write regression** (concurrent + serial both store). | FDC-03-04 (`==1`; mutation removing the `:1006-1019` skip → 2). |
| **Blanket dual-write** (firing on reuse/local). | FDC-03-P1/P2 (reuse/local stay 0; mutation dropping a guard → 1). |
| **Losing the live relay path** by dropping the probe before FDC-02 lands. | Stop-if blocker (Step plan); FDC-02 in-race relay leg is the replacement. FDC-03-03 asserts custody is still reached (via inbox) when no live leg lands. |
| **Recipient cost rises** (extra retrieve+ack per deposit; §6.2 honesty note). | Acknowledged design cost; receiver `messageId` dedup keeps it correct (FDC-03-06 asserts one copy after drain). Net relay/recipient work increase is a **measure-it** item → device/sim. |
| **Bridge head-of-line** between the concurrent deposit and the live send (§10). | FDC-03-02 asserts the live leg still wins in the fake; real contention → device-proof. |
| **`direct_timeout`/`relayProbeEligible` becomes vestigial** after the probe tail is removed (FDC-01's change). | Dependency Impact note; no test asserts the probe runs anymore (those tests are migrated in Step 5). |

---

## Device/Relay Proof Profile

- **Host-only for closure of the FDC-03 contract:** the gate generalization, the no-double-write invariant, the probe-tail removal, and the concurrency discriminator are **fully host-testable** (FDC-03-01..06) — these *are* the closure criteria for the code change.
- **Requires sim/device (NOT host-closable):** the proposal's host-fake **false-positive caveat** (§9.1 / FDC-00 false-positive caveat) applies — a host fake can pass FDC-03-01/06 **via the inbox copy even if the live leg never fired**, because both sides dedup by `messageId`. So host-green proves *delivery + concurrent deposit*, **not** that the live leg actually won. **Closure scenario:** after FDC-04 (end of the MVP cut), run `./scripts/check_reliability_simulation_discovery.sh` then `/sims 1to1 --only <N>` asserting the transport label (`direct`/`local` vs `inbox`/`relay`) on a live-reachable peer, plus a **two-device smoke** observing the live path win while the inbox copy is deduped. FDC-03 does not independently gate a new sim scenario (no new `classify_path()` case) — it rides the existing 1:1 reliability scope.

---

## Acceptance Gates  (LITERAL — copy/paste)

```
# Home gate (send_chat_message_use_case_test.dart + offline_inbox_roundtrip_test.dart live here)
./scripts/run_test_gates.sh 1to1            # expected: 1226 (capture green baseline AFTER FDC-02, BEFORE FDC-03; prior ~1226)

# Regression floors
./scripts/run_test_gates.sh baseline        # expected: 112 host
./scripts/run_test_gates.sh feed            # expected: 279
./scripts/run_test_gates.sh groups          # expected: 896 (group path untouched — must not regress)

# Host floor
./scripts/run_host_test_gates.sh feature-host-all   # 0 fail
./scripts/run_host_test_gates.sh core-host-all      # 0 fail

# Hygiene
flutter analyze        # 0 new
git diff --check
```

(The `transport` integration gate — `integration_test/{background_reconnect,wifi_relay_fallback_smoke,transport_e2e,media_stable_id_smoke}_test.dart` — is not edited by FDC-03 but should be re-run as a Phase-0 floor: `./scripts/run_test_gates.sh transport`, expected device/fixture-gated (skips on lone sim).)

---

## Known-Failure Interpretation

- A pre-existing `groups` flake (ML-004 / durable-media-upload, per MEMORY) is **not** FDC-03 — re-run in isolation to confirm. FDC-03 edits no group code.
- If `1to1` RED count after Step 5 differs from the pre-FDC-03 baseline by exactly the migrated-test delta (U-N3 inversions + Phase-3 probe-block rewrites + the two `0→1` updates), that is **expected** — diff the named tests, not the raw count.
- **`core-host-all` / `feature-host-all` will go RED until Step 5b lands** (review finding): a compile error from removing `kLowConfidenceWindow` (consumed by `p2p_service_fault_injection_test.dart:603`) plus the inverted negative controls in `p2p_service_fault_injection_test.dart` (probe tail → 0; Phase-4 recovery 0→1) and `concurrent_durable_fallback_roundtrip_test.dart` (N-online 0→1). These are **expected, migration-pending** failures, not regressions — they must be green before the gate closes.
- A FDC-03-01/06 that passes on HEAD would mean FDC-02 already generalized the gate (it did not — verify against the merged FDC-02 diff before assuming a stale baseline).

---

## Done Criteria

- [ ] FDC-03-01..06 authored RED-first, each RED on the (post-FDC-02) tree for the stated reason, then GREEN.
- [ ] Each behavior-bearing edit has a named mutation that re-REDs its lock (recency-gate restore; probe-block restore; double-write skip removal; unacked re-gate; guard-drop for P1/P2).
- [ ] Preserved FDC-03-P1..P4 stay green.
- [ ] Inverted/affected existing tests migrated with `// FDC-03:` rationale; intent preserved — in `send_chat_message_use_case_test.dart` (U-N3 ×2, Phase-3 probe block, `slow relay`, `live acked`, E2 RELAY_PROBE) **and (review finding) `concurrent_durable_fallback_roundtrip_test.dart` (N-online 0→1, I1) + `p2p_service_fault_injection_test.dart` (probe tail → 0, Phase-4 recovery 0→1)**.
- [ ] `kLowConfidenceWindow` + the `getLatestMessageForContact` gate read removed from the send hot path (or explicitly retired); the serial relay-probe block removed; **and the `p2p_service_fault_injection_test.dart:603` consumer of `kLowConfidenceWindow` updated so the constant removal compiles**.
- [ ] All Acceptance Gates green; `flutter analyze` 0-new; `git diff --check` clean.
- [ ] Durability hazard cross-referenced to FDC-10; device/sim proof profile recorded as deferred-not-waived.
- [ ] **PRODUCTION RELEASE GATE (NOT host-closable — host-green closes the *code*, it does NOT authorize the volume ramp):** FDC-10 (Redis durable backend) confirmed **live on every relay front-end** (`RELAY_BACKEND=redis`, not the restart-losable in-memory default at `go-relay-server/server_bootstrap.go:36-39`) **before FDC-03's concurrent inbox deposits reach production volume** (FDC-00 durability-ordering hazard + Recommended MVP cut).

---

## Scope Guard  (hard Do-not)

- **Do NOT** edit any file other than `send_chat_message_use_case.dart` (prod) + the **affected test files**: `send_chat_message_use_case_test.dart`, `offline_inbox_roundtrip_test.dart`, **and (review finding) `concurrent_durable_fallback_roundtrip_test.dart` + `p2p_service_fault_injection_test.dart`** — the latter two carry inverted negative controls / the `kLowConfidenceWindow` reference and WILL fail `feature-host-all` / `core-host-all` otherwise. No `p2p_service_impl.dart`, no Go, no relay. (Retrier/benchmark tests: audit only, edit solely if an assertion actually regresses.)
- **Do NOT** add or change `messageId` dedup (server-side, already correct — FDC-10/Go own the inbox).
- **Do NOT** add presence-based lazy/inbox-first branching (FDC-08).
- **Do NOT** fire the concurrent inbox for reuse/connected/LAN-local sends.
- **Do NOT** rewrite the race body / per-leg budgets (FDC-02).
- **Do NOT** run in parallel with any other FDC plan that touches `send_chat_message_use_case.dart` (collision — strictly sequential, FDC-00 collision map).
- **Do NOT** delete `_tryRelayProbeSend` if FDC-02 still references it in-race; only remove the *tail consumer* block.

---

## Accepted Differences

- **All non-connected/non-local sends are treated as UNKNOWN presence** → concurrent inbox always. The proposal's reachable→lazy / unreachable→inbox-first split (§6.3) is **deliberately not** implemented here; it arrives with the presence signal in FDC-08. This means FDC-03 deposits more inbox copies than the eventual presence-aware steady state — accepted, and the reason FDC-10 is pulled earlier.
- **LAN-local sends do not deposit a concurrent inbox copy**, diverging from a literal reading of §6.2b "always, regardless of the race." Justification: the LAN nonce ack is itself a delivery confirmation, and the §6.2 honesty note ("recipient cost rises … measure it") argues against paying the deposit where a confirmed path exists. Kept as a belt-and-suspenders `!isLocalPeer` guard (consistent with §6.1's `isLocalPeer` gating).
- **Push-to-wake is server-side on store** (the relay FCM-pushes on inbox deposit, proposal §2) — FDC-03 adds **no** new client push call; "delivered(inbox)+push-to-wake" is satisfied by the existing `storeInInbox` → server push.

---

## Dependency Impact

- **Depends on (must land first):** FDC-01 (`direct_timeout` correctness), FDC-02 (ranked race with in-race relay leg). FDC-03 is third in the sequential Phase-0 cut (FDC-00 Phase-0 cut sequence). After FDC-03, **FDC-01's `relayProbeEligible`/`direct_timeout` change becomes vestigial** (the probe tail consumer is removed) — note for a future cleanup; FDC-01 remains valuable as an independently-shipped correctness fix in its own window.
- **Raises load on:** the relay inbox (volume ramp) → **FDC-10 (Redis durable backend + relay pool) should land alongside/before FDC-03** to keep the new copies durable (FDC-00 durability-ordering hazard).
- **Collision file:** `lib/features/conversation/application/send_chat_message_use_case.dart` — shared with FDC-01, FDC-02, FDC-04. Strictly sequential; FDC-03 commits and re-greens `1to1` before FDC-04 starts.
- **No migration, no schema change, no l10n, no Go/relay deploy.**
