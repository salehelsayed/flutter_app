# FDC-18 — 1:1 reaction send reliability (concurrent durable inbox + no online-peer misroute)  (Modification)

Status: awaiting-review
Spec: Network-Arch/Fast-Direct-Connection-Architecture-Proposal.md (§4.1 "the correctness bug worth fixing on its own"; §6.2 "Staggered ranked race + parallel durable inbox (no window)" / §6.2(b) durable-inbox separate tier) · FDC-00-roadmap.md "Known gaps" reaction scope note (*"Reaction send reliability, if wanted, is a small follow-on (FDC-18) mirroring FDC-01+FDC-03 onto sendReaction."*)

---

## Source Of Truth

- **Proposal** §4.1 (`:117` — online-but-slow peer must not be demoted to the offline inbox) and §6.2 / §6.2(b) (`:200` — the durable inbox is a **separate tier fired in parallel**, not a late serial fallback).
- **Roadmap** `FDC-00-roadmap.md`:
  - The **reaction scope note**: reactions use `send_reaction_use_case.dart` → the **thin** `p2pService.sendMessage()` + a manual `storeInInbox()` fallback, **not** `send_chat_message_use_case.dart`, so they inherit **none** of FDC-01/02/03/04's orchestration wins; FDC-18 is the named follow-on "mirroring FDC-01+FDC-03 onto sendReaction"; the FDC-13 'upgraded' badge is **N/A** (reactions carry no transport field).
  - The **group-safety mandate**: the whole epic is **1:1-only**; group messaging must not regress.
  - The **parallel-execution tracks**: only the send-path spine (`send_chat_message_use_case.dart`) is strictly serial; plans in **disjoint file sets** run in parallel.
