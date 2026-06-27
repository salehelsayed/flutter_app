# FDC-18 — 1:1 reaction add+remove send reliability (concurrent durable inbox + no online-peer misroute)  (Modification)

Status: awaiting-review
Spec: Network-Arch/Fast-Direct-Connection-Architecture-Proposal.md (§4.1 "the correctness bug worth fixing on its own"; §6.2 "Staggered ranked race + parallel durable inbox (no window)" / §6.2(b) durable-inbox separate tier) · FDC-00-roadmap.md "Known gaps" reaction scope note (*"Reaction send reliability, if wanted, is a small follow-on (FDC-18) mirroring FDC-01+FDC-03 onto sendReaction."*)

> **Plan-review note (2026-06-27).** This plan was re-grounded against branch `new-orbit` by a verify→refute workflow (5 grounding agents + 3 adversarial critique lenses) plus a direct read of every cited file. The review's verdict, the anchors it corrected, and the scope it expanded are recorded in **Reviewer Findings** at the end. The headline change: FDC-18 now covers **both** reaction-toggle halves — `sendReaction` (add) **and** `removeReaction` (un-react), which is a confirmed structural twin with the identical bug (see Root Cause). All `file:line` below were re-verified against `new-orbit`; line numbers in `p2p_service_impl.dart` and the host fakes are known to drift, so anchors there are given as "verify-by-symbol" with the current value.

---

## Source Of Truth

- **Proposal** §4.1 (online-but-slow peer must not be demoted to the offline inbox) and §6.2 / §6.2(b) (the durable inbox is a **separate tier fired in parallel**, not a late serial fallback).
- **Roadmap** `FDC-00-roadmap.md`:
  - The **reaction scope note**: reactions use `send_reaction_use_case.dart` / `remove_reaction_use_case.dart` → the **thin** `p2pService.sendMessage()` + a manual `storeInInbox()` fallback, **not** `send_chat_message_use_case.dart`, so they inherit **none** of FDC-01/02/03/04's orchestration wins; FDC-18 is the named follow-on "mirroring FDC-01+FDC-03 onto sendReaction"; the FDC-13 'upgraded' badge is **N/A** (reactions carry no transport field).
  - The **group-safety mandate**: the whole epic is **1:1-only**; group messaging must not regress.
  - The **parallel-execution tracks**: only the send-path spine (`send_chat_message_use_case.dart`) is strictly serial; plans in **disjoint file sets** run in parallel.
