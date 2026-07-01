# 184 - Optimistic 2-tick send-status progression for 1:1 messages  (Feature — Spec)

Status: awaiting-review (spec only — problem + current state + test cases; no solution design).

Relation to earlier work:
- Builds on the (uncommitted) **clock→tick** change already in the working tree (`pending`/`sending` → single tick `Icons.done_rounded`).
- Reverses part of **155** (the deliberate two-tick `done_all` retirement) — flagged below as an explicit decision.

---

## Problem Statement

A 1:1 send confirms its status **late** and **all at once**, even though the message is durably safe almost immediately.

- The message is inserted **optimistically** at `status:'sending'` on tap and shows a **single tick** (`conversation_wired.dart:2144-2162`). Good — instant feedback. But that tick is *purely optimistic*: it's drawn before anything is confirmed (it flips to an error only if the whole send later fails).
- The **durable inbox copy ACKs at ~110 ms** (the concurrent `storeInInbox`), but that ACK currently **only records a transport metric** — it does **not** update the message status (`send_chat_message_use_case.dart:733-736`).
- The visible status therefore changes **once, at the very end**, when the entire live race resolves: `'delivered'` (live ack), `'inboxed'` (custody), `'sent'` (best-effort), or `'failed'` — written via `saveMessage` at `send_chat_message_use_case.dart:2087/2112/1112/1119`. That's ~150–350 ms for a live peer and **~1.8 s for an offline peer**.

So between tap and the final status there is a long stretch where the bubble shows only an optimistic single tick with **no honest "the system actually has it" milestone** — and for an offline peer the single tick sits unchanged for ~1.8 s before the inbox glyph appears.

**What must improve:** give the user a **progressive, honest** confirmation that *feels* instant:

```
tap            → 1 tick   (sending — optimistic, "on its way")          [EXISTS]
~110 ms        → 2 ticks  (relay/inbox confirmed custody — "it's safe") [NEW]
live delivery  → transport glyph (wifi / direct — "delivered live")     [EXISTS as the reached glyph]
true failure   → error glyph                                            [EXISTS]
```

The **2-tick** is the new, honest milestone: the first point at which the system *confirms* it has the message (the ~110 ms relay custody ACK), distinct from the optimistic single tick. For an **offline** peer the bubble simply **rests at 2 ticks** (custody secured) instead of spinning until the ~1.8 s race timeout.

---

## Impact Analysis

| Dimension | Detail |
|---|---|
| Severity | Perceived-speed + send-truthfulness (UX), no delivery/data change. |
| Frequency | Every 1:1 outgoing send. |
| User-visible | Sends *feel* instant and show an honest custody confirmation at ~110 ms instead of a single optimistic tick held until the race resolves (~1.8 s offline). |
| Truthfulness | Restores a confirmed milestone on top of the optimistic tick (cf. the 114–116 send-truthfulness program). |
| Platforms | iOS + Android (UI + send-flow, shared Dart). |

---

## Current State (verified, file:line)

### Status model + optimistic insert
- `ConversationMessage.status` (String) — `lib/features/conversation/domain/models/conversation_message.dart:23-25`; `copyWith` `:162`.
- **Optimistic insert exists:** tap creates `ConversationMessage(status:'sending')` and upserts it into the list + DB *before* the network call — `conversation_wired.dart:2144-2165`; the send fires later at `:2410`.
- Statuses the 1:1 send path actually writes: `'sending'` (start, `conversation_wired.dart:2150`) → terminal `'delivered'` (live ack, `send_chat_message_use_case.dart:2087`) / `'inboxed'` (custody, `:2112/:2141/:1112`) / `'sent'` (best-effort, `:2169/:1158`) / `'failed'` (`:1276/:1307`). (`'queued'` is telemetry-only; `'pending'`/`'send_failed'` are other flows.)

### The ~110 ms ACK does NOT update status today
- Concurrent durable inbox: `send_chat_message_use_case.dart:717-737`. Its `.then((ok){...})` at **`:733-736`** does **only** `transportMetrics?.recordAttempt(leg:'inbox')` — no `saveMessage`, no status change. **This is the exact resolve point a 2-tick status bump would hook.**
- Status is written only at the terminal `saveMessage` (`_persistOutgoingSendResult` `:2012`, `persistInboxAccepted` `:1119`).