- **Patterns to mirror** — `FDC-01-direct-timeout-misroute-fix-tdd-plan.md` (don't demote an online peer to the inbox) and `FDC-03-concurrent-durable-inbox-safety-net-tdd-plan.md` (fire `storeInInbox` **concurrently** with the live attempt, deduped by `messageId`, drop the serial tail; "exactly one relay write per message"; "confirmed-path ⇒ single-path").
- **`scripts/run_test_gates.sh` wins over prose:** the reaction integration test `emoji_reaction_exchange_test.dart` is in `OPTIONAL_MANUAL_TESTS` (`run_test_gates.sh:195`) — a **manual / non-gated** suite, **NOT** in the curated `ONE_TO_ONE_TESTS` `1to1` gate; the unit reaction tests under `test/features/**` **auto-glob** into `feature-host-all`. **So FDC-18's new RED locks must be explicitly appended to `ONE_TO_ONE_TESTS` if they are to run in the curated `1to1` gate** (auto-glob only covers `feature-host-all`/`core-host-all`).
- Every `file:line` below was re-verified by Read against branch `new-orbit` (not from memory).

---

## Session Classification

**implementation-ready.** Pure-Dart control-flow change in **one** use-case file (`send_reaction_use_case.dart`); host-fake testable through the existing `FakeP2PService` / `FakeReactionRepository` / `captureFlowEvents` harness. No relay/Go deploy. **No migration** — the `message_reactions` table already exists (migration 016). No native build. The real-wire "live-wins / not-dropped" angle carries the same host-fake false-positive risk as FDC-01/03 (proposal §9.1) → device/sim smoke is DEFERRED, not gating (see Device/Relay Proof Profile).

---

## Exact Problem Statement

**What's broken.** Sending an emoji reaction to a **slow or momentarily-unreachable** 1:1 peer is delivered **late or dropped**, while the chat send path now (FDC-01/03) avoids exactly this. The reaction send path uses the **thin** `p2pService.sendMessage()` and a **serial** inbox fallback:

- `send_reaction_use_case.dart:106` — `final sent = await p2pService.sendMessage(targetPeerId, jsonString);`
- `:107-119` — **only if `sent == false`** does it then `await p2pService.storeInInbox(...)` — a **serial tail**, paid *after* the full live attempt is spent, not concurrently.
- `:131-132` — optimistic local persist happens *after* the send block returns.

`sendMessage` (`p2p_service_impl.dart:1897-1959`) is a **single** Go-bridge call (`callP2PMessageSend :1910`) that returns one `bool`. It has **no Dart-level discover→dial→send race, no per-step budget, no relay probe, and no concurrent inbox** — the orchestration FDC-01/02/03 added all lives in `send_chat_message_use_case.dart`, which the reaction path never calls.

Two consequences for a slow/offline peer:

1. **Late durability (the FDC-03 gap).** The durable inbox copy — the delivery-guarantee tier — is deposited **serially after** the live `sendMessage` returns `false`, so a reaction to an offline peer lands in custody *seconds* later than necessary (and, on a transient bridge hiccup, the deposit is the *only* attempt).
2. **Online-but-slow misroute risk (the FDC-01 spirit).** When `sendMessage` returns `false` for a transient un-ack against an actually-reachable peer, the reaction is demoted to an **inbox-only** late delivery — the receiver only sees it on its next ~30 s inbox drain / push-wake, so the reaction "feels dropped."

**Who feels it.** Anyone tapping a reaction on a 1:1 message to a peer who is reachable-via-relay but momentarily slow, or briefly offline (cold-ish open, congested rendezvous). The reaction is the most latency-sensitive micro-interaction (instant visual feedback expected), so the lateness is disproportionately felt.

**What must improve.**
- For an **unknown-presence** 1:1 reaction send, fire `storeInInbox` **concurrently** with the live `sendMessage` as a strictly separate durability tier — so an offline/slow peer's reaction holds custody immediately, not on a late serial tail.
- Keep the **live `sendMessage` attempt** so an online peer's reaction is delivered **live**; the concurrent inbox copy is a parallel safety net, deduped on receive — the reaction is **not demoted to inbox-only**.
- Preserve **exactly one** `storeInInbox` per reaction (no concurrent + serial double-write).

**What must stay unchanged → preserved sentinels.**
- **Receive idempotency / last-writer-wins tombstone** is the correctness backstop and is **not touched**. A reaction is a TOGGLE; a stale or duplicate copy is dropped by `_isStaleComparedToCurrent` (`handle_incoming_reaction_use_case.dart:202-222`, helper `:296-307`; comparand = `removedAt ?? timestamp`, `:206-208`). The new concurrent deposit *raises* the rate of duplicate arrivals (live copy + drained inbox copy) → this invariant must visibly hold.
- **Confirmed-path ⇒ single-path.** A reaction to an **already-connected** peer (`isConnectedToPeer == true`, `p2p_service.dart:179`) keeps a single live path — no concurrent inbox copy (mirrors FDC-03 invariant 2; bounds the extra relay traffic for a tiny, frequently-toggled payload).
- **Both-fail ⇒ `sendFailed`, no local persist.** When the live send AND the inbox deposit both fail, return `SendReactionResult.sendFailed` and write **no** reaction row (existing test `send_reaction_use_case_test.dart:154-177`).
- **No message-retry-pipeline involvement (source pin).** `send_reaction_use_case.dart` must continue to contain **neither** `MessageRepository` **nor** `saveMessage` — the 116-P1.2 source-pin (`send_reaction_use_case_test.dart:184-193`) asserts this. The new arm uses only `P2PService.storeInInbox`/`sendMessage` + `ReactionRepository.saveReaction`, so the pin is preserved.
- **No transport badge** (FDC-13 is N/A): `MessageReaction` has **no** `transport` field (`message_reaction.dart:6-39`) — do **not** add one.
- **Move-feature safety inherited.** `sendMessage` and `storeInInbox` already gate on `_allowsAccountNetworkSideEffects(...)` (`p2p_service_impl.dart:1899` `'p2p_send_message'`; the inbox path likewise). FDC-18 adds **no new ungated wire primitive** — it only reorders/parallelizes existing gated calls. No new gate needed.

---

## Root Cause (verify→refute confirmed)

**Mechanism (verified by Read, branch `new-orbit`):**

1. **Serial-only deposit.** `send_reaction_use_case.dart:104-128`: the single `sendMessage` is awaited first (`:106`); `storeInInbox` runs **only inside `if (!sent)`** (`:107-111`). There is no concurrent arm and no presence branch — the inbox is a strictly serial last resort.
2. **Thin transport, no orchestration.** The reaction path calls `p2pService.sendMessage` (`:106`) → `p2p_service_impl.dart:1897` thin `callP2PMessageSend` (`:1910`), returning one `bool`. None of FDC-01's per-step budgets / `direct_timeout` probe-eligibility nor FDC-03's concurrent gate exist on this path; those edits are confined to `send_chat_message_use_case.dart` (FDC-00 collision map). So the reaction path inherits the **R6** late-custody behavior FDC-03 fixed for chat.

**Confirmed (single transport leg — full race is overkill).** The reaction send has exactly **one** transport leg: `sendMessage` (a single Go-bridge `callP2PMessageSend`). There is **no** `discoverPeer` / `dialPeer` / `probeRelay` call anywhere in `send_reaction_use_case.dart` (verified — the file imports only `P2PService`, `Bridge`, `ReactionRepository`, and the reaction models). Therefore FDC-02's **ranked relay-penalized race** has nothing to rank for reactions, and FDC-01's **per-step budget / direct_timeout probe-eligibility** has no per-step cascade to decouple. The transferable wins are **only**: (a) FDC-03's concurrent durable inbox, and (b) FDC-01's *intent* — keep attempting live, don't demote an online peer to inbox-only — achieved here via concurrency, not a probe.

**Refuted / do-NOT-do.**
- *"Route `sendReaction` through `sendChatMessage` to inherit FDC-01/02/03."* — **Refuted.** Reactions are a distinct envelope (`ReactionPayload`, not a chat message), write **no** `messages` row, take **no** `MessageRepository`, and have a separate receive use case + last-writer-wins tombstone. Routing through `sendChatMessage` would violate the 116-P1.2 source-pin (`send_reaction_use_case_test.dart:184-193`) and the reaction/message separation. (See Design Decision.)
- *"Mirror the full FDC-02 ranked race onto reactions."* — **Refuted as overkill**: one transport leg (above). A staggered relay-penalized race needs ≥2 legs to rank.
- *"Blanket dual-write every reaction (deposit even when connected)."* — **Refuted**: a live-connected peer has a confirmed path; mirror FDC-03's `!isConnectedToPeer` guard so the concurrent inbox fires only for unknown presence, bounding extra relay traffic for a frequently-toggled payload.
- *"Add presence-based lazy/inbox-first emphasis."* — Out of scope (FDC-08); FDC-18 treats every non-connected reaction as UNKNOWN → concurrent deposit, exactly as FDC-03 does for chat.

---

## Design Decision — REUSE vs MIRROR  →  **MIRROR (b)**

**Chosen: (b) mirror — add a minimal concurrent-inbox arm directly onto `send_reaction_use_case.dart`.** Grounded justification:

1. **FDC-03 extracts no shared helper to reuse.** FDC-03's concurrent-inbox logic is **inlined** into the chat send orchestration — the `lowConfidence`→`unknownPresence` gate (`send_chat_message_use_case.dart:597-660`), the `concurrentInbox` future threaded through `_completeSuccessfulSend` and `_persistOutgoingSendResult`, and the `_RaceResult` race machinery. There is **no** standalone, reaction-callable `depositConcurrentInbox(...)` function produced by FDC-03 (verified against the FDC-03 plan's Real Scope — "the only edited file" is `send_chat_message_use_case.dart`). Option (a) "reuse if FDC-03 extracts a shared helper" therefore has **no helper to reuse**.
2. **The reaction path is single-leg and envelope-distinct** (see Root Cause), so the FDC-03 orchestration would not even fit — there is no race to thread a `concurrentInbox` future into. The transferable surface is just "start the inbox deposit before awaiting the live result; commit on either; exactly one write."
3. **Reuse via `sendChatMessage` is refuted** (above) — it breaks the reaction/message separation and the 116-P1.2 source-pin.

So FDC-18 **mirrors the FDC-03 *pattern*** (concurrent deposit, `messageId`/last-writer-wins dedup, exactly-one-write, confirmed-path-single-path) onto the reaction file's own minimal shape, calibrated down to one transport leg.

**Dependency framing.** FDC-18 should land **AFTER FDC-03** so it copies the *established, reviewed* concurrent-inbox pattern and does not diverge from it. But it edits **`send_reaction_use_case.dart`** — a **different file** from Track A's `send_chat_message_use_case.dart` — so it is **NOT** in the strict send-path collision spine and is **parallelizable** with Track A (its own one-file mini-track). See Dependency Impact.

