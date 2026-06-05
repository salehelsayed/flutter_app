# Double / Stacked Message Cards — Group Chat Investigation

> Investigation date: 2026-06-04 · Branch: `121-improvements`
> Method: multi-agent workflow (11 agents) — parallel code mapping → ranked hypotheses → adversarial verification → synthesis. Every claim is cited to `file:line`.

## Summary

This is **data duplication, not a UI artifact**: two persisted `group_messages` rows with **different `id` (primary key) values but identical content** are being rendered as two stacked, slightly-offset list items. The UI layer is exonerated — it faithfully de-dups by `message.id` at three layers and a single `LetterCard` draws exactly one bordered container. **Confidence is moderate (~0.6) on the category (data/timing dedup gap) and lower (~0.4) on the precise trigger.** The most defensible single explanation is that the receive-side dedup is keyed *exclusively* on the wire `messageId`; the content-based fallback is gated behind `if (stableMessageId == null)` and so is bypassed for normal `messageId`-bearing group messages — meaning any second delivery that arrives under a *different* `id` (or an id-less copy whose normalized timestamp diverges) survives all the way to two cards. The exact mechanism that produces the second divergent id could not be pinned down from static analysis alone and needs on-device/DB confirmation.

## Symptom & Reproduction

**What the user saw** (from a group-chat screenshot):
- Some *incoming* (received, left-accent) short Arabic **text** messages render as **two cards stacked and slightly offset** — a "double border" / "card behind a card" look.
- No images in the affected cases.
- Two of the doubled cards carry a small heart reaction; one does not.
- Timestamps look normal (12:45 PM, 12:52 PM).

**Conditions under which it likely occurs** (inferred, not yet reproduced):
- A received text message that was delivered via **two transports** — live GossipSub *and* the offline-inbox / relay store-and-forward path — or otherwise redelivered.
- The two copies end up persisted under **two different `id`s**, so neither the id-based dedup nor the (skipped) content dedup collapses them.
- The "heart on one card, not the other" detail is **diagnostic**: reactions are looked up strictly per `message.id` (`group_conversation_screen.dart:585`). A single widget drawn twice would share one `id` and therefore one reaction state — it could not differ. Differing reaction state therefore implies **two rows with two distinct ids**, corroborating data duplication over a pure-UI artifact.

## How incoming group messages flow

**Live (GossipSub) path:**
- Go bridge → `bridge.onGroupMessageReceived(data)` → broadcast `StreamController` (`main.dart:1809-1811`).
- Stream handed to `groupMessageListener.start(...)` (`main.dart:2070-2072`), wired as `incomingGroupMessages.asyncMap(_handleLiveMessage)` (`group_message_listener.dart:249-251`).
- `_handleLiveMessage` → `_handleQueuedUserMessage(...)` → `_handleMessage` → `handleIncomingGroupMessage(...)` (`group_message_listener.dart:324-328`, `:644`, `:800-817`).
- One UI emit per successful handle: `_emitGroupMessage(result)` → `_messageController.add(message)` (`group_message_listener.dart:820`, `:309-312`).

**Offline-inbox / store-and-forward path:**
- `drain_group_offline_inbox_use_case.dart` decodes relay messages and calls `groupMessageListener.handleReplayEnvelope({... 'messageId': payload['messageId'] ...})` (`:670-685`, sys at `:591-606`, history-gap repair at `:1387-1402`).
- `handleReplayEnvelope` → `_handleQueuedUserMessage` → `_handleMessage` → `handleIncomingGroupMessage` — **same sink.** The inbox path reuses the sender's `payload['messageId']` (not a fresh id).

**Per-id serialization:** `_handleQueuedUserMessage` serializes work per wire `messageId` via `_userMessageWorkQueue` (`group_message_listener.dart:354-365` key; `:385-404` queue). The live stream is *additionally* serialized by `.asyncMap`; the inbox replay path is **not** — so the work queue is the only cross-path serializer between live and replay.