- **Patterns to mirror** — `FDC-01-direct-timeout-misroute-fix-tdd-plan.md` (don't demote an online peer to the inbox) and `FDC-03-concurrent-durable-inbox-safety-net-tdd-plan.md` (fire `storeInInbox` **concurrently** with the live attempt, deduped on receive, drop the serial tail; "exactly one relay write per message"; "confirmed-path ⇒ single-path"). FDC-03's concurrent-inbox event is literally **`CHAT_MSG_SEND_CONCURRENT_INBOX_BEGIN`** (`send_chat_message_use_case.dart:714`), its gate is `unknownPresence = !isAlreadyConnected && !isLocalPeer && !p2pService.isConnectedToPeer(...)` (`:697-700`), `kLowConfidenceWindow` is **retired** (`:75-78`), and its logic is **inlined** (no reusable helper) — verified, which is why FDC-18 **mirrors** rather than reuses (see Design Decision).
- **`scripts/run_test_gates.sh` wins over prose:** the reaction integration test `emoji_reaction_exchange_test.dart` is in **`OPTIONAL_MANUAL_TESTS`** (`run_test_gates.sh:204`; array header `:198`) — a **manual / non-gated** suite for the *curated* gates, **NOT** in `ONE_TO_ONE_TESTS` (`:17-81`). **However**, because the host gate `feature-host-all` is a *glob* (`run_host_test_gates.sh:167` = `rg --files test/features -g '*_test.dart'`), `emoji_reaction_exchange_test.dart` and every reaction `*_test.dart` under `test/features/**` **DOES auto-run in `feature-host-all`**. So the reaction **regression floor is `feature-host-all` (glob)**, and appending the new locks to `ONE_TO_ONE_TESTS` is **REQUIRED** only if they must also run in the curated `1to1` headline gate. (The unit fake `fake_p2p_service.dart` is a *helper*, not a `*_test.dart`, so it does **not** itself glob into `core-host-all`; it is exercised transitively by every test that imports it.)
- Every `file:line` below was re-verified by Read against branch `new-orbit` (not from memory).

---

## Session Classification

**implementation-ready.** Pure-Dart control-flow change in **two** use-case files (`send_reaction_use_case.dart` + its structural twin `remove_reaction_use_case.dart`); host-fake testable through the existing `FakeP2PService` / `FakeReactionRepository` / `FakeBridge` harness **plus a small per-file flow-event capture helper that must be added** (the reaction test files have no flow-capture today — see Prerequisite P0). No relay/Go deploy. **No migration** — `message_reactions` exists (migration 016) and its `removed_at` tombstone column exists (migration 082). No native build. The real-wire "live-wins / not-dropped" angle carries the same host-fake false-positive risk as FDC-01/03 (proposal §9.1) → device/sim smoke is DEFERRED, not gating (see Device/Relay Proof Profile).

---

## Exact Problem Statement

**What's broken.** Tapping a reaction **on** (add) **or** tapping it **off** (remove) to a **slow or momentarily-unreachable** 1:1 peer is delivered **late or dropped**, while the chat send path now (FDC-01/03) avoids exactly this. Both reaction use cases use the **thin** `p2pService.sendMessage()` and a **serial** inbox fallback:

- **Add** `send_reaction_use_case.dart:106` — `final sent = await p2pService.sendMessage(targetPeerId, jsonString);`; `:107-119` — **only if `sent == false`** does it then `await p2pService.storeInInbox(...)` (a **serial tail**, paid *after* the full live attempt); `:131-132` — optimistic local persist (`saveReaction`) happens *after* the send block returns.
- **Remove** `remove_reaction_use_case.dart:98` — same thin `sendMessage`; `:99-112` — same `if (!sent) storeInInbox` serial tail; `:122-128` — local tombstone delete (`reactionRepo.removeReaction(..., removedAtTimestamp: timestamp)`) *after* the send block.

`sendMessage` (`p2p_service_impl.dart:1973`, verify-by-symbol) is a **single** Go-bridge call (`callP2PMessageSend :1985`) that returns one `bool`. It has **no Dart-level discover→dial→send race, no per-step budget, no relay probe, and no concurrent inbox** — that orchestration lives only in `send_chat_message_use_case.dart`, which neither reaction path calls.

Two consequences for a slow/offline peer (apply equally to add **and** remove):

1. **Late durability (the FDC-03 gap).** The durable inbox copy — the delivery-guarantee tier — is deposited **serially after** the live `sendMessage` returns `false`, so a reaction toggle to an offline peer lands in custody *seconds* later than necessary (and, on a transient bridge hiccup, the deposit is the *only* attempt).
2. **Online-but-slow misroute risk (the FDC-01 spirit).** When `sendMessage` returns `false` for a transient un-ack against an actually-reachable peer, the toggle is demoted to an **inbox-only** late delivery — the receiver only sees it on its next ~30 s inbox drain / push-wake, so the reaction "feels dropped."

**Who feels it.** Anyone tapping (or un-tapping) a reaction on a 1:1 message to a peer who is reachable-via-relay but momentarily slow, or briefly offline (cold-ish open, congested rendezvous). The reaction is the most latency-sensitive micro-interaction (instant visual feedback expected), so the lateness is disproportionately felt — and an asymmetric fix (fast to react, slow to un-react) would itself be a visible bug.

**What must improve (both halves).**
- For an **unknown-presence** 1:1 reaction add **or** remove, fire `storeInInbox` **concurrently** with the live `sendMessage` as a strictly separate durability tier — so an offline/slow peer's toggle holds custody immediately, not on a late serial tail.
- Keep the **live `sendMessage` attempt** so an online peer's toggle is delivered **live**; the concurrent inbox copy is a parallel safety net, deduped on receive — the toggle is **not demoted to inbox-only**.
- Preserve **exactly one** `storeInInbox` per toggle (no concurrent + serial double-write).

**What must stay unchanged → preserved sentinels.**
- **Receive idempotency / last-writer-wins tombstone** is the correctness backstop and is **not touched**. A reaction is a TOGGLE; a stale or duplicate copy is dropped by `_isStaleComparedToCurrent` (`handle_incoming_reaction_use_case.dart:296-307`; called at `:202`; comparand = `removedAt ?? timestamp`, `:206-208`; emits `REACTION_RECEIVE_STALE_IGNORED` `:212`). The new concurrent deposit *raises* the rate of duplicate arrivals (live copy + drained inbox copy, **byte-identical**: same reactionId + timestamp) → this invariant must visibly hold.
- **Confirmed-path ⇒ single-path.** A toggle to an **already-connected** peer (`isConnectedToPeer == true`) keeps a single live path — no concurrent inbox copy (mirrors FDC-03 invariant 2; bounds the extra relay traffic for a tiny, frequently-toggled payload).
- **Both-fail ⇒ `sendFailed`, no local mutation.** When the live send AND the inbox deposit both fail, return `sendFailed` and write **no** reaction row (add: existing `send_reaction_use_case_test.dart:154-177`) / leave the existing reaction in place (remove: existing `remove_reaction_use_case_test.dart:119-154`).
- **No message-retry-pipeline involvement (source pin).** Both files must continue to contain **neither** `MessageRepository` **nor** `saveMessage` — the 116-P1.2 source-pin (`send_reaction_use_case_test.dart:184-193`) asserts this for the add file; FDC-18 must not introduce those tokens in either file (a matching pin is added for the remove file — TC-FDC-18-P2b).
- **No transport badge** (FDC-13 N/A): `MessageReaction` has **no** `transport` field (`message_reaction.dart:6-39`; `==` by `id` `:120-124`) — do **not** add one.
- **Move-feature safety inherited.** `sendMessage` gates on `_allowsAccountNetworkSideEffects('p2p_send_message')` (`p2p_service_impl.dart:1974`) and the inbox path gates on `_allowsAccountNetworkSideEffects('p2p_store_inbox')` (`storeInInboxDetailed :4073`). FDC-18 adds **no new ungated wire primitive** — it only reorders/parallelizes existing gated calls. No new gate needed.

---

## Root Cause (verify→refute confirmed)

**Mechanism (verified by Read, branch `new-orbit`):**

1. **Serial-only deposit (add).** `send_reaction_use_case.dart:104-128`: the single `sendMessage` is awaited first (`:106`); `storeInInbox` runs **only inside `if (!sent)`** (`:107-111`). No concurrent arm, no presence branch — the inbox is a strictly serial last resort. The optimistic `saveReaction` (`:131-132`) runs after.
2. **Serial-only deposit (remove) — the structural twin.** `remove_reaction_use_case.dart:96-120` is a near-exact copy: thin `sendMessage` (`:98`) then `if (!sent) storeInInbox` (`:99-103`), both-fail → `sendFailed` (`:104-111`), local tombstone delete (`:122-128`). **Same single leg, same envelope shape, same imports, same antipattern.** Confirmed by direct read — this is *not* the receive tombstone (that lives in `handle_incoming_reaction_use_case.dart` and is genuinely read-only); it is a live **send** path carrying `action: 'remove'`.
3. **Thin transport, no orchestration.** Both paths call `p2pService.sendMessage` → `p2p_service_impl.dart:1973` thin `callP2PMessageSend` (`:1985`), returning one `bool`. None of FDC-01's per-step budgets / `direct_timeout` probe-eligibility nor FDC-03's concurrent gate exist on this path (those edits are confined to `send_chat_message_use_case.dart`, FDC-00 collision map). So both reaction paths inherit the **R6** late-custody behavior FDC-03 fixed for chat.

**Confirmed (single transport leg — full race is overkill).** Each reaction send has exactly **one** transport leg: `sendMessage`. There is **no** `discoverPeer` / `dialPeer` / `probeRelay` anywhere in either reaction use case (verified — both files import only `P2PService`, `Bridge`, `ReactionRepository`, `ReactionPayload`/`MessageReaction`, and `flow_event_emitter`). Therefore FDC-02's **ranked relay-penalized race** has nothing to rank, and FDC-01's **per-step budget / direct_timeout probe-eligibility** has no per-step cascade to decouple. The transferable wins are **only**: (a) FDC-03's concurrent durable inbox, and (b) FDC-01's *intent* — keep attempting live, don't demote an online peer to inbox-only — achieved here via concurrency, not a probe.

**Refuted / do-NOT-do.**
- *"Route the reaction paths through `sendChatMessage` to inherit FDC-01/02/03."* — **Refuted.** Reactions are a distinct envelope (`ReactionPayload`, not a chat message), write **no** `messages` row, take **no** `MessageRepository`, and have a separate receive use case + last-writer-wins tombstone. Routing through `sendChatMessage` would violate the 116-P1.2 source-pin and the reaction/message separation. (See Design Decision.)
- *"Mirror the full FDC-02 ranked race onto reactions."* — **Refuted as overkill**: one transport leg (above).
- *"Blanket dual-write every reaction (deposit even when connected)."* — **Refuted**: a live-connected peer has a confirmed path; mirror FDC-03's `!isConnectedToPeer` guard so the concurrent inbox fires only for unknown presence.
- *"Add presence-based lazy/inbox-first emphasis."* — Out of scope (FDC-08); FDC-18 treats every non-connected toggle as UNKNOWN → concurrent deposit, exactly as FDC-03 does for chat.
- *"Fix only the add path; remove is read-only."* — **Refuted by direct read** (Root Cause #2): `remove_reaction_use_case.dart` is a live send with the identical bug. Splitting the fix would leave the reaction toggle fast in one direction and slow in the other. (The plan's earlier "remove is read-only" claim conflated the send-remove use case with the receive tombstone — corrected.)

---

## Design Decision — REUSE vs MIRROR  →  **MIRROR (b)**

**Chosen: (b) mirror — add a minimal concurrent-inbox arm directly onto both `send_reaction_use_case.dart` and `remove_reaction_use_case.dart`.** Grounded justification:

1. **FDC-03 extracts no shared helper to reuse.** FDC-03's concurrent-inbox logic is **inlined** into the chat send orchestration — the `unknownPresence` gate (`send_chat_message_use_case.dart:697-700`), the `concurrentInbox` future threaded through the race, the `CHAT_MSG_SEND_CONCURRENT_INBOX_BEGIN`/`_CUSTODY` events. There is **no** standalone, reaction-callable `depositConcurrentInbox(...)` function (verified). Option (a) "reuse if FDC-03 extracts a shared helper" has **no helper to reuse**.
2. **The reaction paths are single-leg and envelope-distinct** (see Root Cause), so the FDC-03 race orchestration would not even fit. The transferable surface is just "start the inbox deposit before awaiting the live result; commit on either; exactly one write."
3. **Reuse via `sendChatMessage` is refuted** (above) — it breaks the reaction/message separation and the 116-P1.2 source-pin.

So FDC-18 **mirrors the FDC-03 *pattern*** (concurrent deposit, byte-identical-envelope dedup on receive, exactly-one-write, confirmed-path-single-path) onto each reaction file's own minimal shape, calibrated down to one transport leg, and applies the **same** edit to both toggle halves so they stay symmetric.

**Dependency framing.** FDC-18 should land **AFTER FDC-03** so it copies the *established, reviewed* concurrent-inbox pattern. But it edits the reaction files — **different files** from Track A's `send_chat_message_use_case.dart` — so it is **NOT** in the strict send-path collision spine and is **parallelizable** with Track A (its own one-mini-track). See Dependency Impact.

---

## Real Scope

**In scope (FDC-18):**
- In **`send_reaction_use_case.dart`** (add) and **`remove_reaction_use_case.dart`** (remove), replace the serial `if (!sent) storeInInbox` tail with a **concurrent durability arm**: for `unknownPresence == !p2pService.isConnectedToPeer(targetPeerId)`, **start** `storeInInbox` (fire-and-forget) **before** awaiting `sendMessage`; emit `REACTION_SEND_CONCURRENT_INBOX_BEGIN` (add) / `REACTION_REMOVE_CONCURRENT_INBOX_BEGIN` (remove) at the start; commit `success` on the live ack **or** the inbox custody; preserve **exactly one** `storeInInbox`.
- For a **connected** peer (`isConnectedToPeer == true`), keep the single live path (no concurrent deposit) in both files.
- Preserve `sendFailed`/no-mutation when both fail; preserve optimistic local persist (`saveReaction`) / local tombstone (`removeReaction`) on success; preserve the source-pin (no `MessageRepository`/`saveMessage`) in both files.
- Lock all of the above with mutation-verified host tests + an offline→drain duplicate-delivery integration assertion (add path) that the receive tombstone still wins.

**Out of scope → owning plan:**
- Ranked relay-penalized race / per-leg budgets for reactions → **N/A** (single leg; FDC-02 has nothing to rank).
- `direct_timeout` per-step probe-eligibility → **N/A** (no Dart-level per-step cascade on `sendMessage`).
- Presence-based lazy/inbox-first emphasis → **FDC-08** (gated FDC-S3).
- Durable Redis inbox backend / relay pool (the inbox-volume durability half) → **FDC-10** (FDC-18 raises reaction inbox volume; flagged, not owned here).
- **Other 1:1 micro-interactions** (delivery/read receipts `send_delivery_receipt_use_case.dart`, delete-for-everyone `delete_message_use_case.dart`) — these use a **different** primitive (`sendMessageWithReply`, which has an ack/reply channel, `send_delivery_receipt_use_case.dart:110`, `delete_message_use_case.dart:225/687/725`), so they have a different reliability profile and are **not** the thin-`sendMessage` twin. **Audited and deliberately deferred** to their own root-cause review (candidate FDC-19) — see Blind-Spot Sweep. No edit here.
- **Group reactions** → separate use case `send_group_reaction_use_case.dart` (pubsub publish via `callGroupPublishReaction :183` + `GroupReactionReplayOutbox`; **never** calls `p2pService.sendMessage`/`storeInInbox`); **untouched** (Scope Guard).
- Any change to `handle_incoming_reaction_use_case.dart` behavior (receive tombstone) — **read-only preserve**, no edit.

---

## Prerequisite P0 — flow-event capture helper (there is none today)

**Required before authoring any RED test that asserts a `*_CONCURRENT_INBOX_BEGIN` event.** The reaction use cases already emit flow events via `emitFlowEvent(...)` (`flow_event_emitter.dart:202`), which forwards to a test sink installed by `debugSetFlowEventSink(...)` (`:38`, backing field `_flowEventTestSink :10`, invoked `:215`). **But the reaction test files have no capture mechanism** — `send_reaction_use_case_test.dart` / `remove_reaction_use_case_test.dart` assert only result codes and call counts; `captureFlowEvents` is **not** a shared importable helper (it is defined per-file: `p2p_service_impl_test.dart:27-54` as `_captureFlowEvents`, `posts_db_helpers_test.dart:68`).

**Action:** add a small local helper to each reaction test file (sink-based is cleanest):

```dart
import 'package:flutter_app/core/utils/flow_event_emitter.dart';

Future<List<Map<String, dynamic>>> _captureFlowEvents(
  Future<void> Function() action,
) async {
  final events = <Map<String, dynamic>>[];
  debugSetFlowEventSink((payload) => events.add(payload));
  try {
    await action();
  } finally {
    debugSetFlowEventSink(null);
  }
  return events;
}
```

Tests then assert e.g. `expect(events.map((e) => e['event']), contains('REACTION_SEND_CONCURRENT_INBOX_BEGIN'))`. (The receive test `handle_incoming_reaction_use_case_test.dart` likewise has no flow assertions today; FDC-18-06 either adds this same helper to assert `REACTION_RECEIVE_STALE_IGNORED`, or asserts behaviorally only — see FDC-18-06.)

---

## Prerequisite P0b — benign fake helpers (HEAD-green; exact code)

Add to the **unit** fake `test/core/services/fake_p2p_service.dart` (NOT the integration fake `test/shared/fakes/fake_p2p_service_integration.dart`, which already has `discoverDelay`/`dialDelay`/`sendDelay` at `:61/:64/:67`). The unit fake has **no** `*Delay` field and `isConnectedToPeer` currently returns `connectedPeers.contains(peerId)` (`:264`), so the override must be explicit:

```dart
// new fields (defaults keep every existing test green)
Duration sendMessageDelay = Duration.zero;
bool isConnectedToPeerResult = false;

// in sendMessage(...) — honor the delay as the FIRST statement (method at :154-160):
Future<bool> sendMessage(String peerId, String message) async {
  if (sendMessageDelay > Duration.zero) await Future.delayed(sendMessageDelay);
  sendMessageCallCount++;          // existing
  // ... existing body ...
}

// change isConnectedToPeer (:264) to honor the override without losing the Set behavior:
@override
bool isConnectedToPeer(String peerId) =>
    isConnectedToPeerResult || connectedPeers.contains(peerId);
```

Defaults (`Duration.zero`, `false`) leave every existing test green (verified: no current test sets either; `connectedPeers` empty by default → `isConnectedToPeer` still false). Mirrors FDC-01's benign delay pattern (which lives in the integration fake).

---

## Files To Inspect Next

**Production (THE edits — two twin files):**
- `lib/features/conversation/application/send_reaction_use_case.dart` — entry `sendReaction :30`; node-running guard `:50`; payload build `:60-70`; v2 encrypt `:72-102`; **send block `:104-128`** (serial `sendMessage :106`, serial inbox `:107-119`); optimistic persist `saveReaction :131-132`; success event `REACTION_SEND_SUCCESS :134-138`. Emits `REACTION_SEND_START/_NODE_NOT_RUNNING/_ENCRYPT_FAILED/_ENCRYPT_ERROR/_FAILED/_SUCCESS`.
- `lib/features/conversation/application/remove_reaction_use_case.dart` — entry `removeReaction :22`; guard `:42`; payload (`action:'remove'`) `:51-62`; encrypt `:64-94`; **send block `:96-120`** (serial `sendMessage :98`, serial inbox `:99-112`); local tombstone `reactionRepo.removeReaction(messageId, senderPeerId, removedAtTimestamp: timestamp) :122-128`; success event `REACTION_REMOVE_SUCCESS :130-137`. Emits `REACTION_REMOVE_START/_NODE_NOT_RUNNING/_ENCRYPT_FAILED/_ENCRYPT_ERROR/_SEND_FAILED/_SUCCESS`.

**Production (dependency-only — NOT edited):**
- `lib/core/services/p2p_service.dart` — `sendMessage(String peerId, String message) :104`, `storeInInbox(String toPeerId, String message, {int? timeoutMs}) :156`, `isConnectedToPeer :185`, `isLocalPeer :195`.
- `lib/core/services/p2p_service_impl.dart` — thin `sendMessage :1973` → `callP2PMessageSend :1985`; move-gate `_allowsAccountNetworkSideEffects('p2p_send_message') :1974`; `storeInInbox`→`storeInInboxDetailed` move-gate `_allowsAccountNetworkSideEffects('p2p_store_inbox') :4073`. *(All `:NN` here drift on `new-orbit`; verify by symbol.)*
- `lib/features/conversation/application/handle_incoming_reaction_use_case.dart` — receive path; staleness `:197-222` (`_isStaleComparedToCurrent :296-307`, comparand `:206-208`, `REACTION_RECEIVE_STALE_IGNORED :212`) (**preserve, do not edit**).
- `lib/features/conversation/domain/models/message_reaction.dart` — model `:6-39`; `removedAt` tombstone comparand `:28-29`; `==` by `id` `:120-124` (no `transport` field → FDC-13 N/A).
- `lib/features/conversation/domain/models/reaction_payload.dart` — `buildEncryptedEnvelope` / `toMessageReaction` / `toInnerJson` (envelope construction; dependency-only).
- `lib/core/database/migrations/016_message_reactions.dart` (creates `message_reactions`) + `082_message_reaction_tombstone.dart` (adds `removed_at`) — both already present ⇒ **no migration needed**.

**Group (verify-disjoint, MUST NOT edit):**
- `lib/features/groups/application/send_group_reaction_use_case.dart` — publishes via `callGroupPublishReaction :183` (pubsub) + stages `GroupReactionReplayOutbox` (`:303/343/355`); it does **not** call `p2pService.sendMessage`/`storeInInbox`. Fully disjoint.
- `lib/features/groups/application/handle_incoming_group_reaction_use_case.dart` — group receive (disjoint).

**Sibling 1:1 micro-interactions (verify-only, OUT of scope — different primitive):**
- `lib/features/conversation/application/send_delivery_receipt_use_case.dart` — `sendMessageWithReply :110` + `storeInInbox :132` (reply-bearing, not thin `sendMessage`).
- `lib/features/conversation/application/delete_message_use_case.dart` — `sendMessageWithReply :225/687/725` + `storeInInbox :357/587` (reply-bearing).

**Tests (the RED catalog targets + helpers):**
- `test/features/conversation/application/send_reaction_use_case_test.dart` — existing: success `:90-114`, "falls back to inbox" `:116-132`, picker-path success `:134-152`, both-fail `sendFailed` `:154-177`, **source-pin** `:184-193`. Host `FakeP2PService` + `FakeBridge` + `FakeReactionRepository`. **No flow capture today** (add P0 helper).
- `test/features/conversation/application/remove_reaction_use_case_test.dart` — existing mirror: nodeNotRunning `:33`, encryptionFailed `:52`, success-deletes-locally (`removeReactionCallCount==1`) `:69-99`, "falls back to inbox" (`storeInInboxCallCount==1`) `:101-117`, both-fail `sendFailed` (keeps row, `removeReactionCallCount==0`) `:119-154`. **No flow capture today** (add P0 helper).
- `test/core/services/fake_p2p_service.dart` — fields `sendMessageResult :22`, `storeInInboxResult :26`, `sentMessageLog :42`, counters `sendMessageCallCount :47`, `storeInInboxCallCount :51`; methods `sendMessage :154-160`, `storeInInbox :205-222`, `isConnectedToPeer :264`, `isLocalPeer :267`. **Benign HEAD-green additions** per Prerequisite P0b.
- `test/features/conversation/domain/repositories/fake_reaction_repository.dart` — `saveReactionCallCount`, `removeReaction :70-75` / `removeReactionCallCount :10`, `getReactionsForMessage`.
- `test/features/conversation/application/handle_incoming_reaction_use_case_test.dart` — receive tombstone/staleness tests (e.g. `:602-721`, `:723-772`); assert behaviorally today (no flow capture) (TC-FDC-18-06).
- `test/features/conversation/integration/reaction_roundtrip_test.dart` — `FakeP2PNetwork` + `TestUser` (`TestUser.sendReaction :274-292`, `setOnline :383`, `drainOfflineInbox :385`); **current test `:63-118` is a straight live send-receive — it does NOT toggle offline/drain** (FDC-18-06b must add that cycle).
- `test/features/conversation/integration/emoji_reaction_exchange_test.dart` — in `OPTIONAL_MANUAL_TESTS:204`; auto-globs into `feature-host-all` (regression floor).

---

## Existing Tests Covering This Area

All exist on `new-orbit`. Every reaction `*_test.dart` under `test/features/**` auto-globs into `feature-host-all` (glob gate). None of them is in `ONE_TO_ONE_TESTS` (the curated `1to1` gate) today.

| Test (file::name) | Exists? | Gate | FDC-18 disposition |
|---|---|---|---|
| `send_reaction_use_case_test.dart::returns success … persists locally` (`:90`) | yes | feature-host-all (glob) | **Stays green** — default presence is unknown (`isConnectedToPeer==false`), so it now ALSO fires one concurrent inbox copy, but the test asserts `sendMessageCallCount==1` and does **not** assert `storeInInboxCallCount`, so it is unaffected. |
| `send_reaction_use_case_test.dart::persists non-preset emoji payloads from the picker path` (`:134`) | yes | feature-host-all (glob) | **Stays green** — same reasoning (asserts send + save counts, not inbox count). |
| `send_reaction_use_case_test.dart::falls back to inbox when direct send fails` (`:116`, asserts `storeInInboxCallCount==1`) | yes | feature-host-all (glob) | **Stays green** — unknown-presence + `sent==false` still yields exactly one `storeInInbox` (now via the concurrent arm). |
| `send_reaction_use_case_test.dart::returns sendFailed … both fail` (`:154`) | yes | feature-host-all (glob) | **Stays green** — both-fail → `sendFailed`, `saveReactionCallCount==0`, `storeInInboxCallCount==1`. Preserved sentinel (FDC-18-05). |
| `send_reaction_use_case_test.dart::reaction failure never writes a failed messages row` source-pin (`:184`) | yes | feature-host-all (glob) | **Stays green** — edit adds no `MessageRepository`/`saveMessage`. Preserved sentinel (FDC-18-P2). |
| `remove_reaction_use_case_test.dart::returns success — encrypts, sends, deletes locally` (`:69`) | yes | feature-host-all (glob) | **Stays green** — asserts `removeReactionCallCount==1`, not inbox count. |
| `remove_reaction_use_case_test.dart::falls back to inbox when direct send fails` (`:101`) | yes | feature-host-all (glob) | **Stays green** — `storeInInboxCallCount==1` via concurrent arm. |
| `remove_reaction_use_case_test.dart::returns sendFailed … both fail` (`:119`) | yes | feature-host-all (glob) | **Stays green** — `sendFailed`, `removeReactionCallCount==0`, row kept. Preserved sentinel (FDC-18-R5). |
| `handle_incoming_reaction_use_case_test.dart` stale/tombstone group (`:602-772`) | yes | feature-host-all (glob) | **Stays green** — receive path untouched; re-locked under new duplicate pressure (FDC-18-06). |
| `emoji_reaction_exchange_test.dart` exchange/toggle suite | yes | **feature-host-all (glob)** + `OPTIONAL_MANUAL_TESTS:204` | Regression floor (must stay green). *(NOT in the `1to1` curated gate.)* |

**Gap:** no test asserts (a) the inbox deposit fires **concurrently** (a `*_CONCURRENT_INBOX_BEGIN` event even on a live-win), (b) a **connected** toggle stays single-path, (c) idempotency under the new duplicate pressure, or (d) any of the above for the **remove** twin. FDC-18-01..06b + FDC-18-R1..R5 add these.

---

## RED Test Catalog  (BEFORE any prod code)

> Tiers: **unit/application (add)** = `send_reaction_use_case_test.dart`; **unit/application (remove)** = `remove_reaction_use_case_test.dart`; **unit/receive** = `handle_incoming_reaction_use_case_test.dart`; **integration** = `reaction_roundtrip_test.dart` (`FakeP2PNetwork` + two `TestUser`).
>
> **Distinct-event discriminator (required):** where a live-success and a serial-tail both end "success/custody," the tests assert the **`REACTION_SEND_CONCURRENT_INBOX_BEGIN`** (add) / **`REACTION_REMOVE_CONCURRENT_INBOX_BEGIN`** (remove) flow-event — present iff the deposit ran **concurrently** (not on the serial `if(!sent)` tail). Mirrors FDC-03's `CHAT_MSG_SEND_CONCURRENT_INBOX_BEGIN`. **Requires Prerequisite P0** (no flow capture exists today).
>
> **Benign helper prerequisite (HEAD-green):** Prerequisite P0b (`sendMessageDelay`/`isConnectedToPeerResult` on the unit fake).

### ADD path

### FDC-18-01 — add to a slow/offline peer takes CONCURRENT inbox custody (the FDC-03 core)
- **file::name:** `send_reaction_use_case_test.dart::FDC-18-01 unknown-presence reaction whose live send fails takes concurrent-inbox custody`
- **Tier:** unit/application (add).
- **Shape/setup:** default `FakeP2PService` (unknown: `isConnectedToPeerResult:false`), `sendMessageResult=false`, `storeInInboxResult=true`; wrap the call in the P0 `_captureFlowEvents`.
- **RED-on-HEAD-because:** on HEAD the deposit runs only on the **serial** `if(!sent)` tail — `REACTION_SEND_CONCURRENT_INBOX_BEGIN` is never emitted → the BEGIN-event assertion fails. *(Also requires P0 to even capture events; without P0 the test cannot be expressed.)*
- **GREEN-asserts:** `result == SendReactionResult.success`; `p2pService.storeInInboxCallCount == 1`; captured events contain `REACTION_SEND_CONCURRENT_INBOX_BEGIN` (details `messageId` = first 8 of `'msg-1'`); `reactionRepo.saveReactionCallCount == 1`.
- **Mutation-that-re-reds (M1):** re-gate the deposit behind the serial `if (!sent)` tail (remove the concurrent arm) → BEGIN absent → RED.

### FDC-18-02 — add: live send WINS AND a concurrent copy fired (no misroute) — **PROD-CRITICAL keystone**
- **file::name:** `send_reaction_use_case_test.dart::FDC-18-02 unknown-presence reaction whose live send WINS still deposits one concurrent inbox copy`
- **Tier:** unit/application (add). **PROD-CRITICAL:** this is the single host test that proves the concurrent arm is *not* behind `if(!sent)` (i.e. fires even on a live win). Treat host-green here as the structural closure criterion for the code change; device/sim (deferred) only confirms the live leg physically lands.
- **Shape/setup:** unknown presence, `sendMessageResult=true`, `..sendMessageDelay = const Duration(milliseconds:150)` (live leg resolves after the deposit has started), `storeInInboxResult=true`; `_captureFlowEvents`.
- **RED-on-HEAD-because:** HEAD deposits **only** when `sent==false`; a live success yields `storeInInboxCallCount==0` and no BEGIN event.
- **GREEN-asserts:** `result==success`; `p2pService.sendMessageCallCount==1`; `p2pService.storeInInboxCallCount==1` (concurrent deposit fired even though live won); `reactionRepo.saveReactionCallCount==1` (persist on either committed path); events contain `REACTION_SEND_CONCURRENT_INBOX_BEGIN`; terminal `REACTION_SEND_SUCCESS`.
- **Mutation-that-re-reds (M2):** move the deposit back behind `if (!sent)` → `storeInInboxCallCount==0` on a live win → RED.

### FDC-18-03 — connected peer stays single-path (mutation-verified guard, not behavioral-RED)
- **file::name:** `send_reaction_use_case_test.dart::FDC-18-03 connected-peer reaction does NOT fire the concurrent inbox`
- **Tier:** unit/application (add).
- **Shape/setup:** `FakeP2PService(...)..isConnectedToPeerResult=true`, `sendMessageResult=true`, `storeInInboxResult=true`.
- **Label (honest framing):** this is a **compile-RED / mutation-verified guard**, *not* a behavioral RED. On HEAD (before P0b) `isConnectedToPeerResult` does not compile; after P0b, HEAD's serial logic already yields `storeInInboxCallCount==0` on a live win, so the test is GREEN unless an implementation deposits unconditionally. Its value is the **mutation** (M3), which proves the `!isConnectedToPeer` guard bites.
- **GREEN-asserts:** `result==success`; `p2pService.storeInInboxCallCount==0`; no `REACTION_SEND_CONCURRENT_INBOX_BEGIN`.
- **Mutation-that-re-reds (M3):** drop the `!isConnectedToPeer` guard (deposit unconditionally) → `storeInInboxCallCount==1` for a connected peer → RED.

### FDC-18-04 — exactly one storeInInbox (no concurrent + serial double-write)
- **file::name:** `send_reaction_use_case_test.dart::FDC-18-04 concurrent-custody reaction writes storeInInbox EXACTLY once`
- **Tier:** unit/application (add).
- **Shape/setup:** unknown presence, `sendMessageResult=false`, `storeInInboxResult=true`; `_captureFlowEvents`.
- **RED-on-HEAD-because:** assert `storeInInboxCallCount==1` **AND** `REACTION_SEND_CONCURRENT_INBOX_BEGIN` present — on HEAD the store happens serially (count 1) but the BEGIN event is absent → RED.
- **GREEN-asserts:** `storeInInboxCallCount==1`; events contain `REACTION_SEND_CONCURRENT_INBOX_BEGIN`; `result==success`.
- **Mutation-that-re-reds (M4):** remove the "await the concurrent future, do NOT start a fresh serial `storeInInbox`" short-circuit → the awaited concurrent future + a fresh serial `storeInInbox` both fire → `storeInInboxCallCount==2` → RED.

### FDC-18-05 — both legs fail ⇒ `sendFailed`, no local persist (preserved sentinel)
- **file::name:** `send_reaction_use_case_test.dart::FDC-18-05 live send and concurrent inbox both fail returns sendFailed and persists nothing`
- **Tier:** unit/application (add).
- **Shape/setup:** unknown presence, `sendMessageResult=false`, `storeInInboxResult=false`. (Equivalent to existing `:154-177`; re-stated under the concurrent arm.)
- **RED-on-HEAD-because:** green on HEAD — **preservation lock**; it would only RED if the concurrent rewrite mishandled the both-fail terminal (e.g. swallowed the inbox failure → wrongly returned success).
- **GREEN-asserts:** `result==SendReactionResult.sendFailed`; `reactionRepo.saveReactionCallCount==0`; `p2pService.storeInInboxCallCount==1`; `getReactionsForMessage('msg-1')` empty.
- **Mutation-that-re-reds (M5):** return `success` when the concurrent inbox future completes `false` → assertion fails.

### REMOVE path (twin — mirrors 01-05 onto `remove_reaction_use_case.dart`)

### FDC-18-R1 — remove to a slow/offline peer takes CONCURRENT inbox custody
- **file::name:** `remove_reaction_use_case_test.dart::FDC-18-R1 unknown-presence reaction REMOVE whose live send fails takes concurrent-inbox custody`
- **Tier:** unit/application (remove).
- **Shape/setup:** pre-seed a reaction to remove (mirror `:69-80`); unknown presence, `sendMessageResult=false`, `storeInInboxResult=true`; `_captureFlowEvents`.
- **RED-on-HEAD-because:** HEAD deposits only on the serial `if(!sent)` tail → `REACTION_REMOVE_CONCURRENT_INBOX_BEGIN` never emitted.
- **GREEN-asserts:** `result==RemoveReactionResult.success`; `storeInInboxCallCount==1`; events contain `REACTION_REMOVE_CONCURRENT_INBOX_BEGIN`; `reactionRepo.removeReactionCallCount==1`; row gone.
- **Mutation-that-re-reds (MR1):** re-gate the deposit behind the serial tail → BEGIN absent → RED.

### FDC-18-R2 — remove: live WINS AND a concurrent copy fired
- **file::name:** `remove_reaction_use_case_test.dart::FDC-18-R2 unknown-presence reaction REMOVE whose live send WINS still deposits one concurrent inbox copy`
- **Tier:** unit/application (remove).
- **Shape/setup:** pre-seed; unknown presence, `sendMessageResult=true`, `sendMessageDelay=150ms`, `storeInInboxResult=true`; `_captureFlowEvents`.
- **RED-on-HEAD-because:** live win on HEAD → `storeInInboxCallCount==0`, no BEGIN.
- **GREEN-asserts:** `result==success`; `sendMessageCallCount==1`; `storeInInboxCallCount==1`; `removeReactionCallCount==1`; events contain `REACTION_REMOVE_CONCURRENT_INBOX_BEGIN`; terminal `REACTION_REMOVE_SUCCESS`.
- **Mutation-that-re-reds (MR2):** move deposit behind `if(!sent)` → 0 on live win → RED.

### FDC-18-R3 — connected peer remove stays single-path (mutation-verified guard)
- **file::name:** `remove_reaction_use_case_test.dart::FDC-18-R3 connected-peer reaction REMOVE does NOT fire the concurrent inbox`
- **Tier:** unit/application (remove). Same compile-RED/mutation-guard framing as FDC-18-03.
- **Shape/setup:** pre-seed; `isConnectedToPeerResult=true`, `sendMessageResult=true`, `storeInInboxResult=true`.
- **GREEN-asserts:** `result==success`; `storeInInboxCallCount==0`; no `REACTION_REMOVE_CONCURRENT_INBOX_BEGIN`.
- **Mutation-that-re-reds (MR3):** drop the `!isConnectedToPeer` guard → `storeInInboxCallCount==1` → RED.

### FDC-18-R4 — remove writes storeInInbox EXACTLY once
- **file::name:** `remove_reaction_use_case_test.dart::FDC-18-R4 concurrent-custody REMOVE writes storeInInbox EXACTLY once`
- **Tier:** unit/application (remove).
- **Shape/setup:** pre-seed; unknown presence, `sendMessageResult=false`, `storeInInboxResult=true`; `_captureFlowEvents`.
- **RED-on-HEAD-because:** assert `storeInInboxCallCount==1` AND `REACTION_REMOVE_CONCURRENT_INBOX_BEGIN` present — BEGIN absent on HEAD → RED.
- **GREEN-asserts:** `storeInInboxCallCount==1`; BEGIN present; `result==success`.
- **Mutation-that-re-reds (MR4):** remove the serial-skip short-circuit → `storeInInboxCallCount==2` → RED.

### FDC-18-R5 — remove both legs fail ⇒ `sendFailed`, no local delete (preserved sentinel)
- **file::name:** `remove_reaction_use_case_test.dart::FDC-18-R5 live send and concurrent inbox both fail returns sendFailed and does not delete locally`
- **Tier:** unit/application (remove).
- **Shape/setup:** pre-seed; unknown presence, `sendMessageResult=false`, `storeInInboxResult=false`. (Equivalent to existing `:119-154`; re-stated under the concurrent arm.)
- **RED-on-HEAD-because:** green on HEAD — **preservation lock** (would RED only if the rewrite swallowed the inbox failure).
- **GREEN-asserts:** `result==RemoveReactionResult.sendFailed`; `reactionRepo.removeReactionCallCount==0`; `storeInInboxCallCount==1`; the pre-seeded reaction row is still present.
- **Mutation-that-re-reds (MR5):** return `success` when the concurrent inbox future completes `false` → RED.

### RECEIVE preservation + integration

### FDC-18-06 — receive tombstone last-writer-wins still wins under the new duplicate pressure (receive preserved)
- **file::name:** `handle_incoming_reaction_use_case_test.dart::FDC-18-06 a stale duplicate reaction (older than the current tombstone) is ignored`
- **Tier:** unit/receive.
- **Shape/setup:** seed a removed (tombstoned) reaction at T2; deliver an incoming **add** with an **older** timestamp T1 (exactly the kind of stale duplicate the concurrent inbox now makes more likely — a drained OLD copy arriving after a remove). Reuse the existing receive harness; optionally add the P0 helper to assert the event.
- **RED-on-HEAD-because:** green on HEAD (receive path is unchanged by FDC-18) — the **preservation floor** the brief mandates ("receive tombstone still wins"), pinned because FDC-18 raises duplicate arrivals.
- **GREEN-asserts:** result has `null` change (stale-ignored); the stored reaction stays tombstoned (no resurrection); **and** (if P0 helper added) events contain `REACTION_RECEIVE_STALE_IGNORED`. *(If you do not add flow capture to this file, assert behaviorally only — `change == null` + no resurrection — and drop the event assertion.)*
- **Mutation-that-re-reds (M6):** weaken `_isStaleComparedToCurrent` (`:296-307`) to `return false` (never stale) → the older add resurrects the tombstone → assertion fails.

### FDC-18-06b — (integration) offline-peer add deposits concurrently and drains to exactly one row
- **file::name:** `reaction_roundtrip_test.dart::FDC-18-06b first-ever offline reaction deposits concurrently and round-trips to exactly one reaction after drain`
- **Tier:** integration (`FakeP2PNetwork` + two `TestUser`).
- **Shape/setup (MUST exercise offline/drain — the current roundtrip test does NOT):** `alice`→`bob`, no prior reaction; **`bob.setOnline(false)`** (`test_user.dart:383`); wrap `alice.sendReaction(bob, 'msg-1', '👍')` in flow capture; then **`bob.setOnline(true); await bob.drainOfflineInbox();`** (`:385`). If the fake net also delivers a live copy on reconnect, both the live and drained inbox copies arrive (byte-identical → receiver idempotent).
- **RED-on-HEAD-because:** with no concurrent arm, `REACTION_SEND_CONCURRENT_INBOX_BEGIN` never appears for the offline send → the BEGIN assertion fails on HEAD. *(Authoring also requires rewriting the test to add the offline/drain cycle — on HEAD the existing `:63-118` test never goes offline, so the scenario is not even exercised.)*
- **GREEN-asserts:** Alice's send returns `success`; events contain `REACTION_SEND_CONCURRENT_INBOX_BEGIN`; after drain, `bob`'s `getReactionsForMessage('msg-1')` contains **exactly one** reaction (byte-identical-dedup → no duplicate row).
- **Mutation-that-re-reds (M7):** re-gate the concurrent arm behind the serial tail → BEGIN absent for the offline send → RED.

### Preserved (green-on-HEAD, must STAY green — locked, not RED)
- **FDC-18-P1** existing add success `:90` + picker-path `:134` — live success still persists.
- **FDC-18-P2** existing add source-pin `:184` — no `MessageRepository`/`saveMessage`.
- **FDC-18-P2b** NEW remove source-pin — add a text-grep test in `remove_reaction_use_case_test.dart` asserting the remove file contains neither `MessageRepository` nor `saveMessage` (mirror of `:184-193`), since FDC-18 now edits that file.
- **FDC-18-P3 / P3b** existing both-fail sentinels (add `:154`, remove `:119`) — folded/co-located with FDC-18-05 / R5.

---

## Test Coverage Matrix

| Spec case | Behavior props | Tier | Test file::name | RED reason on HEAD | Mutation revert | Acceptance gate cmd | Harness registration |
|---|---|---|---|---|---|---|---|
| Add: slow/offline → concurrent custody | `storeInInboxCallCount==1`, `SEND…BEGIN`, success | unit/app (add) | `send_reaction_use_case_test.dart::FDC-18-01` | deposit only on serial `if(!sent)` → BEGIN absent (needs P0) | M1 re-gate behind serial tail | `./scripts/run_host_test_gates.sh feature-host-all` (+ `1to1` if appended) | auto-globs `feature-host-all`; **append to `ONE_TO_ONE_TESTS` for the `1to1` gate** |
| Add: online not demoted; concurrent (**PROD-CRITICAL**) | `sendMessageCallCount==1`, `storeInInboxCallCount==1`, `saveReactionCallCount==1`, BEGIN | unit/app (add) | `…::FDC-18-02` | HEAD deposits 0 on live win | M2 move deposit behind `if(!sent)`→0 | same | same |
| Add: connected single-path | `storeInInboxCallCount==0`, no BEGIN | unit/app (add) | `…::FDC-18-03` | compile-RED/guard (locks `!isConnectedToPeer`) | M3 drop guard→1 | same | same |
| Add: exactly one write | `storeInInboxCallCount==1` + BEGIN | unit/app (add) | `…::FDC-18-04` | BEGIN absent (serial) on HEAD | M4 remove serial-skip→2 | same | same |
| Add: both fail ⇒ sendFailed, no persist | `sendFailed`, `saveReactionCallCount==0`, store 1 | unit/app (add) | `…::FDC-18-05` | preservation (green) | M5 success-on-inbox-false | same | same |
| Remove: slow/offline → concurrent custody | `storeInInboxCallCount==1`, `REMOVE…BEGIN`, `removeReactionCallCount==1` | unit/app (remove) | `remove_reaction_use_case_test.dart::FDC-18-R1` | serial tail → BEGIN absent (needs P0) | MR1 re-gate behind serial tail | `./scripts/run_host_test_gates.sh feature-host-all` (+ `1to1` if appended) | auto-globs `feature-host-all`; **append to `ONE_TO_ONE_TESTS`** |
| Remove: online not demoted; concurrent | `sendMessageCallCount==1`, `storeInInboxCallCount==1`, `removeReactionCallCount==1`, BEGIN | unit/app (remove) | `…::FDC-18-R2` | HEAD deposits 0 on live win | MR2 move behind `if(!sent)`→0 | same | same |
| Remove: connected single-path | `storeInInboxCallCount==0`, no BEGIN | unit/app (remove) | `…::FDC-18-R3` | compile-RED/guard | MR3 drop guard→1 | same | same |
| Remove: exactly one write | `storeInInboxCallCount==1` + BEGIN | unit/app (remove) | `…::FDC-18-R4` | BEGIN absent (serial) | MR4 remove serial-skip→2 | same | same |
| Remove: both fail ⇒ sendFailed, keep row | `sendFailed`, `removeReactionCallCount==0`, row kept, store 1 | unit/app (remove) | `…::FDC-18-R5` | preservation (green) | MR5 success-on-inbox-false | same | same |
| Receive tombstone LWW preserved | stale add ignored, no resurrection (+ `RECEIVE_STALE_IGNORED` if P0) | unit/receive | `handle_incoming_reaction_use_case_test.dart::FDC-18-06` | preservation (green) | M6 weaken `_isStaleComparedToCurrent`→resurrect | `./scripts/run_host_test_gates.sh feature-host-all` | auto-globs `feature-host-all`; append optional |
| Offline add → one row after drain | BEGIN present; exactly one reaction post-drain | integration | `reaction_roundtrip_test.dart::FDC-18-06b` | no concurrent arm → BEGIN absent; **+ test must add offline/drain cycle** | M7 re-gate concurrent arm | `./scripts/run_host_test_gates.sh feature-host-all` (+ `1to1` if appended) | auto-globs `feature-host-all`; **append to `ONE_TO_ONE_TESTS`** |
| Remove source-pin (no MessageRepository/saveMessage) | grep absent in remove file | unit/app (remove) | `remove_reaction_use_case_test.dart::FDC-18-P2b` | n/a (green) | (text-pin) | `./scripts/run_host_test_gates.sh feature-host-all` | auto-globs `feature-host-all` |
| **PRESERVE** add live-success persists | existing `:90`/`:134` green | unit/app (add) | `…::returns success …` | n/a (green) | n/a | feature-host-all | existing |
| **PRESERVE** add source-pin | existing `:184` green | unit/app (add) | `…::reaction failure never writes a failed messages row` | n/a (green) | n/a | feature-host-all | existing |
| **GROUP-SAFETY floor** (group reactions untouched) | group reaction suites green | gate | (group reaction tests) | n/a | n/a | `./scripts/run_test_gates.sh groups` | existing |
| **Regression floor** | full gates green | gate | (all above + existing) | n/a | n/a | `feature-host-all` · `core-host-all` · `groups` · `feed` · `baseline` · (`1to1` after append) | n/a |

No empty cells.

---

## Blind-Spot Sweep

- **Lifecycle / derived-state durability.** No new in-memory derived state (no latch/flag/cached capability) is added — the change is a control-flow reorder of two existing async calls; the durable artifacts (reaction row, tombstone) already round-trip through SQLCipher (migrations 016/082). The concurrent deposit fires for **every unknown-presence toggle** → reaction inbox volume rises (FDC-03 §9.3 hazard, scaled down — reactions are tiny). New copies land in the **in-memory relay backend** by default (wiped on a relay bounce). **Owner: FDC-10 (Redis)** — flagged here, not fixed. Reactions are smaller and reclaimed within ~30 s (Q3), so the durability-window blast radius is materially smaller than chat's.
- **Sibling-surface consistency.** Surveyed all 1:1 micro-interactions:
  - **Reaction REMOVE** (`remove_reaction_use_case.dart`) — the exact thin-`sendMessage`+serial-inbox twin → **now IN SCOPE** (FDC-18-R1..R5). (The prior version of this plan wrongly called this "read-only"; corrected.)
  - **Group reactions** (`send_group_reaction_use_case.dart`) — separate pubsub path (`callGroupPublishReaction` + `GroupReactionReplayOutbox`); **no** `p2pService.sendMessage`/`storeInInbox` → fully disjoint, **no edit**. Floor: `groups` gate.
  - **Delivery/read receipts** (`send_delivery_receipt_use_case.dart`) and **delete-for-everyone** (`delete_message_use_case.dart`) — use `sendMessageWithReply` (an ack/reply-bearing primitive, *not* thin `sendMessage`), so they have a different reliability profile. **Audited and deliberately deferred** to a separate root-cause review (candidate FDC-19); not the reaction twin, no edit here.
- **Destructive-action side-effects.** The reaction REMOVE (tombstone) path is itself a **destructive send** now in scope: FDC-18-R5 asserts the both-fail case does **not** delete locally (row preserved) and FDC-18-R1/R2 assert the success path deletes exactly once (`removeReactionCallCount==1`). The receive tombstone (`handle_incoming_reaction_use_case.dart`) is read-only here and re-locked by FDC-18-06.
- **Invariant re-verification under the new transition.** "Exactly one relay write" (the invariant most at risk under "deposit now starts before the live result") is re-locked by FDC-18-04 / R4 (`==1`, mutation → 2). "Confirmed-path ⇒ single-path" by FDC-18-03 / R3. Receive idempotency under raised duplicate pressure by FDC-18-06 / 06b. **Concurrent add/remove timing:** the realistic hazard introduced by the concurrent deposit is a **drained OLD copy arriving after a newer toggle** (e.g. a drained add(T1) after a remove(T2)); this is dropped by `_isStaleComparedToCurrent` (comparand `removedAt ?? timestamp`) → covered by FDC-18-06. The **exact-duplicate** case (same reactionId+timestamp arriving twice, live + drained) is covered by FDC-18-06b (one row after drain). A genuinely **newer** add after a remove (T3 > T2) resurrecting the reaction is **correct-by-design** (last-writer-wins) and intentionally NOT blocked — so no "remove→newer-add stays removed" lock is added (it would assert incorrect behavior).
- **Optimistic local mutation ordering.** Add persists via `saveReaction` (`:131-132`) and remove deletes via `removeReaction` (`:122-128`), both **after** the send block. The rewrite must keep that mutation on **either** committed path (live ack OR inbox custody) and **not** on the both-fail terminal (FDC-18-05 / R5). The mutation stays a single call — asserted `saveReactionCallCount==1` (FDC-18-01/02) / `removeReactionCallCount==1` (FDC-18-R1/R2).
- **Go bridge concurrency (§10, per FDC-S5).** FDC-S5 found the bridge is **largely concurrent in the warm/steady state** (only `Node.Start`'s cold-path write lock serializes), so the concurrent `storeInInbox` deposit does **not** introduce a blanket head-of-line block on the live `sendMessage`. Residual risk = native thread-pool / libp2p send-limit contention under heavy concurrency. FDC-18 starts the deposit **fire-and-forget** (does not `await` before the live send), mirroring FDC-03; FDC-18-02/R2's `sendMessageDelay` asserts the live leg still completes. Real-resource contention is a device-proof concern (flagged, not host-provable).
- **Source-pin fragility.** The 116-P1.2 pin greps file text for `MessageRepository`/`saveMessage`. The new arm in **both** files must use only `storeInInbox`/`sendMessage`/`saveReaction`/`removeReaction` — none collide with the forbidden tokens. FDC-18-P2 (add) + new FDC-18-P2b (remove) pin this.

---

## Invariants (locked by tests)

1. **Unknown presence ⇒ concurrent durable inbox.** A toggle (add or remove) to a non-connected 1:1 peer fires `storeInInbox` concurrently with the live `sendMessage`. (FDC-18-01/02/R1/R2; integration 06b.)
2. **Online peer not demoted.** The live `sendMessage` is always attempted; an online peer's toggle is delivered live, the inbox copy is a deduped parallel safety net. (FDC-18-02/R2.)
3. **Confirmed-path ⇒ single-path.** A connected-peer toggle fires no concurrent inbox copy. (FDC-18-03/R3.)
4. **Exactly one relay write per toggle.** No concurrent + serial double-write. (FDC-18-04/R4.)
5. **Both-fail ⇒ sendFailed, no local mutation.** (FDC-18-05/R5.)
6. **Receive last-writer-wins tombstone preserved** under raised duplicate pressure; exact-duplicate ⇒ one row. (FDC-18-06/06b.)
7. **No message-retry-pipeline involvement** (no `MessageRepository`/`saveMessage` in either file). (FDC-18-P2 `:184` / FDC-18-P2b.)

---

## Step-By-Step Implementation Plan  (RED first)

> **Stop-if (sequencing):** FDC-18 lands **after FDC-03** (mirror its reviewed concurrent-inbox pattern; do not diverge). It does **not** edit `send_chat_message_use_case.dart`, so it does not collide with Track A and may run in its own parallel session once FDC-03's pattern is settled.

0. **Snapshot the dirty tree.** `git status --short > /tmp/fdc18-dirty-tree.txt` — `new-orbit` is a SHARED tree with concurrent uncommitted work; record the baseline so unrelated changes are not confused with FDC-18 edits or reverted. **Do NOT** run `git checkout`/`stash`/`reset` on shared files. **Re-capture the CURRENT green baselines** (`feature-host-all`, `core-host-all`, and `1to1` if appending) on HEAD before any edit — do NOT trust the historical `1226`/`896`/`279`/`112` numbers (the `1to1` floor is the stale FDC-S0 baseline; sibling FDC plans already reference higher counts).
1. **RED — prerequisites + catalog.** (a) Add the P0 `_captureFlowEvents` helper to `send_reaction_use_case_test.dart`, `remove_reaction_use_case_test.dart`, and (if asserting the event) `handle_incoming_reaction_use_case_test.dart`. (b) Add the P0b benign fake fields to `test/core/services/fake_p2p_service.dart`. (c) Author FDC-18-01..05 (add), R1..R5 (remove), 06 (receive), P2b (remove source-pin), and rewrite/author 06b (integration, **adding the offline/drain cycle**). Run the focused gates; confirm 01/02/04/06b + R1/R2/R4 RED for the stated reasons (03/R3 are compile-RED/mutation guards; 05/R5/06/P2b green preservation). **Stop-if:** FDC-18-01 passes on HEAD (means the deposit already fired concurrently — it does not; re-check the BEGIN-event assertion and that P0 is wired).
2. **GREEN step A — concurrent arm (apply identically to both files).** Replace the send block (`send_reaction_use_case.dart:104-128`; `remove_reaction_use_case.dart:96-120`). Compute `final unknownPresence = !p2pService.isConnectedToPeer(targetPeerId);`. When `unknownPresence`: emit the BEGIN event (`REACTION_SEND_CONCURRENT_INBOX_BEGIN` / `REACTION_REMOVE_CONCURRENT_INBOX_BEGIN`, details `{'messageId': <first 8 of messageId>}`) and **start** `final inboxFuture = p2pService.storeInInbox(targetPeerId, jsonString).catchError((_) => false);` **without awaiting** (fire-and-forget; the `.catchError((_) => false)` keeps the future from going unhandled — reactions record no transport metrics, so no `.then(...)` wrapper). The `jsonString` deposited is the **same** encrypted envelope as the live send (so the drained copy is byte-identical → receiver dedups).
3. **GREEN step B — terminal resolution (exactly one write; trace all four cases).** After starting the optional `inboxFuture`, `bool sent; try { sent = await p2pService.sendMessage(targetPeerId, jsonString); } catch (_) { sent = false; }`. Then:
   - **(1) unknownPresence=true, sent=true** → live win; do **not** await `inboxFuture` (background custody, deduped on receive); `delivered=true`. → `storeInInboxCallCount==1`. (FDC-18-02/R2)
   - **(2) unknownPresence=true, sent=false** → `final delivered = await inboxFuture!;` — the SAME concurrent deposit, **no fresh `storeInInbox`**. → count 1. (FDC-18-01/04/R1/R4)
   - **(3) unknownPresence=false, sent=true** → no inbox at all; `delivered=true`. → count 0. (FDC-18-03/R3)
   - **(4) unknownPresence=false, sent=false** → the **only** path that starts a fresh serial `final delivered = await p2pService.storeInInbox(...)`. → count 1 (preserves exactly-one for the connected-but-failed edge).
   If `!delivered` → emit the FAILED event and return `sendFailed` (**no** local mutation). (FDC-18-05/R5; M4/MR4 → count 2 if the short-circuit in case 2 is removed.) *(On a live **throw** with `unknownPresence`, case 2 still honors the concurrent `inboxFuture`; with a connected peer, a throw → `sendFailed` with no fresh deposit, matching today's catch behavior.)*
4. **GREEN step C — optimistic local mutation.** Keep `reactionRepo.saveReaction(reaction)` (add `:131-132`) / `reactionRepo.removeReaction(messageId, senderPeerId, removedAtTimestamp: timestamp)` (remove `:122-128`) reachable on **either** committed path and **not** on both-fail. Verify `saveReactionCallCount==1` / `removeReactionCallCount==1` on success and `==0` on both-fail.
5. **Verify mutations** M1–M7 + MR1–MR5 + M3/MR3 (guard) each re-red exactly their mapped test, then restore.
6. **Harness registration (REQUIRED for the `1to1` gate; coverage otherwise via `feature-host-all` glob).** Append `send_reaction_use_case_test.dart`, `remove_reaction_use_case_test.dart`, `handle_incoming_reaction_use_case_test.dart`, and `reaction_roundtrip_test.dart` to the `ONE_TO_ONE_TESTS` array in `scripts/run_test_gates.sh` (lines 17-81) so the headline reaction locks run in the curated `1to1` gate. They already auto-glob into `feature-host-all`, so the locks run regardless; the append is what makes them count toward the `1to1` headline gate. **Do NOT** add `emoji_reaction_exchange_test.dart` (leave it in `OPTIONAL_MANUAL_TESTS`) and **do NOT** add any group reaction file.
7. **Run gates** (below) + `flutter analyze` (0 new) + `git diff --check`. **Stop-if:** any existing reaction test or `groups` test regresses.

---

## Risks And Edge Cases

| Risk / edge | Pinned by |
|---|---|
| Reaction inbox-volume ramp before durable backend (§9.3, scaled down; now doubled by remove) | Cross-plan: **FDC-10 (Redis)**; flagged, not owned. Reactions are tiny + reclaimed ~30 s (Q3). |
| Double-write (concurrent + serial both store) | FDC-18-04 / R4 (`==1`; M4/MR4 → 2). |
| Blanket dual-write (firing on connected peer) | FDC-18-03 / R3 (`==0`; M3/MR3 → 1). |
| Online peer wrongly demoted to inbox-only | FDC-18-02 / R2 (live `sendMessageCallCount==1` + concurrent copy; receiver dedups). |
| Duplicate reaction corrupts the toggle state | FDC-18-06/06b — receiver last-writer-wins tombstone (`_isStaleComparedToCurrent`); M6 proves the lock bites. Dedup is **receiver-side** (byte-identical envelopes), NOT relay-side messageId dedup — no Go/relay change. |
| Unhandled fire-and-forget future on a live-win path | Step 2 `.catchError((_) => false)` on `inboxFuture`; asserted indirectly by no test throwing on FDC-18-02/R2. |
| Asymmetric toggle (add fixed, remove slow) | Remove twin now IN SCOPE (FDC-18-R1..R5). |
| Bridge resource contention between deposit and live send (§10; FDC-S5: bridge concurrent in warm state) | Deposit started fire-and-forget (non-blocking); FDC-18-02/R2 assert the live leg still completes in the fake; real thread-pool/send-limit contention → device-proof. |
| Source-pin breakage (MessageRepository/saveMessage substrings) | FDC-18-P2 (`:184`, add) + FDC-18-P2b (remove); both arms use only `storeInInbox`/`sendMessage`/`saveReaction`/`removeReaction`. |
| FDC-18-06b not actually exercising offline/drain (current roundtrip test is straight send-receive) | Step 1c REQUIRES adding `bob.setOnline(false)`→send→`setOnline(true)`→`drainOfflineInbox()`; M7 re-reds. |

---

## Device/Relay Proof Profile

- **Host-only closes the FDC-18 contract:** the concurrent-arm gate, exactly-one-write, confirmed-path-single-path, both-fail terminal, and receive idempotency are **fully host-testable** (FDC-18-01..06b + R1..R5) — these *are* the closure criteria for the code change. **Keystone host tests: FDC-18-02 and FDC-18-R2** (PROD-CRITICAL) — they prove the concurrent arm fires even on a live win (the 150 ms `sendMessageDelay` makes the race observable), ruling out a naive serial implementation. No relay/Go deploy, no migration.
- **Requires sim/device (NOT host-closable):** the proposal's host-fake **false-positive caveat** (§9.1 / FDC-00) applies — a host fake can pass FDC-18-01/06b **via the inbox copy even if the live `sendMessage` never landed**, because both sides dedup. So host-green proves *delivery + concurrent deposit*, **not** that the live leg actually won. **Closure scenario (DEFERRED, not gating):** a two-device 1:1 smoke — react AND un-react to a slow/offline peer, observe each arrive (live when reachable; inbox-drained when not) with **exactly one** reaction row and the correct toggle state. There is no deterministic way to force "slow-but-reachable" on a sim (shared host mDNS). FDC-18 rides the existing 1:1 reliability scope; it adds no new `classify_path()` case.

---

## Acceptance Gates  (LITERAL — copy/paste)

```
# Re-capture CURRENT baselines on HEAD BEFORE editing (do NOT trust the historical numbers below;
# 1226 is the stale FDC-S0 floor — sibling FDC locks already pushed the real 1to1 count higher).

# Host floor — the TRUE reaction regression floor (globs every reaction *_test.dart under test/features/**)
./scripts/run_host_test_gates.sh feature-host-all   # expected: current baseline + new reaction locks, 0 fail
./scripts/run_host_test_gates.sh core-host-all      # expected: current baseline, 0 fail (fake_p2p_service.dart helper change exercised transitively)

# 1:1 headline gate (only meaningful AFTER appending the reaction files to ONE_TO_ONE_TESTS per Step 6)
./scripts/run_test_gates.sh 1to1            # expected: <re-captured baseline> + (added reaction files), 0 fail

# GROUP-SAFETY floor (group reactions use a SEPARATE pubsub use case — must not regress)
./scripts/run_test_gates.sh groups          # expected: <re-captured baseline>, 0 fail

# Regression floors
./scripts/run_test_gates.sh feed            # expected: <re-captured baseline>, 0 fail
./scripts/run_test_gates.sh baseline        # expected: <re-captured baseline>, 0 fail

# Focused (fast iteration during RED/GREEN)
flutter test test/features/conversation/application/send_reaction_use_case_test.dart
flutter test test/features/conversation/application/remove_reaction_use_case_test.dart
flutter test test/features/conversation/application/handle_incoming_reaction_use_case_test.dart
flutter test test/features/conversation/integration/reaction_roundtrip_test.dart

# Hygiene
flutter analyze                             # expected: 0 new
git diff --check                            # expected: clean
```

---

## Known-Failure Interpretation

- Pre-existing `groups` media-upload flakes (`ML-004` / durable-media-upload) and the `ambient_background` Test-Flight-Improv guard are **not** FDC-18 — re-run in isolation. FDC-18 edits no group code and no media code.
- The branch-wide cold-start `sinceProcessStartMs` privacy-allowlist failure (FDC-S0/S1) is **pre-existing**, not FDC-18.
- Any NEW failure in a reaction test (`send_reaction_use_case_test.dart`, `remove_reaction_use_case_test.dart`, `handle_incoming_reaction_use_case_test.dart`, `reaction_roundtrip_test.dart`, `emoji_reaction_exchange_test.dart`) is in-scope and gating.

---

## Done Criteria (checkbox)

- [ ] Dirty-tree snapshot recorded; current baselines re-captured on HEAD (no `git checkout` on shared files).
- [ ] P0 `_captureFlowEvents` helper added to each reaction test file that asserts a flow event.
- [ ] P0b benign `FakeP2PService.sendMessageDelay` + `isConnectedToPeerResult` added with explicit honor/override (defaults keep HEAD green).
- [ ] FDC-18-01..05 (add), R1..R5 (remove), 06 (receive), 06b (integration w/ offline+drain), P2b (remove source-pin) authored RED-first, each RED/green for its stated reason.
- [ ] Concurrent-arm + exactly-one-write + confirmed-path-single-path + both-fail terminal implemented **identically** in `send_reaction_use_case.dart` AND `remove_reaction_use_case.dart`.
- [ ] M1–M7 + MR1–MR5 + M3/MR3 each verified to re-red their mapped lock, then restored.
- [ ] Add source-pin (`:184`) + new remove source-pin stay green; receive path unedited.
- [ ] `feature-host-all` + `core-host-all` + `groups` + `feed` + `baseline` green; `1to1` green after the ONE_TO_ONE_TESTS append; `flutter analyze` 0-new; `git diff --check` clean.
- [ ] No edit to any group reaction file or `handle_incoming_reaction_use_case.dart`; no migration.
- [ ] Durability hazard cross-referenced to FDC-10; sibling micro-interactions (receipts/delete) deferred-noted; device/sim proof recorded deferred-not-waived.

---

## Scope Guard  (hard Do-not)

- **Do NOT** edit any production file other than `send_reaction_use_case.dart` and `remove_reaction_use_case.dart` (plus the benign `fake_p2p_service.dart` test helper + the named test files + the `run_test_gates.sh` array append).
- **Do NOT touch group reactions** — `send_group_reaction_use_case.dart` / `handle_incoming_group_reaction_use_case.dart` and the group reaction replay outbox use a **separate pubsub path**; out of scope, must stay byte-identical.
- **Do NOT** edit `handle_incoming_reaction_use_case.dart` (receive tombstone) — FDC-18-06 is a read-only preservation lock.
- **Do NOT** edit the receipt/delete micro-interaction paths (`send_delivery_receipt_use_case.dart`, `delete_message_use_case.dart`) — different primitive (`sendMessageWithReply`), deferred to a separate review (FDC-19 candidate).
- **Do NOT** route the reaction paths through `sendChatMessage` or add a `MessageRepository`/`saveMessage` (breaks the 116-P1.2 source-pin).
- **Do NOT** add a `transport` field/badge to reactions (FDC-13 N/A; `message_reaction.dart` carries none).
- **Do NOT** add a ranked race / per-leg budget / relay probe to the reaction paths (single leg; overkill).
- **Do NOT** add presence-based lazy/inbox-first emphasis (FDC-08).
- **Do NOT** rely on or change server-side `messageId` dedup — dedup is **receiver-side** (byte-identical envelopes via `_isStaleComparedToCurrent`). FDC-10/Go own the inbox backend.
- **Do NOT** run any mutating git/graphify command; no Go/relay deploy; no migration.

---

## Accepted Differences

- **Single transport leg, no race.** Unlike chat (FDC-02), reactions have one `sendMessage` leg, so FDC-18 implements **only** the concurrent-inbox + not-demote wins, not a ranked relay-penalized race. Deliberate (Root Cause).
- **Concurrent deposit fires even on a live-win** (for unknown presence) → an extra **byte-identical** reaction copy per unknown-presence toggle. Accepted because reactions are TINY (no media; the §6.2 "recipient cost rises" objection is minimal), IDEMPOTENT on receive (same reactionId+timestamp → dropped/no-op at ~zero cost), and reclaimed within ~30 s (Q3). Bounded by the `!isConnectedToPeer` single-path guard (FDC-18-03/R3). Dedup is **receiver-side**, not relay-side.
- **No reuse of an FDC-03 helper** — FDC-03 extracts none (its logic is inlined in the chat race orchestration); FDC-18 **mirrors the pattern** onto each reaction file's own minimal shape (Design Decision).
- **Add + remove fixed together** — the toggle is symmetric. Other 1:1 micro-interactions (receipts, delete-for-everyone) use a different primitive and are deferred (Blind-Spot Sweep), not silently ignored.
- **Local optimistic mutation remains a single `saveReaction`/`removeReaction`** on either committed path; FDC-18 does not add a separate retry/outbox for 1:1 reactions (that is the group path's model, out of scope).

---

## Dependency Impact

- **productionFiles:** `lib/features/conversation/application/send_reaction_use_case.dart`, `lib/features/conversation/application/remove_reaction_use_case.dart`.
- **testFiles (+ benign helper):** `test/core/services/fake_p2p_service.dart` (benign `sendMessageDelay`/`isConnectedToPeerResult`), `test/features/conversation/application/send_reaction_use_case_test.dart`, `test/features/conversation/application/remove_reaction_use_case_test.dart`, `test/features/conversation/application/handle_incoming_reaction_use_case_test.dart`, `test/features/conversation/integration/reaction_roundtrip_test.dart`; `scripts/run_test_gates.sh` `ONE_TO_ONE_TESTS` append.
- **Depends on (land after):** **FDC-03** — to copy the reviewed concurrent-inbox pattern and not diverge. (FDC-01/02 are chat-race-specific and have no reaction analog.)
- **NOT in the send-path collision spine:** edits the reaction files, **different** from Track A's `send_chat_message_use_case.dart`. **Parallelizable** with Track A. The only shared touch is the benign `fake_p2p_service.dart` test helper and the `ONE_TO_ONE_TESTS` array; coordinate (one writer at a time) if co-scheduled with a plan that also edits those.
- **Raises load on:** the relay reaction inbox (volume ramp, now ×2 for add+remove) → **FDC-10 (Redis)** should be live before FDC-18 reaches prod volume (FDC-00 durability-ordering hazard).
- **No migration** (table `message_reactions` migration 016; `removed_at` migration 082), no schema change, no l10n, no Go/relay deploy, no native build.
- **Group-safety:** group reactions are a disjoint pubsub use case → untouched; `groups` floor in Acceptance Gates.

---

## Reviewer Findings  (verify→refute, 2026-06-27 — branch `new-orbit`)

Vehicle: a Workflow with 5 grounding agents (production send path; tests + fakes; harness/gates; FDC-03 + receive + model + migration; P2P service + group disjointness) and 3 adversarial critique lenses (facts/contradictions; design feasibility; coverage/blind-spots), plus a direct main-loop read of every cited file. Verdict on the **pre-review** draft: **not yet sufficient — 3-4 blockers + several majors**. All are addressed in this revision.

**Blockers fixed:**
1. **Flow-event capture harness did not exist** in the reaction test files (the draft assumed an importable `captureFlowEvents`). The use cases *do* emit via `emitFlowEvent`→`debugSetFlowEventSink` (`flow_event_emitter.dart:38`), but capture is per-file. → Added **Prerequisite P0** (local helper).
2. **`remove_reaction_use_case.dart` is a structural twin with the identical bug**, wrongly dismissed as "read-only" in the draft's blind-spot sweep. → **Expanded scope** to both toggle halves (FDC-18-R1..R5, `REACTION_REMOVE_CONCURRENT_INBOX_BEGIN`).
3. **`emoji_reaction_exchange_test.dart` gate contradiction** — it is in `OPTIONAL_MANUAL_TESTS:204` and auto-globs into `feature-host-all`, **not** `ONE_TO_ONE_TESTS`. → Corrected throughout; reframed the regression floor as `feature-host-all` and the `ONE_TO_ONE_TESTS` append as REQUIRED for the `1to1` gate.
4. **`reaction_roundtrip_test.dart` never toggles offline/drain** (`:63-118` straight send-receive); helpers exist unused (`setOnline:383`, `drainOfflineInbox:385`). → FDC-18-06b now REQUIRES adding the offline/drain cycle.

**Majors fixed:** stale anchors corrected (fake fields `:47/:51`, methods `:154-160`/`:205-222`/`:264`; impl `sendMessage:1973`/gate`:1974`/`storeInInbox` gate `'p2p_store_inbox':4073`; interface `:185/:195`); benign-fake spec made explicit (`isConnectedToPeer` honors an override, not a hardcoded false; `*Delay` lives in the *integration* fake); exactly-once terminal flow traced for all four cases; dedup model clarified as **receiver-side** (byte-identical envelopes), not relay-side; FDC-18-03/R3 relabeled honestly as compile-RED/mutation guards; FDC-18-02/R2 named PROD-CRITICAL; baseline `1226` flagged stale (re-capture on HEAD); dirty-tree snapshot + remove source-pin (P2b) added.

**Refuted / deliberately NOT planned:** (a) a "remove→**newer**-add stays removed" lock — would assert *incorrect* behavior (a genuinely newer add must resurrect under last-writer-wins); the realistic concurrent hazard (drained **old** add after a remove) is covered by FDC-18-06 and exact-duplicate by 06b. (b) Fixing receipts/delete-for-everyone here — they use the reply-bearing `sendMessageWithReply`, a different primitive, deferred to an FDC-19 candidate. (c) Routing reactions through `sendChatMessage` — breaks the source-pin and reaction/message separation.

**Confirmed accurate in the draft (no change needed):** every production reaction-file anchor (`:30/:50/:60-70/:72-102/:104-128/:131-132/:134-138`); FDC-03 event name and gate; the receive `REACTION_RECEIVE_STALE_IGNORED:212` + `_isStaleComparedToCurrent:296-307` + comparand `:206-208`; the model has no `transport` field; group reactions are disjoint; no migration needed.