---

## Real Scope

**In scope (FDC-18):**
- In `send_reaction_use_case.dart`, replace the serial `if (!sent) storeInInbox` tail with a **concurrent durability arm**: for `unknownPresence == !p2pService.isConnectedToPeer(targetPeerId)`, **start** `storeInInbox` (fire-and-forget) **before** awaiting `sendMessage`; emit a `REACTION_SEND_CONCURRENT_INBOX_BEGIN` flow-event at the start; commit `SendReactionResult.success` on the live ack **or** the inbox custody; preserve **exactly one** `storeInInbox`.
- For a **connected** peer (`isConnectedToPeer == true`), keep the single live path (no concurrent deposit).
- Preserve `sendFailed`/no-persist when both fail; preserve optimistic local persist on success; preserve the source-pin (no `MessageRepository`/`saveMessage`).
- Lock all of the above with mutation-verified host tests + a duplicate-delivery integration assertion that the receive tombstone still wins.

**Out of scope → owning plan:**
- Ranked relay-penalized race / per-leg budgets for reactions → **N/A** (single leg; FDC-02 has nothing to rank).
- `direct_timeout` per-step probe-eligibility → **N/A** (no Dart-level per-step cascade on `sendMessage`).
- Presence-based lazy/inbox-first emphasis → **FDC-08** (gated FDC-S3).
- Durable Redis inbox backend / relay pool (the inbox-volume durability half) → **FDC-10** (FDC-18 raises reaction inbox volume; flagged, not owned here).
- **Group reactions** → separate use case `sendGroupReaction` (pubsub publish + replay outbox); **untouched** (Scope Guard).
- Any change to `handle_incoming_reaction_use_case.dart` behavior (receive tombstone) — **read-only preserve**, no edit.

---

## Files To Inspect Next

**Production (THE edit — only file):**
- `lib/features/conversation/application/send_reaction_use_case.dart` — entry `sendReaction :30`; node-running guard `:50`; payload build `:60-70`; v2 encrypt `:72-102`; **send block `:104-128`** (serial `sendMessage :106`, serial inbox `:107-119`); optimistic persist `:131-132`; success event `:134-138`.

**Production (dependency-only — NOT edited):**
- `lib/core/services/p2p_service.dart` — `sendMessage` (no signature shown), `storeInInbox`, `isConnectedToPeer :179`, `isLocalPeer :189`.
- `lib/core/services/p2p_service_impl.dart` — thin `sendMessage :1897-1959` → `callP2PMessageSend :1910`; move-gate `_allowsAccountNetworkSideEffects('p2p_send_message') :1899`.
- `lib/features/conversation/application/handle_incoming_reaction_use_case.dart` — receive path; tombstone/staleness `:197-222`, helper `:296-307` (**preserve, do not edit**).
- `lib/features/conversation/domain/models/message_reaction.dart` — model `:6-39`; `removedAt` tombstone comparand `:28-29`; `==` by `id` `:120-127` (no `transport` field → FDC-13 N/A).
- `lib/features/conversation/domain/models/reaction_payload.dart` — `buildEncryptedEnvelope` / `toMessageReaction` (envelope construction; dependency-only).

**Group (verify-disjoint, MUST NOT edit):**
- `lib/features/groups/application/send_group_reaction_use_case.dart` — `sendGroupReaction` publishes via `bridge` (pubsub) + stages a `GroupReactionReplayOutbox` entry; it does **not** call `p2pService.sendMessage`/`storeInInbox`. Fully disjoint from the 1:1 path.
- `lib/features/groups/application/handle_incoming_group_reaction_use_case.dart` — group receive (disjoint).

**Tests (the RED catalog targets + benign fake helper):**
- `test/features/conversation/application/send_reaction_use_case_test.dart` — existing: success `:90-114`, "falls back to inbox" `:116-132`, both-fail `sendFailed` `:154-177`, **source-pin** `:184-193`. Host `FakeP2PService` + `FakeBridge` + `FakeReactionRepository`.
- `test/core/services/fake_p2p_service.dart` — `sendMessage :130-137` (no delay today), `storeInInbox :170-179`, `isConnectedToPeer => false :220`, result fields `sendMessageResult :22` / `storeInInboxResult :26`, counters `sendMessageCallCount :40` / `storeInInboxCallCount :44`, `sentMessageLog :35`. **Benign HEAD-green helpers to add:** `Duration sendMessageDelay = Duration.zero;` (honored at top of `sendMessage`) and `bool isConnectedToPeerResult = false;` (returned by `isConnectedToPeer`) — mirrors FDC-01's benign `discoverDelay`; defaults leave every existing test green.
- `test/features/conversation/application/handle_incoming_reaction_use_case_test.dart` — receive tombstone/staleness preservation (TC-06).
- `test/features/conversation/integration/reaction_roundtrip_test.dart` — two-user `TestUser.sendReaction :274-283`; offline→drain duplicate-delivery (TC-06b).
- `test/features/conversation/integration/emoji_reaction_exchange_test.dart` — already in `ONE_TO_ONE_TESTS:195` (regression floor).

---

## Existing Tests Covering This Area

All exist on `new-orbit`. Unit reaction tests under `test/features/**` auto-glob into `feature-host-all`; `emoji_reaction_exchange_test.dart` is the only reaction file explicitly in `ONE_TO_ONE_TESTS` (line 195).

| Test (file::name) | Exists? | Gate | FDC-18 disposition |
|---|---|---|---|
| `send_reaction_use_case_test.dart::returns success — encrypts, sends, persists locally` (`:90`) | yes | feature-host-all | **Stays green** (live success still persists; now also fires one concurrent inbox copy — asserts `sendMessageCallCount==1`, does not assert inbox count, so unaffected). |
| `…::falls back to inbox when direct send fails` (`:116`, asserts `storeInInboxCallCount==1`) | yes | feature-host-all | **Stays green** — unknown-presence + `sent==false` still yields exactly one `storeInInbox` (now via the concurrent arm). |
| `…::returns sendFailed … when direct send and inbox store both fail` (`:154`) | yes | feature-host-all | **Stays green** — both-fail → `sendFailed`, `saveReactionCallCount==0`, `storeInInboxCallCount==1`. Preserved sentinel (FDC-18-P3). |
| `…::reaction failure never writes a failed messages row (retry-pipeline non-involvement)` source-pin (`:184`) | yes | feature-host-all | **Stays green** — edit adds no `MessageRepository`/`saveMessage`. Preserved sentinel (FDC-18-P2). |
| `handle_incoming_reaction_use_case_test.dart` stale/tombstone group | yes | feature-host-all | **Stays green** — receive path untouched; re-locked under new duplicate pressure (FDC-18-06). |
| `emoji_reaction_exchange_test.dart` exchange/toggle suite | yes | **1to1** (`:195`) | Regression floor (must stay green). |