**Authoritative dedup** lives in `handle_incoming_group_message_use_case.dart`, keyed on primary-key `id` (= wire `messageId`):
- `stableMessageId` = `messageId`, or `null` when messageId is missing/empty (`:55-57`).
- Id-based dedup runs pre-lookup (`:86-137`) and post-event-log (`:461-512`): existing row with same id → `return null` (dropped).
- Content fallback `existsByContent(groupId, senderId, text, normalizedTimestamp)` runs **only** under `if (stableMessageId == null)` (`:568-587`); helper matches exact `text = ? AND timestamp = ?` (`group_messages_db_helpers.dart:543-556`).
- Id-less copies mint a fresh UUID: `resolvedMessageId = stableMessageId ?? const Uuid().v4()` (`:590`).

**DB:** `group_messages` has `id TEXT PRIMARY KEY` as the *only* uniqueness guarantee (`migrations/018_group_messages_tables.dart:19`); two indexes are non-unique (`:35`, `:40`). `dbInsertGroupMessage` does a plain `db.insert` with no `ConflictAlgorithm` (`group_messages_db_helpers.dart:32`); it catches only the **id** UNIQUE conflict and enriches in place (`:33-38`, `_handleDuplicateGroupMessageInsert :61-106`). A **different id with identical content inserts a second row silently.** Load queries have no `DISTINCT`/`GROUP BY` and order by `timestamp ASC, id ASC` (`dbLoadAllGroupMessages :195-230`), so near-duplicates render adjacent.

**UI:** `GroupConversationWired` subscribes to `groupMessageStream` → `_applyMessageUpdate` → `_upsertMessage` (id-keyed merge, `group_conversation_wired.dart:2917-2926`); `orderGroupMessagesForTimeline` rebuilds from a `byId` map (`group_message_ordering.dart:15-56`); `ListView.builder` keys rows `ValueKey('grp-msg-${message.id}')` (`group_conversation_screen.dart:611`).

## Root-cause hypotheses (ranked)

### H3 — No content-based UNIQUE constraint + insert path never calls content dedup (structural enabler) — **CONFIRMED**
- **Mechanism:** `group_messages` enforces uniqueness only on `id` (`migrations/018_group_messages_tables.dart:19`; both indexes non-unique `:35`/`:40`; no later migration adds a UNIQUE constraint — 026/041/061/073 are ALTER … ADD COLUMN only). `dbInsertGroupMessage` (`group_messages_db_helpers.dart:9-53`) uses a plain `db.insert` and only collapses **id** collisions. The content-equality helper `dbExistsGroupMessageByContent` exists (`:536-557`) and is DI-wired into the repo as `existsByContent` (`group_message_repository_impl.dart:395-407`), **but the insert path `saveMessage` never calls it** — it only does `dbLoadGroupMessage(message.id)` then `dbInsertGroupMessage` (`impl:215-247`). Two rows with different ids + identical content both persist; load queries return both (`:195-230`).
- **Verdict:** **Confirmed** as the structural enabler. This is what lets any divergent-id copy survive to the UI. It is a *missing defense*, not the trigger — on its own it cannot create the second id.
- **Supporting:** `migrations/018_group_messages_tables.dart:19,35,40`; `group_messages_db_helpers.dart:9-53,536-557`; `group_message_repository_impl.dart:215-247,395-407`; `group_messages_db_helpers.dart:195-230`.
- **Refuting / nuance:** The receive use case is not *fully* defenseless — it has a content guard at `handle_incoming_group_message_use_case.dart:569` — but that guard is gated behind `if (stableMessageId == null)` (`:568`) and is bypassed whenever the wire carries a `messageId` (the normal v3 group case). So it is a partial guard, consistent with this being an enabler ranked below the id-divergence trigger.