### Icon mapping (the glyphs)
- `lib/features/conversation/presentation/widgets/letter_card.dart`: `_transportIcon` `:1037-1057` (`wifi`/`local`→`Icons.wifi`; `direct`/`reuse`→`device_hub`; `relay`→`cell_tower`; `inbox`→`Icons.inbox`); `_statusIcon` `:1059-1079`; `_resolvedStatusIcon` `:1131-1143` (the 1:1 path, used when `transportStatusGlyph==true`).
- `pending`/`sending` → `Icons.done_rounded` (single tick — the just-applied clock→tick change, `:1075/:1136`).
- **Two-tick `done_all` is RETIRED** (`:1062-1064` "kept in the model for future debug/read-receipt reuse"). Today's "reached the inbox" indicator is `Icons.inbox_rounded` (group/legacy) or the transport glyph (1:1).
- `transportStatusGlyph` is `true` **only for 1:1** (`conversation_screen.dart:633`).

### Status → UI propagation (the mid-send re-render channel ALREADY exists)
- `MessageRepositoryImpl.saveMessage` writes the row then emits on `messageChanges` (`message_repository_impl.dart:141`).
- The screen subscribes (`conversation_wired.dart:1529-1599`) and the gate `_shouldRefreshFromRepositoryChange` admits **`sent` || `delivered` || `failed` || `inboxed`** (`:1602-1606`).
- **Consequence:** because `'inboxed'` is already admitted, if the ~110 ms `.then` callback (`:733`) did `saveMessage(copyWith(status:'inboxed', transport:'inbox'))`, the existing subscription would re-render the bubble mid-send **with no screen changes** — the only missing piece is that `saveMessage` call.

### Existing tests (the surface that changes — see Test Cases)
- `test/features/conversation/presentation/widgets/letter_card_test.dart` — per-status glyph + a11y + color; a TC-04 sweep asserting `done_all` `findsNothing` for ALL outgoing statuses (`:357-383`).
- `test/features/conversation/presentation/screens/conversation_wired_sending_to_failed_test.dart` — drives the `messageChanges` stream across sending→{failed,sent,delivered}.

---

## Scope Clarification + decisions to settle