**Gap:** no test asserts (a) the inbox deposit fires **concurrently** (a `*_CONCURRENT_INBOX_BEGIN` event even on a live-win), (b) a **connected** reaction stays single-path, or (c) idempotency under the new duplicate pressure. FDC-18-01..06 add these.

---

## RED Test Catalog  (BEFORE any prod code)

> Tiers: **unit/application** = `send_reaction_use_case_test.dart` (drives `sendReaction` through `FakeP2PService`/`FakeReactionRepository`/`captureFlowEvents`); **unit/receive** = `handle_incoming_reaction_use_case_test.dart`; **integration** = `reaction_roundtrip_test.dart` (two `TestUser`).
>
> **Distinct-event discriminator (required):** where a live-success and a serial-tail both end "success/custody," the tests assert the **`REACTION_SEND_CONCURRENT_INBOX_BEGIN`** flow-event — present iff the deposit ran **concurrently** (not on the serial `if(!sent)` tail). Mirrors FDC-03's `CHAT_MSG_SEND_CONCURRENT_INBOX_BEGIN`.
>
> **Benign helper prerequisite (HEAD-green):** add `sendMessageDelay`/`isConnectedToPeerResult` to `FakeP2PService` (see Files To Inspect). Defaults (`zero`/`false`) keep every existing test green.

### FDC-18-01 — reaction to a slow/offline peer takes CONCURRENT inbox custody (the FDC-03 core)
- **file::name:** `send_reaction_use_case_test.dart::FDC-18-01 unknown-presence reaction whose live send fails takes concurrent-inbox custody`
- **Tier:** unit/application.
- **Shape/setup:** default `FakeP2PService(isConnectedToPeerResult: false)` (unknown), `sendMessageResult = false`, `storeInInboxResult = true`; wrap in `captureFlowEvents`.
- **RED-on-HEAD-because:** on HEAD the deposit runs only on the **serial** `if(!sent)` tail — `REACTION_SEND_CONCURRENT_INBOX_BEGIN` is never emitted → the BEGIN-event assertion fails.
- **GREEN-asserts:** `result == SendReactionResult.success`; `p2pService.storeInInboxCallCount == 1`; captured events contain `REACTION_SEND_CONCURRENT_INBOX_BEGIN` with `details['messageId'] == 'msg-1'.substring(0, min(8, len))`; `reactionRepo.saveReactionCallCount == 1`.
- **Mutation-that-re-reds (M1):** re-gate the deposit behind the serial `if (!sent)` tail (remove the concurrent arm) → BEGIN absent → RED.
- **Discriminator:** the BEGIN event proves the deposit was parallel, not the late serial tail.

### FDC-18-02 — online peer: live send wins AND a concurrent inbox copy fired (no misroute, deposit is concurrent)
- **file::name:** `send_reaction_use_case_test.dart::FDC-18-02 unknown-presence reaction whose live send WINS still deposits one concurrent inbox copy`
- **Tier:** unit/application.
- **Shape/setup:** default `FakeP2PService(isConnectedToPeerResult: false)`, `sendMessageResult = true`, `..sendMessageDelay = const Duration(milliseconds: 150)` (live leg resolves after the deposit has started), `storeInInboxResult = true`; `captureFlowEvents`.
- **RED-on-HEAD-because:** HEAD deposits **only** when `sent == false`; a live success yields `storeInInboxCallCount == 0` and no BEGIN event.
- **GREEN-asserts:** `result == success`; `p2pService.sendMessageCallCount == 1`; `p2pService.storeInInboxCallCount == 1` (concurrent deposit fired even though live won); events contain `REACTION_SEND_CONCURRENT_INBOX_BEGIN`; terminal event `REACTION_SEND_SUCCESS`. (The 150 ms `sendMessageDelay` makes the concurrency observable: the deposit must have been started before the live result was known, else it would never fire on a live win.)
- **Mutation-that-re-reds (M2):** move the deposit back behind `if (!sent)` → `storeInInboxCallCount == 0` on a live win → RED.
- **Discriminator:** this is the FDC-01-spirit "online peer not demoted to inbox-only" + FDC-03 "concurrent, not serial" lock.

### FDC-18-03 — connected peer stays single-path (preserved sentinel, bounds traffic)
- **file::name:** `send_reaction_use_case_test.dart::FDC-18-03 connected-peer reaction does NOT fire the concurrent inbox`
- **Tier:** unit/application.
- **Shape/setup:** `FakeP2PService(isConnectedToPeerResult: true)`, `sendMessageResult = true`, `storeInInboxResult = true`.
- **RED-on-HEAD-because:** compile/contract RED — `isConnectedToPeerResult` does not exist on HEAD's fake until the benign helper is added; once added, HEAD's serial logic already yields `storeInInboxCallCount == 0` on a live win, so this test is RED **only** if a naive implementation deposits unconditionally. (Authored RED-first against the *intended* unconditional-deposit mistake; it locks the `!isConnectedToPeer` guard.)
- **GREEN-asserts:** `result == success`; `p2pService.storeInInboxCallCount == 0`; no `REACTION_SEND_CONCURRENT_INBOX_BEGIN`.
- **Mutation-that-re-reds (M3):** drop the `!isConnectedToPeer` guard (deposit unconditionally) → `storeInInboxCallCount == 1` for a connected peer → RED.
- **Discriminator:** mirrors FDC-03 invariant 2 (confirmed-path ⇒ single-path).