### H1 — Id-less copy forces UUID-mint; content fallback misses on a timestamp mismatch → two rows — **REFUTED (as the normal-flow trigger)**
- **Mechanism:** When `messageId` is absent, `stableMessageId == null`, the use case mints a fresh `Uuid().v4()` (`:590`), and the *only* guard is `existsByContent` keyed on exact `text` + `timestamp` ISO string (`group_messages_db_helpers.dart:543-556`). If the two delivery copies normalize to different timestamps (e.g. `_normalizeIncomingMessageTimestamp` clamping a future timestamp to `receivedAt`, `handle…:1004-1030`; or the drain path defaulting to `now()` when the field is absent, `drain…:503-505`), the content match fails → second row with a different minted UUID.
- **Verdict:** **Refuted for the normal flow.** Both *trigger preconditions* are contradicted by the code:
  - **Precondition 1 (id-less copy) fails:** the Dart sender *always* produces a non-empty `messageId` (`send_group_message_use_case.dart:240-279`, regenerates empties at `:246-249`), embedded into both the wire envelope (`:764`) and the inbox payload (`:780`). The Go layer also mints a UUID if empty and writes it to `env.MessageId` + payload Extra (`go-mknoon/node/pubsub.go:423-425,463,1678-1693`); the receive event copies `messageId` from Extra (`:1741-1745`). So `data['messageId']` is always non-empty for app messages → `stableMessageId != null` → id-based dedup at `:86-137`/`:461-512` collapses duplicates. The content fallback is effectively dead code for real app messages.
  - **Precondition 2 (timestamp divergence) fails:** the sender embeds one resolved `timestamp` into both copies (`send…:779`, `:860` via `bridge_group_helpers.dart:437-438`); the live path forwards `payload.Timestamp` unchanged (`pubsub.go:1736`) and the drain path uses `payload['timestamp']` unchanged (`drain…:503-505`). `_normalizeIncomingMessageTimestamp` returns them unchanged (`handle…:1010-1017`); the clamp branch fires only for >5-min-future timestamps.
- **Supporting (accurate parts):** dedup structure as described — `handle…:55-57,568-590`; `group_messages_db_helpers.dart:32,543-556`.
- **Refuting:** `send_group_message_use_case.dart:240-279,764,780`; `go-mknoon/node/pubsub.go:423-425,463,1678-1693,1736,1741-1745`; `drain_group_offline_inbox_use_case.dart:503-505`. Test PGC-007 (`handle_incoming_group_message_use_case_test.dart:1355-1396`) shows the *real* double-row mechanism is **same content + same timestamp but DIFFERENT stable messageIds** — which does *not* go through the id-less content fallback this hypothesis blames.

### H2 — Id-less messages bypass per-messageId serialization → TOCTOU race, both copies insert — **LIKELY (latent bug), low reachability for this symptom**
- **Mechanism (verified):** `_userMessageWorkKey` returns `null` for missing/empty/non-String `messageId` (`group_message_listener.dart:354-365`); in that case `_handleQueuedUserMessage` runs `_handleMessage` **without enqueuing** on `_userMessageWorkQueue` (`:374-383`). The id-less branch in the use case (`if (stableMessageId == null)`, `handle…:568`) relies solely on `existsByContent` — a read (`group_message_repository_impl.dart:395-407`) and a separate awaited `saveMessage` (`:215-247`) with **no transaction/lock spanning them** (TOCTOU). No UNIQUE content constraint exists (`018:19,35,40`). Each id-less copy mints a distinct UUID (`handle…:590`), so both inserts succeed (no id conflict) → two rows. A genuinely concurrent second path exists: live GossipSub is serialized by `.asyncMap` (`:249-250`), but inbox replay enters via `handleReplayEnvelope` → `_handleQueuedUserMessage` directly (`:194-206`) — the work queue is the only cross-path serializer, and it's skipped for id-less messages.
- **Verdict:** **Likely as a real latent bug, but low reachability for the screenshot.** The id-less branch is essentially unreachable for normal modern-app text messages (see H1 precondition 1). It fires only if the *sender* omitted `messageId` (legacy/non-conforming/corrupted peer) **and** the same id-less message arrives twice concurrently via two paths with identical content+timestamp. One drain replay site even drops id-less payloads before replay (`drain_group_offline_inbox_use_case.dart:1381-1384`).
- **Supporting:** `group_message_listener.dart:354-365,374-404,194-206,249-250,583-597`; `handle…:55-57,568-590`; `group_message_repository_impl.dart:215-247,395-407`; `group_messages_db_helpers.dart:32,536-556`; `018:19,35,40`; `group_message.dart:116`.
- **Refuting:** `send_group_message_use_case.dart:764,780`; `bridge_group_helpers.dart:353-354,434-435`; `drain…:1381-1384`; within-live serialization at `group_message_listener.dart:249-250` rules out the "two GossipSub mesh paths" sub-claim for the live stream.