| Area | Status |
|---|---|
| Emit a **custody-confirmed status update at the ~110 ms inbox ACK** (`send_chat_message_use_case.dart:733`) so the bubble advances mid-send | **In scope** — the core change. |
| Render that custody state as **two ticks** | **In scope — DECISION: un-retire `done_all` for the custody state** (reverses 155). The user explicitly wants "2 ticks." Alternative considered: keep `inbox_rounded` but show it earlier — rejected because it isn't literally two ticks. |
| Upgrade to the transport glyph (`wifi`/`direct`) on live delivery; rest at 2 ticks for an offline peer | **In scope** — the transport-glyph-on-reached already exists; the new part is that the offline-final state is the 2-tick custody glyph (replacing today's inbox glyph as the 1:1 custody indicator). |
| Ordering guard: a live ack that lands **before** the inbox ack goes straight to the transport glyph and never regresses to 2 ticks; `'delivered'` never reverts to `'inboxed'` | **In scope** — correctness invariant. |
| Failure path (no custody, race fails) → error glyph | **Unchanged** — stays as today. |
| Group / legacy (`transportStatusGlyph==false`) status glyphs | **Out of scope — unchanged** (keep the v1 `_statusIcon` inbox glyph; the 2-tick is 1:1 only). |
| The send transport/race/budgets/inbox mechanics | **Out of scope — unchanged.** This is a status-surfacing change only. |
| Read receipts / "delivered to recipient device" two-tick semantics | **Out of scope.** Here 2 ticks = "relay has custody," NOT "recipient device received." (The model keeps `done_all` for future read-receipt reuse — this spec borrows the glyph, not that meaning.) |

**Decisions the TDD plan must lock:**
1. **Glyph for the 2-tick custody state** — `done_all` (un-retire) vs. a re-use of `inbox`/transport glyph. (Spec proposes `done_all`.)
2. **What replaces the inbox glyph** as the offline-final indicator — 2-tick custody, or keep `inbox` for 1:1 too. (Spec proposes 2-tick = the 1:1 custody indicator; `inbox` stays for group/legacy.)
3. **Color** for the 2-tick (neutral vs the amber currently used for the in-flight state).
4. Whether the ~110 ms bump goes through `saveMessage('inboxed')` (reuses the existing stream gate — preferred) or a screen-side setter.

---

## Test Cases

IDs `TC-184-XX`. Host-tier (widget/unit) unless marked `[device]`.

### Group A — The status progression (widget, `letter_card`, `transportStatusGlyph:true`)
- **TC-184-01** — `sending` → single tick (`done_rounded`). (Already true; lock it.)
- **TC-184-02** — `inboxed` (custody) → **two ticks** (`done_all`) in the 1:1 path. (NEW — the core glyph change.)
- **TC-184-03** — reached live (`delivered` with `transport:'wifi'`/`'direct'`) → the transport glyph (`Icons.wifi` / `device_hub`), NOT two ticks.
- **TC-184-04** — `failed`/`send_failed` → error glyph (unchanged).
- **TC-184-05** — Group/legacy (`transportStatusGlyph:false`) `inboxed` → still `inbox_rounded`, never `done_all` (the 2-tick stays 1:1-only).

### Group B — The mid-send bump (send-flow + stream, the ~110 ms hook)
- **TC-184-10** — RED-on-HEAD: the concurrent-inbox `.then` callback (`send_chat_message_use_case.dart:733`) writes `saveMessage(status:'inboxed', transport:'inbox')` at the ACK. (Today it only records a metric — this is the new behavior; assert a `saveMessage('inboxed')` fires at the inbox-ACK, distinct from the terminal save.)
- **TC-184-11** — Mid-send re-render: emitting `'inboxed'` on `messageChanges` advances the bubble from 1 tick → 2 ticks **without** the live race having resolved (the stream gate already admits `'inboxed'`, `conversation_wired.dart:1604`).
- **TC-184-12** — Ordering guard: a `'delivered'` (live ack) that arrives **before** the inbox ACK renders the transport glyph and a subsequent late `'inboxed'` does **not** regress it to two ticks.
- **TC-184-13** — Offline rest state: an offline send (live legs fail) settles and **rests at two ticks** (custody), not the error glyph, not a spinner.
- **TC-184-14** — Inbox-store failure: if custody is NOT secured (inbox store fails) the bubble stays at one tick until the race resolves to `delivered`/`failed` (no false 2-tick).

### Group C — Test-surface updates (REQUIRED — flagged from grounding)
- **TC-184-20** — **Fix the already-broken test:** `letter_card_test.dart:441-444` (TC-08) still asserts `find.byIcon(Icons.schedule_rounded)` + amber for `pending`; `schedule_rounded` no longer exists after the clock→tick change, so it throws today. Update to the single-tick (`done_rounded`) expectation. (This breakage exists in the working tree **now**, independent of the rest of 184.)
- **TC-184-21** — Rewrite the `done_all` anti-regression contract: `letter_card_test.dart:357-383` (TC-04 sweep) + the six per-status `done_all findsNothing` asserts (`:224,:232,:275,:286,:326,:352`) must be re-scoped — `done_all` is now the *expected* glyph for the 1:1 `inboxed` custody state (and still absent everywhere else).
- **TC-184-22** — Update the stream-transition tests (`conversation_wired_sending_to_failed_test.dart:344/460/498`) to cover the new `sending → inboxed(2-tick) → delivered(transport glyph)` path, and add the ordering-guard case.

### Group D — Device-proof (closure)
- **TC-184-30 `[device]`** — Send to an **offline** peer: the bubble shows 1 tick on tap → **2 ticks within ~100–200 ms** (not after the ~1.8 s race), and rests there. Send to an **online** peer: 1 tick → (2 ticks or straight to) the transport glyph on live delivery. No spinner/clock anywhere.

---

## Notes
- The 2-tick is the **honest** milestone the optimistic single tick lacks today (custody confirmed at the relay), aligning with the send-truthfulness program — distinct from "delivered to the recipient's device," which this spec does **not** claim.
- This spec also formally absorbs the loose end from the clock→tick experiment (TC-184-20): that change is what makes `pending` render a tick, and it left `letter_card_test.dart` TC-08 stale.