### FDC-18-04 — exactly one storeInInbox (no concurrent + serial double-write)
- **file::name:** `send_reaction_use_case_test.dart::FDC-18-04 concurrent-custody reaction writes storeInInbox EXACTLY once`
- **Tier:** unit/application.
- **Shape/setup:** unknown presence, `sendMessageResult = false`, `storeInInboxResult = true`; `captureFlowEvents`.
- **RED-on-HEAD-because:** assert `storeInInboxCallCount == 1` **AND** `REACTION_SEND_CONCURRENT_INBOX_BEGIN` present — on HEAD the store happens serially (count 1) but the BEGIN event is absent → RED.
- **GREEN-asserts:** `storeInInboxCallCount == 1`; events contain `REACTION_SEND_CONCURRENT_INBOX_BEGIN`; `result == success`.
- **Mutation-that-re-reds (M4):** remove the "skip the serial fallback when the concurrent deposit already ran" short-circuit → the awaited concurrent future + a fresh serial `storeInInbox` both fire → `storeInInboxCallCount == 2` → RED.

### FDC-18-05 — both legs fail ⇒ `sendFailed`, no local persist (preserved sentinel)
- **file::name:** `send_reaction_use_case_test.dart::FDC-18-05 live send and concurrent inbox both fail returns sendFailed and persists nothing`
- **Tier:** unit/application.
- **Shape/setup:** unknown presence, `sendMessageResult = false`, `storeInInboxResult = false`. (Equivalent to existing `:154-177`; re-stated under the concurrent arm.)
- **RED-on-HEAD-because:** green on HEAD — this is a **preservation lock**; it would only RED if the concurrent rewrite mishandled the both-fail terminal (e.g. swallowed the inbox failure → wrongly returned success).
- **GREEN-asserts:** `result == SendReactionResult.sendFailed`; `reactionRepo.saveReactionCallCount == 0`; `p2pService.storeInInboxCallCount == 1`; `getReactionsForMessage('msg-1')` empty.
- **Mutation-that-re-reds (M5):** return `success` when the concurrent inbox future completes `false` → assertion fails (guards the terminal-result logic).

### FDC-18-06 — receive tombstone last-writer-wins still wins under the new duplicate pressure (receive preserved)
- **file::name:** `handle_incoming_reaction_use_case_test.dart::FDC-18-06 a stale duplicate reaction (older than the current tombstone) is ignored`
- **Tier:** unit/receive.
- **Shape/setup:** seed a removed (tombstoned) reaction at T2; deliver an incoming **add** with an **older** timestamp T1 (the kind of stale duplicate the concurrent inbox now makes more likely). Reuse the existing receive harness.
- **RED-on-HEAD-because:** green on HEAD (receive path is unchanged by FDC-18) — this is the **preservation floor** the brief mandates ("receive tombstone still wins"), pinned explicitly because FDC-18 raises duplicate arrivals.
- **GREEN-asserts:** result `HandleReactionResult.success` with `null` change (stale-ignored); `REACTION_RECEIVE_STALE_IGNORED` emitted; the stored reaction stays tombstoned (no resurrection).
- **Mutation-that-re-reds (M6):** weaken `_isStaleComparedToCurrent` (`:296-307`) to `return false` (never stale) → the older add resurrects the tombstone → assertion fails. (Proves the lock bites the receive idempotency.)

### FDC-18-06b — (integration) offline-peer reaction drains to exactly one row despite a live duplicate
- **file::name:** `reaction_roundtrip_test.dart::FDC-18-06b first-ever offline reaction deposits concurrently and round-trips to exactly one reaction after drain`
- **Tier:** integration (`TestUser` two-user).
- **Shape/setup:** `alice`→`bob`, no prior reaction; `bob` offline; `alice.sendReaction(...)`; capture flow events; `bob` online + drain. (If the two-user fake also delivers a live copy on reconnect, both the live and the drained inbox copies arrive.)
- **RED-on-HEAD-because:** with no concurrent arm, `REACTION_SEND_CONCURRENT_INBOX_BEGIN` never appears for the offline send → the BEGIN assertion fails on HEAD (delivery itself already passes — the RED is specifically about the concurrent deposit).
- **GREEN-asserts:** Alice's send returns `success`; events contain `REACTION_SEND_CONCURRENT_INBOX_BEGIN`; after drain, `bob`'s `getReactionsForMessage(...)` contains **exactly one** reaction (last-writer-wins dedup → no duplicate row).
- **Mutation-that-re-reds (M7):** re-gate the concurrent arm behind the serial tail → BEGIN absent for the offline send → RED.

### Preserved (green-on-HEAD, must STAY green — locked, not RED)
- **FDC-18-P1** existing `…::returns success — encrypts, sends, persists locally` (`:90`) — live success still persists.
- **FDC-18-P2** existing source-pin `…::reaction failure never writes a failed messages row` (`:184`) — no `MessageRepository`/`saveMessage` introduced.
- **FDC-18-P3** existing both-fail `sendFailed` (`:154`) — folded/co-located with FDC-18-05.

---

## Test Coverage Matrix