### H4 — Heart-on-one-card-not-the-other confirms two distinct ids (corroborating, not causal) — **LIKELY (diagnostic)**
- **Mechanism:** Reactions are keyed strictly per `message.id` at every layer: screen lookup `reactions[message.id]` (`group_conversation_screen.dart:585`); wired state `Map<String, List<MessageReaction>>` keyed by id, updated per `change.messageId` (`group_conversation_wired.dart:223`, `:4019-4034`); incoming reaction targets `payload.messageId` and requires the target row to already exist (`handle_incoming_group_reaction_use_case.dart:134-148,169,193-194`). The chip renders *inside* the single `LetterCard` footer from the `reactions` prop (`letter_card.dart:342-359,436-449`). So a reactor's reaction lands on whichever local row's id matches its own DB — explaining heart-on-one-not-the-other and proving **two distinct ids**.
- **Verdict:** **Likely** — sound diagnostic logic that selects the data/timing category over UI-rendering, but it does not name *how* two ids arise (defers to the trigger above) and its premise (the screenshot truly shows two genuinely-stacked cards with differing reaction state) cannot be verified from code alone.
- **Supporting:** `group_conversation_screen.dart:585`; `letter_card.dart:342-359,436-449`; `group_conversation_wired.dart:2917-2926,4019-4034`; `handle_incoming_group_message_use_case.dart:86-137,461-512`; `handle_incoming_group_reaction_use_case.dart:134-148`.
- **Refuting:** Corroborating, not causal; premise unverifiable from code; an alternative single-id "double border" (the highlight `AnimatedContainer`, see H5) would carry the *same* reaction and so does not match the heart-on-one pattern.

### H5 — Pure-UI double-border artifact (one widget drawing two stacked borders) — **REFUTED as root cause (exoneration LIKELY)**
- **Mechanism considered:** A single card widget drawing two stacked containers/borders/shadows.
- **Verdict:** **Refuted as the root cause.** A single `LetterCard` draws exactly ONE bordered container: `ClipRRect` → `BackdropFilter` → one `Container` with one `BoxDecoration` / one `Border.all` (`letter_card.dart:89-96`); the Stack children are decorative overlays of the *same* card — a 60px accent glow (`:100-141`) and a 3px accent edge strip (`:143-170`) — identical on every card, so they cannot explain why *only some* messages double. The list cannot hold two items with the same id: `_upsertMessage` (`group_conversation_wired.dart:2917-2926`), `orderGroupMessagesForTimeline` (`group_message_ordering.dart:15-56`), per-id `ValueKey` (`group_conversation_screen.dart:611`). `SwipeToQuoteBubble`'s reply icon is opacity-0 at rest (`swipe_to_quote_bubble.dart:115,135-136`); the context-overlay `LetterCard` lives in a `showDialog` route (`group_conversation_screen.dart:732`), not the scroll list. A genuine two-card render therefore *requires* two rows with two different ids → reduces to the data/timing category.
- **Supporting:** `letter_card.dart:85-96,100-141,143-170`; `group_conversation_wired.dart:2917-2926`; `group_message_ordering.dart:15-56`; `group_conversation_screen.dart:611`; `swipe_to_quote_bubble.dart:115,126-162`.
- **Refuting (completeness caveat, does NOT overturn):** the `isHighlighted` branch wraps the bubble in an `AnimatedContainer` with `BorderRadius.circular(20)` + `Border.all(color: readableColors.border)` (`group_conversation_screen.dart:633-645`) — a genuine SECOND full-perimeter border around the card's own 24-radius border, for a single id. It is transient (~180ms, one `highlightedMessageId` at a time), so it does not match a static screenshot of *multiple* doubled messages with reactions, and it would carry the *same* reaction on both layers (contradicting heart-on-one). It is a real single-id double-border path worth knowing about, but not the reported artifact.

## Most likely root cause