| Spec case | Behavior props | Tier | Test file::name | RED reason on HEAD | Mutation revert | Acceptance gate cmd | Harness registration |
|---|---|---|---|---|---|---|---|
| Slow/offline reaction → concurrent inbox custody | `storeInInboxCallCount==1`, `CONCURRENT_INBOX_BEGIN`, `success` | unit/app | `send_reaction_use_case_test.dart::FDC-18-01` | deposit only on serial `if(!sent)` → BEGIN absent | M1 re-gate behind serial tail | `./scripts/run_test_gates.sh 1to1` (+ `feature-host-all`) | auto-globs `feature-host-all`; **append file to `ONE_TO_ONE_TESTS`** (recommended) |
| Online peer not demoted; deposit is concurrent | `sendMessageCallCount==1`, `storeInInboxCallCount==1` on live win, `BEGIN` | unit/app | `…::FDC-18-02` | HEAD deposits 0 on live win | M2 move deposit behind `if(!sent)` → 0 | `./scripts/run_test_gates.sh 1to1` | same |
| Connected peer single-path (confirmed ⇒ no deposit) | `storeInInboxCallCount==0`, no `BEGIN` | unit/app | `…::FDC-18-03` | locks `!isConnectedToPeer` guard | M3 drop guard → 1 | `./scripts/run_test_gates.sh 1to1` | same |
| Exactly one relay write (no double-write) | `storeInInboxCallCount==1` + `BEGIN` | unit/app | `…::FDC-18-04` | BEGIN absent (serial) on HEAD | M4 remove serial-skip short-circuit → 2 | `./scripts/run_test_gates.sh 1to1` | same |
| Both fail ⇒ sendFailed, no persist | `sendFailed`, `saveReactionCallCount==0`, store 1 | unit/app | `…::FDC-18-05` | preservation (green) | M5 return success on inbox-false | `./scripts/run_test_gates.sh 1to1` | same |
| Receive tombstone last-writer-wins preserved | stale add ignored, `RECEIVE_STALE_IGNORED`, no resurrection | unit/receive | `handle_incoming_reaction_use_case_test.dart::FDC-18-06` | preservation (green) | M6 weaken `_isStaleComparedToCurrent` → resurrect | `./scripts/run_test_gates.sh 1to1` (+ `feature-host-all`) | auto-globs `feature-host-all`; recommend append |
| Offline reaction → one row after drain (concurrent + dedup) | `BEGIN` present; exactly one reaction post-drain | integration | `reaction_roundtrip_test.dart::FDC-18-06b` | no concurrent arm → BEGIN absent | M7 re-gate concurrent arm | `./scripts/run_test_gates.sh 1to1` (+ `feature-host-all`) | recommend append |
| **PRESERVE** live-success persists | existing `:90` stays green | unit/app | `…::returns success — encrypts, sends, persists locally` | n/a (green) | n/a | `./scripts/run_test_gates.sh 1to1` | existing |
| **PRESERVE** source-pin (no MessageRepository/saveMessage) | existing `:184` stays green | unit/app | `…::reaction failure never writes a failed messages row` | n/a (green) | n/a | `./scripts/run_test_gates.sh 1to1` | existing |
| **GROUP-SAFETY floor** (group reactions untouched) | group reaction suites green | gate | (group reaction tests) | n/a | n/a | `./scripts/run_test_gates.sh groups` | existing |
| **Regression floor** (1:1 + feed + baseline) | full gates green | gate | (all above + existing) | n/a | n/a | `./scripts/run_test_gates.sh 1to1` · `feed` · `baseline` · `./scripts/run_host_test_gates.sh feature-host-all` | n/a |

No empty cells.

---

## Blind-Spot Sweep