**Two persisted `group_messages` rows for one logical text message, carrying two different `id` (primary-key) values, both rendered as adjacent stacked cards.** The structural enabler (H3, confirmed) is that the receive path's content-based dedup is gated behind `if (stableMessageId == null)` (`handle_incoming_group_message_use_case.dart:568`) and so is **bypassed for every normal `messageId`-bearing group message**, while the DB enforces uniqueness only on `id` (`migrations/018:19`) and `dbInsertGroupMessage` never consults the content helper (`group_messages_db_helpers.dart:32`). Dedup is therefore *id-only* for real messages — so the moment the same logical message reaches the receiver under two different ids, two rows persist and two cards render.

**Honest uncertainty about the trigger:** Static analysis confirms the sender *cannot* emit two text copies with different ids (id and timestamp are minted once and reused across all retry/timeout/inbox paths — `send_group_message_use_case.dart:621,764,780`, refuting the image-retry analogy), and it confirms the id-less branch (H1/H2) is essentially unreachable for modern-app text. **What is NOT established from code alone is the exact path that produces the second divergent id for a normal message** — e.g. receive-side id parsing/normalization (trimming/casing) yielding two distinct strings, a media-retry canonicalization that doesn't cover text, or a peer running an older/non-conforming client. Test PGC-007 (`handle_incoming_group_message_use_case_test.dart:1355-1396`) proves the *outcome* (same content+timestamp, different messageIds → 2 rows) but not the field cause. **This is the single biggest open question.**

## Recommended fix

Two complementary changes — a robust receive-path guard (primary) plus a DB defense-in-depth (optional). Pairing them eliminates the double-card regardless of *how* the second id arises.

**1. Make incoming content-dedup run even when a `messageId` IS present (primary fix).**
In `handle_incoming_group_message_use_case.dart`, the content check at `:569` is currently gated by `if (stableMessageId == null)` (`:568`). After the id-based dedup misses (after `:512`, before saving at `:609`), also run a content/logical dedup for non-system incoming messages — collapsing two rows that match on logical identity (`group_id + sender_peer_id + text + timestamp + quoted_message_id`) even when the wire `messageId` differs. Concretely, generalize the existing media-only logical-dedup (`_findCanonicalIncomingMediaRetryMessageId` / `_isSameLogicalIncomingMediaRetryEnvelope`, `:520-556,645-727`, currently gated on `media != null && media.isNotEmpty` at `:522-523`) to also cover TEXT messages. Guard with `text.isNotEmpty` and exclude self-delivery/system rows so legitimately-distinct messages are not merged.

**2. Close the id-less TOCTOU and stop bypassing serialization (hardening for H2).**
In `group_message_listener.dart:354-365`, when `messageId` is missing, return a **synthetic queue key** built from the same fields used by `existsByContent` (`group_id + sender + text + timestamp`) instead of `null`, so two id-less copies are forced through `_userMessageWorkQueue` (`:385-404`) and cannot race. Separately, wrap the id-less `existsByContent` + `saveMessage` (`handle…:568-609`) in a single repository transaction.

**3. DB defense-in-depth (optional).**
Add a content-uniqueness guard in a new migration, e.g.:
```sql
CREATE UNIQUE INDEX IF NOT EXISTS idx_group_messages_content
  ON group_messages(group_id, sender_peer_id, text, timestamp)
  WHERE is_incoming = 1;
```
(Note SQLite partial-index semantics; verify it does not break legitimate distinct same-second messages — consider including `quoted_message_id`.) Then extend `dbInsertGroupMessage` (`group_messages_db_helpers.dart:31-38`) to catch this content-UNIQUE conflict alongside the existing id-conflict branch and treat it as a no-op/enrich rather than a second insert.

**Do NOT** "fix" this in the UI (`_upsertMessage`) as the primary remedy — the rows are still wrong in the DB and would resurface (reactions, read state, recovery). A UI-side logical-collapse in `_upsertMessage` (`group_conversation_wired.dart:2917-2926`) is acceptable only as a belt-and-suspenders guard.

## How to confirm (before fixing)

1. **Capture both rows for one affected message.** On-device DB query:
   ```sql
   SELECT id, group_id, sender_peer_id, text, timestamp, created_at, is_incoming
   FROM group_messages
   WHERE group_id = '<gid>' AND text = '<the doubled Arabic text>'
   ORDER BY timestamp ASC, id ASC;
   ```
   Confirm there are **two rows with different `id`** and compare their `timestamp` strings **byte-for-byte** (does the second copy have a 1ms/format-shifted timestamp, or an identical one?). This decides between H1-style timestamp divergence vs PGC-007-style same-timestamp-different-id.