- **Lifecycle / derived-state durability.** The concurrent deposit fires for **every unknown-presence reaction** → reaction inbox volume rises (the FDC-03 §9.3 hazard, scaled down — reactions are tiny). New copies land in the **in-memory relay backend** by default (wiped on a relay bounce). **Owner: FDC-10 (Redis)** — flagged here, not fixed. Reactions are smaller and reclaimed within ~30 s (Q3), so the durability-window blast radius is materially smaller than chat's.
- **Sibling-surface consistency (GROUP reactions).** Group reactions use a **separate** use case `sendGroupReaction` (pubsub publish + `GroupReactionReplayOutbox`, **no** `p2pService.sendMessage`/`storeInInbox`) — fully disjoint. **No group-path edit.** Floor: `./scripts/run_test_gates.sh groups`.
- **Destructive-action side-effects.** None. The reaction *remove* (tombstone) path is unrelated; FDC-18 touches only the *send* (`add`) path's transport arm. `removeReaction` and the tombstone comparand are read-only here.
- **Invariant re-verification under the new transition.** "Exactly one relay write" is the invariant most at risk under "deposit now starts before the live result" — re-locked by FDC-18-04 (`==1`, mutation → 2). "Confirmed-path ⇒ single-path" re-locked by FDC-18-03. Receive idempotency under raised duplicate pressure re-locked by FDC-18-06/06b.
- **Optimistic local persist ordering.** Today the sender persists its own reaction at `:131-132` **after** the send block. The rewrite must keep the local persist on **either** committed path (live ack or inbox custody) and **not** persist on the both-fail terminal (FDC-18-05). No reordering that would double-persist (the `saveReaction` stays a single call — asserted `saveReactionCallCount==1` in FDC-18-01).
- **Go bridge concurrency (§10, per FDC-S5).** FDC-S5 found the bridge is **largely concurrent in the warm/steady state** (only `Node.Start`'s cold-path write lock serializes), so the concurrent `storeInInbox` deposit does **not** introduce a blanket head-of-line block on the live `sendMessage`. The residual risk is **native thread-pool / libp2p send-limit contention** under heavy concurrency. FDC-18 still starts the deposit **fire-and-forget** (does not `await` before the live send), mirroring FDC-03; FDC-18-02's `sendMessageDelay` asserts the live leg still completes. Real-resource contention is a device-proof concern (flagged, not host-provable).
- **Source-pin fragility.** The 116-P1.2 pin greps the file text for `MessageRepository`/`saveMessage`. The new arm must use only `storeInInbox`/`sendMessage`/`saveReaction` — verified none of those substrings collide with the forbidden tokens.

---

## Invariants (locked by tests)

1. **Unknown presence ⇒ concurrent durable inbox.** A reaction to a non-connected 1:1 peer fires `storeInInbox` concurrently with the live `sendMessage`. (FDC-18-01/02; integration 06b.)
2. **Online peer not demoted.** The live `sendMessage` is always attempted; an online peer's reaction is delivered live, the inbox copy is a deduped parallel safety net. (FDC-18-02.)
3. **Confirmed-path ⇒ single-path.** A connected-peer reaction fires no concurrent inbox copy. (FDC-18-03.)
4. **Exactly one relay write per reaction.** No concurrent + serial double-write. (FDC-18-04.)
5. **Both-fail ⇒ sendFailed, no persist.** (FDC-18-05.)
6. **Receive last-writer-wins tombstone preserved** under raised duplicate pressure. (FDC-18-06/06b.)
7. **No message-retry-pipeline involvement** (no `MessageRepository`/`saveMessage`). (FDC-18-P2 / `:184`.)

---

## Step-By-Step Implementation Plan  (RED first)

> **Stop-if (sequencing):** FDC-18 lands **after FDC-03** (mirror its reviewed concurrent-inbox pattern; do not diverge). It does **not** edit `send_chat_message_use_case.dart`, so it does not collide with Track A and may run in its own parallel session once FDC-03's pattern is settled. Re-capture the green `1to1` + `feature-host-all` baseline before starting.

1. **RED — author the catalog + benign fake helpers.** Add `sendMessageDelay` (honored at top of `FakeP2PService.sendMessage` via `await Future.delayed(sendMessageDelay)`) and `bool isConnectedToPeerResult = false;` (returned by `isConnectedToPeer`) to `test/core/services/fake_p2p_service.dart`. Add FDC-18-01..05 to `send_reaction_use_case_test.dart`, FDC-18-06 to `handle_incoming_reaction_use_case_test.dart`, FDC-18-06b to `reaction_roundtrip_test.dart`. Run `./scripts/run_test_gates.sh 1to1` + `./scripts/run_host_test_gates.sh feature-host-all`; confirm 01/02/04/06b RED for the stated reasons (03 RED against an unconditional-deposit stub, 05/06 green preservation). **Stop-if:** FDC-18-01 passes on HEAD (means the deposit already fired concurrently — it does not; re-check the BEGIN-event assertion).
2. **GREEN step A — concurrent arm.** In `send_reaction_use_case.dart`, replace the `:104-128` send block. Compute `final unknownPresence = !p2pService.isConnectedToPeer(targetPeerId);`. When `unknownPresence`: emit `REACTION_SEND_CONCURRENT_INBOX_BEGIN` (details `{'messageId': <first 8>}`) and **start** `final inboxFuture = p2pService.storeInInbox(targetPeerId, jsonString);` **without awaiting**, attaching a `.catchError(...)` so a fire-and-forget failure is captured, not unhandled. Then `final sent = await p2pService.sendMessage(targetPeerId, jsonString);`. (Greens FDC-18-01/02; the `messageId` here is the reaction's *target* messageId carried in the envelope — confirm the deposit envelope is the same `jsonString` as the live send so server-side `messageId` dedup + receiver tombstone apply.) **Seam:** the `:104-128` try block only.
3. **GREEN step B — terminal resolution (exactly one write).** After `sent`: if `sent == true`, do **not** await `inboxFuture` (fire-and-forget custody; the receiver dedups) — but ensure its error is swallowed. If `sent == false`: `final stored = unknownPresence ? await inboxFuture : await p2pService.storeInInbox(...)` (the connected edge with `sent==false` is the **only** path that starts a fresh serial deposit — preserving exactly-one); if `!stored` → `sendFailed` (no persist). (Greens FDC-18-03/04/05.) **Seam:** the terminal branch.
4. **GREEN step C — optimistic persist.** Keep the `:131-132` `reactionRepo.saveReaction(reaction)` reachable on **either** committed path (live ack OR inbox custody) and **not** on both-fail. Verify `saveReactionCallCount==1` (FDC-18-01) and `==0` on both-fail (FDC-18-05).
5. **Verify mutations** M1–M7 each re-red exactly its mapped test, then restore.
6. **Harness registration (recommended).** Append `send_reaction_use_case_test.dart`, `handle_incoming_reaction_use_case_test.dart`, `reaction_roundtrip_test.dart` to the `ONE_TO_ONE_TESTS` array in `scripts/run_test_gates.sh` so the headline reaction locks run in the `1to1` gate (they already auto-glob into `feature-host-all`, so coverage is guaranteed either way; this is for headline visibility). **Do not** add any group reaction file.
7. **Run gates** (below) + `flutter analyze` (0 new) + `git diff --check`. **Stop-if:** any existing reaction test or `groups` test regresses.

---

## Risks And Edge Cases

| Risk / edge | Pinned by |
|---|---|
| Reaction inbox-volume ramp before durable backend (§9.3, scaled down) | Cross-plan: **FDC-10 (Redis)**; flagged, not owned. Reactions are tiny + reclaimed ~30 s (Q3). |
| Double-write (concurrent + serial both store) | FDC-18-04 (`==1`; M4 → 2). |
| Blanket dual-write (firing on connected peer) | FDC-18-03 (`==0`; M3 → 1). |
| Online peer wrongly demoted to inbox-only | FDC-18-02 (live `sendMessageCallCount==1` + concurrent copy; receiver dedups). |
| Duplicate reaction corrupts the toggle state | FDC-18-06/06b — receive last-writer-wins tombstone (`_isStaleComparedToCurrent`); M6 proves the lock bites. |
| Unhandled fire-and-forget future on a live-win path | Step 2 `.catchError(...)` on `inboxFuture`; asserted indirectly by no test throwing on FDC-18-02. |
| Bridge resource contention between deposit and live send (§10; FDC-S5: bridge concurrent in warm state, no blanket head-of-line) | Deposit started fire-and-forget (non-blocking), so the live send is never queued on the deposit; FDC-18-02 asserts the live leg still completes in the fake; real thread-pool/send-limit contention → device-proof. |
| Source-pin breakage (MessageRepository/saveMessage substrings) | FDC-18-P2 (`:184`); arm uses only `storeInInbox`/`sendMessage`/`saveReaction`. |

---

## Device/Relay Proof Profile

- **Host-only closes the FDC-18 contract:** the concurrent-arm gate, exactly-one-write, confirmed-path-single-path, both-fail terminal, and receive idempotency are **fully host-testable** (FDC-18-01..06b) — these *are* the closure criteria for the code change. No relay/Go deploy, no migration.
- **Requires sim/device (NOT host-closable):** the proposal's host-fake **false-positive caveat** (§9.1 / FDC-00 host-fake false-positive caveat) applies — a host fake can pass FDC-18-01/06b **via the inbox copy even if the live `sendMessage` never landed**, because both sides dedup. So host-green proves *delivery + concurrent deposit*, **not** that the live leg actually won. **Closure scenario (DEFERRED, not gating):** a two-device 1:1 smoke — react to a slow/offline peer, observe the reaction arrive (live when reachable; inbox-drained when not) with **exactly one** reaction row and the correct toggle state. There is no deterministic way to force "slow-but-reachable" on a sim (shared host mDNS). FDC-18 rides the existing 1:1 reliability scope; it adds no new `classify_path()` case.

---

## Acceptance Gates  (LITERAL — copy/paste)

```
# 1:1 home gate (emoji_reaction_exchange_test.dart lives here; append the 3 reaction files per Step 6)
./scripts/run_test_gates.sh 1to1            # expected: 1226 baseline +6 new locks, 0 fail

# GROUP-SAFETY floor (group reactions use a SEPARATE pubsub use case — must not regress)
./scripts/run_test_gates.sh groups          # expected: 896, 0 fail

# Regression floors
./scripts/run_test_gates.sh feed            # expected: 279, 0 fail
./scripts/run_test_gates.sh baseline        # expected: 112 host, 0 fail

# Host floor (auto-globs the unit reaction tests under test/features/**)
./scripts/run_host_test_gates.sh feature-host-all   # expected: 0 fail
./scripts/run_host_test_gates.sh core-host-all      # expected: 0 fail (fake_p2p_service.dart helper change)

# Hygiene
flutter analyze                             # expected: 0 new
git diff --check                            # expected: clean
```

---

## Known-Failure Interpretation

- Pre-existing `groups` media-upload flakes (`ML-004` / durable-media-upload) and the `ambient_background` Test-Flight-Improv guard are **not** FDC-18 — re-run in isolation. FDC-18 edits no group code and no media code.
- Any NEW failure in a reaction test (`send_reaction_use_case_test.dart`, `handle_incoming_reaction_use_case_test.dart`, `reaction_roundtrip_test.dart`, `emoji_reaction_exchange_test.dart`) is in-scope and gating.

---

## Done Criteria (checkbox)

- [ ] Benign `FakeP2PService.sendMessageDelay` + `isConnectedToPeerResult` added (defaults keep HEAD green).
- [ ] FDC-18-01..05 (send), 06 (receive), 06b (integration) authored RED-first, each RED/green for its stated reason.
- [ ] Concurrent-arm + exactly-one-write + confirmed-path-single-path + both-fail terminal implemented in `send_reaction_use_case.dart` only.
- [ ] M1–M7 each verified to re-red its mapped lock, then restored.
- [ ] Source-pin (`:184`) and live-success (`:90`) stay green; receive path unedited.
- [ ] `1to1` + `groups` + `feed` + `baseline` + `feature-host-all` + `core-host-all` green; `flutter analyze` 0-new; `git diff --check` clean.
- [ ] No edit to any group reaction file or `handle_incoming_reaction_use_case.dart`; no migration.
- [ ] Durability hazard cross-referenced to FDC-10; device/sim proof recorded deferred-not-waived.

---

## Scope Guard  (hard Do-not)

- **Do NOT** edit any production file other than `send_reaction_use_case.dart` (plus the benign `fake_p2p_service.dart` test helper + the named test files + the optional `run_test_gates.sh` array append).
- **Do NOT touch group reactions** — `send_group_reaction_use_case.dart` / `handle_incoming_group_reaction_use_case.dart` and the group reaction replay outbox use a **separate pubsub path**; they are out of scope and must stay byte-identical.
- **Do NOT** edit `handle_incoming_reaction_use_case.dart` (receive tombstone) — FDC-18-06 is a read-only preservation lock.
- **Do NOT** route `sendReaction` through `sendChatMessage` or add a `MessageRepository`/`saveMessage` (breaks the 116-P1.2 source-pin).
- **Do NOT** add a `transport` field/badge to reactions (FDC-13 N/A; `message_reaction.dart` carries none).
- **Do NOT** add a ranked race / per-leg budget / relay probe to the reaction path (single leg; overkill).
- **Do NOT** add presence-based lazy/inbox-first emphasis (FDC-08).
- **Do NOT** change server-side `messageId` dedup (FDC-10/Go own the inbox).
- **Do NOT** run any mutating git/graphify command; no Go/relay deploy; no migration.

---

## Accepted Differences

- **Single transport leg, no race.** Unlike chat (FDC-02), reactions have one `sendMessage` leg, so FDC-18 implements **only** the concurrent-inbox + not-demote wins, not a ranked relay-penalized race. Deliberate (Root Cause).
- **Concurrent deposit fires even on a live-win** (for unknown presence) → an extra deduped reaction copy per unknown-presence reaction. Accepted because reactions are TINY (no media; the §6.2 "recipient cost rises" objection is minimal), IDEMPOTENT on receive (last-writer-wins tombstone drops the duplicate at ~zero cost), and reclaimed within ~30 s (Q3). Bounded further by the `!isConnectedToPeer` single-path guard (FDC-18-03).
- **No reuse of an FDC-03 helper** — FDC-03 extracts none (its logic is inlined in the chat race orchestration); FDC-18 **mirrors the pattern** onto the reaction file's own minimal shape (Design Decision).
- **Local optimistic persist remains a single `saveReaction`** on either committed path; FDC-18 does not add a separate retry/outbox for 1:1 reactions (that is the group path's model, out of scope).

---

## Dependency Impact

- **productionFiles:** `lib/features/conversation/application/send_reaction_use_case.dart` (only).
- **testFiles (+ benign helper):** `test/core/services/fake_p2p_service.dart` (benign `sendMessageDelay`/`isConnectedToPeerResult`), `test/features/conversation/application/send_reaction_use_case_test.dart`, `test/features/conversation/application/handle_incoming_reaction_use_case_test.dart`, `test/features/conversation/integration/reaction_roundtrip_test.dart`; optional `scripts/run_test_gates.sh` `ONE_TO_ONE_TESTS` append.
- **Depends on (land after):** **FDC-03** — to copy the reviewed concurrent-inbox pattern and not diverge. (FDC-01/02 are chat-race-specific and have no reaction analog; FDC-18 does not depend on their code, only on FDC-03's pattern being settled.)
- **NOT in the send-path collision spine:** edits `send_reaction_use_case.dart`, a **different file** from Track A's `send_chat_message_use_case.dart` (FDC-01/02/03/04). **Parallelizable** with Track A — its own one-file mini-track (no shared hot region). The only shared touch is the benign `fake_p2p_service.dart` test helper and the `ONE_TO_ONE_TESTS` array; coordinate (one writer at a time) if co-scheduled with a plan that also edits those.
- **Raises load on:** the relay reaction inbox (volume ramp, scaled down) → **FDC-10 (Redis)** should be live before FDC-18 reaches prod volume (FDC-00 durability-ordering hazard).
- **No migration** (table `message_reactions` exists, migration 016), no schema change, no l10n, no Go/relay deploy, no native build.
- **Group-safety:** group reactions are a disjoint pubsub use case → untouched; `groups` floor in Acceptance Gates.