2. **Grep FLOW logs** for that message: look for `GROUP_HANDLE_INCOMING_MSG_SUCCESS` (how many?), `GROUP_HANDLE_INCOMING_MSG_DUPLICATE` with `dedupeBy: 'messageId'` vs `dedupeBy: 'content'`, and whether either copy hit the `stableMessageId == null` / `Uuid().v4()` mint path (`handle…:590`). Two `SUCCESS` events with different resolved ids = confirmed data dup; presence/absence of a `DUPLICATE` event tells you which guard (if any) engaged.
3. **Inspect the raw wire `messageId` on both deliveries.** Add a one-line FLOW log of `data['messageId']` (raw, pre-trim) at `group_message_listener.dart:354-365` and at the drain replay site, to confirm whether one path delivered an empty/missing/whitespace-different/cased-different id. This is the key to identifying the *trigger* the static analysis could not.
4. **Reaction cross-check.** Query the reactions store for the reactor's target `messageId` and confirm it equals exactly one of the two row ids — verifying H4's diagnostic claim end-to-end.

## Open questions / what could not be determined from static analysis

- **The exact mechanism that produces the second divergent `id` for a normal text message.** Sender (`send_group_message_use_case.dart`) and Go (`pubsub.go`) both guarantee a stable non-empty `messageId`; the id-less path (H1/H2) is essentially unreachable for modern-app text. So either (a) a peer is running an older/non-conforming client that omits or differently-formats `messageId`, (b) receive-side id parsing/normalization (trim/case/encoding) yields two distinct strings for the same wire id, or (c) some redelivery path re-stamps the id. None of these can be confirmed without on-device wire/DB capture (step 3 above).
- **Whether the screenshot truly shows two persisted stacked cards** vs two legitimately-distinct adjacent messages, or a transient highlight `AnimatedContainer` border (`group_conversation_screen.dart:633-645`). The DB query in step 1 settles this.
- **Timestamp byte-equality between the two copies** — whether `_normalizeIncomingMessageTimestamp` (`handle…:1004-1030`) or the drain `now()` default (`drain…:503-505`) ever fires for the affected messages. Only inspectable from real data.
- **Whether the affected messages came via live GossipSub, the offline inbox, history-gap repair, or some combination** — the FLOW logs (step 2) will disambiguate, but cannot be inferred statically.

## Relevant files

- `lib/features/groups/application/handle_incoming_group_message_use_case.dart`
- `lib/features/groups/application/group_message_listener.dart`
- `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`
- `lib/features/groups/application/send_group_message_use_case.dart`
- `lib/core/database/helpers/group_messages_db_helpers.dart`
- `lib/core/database/migrations/018_group_messages_tables.dart`
- `lib/features/groups/domain/repositories/group_message_repository_impl.dart`
- `lib/features/groups/presentation/screens/group_conversation_screen.dart`
- `lib/features/groups/presentation/screens/group_conversation_wired.dart`
- `lib/features/groups/domain/utils/group_message_ordering.dart`
- `lib/features/conversation/presentation/widgets/letter_card.dart`
- `go-mknoon/node/pubsub.go`

---

### Appendix — hypothesis scoreboard

| ID | Hypothesis | Category | Prior | Verdict |
|----|------------|----------|-------|---------|
| H3 | No content UNIQUE constraint + insert never calls content dedup (enabler) | data-duplication | 0.30 | **Confirmed** |
| H2 | Id-less messages bypass per-id serialization → TOCTOU race | timing-dedup-gap | 0.34 | **Likely** (low reachability) |
| H4 | Heart-on-one-card confirms two distinct ids | data-duplication | 0.28 | **Likely** (diagnostic, not causal) |
| H1 | Id-less UUID-mint + timestamp-mismatch content miss | timing-dedup-gap | 0.50 | **Refuted** (normal flow) |
| H5 | Pure-UI double-border artifact | ui-rendering | 0.08 | **Refuted** (UI exonerated) |
