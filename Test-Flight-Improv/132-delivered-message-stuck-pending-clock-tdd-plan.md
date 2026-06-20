# 132 — A delivered 1:1 message stays on the amber "pending" clock (the "green circle")

Status: **IMPLEMENTED + DEVICE-VERIFIED** (2026-06-19). TDD-first. Phase 0 + Phase 1 landed
host-green; `kConfirmatoryDirectLanReceiptEnabled` flipped **ON by default** after on-device evidence.

> **Device verification (2026-06-19, iPhone 00008110 ↔ Pixel 6, prod relay, debug builds):**
> - **Dead-end confirmed (flag OFF):** every live message logged
>   `DELIVERY_RECEIPT_MINT_SKIPPED reason=direct transport=relay` → a delivered-but-unacked row would
>   stay on the amber clock with no repair.
> - **Relay-inbox self-heal confirmed (flag OFF):** an offline→inbox-drained send (`stuck1`, status
>   `inboxed`) → recipient drained → `DELIVERY_RECEIPT_SENT(via:live)` → sender flipped
>   `inboxed→delivered` (`DELIVERY_RECEIPT_APPLIED`, ✓✓). Proven twice. So Phase 2 (durable outbox) is
>   NOT needed for the offline case on the current build.
> - **Phase 1 engages (flag ON):** the identical live-relay path now logs
>   `DELIVERY_RECEIPT_SENT(id:4ea6fb5e)` on the recipient instead of `MINT_SKIPPED` — the confirmatory
>   receipt is the safety net that converges the sender when the live ack is lost.
> - Separate finding surfaced during this session: **Android cold-launch 1:1 notification tap routes
>   to Feed, not the conversation** → filed as `133-android-cold-launch-notification-routes-to-feed-spec.md`.

## Reported symptom (device)
A 1:1 message the user sent — and that the recipient demonstrably received (they replied to it in the
same thread) — keeps showing a "small green circle" next to the timestamp instead of the
delivered (✓✓) mark. See screenshot: the 2:00 PM and 2:03 PM outgoing messages show the clock; the
9:39 AM one shows ✓✓.

## What it actually is (verified)
There is **no green circle / `Colors.green` status indicator** anywhere. The glyph is the **amber
pending clock** `Icons.schedule_rounded`, size 14, color `Color(0xFF8A4A00)` (light) /
`Color.fromRGBO(255,200,100,0.5)` (dark) — `lib/features/conversation/presentation/widgets/letter_card.dart:407-419`
(the status `Icon` next to the time), mapped at `_statusIcon :618-619` and `_statusColor :638-641`. A
warm amber rounded-clock at 14px reads as a small colored dot. It means the row's status string is
**`inboxed`** (relay holds it, receiver not confirmed) or **`pending`** — NOT `delivered`. The only
genuinely teal pixels in the bubble are the incoming-bubble accent edge (`:169`) and the upload spinner
(`:451`), neither next to the outgoing time.

The four status glyphs (`_statusIcon`/`_statusColor`):
| status | glyph | color | meaning |
|---|---|---|---|
| `sending`/`sent` | single ✓ | grey | handed to transport, no ack |
| `delivered`/`queued` | double ✓✓ | muted | receiver confirmed |
| **`pending`/`inboxed`** | **clock** | **amber** | **relay custody, receiver NOT confirmed** |
| `failed`/`send_failed` | error-outline | red | send failed |

## Root cause (8-agent trace, adversarially verified — claim HELD)
**The sender's outgoing status is receipt/ack-driven, and the single promotion path to `delivered` is
a returned + matched `delivery_receipt` — a channel that is (a) minted only for relay-inbox arrivals,
(b) sent one-shot with no retry, and (c) has no self-healing repair when lost. So a genuinely-delivered
message whose confirmation signal is lost or never minted is stuck on the amber clock forever.**

Mechanism, with file:line:
1. Outgoing row starts optimistic `sending` (`conversation_wired.dart:1901,2876`).
2. `_persistOutgoingSendResult` decides status purely on the ack flag
   (`send_chat_message_use_case.dart:1790-1892`): `acknowledged == true` ⇒ `delivered` (:1801-1809);
   else concurrent durable relay custody ⇒ `inboxed` (:1819-1836); else sequential `storeInInbox`
   success ⇒ `inboxed` (:1850-1864); else ⇒ `sent` (:1884-1892). An unacked live/relay send commonly
   settles **`inboxed`** with the wire envelope retained.
3. UI renders `inboxed` as the amber clock (above).
4. The receiver does receive + durably persist, and fires `maybeSendDeliveryReceipt`
   (`handle_incoming_chat_message_use_case.dart:89-109`) — but gated by `shouldMintDeliveryReceipt`
   (`send_delivery_receipt_use_case.dart:14-20`): for `direct:`/`lan:`-staged arrivals OR any
   non-`inbox` transport it **mints nothing**; only relay-`inbox` arrivals mint.
5. `sendDeliveryReceipt` (`send_delivery_receipt_use_case.dart:31-105`) does **one** live send then
   **one** relay-store fallback, **no retry** (documented "D-5" `:26-28`). If both legs fail, or the
   plaintext receipt is dropped by an old router, or the live ack is lost — the receipt never reaches
   the sender. Re-mint happens **only on a duplicate receive** of the same message — which won't recur
   once the receiver has persisted it (the relay copy is consumed).
6. On the sender, the ONLY `inboxed→delivered` (and `sent→delivered`) flip is
   `handleDeliveryReceipt` (`handle_delivery_receipt_use_case.dart:68-81`). With no receipt arriving it
   never fires. (Receive-side wiring is intact: `incoming_message_router.dart:259` →
   `delivery_receipt_listener.dart:35` → `handleDeliveryReceipt`. So this is NOT a missing route — it
   is a missing/lost signal.)
7. No repair: the custody sweep `verifyInboxCustody` can only **downgrade** `inboxed→sent`
   (`verify_inbox_custody_use_case.dart:127-143`), never promote; `retry_failed_messages`/`retry_unacked`
   never self-promote to `delivered`. So the row is permanently stuck despite real delivery.

### The two dead-ends, ranked by likelihood for the reporter's *active live chat*
- **D-DIRECT/LAN (most likely here):** the message was delivered live/LAN but the ack was lost
  (`acknowledged == false`) ⇒ settled `inboxed`/`sent`, and **no receipt is ever minted** for
  direct/LAN ⇒ **no repair path at all**. (Verifier scenarios B & F.)
- **D-RELAY:** relay-inbox delivered, receiver minted **one** receipt, but it was lost (both legs
  failed / dropped by old router / unmatched on sender) ⇒ no re-mint ⇒ stuck. (Verifier scenario D/E.)

> Note: there is **no read-receipt back-channel** (read is local-only, `markConversationRead`
> `conversation_wired.dart:1349`), so `delivered` (✓✓) is the terminal positive state by design — the
> bug is the row never reaching even that.

## Why we instrument before "fixing"
The right fix differs by dead-end (D-DIRECT/LAN needs broadened minting; D-RELAY needs a durable/repair
receipt). The existing flow events (`DELIVERY_RECEIPT_SENT`/`_STORE_FAILED`/`_UNMATCHED`/
`_NO_TRANSITION`/`_APPLIED`/`_LIVE_SEND_ERROR`) already discriminate the receiver/sender legs, but the
**mint-skip** branch is silent. We add that one breadcrumb so a single device session names the exact
dead-end. We do **not** ship a truth-changing promotion default-on without that evidence — the code
comments correctly warn "a quarantined replay must never flip a sender to `delivered`."

## Plan

### Phase 0 — Instrumentation (pure win, default-on, no behavior change) [SHIP NOW]
- In `maybeSendDeliveryReceipt` (`handle_incoming_chat_message_use_case.dart:89-96`), when
  `shouldMintDeliveryReceipt(...)` returns **false**, emit
  `FL DELIVERY_RECEIPT_MINT_SKIPPED { reason: 'direct'|'lan'|'non_inbox', transport, idPreview }`.
  Refactor `shouldMintDeliveryReceipt` to return a small enum/result (or add a sibling
  `deliveryReceiptMintDecision(...)`) so the reason is testable and the gate logic stays single-source.
- **Tests** (`send_delivery_receipt_use_case_test.dart` / `handle_incoming_chat_message_*`): the
  decision returns `mint` for `transport=='inbox'` and no staged id; `skip(direct)` for `direct:`
  staged; `skip(lan)` for `lan:` staged; `skip(non_inbox)` for `transport=='direct'`/null with no
  staged id. Assert the skip breadcrumb carries the reason. Mutation: invert a branch → red.
- **INV-132-0:** zero behavior change — only adds a flow event on the existing skip branch; the
  `mint` decision is byte-identical to today's `shouldMintDeliveryReceipt` truth table (locked by a
  parity test).

### Phase 1 — Confirmatory delivery receipt for direct/LAN durable arrivals [SHIP DARK, flag default-off]
Closes **D-DIRECT/LAN**. New flag `const bool kConfirmatoryDirectLanReceiptEnabled = false;`
(co-located with the receipt use-case; flip-on is a one-line release after device proof — mirrors
`kOnJoinMetadataResyncEnabled` / `kMultiDeviceSyncEnabled` convention).

- When the flag is on, broaden the mint decision to ALSO mint for `direct:`/`lan:`/non-inbox arrivals —
  but **only after a confirmed durable persist** (the hook already fires post-persist;
  `handle_incoming_chat_message_use_case.dart:82` comment), and **never** for quarantined/rejected
  replays. Verify each `maybeSendDeliveryReceipt` call site fires only on the durable-persist /
  duplicate-of-persisted branches (`:324,:409,:431` duplicate, `:492` fresh) — NOT on a quarantine
  path — and add a guard/assert so a future quarantine call site can't mint.
- The sender side needs **no change**: `handleDeliveryReceipt` already flips `sent→delivered`
  (`handle_delivery_receipt_use_case.dart:76-80`) and `inboxed→delivered` (`:68-72`) on a matched
  receipt. So a direct/LAN message that settled `sent`/`inboxed` (lost ack) converges to `delivered`
  once the confirmatory receipt lands.
- **Tests** (host, deterministic):
  - **T1 (RED):** receiver durably persists a `lan:`-staged message → with flag ON, a receipt is sent;
    with flag OFF, none (locks default-off).
  - **T2:** end-to-end (two fake repos / the shared receipt fixture): sender row at `sent` (lost ack) +
    receiver mints confirmatory receipt → `handleDeliveryReceipt` flips sender to `delivered`.
    Mutation: force the receiver mint to skip → sender stays `sent` (proves the receipt is the cause).
  - **T3 (safety):** a quarantined/rejected inbound (not durably persisted) mints **no** receipt even
    with the flag ON (INV-132-2). Mutation: move the mint before the persist guard → T3 red.
- **INV-132-1:** with the flag off, byte-identical to today (no new receipts).
- **INV-132-2:** a receipt is minted only after a durable main-table persist — never for a quarantined,
  rejected, or undecryptable replay (no false `delivered`).
- **INV-132-3:** idempotent — duplicate confirmatory receipts are no-ops on the sender
  (`handleDeliveryReceipt` already early-returns on `status=='delivered'`, `:63-66`).

### Phase 2 — Durable receipt outbox + bounded retry [PLANNED; needs migration 092 — defer unless D-RELAY confirmed]
Closes **D-RELAY** (lost one-shot relay receipt). Today `sendDeliveryReceipt` has no retry and no
durability; a receiver killed before a successful send loses the receipt permanently.
- New table `092_pending_delivery_receipts` (DB v92): `{messageId, targetPeerId, createdAt, attempts}`.
- Receiver enqueues a pending receipt at mint time; a drainer (app-resume + periodic, mirroring
  `GroupPendingKeyDistributionRunner` / `pending_group_broadcasts`) retries live→relay with bounded
  backoff and a terminal cap; clears on confirmed send. Re-mints survive app-kill.
- **Tests:** enqueue on mint; drain retries on resume; terminal cap; clear on success; mutation checks.
- **Defer trigger:** only build Phase 2 if device logs (Phase 0) show `DELIVERY_RECEIPT_STORE_FAILED` /
  `_LIVE_SEND_ERROR` on the **receiver** for the reporter's stuck messages (i.e. D-RELAY). If the logs
  show `DELIVERY_RECEIPT_MINT_SKIPPED reason=direct|lan` (D-DIRECT/LAN), Phase 1 alone is the fix.

### Phase 3 — Sender-side relay-consumed promotion [PLANNED; relay-assisted, deploy-gated] (optional)
A positive "was message X consumed/drained by the peer?" relay query so `verifyInboxCustody` can
**promote** `inboxed→delivered` (today it can only downgrade) without depending on the lossy receipt
channel. Requires a relay-protocol addition (sidecar) and an EC2 deploy — out of this plan's client
scope; capture as a follow-on if Phases 1–2 leave residue.

## What ships in THIS pass
- **Phase 0** (instrumentation) — default-on, host-green.
- **Phase 1** (direct/LAN confirmatory receipt) — implemented + host-tested **behind a default-off
  flag**. The user flips `kConfirmatoryDirectLanReceiptEnabled = true` after a device session confirms
  D-DIRECT/LAN (or we confirm via the Phase-0 breadcrumbs). **Honest status:** the bug is not
  *user-visibly* fixed until the flag is flipped + device-proofed; the code path is built and tested.
- **Phases 2–3** — planned, deferred behind the Phase-0 evidence gate (Phase 2 needs migration 092).

## Gates
- `flutter test test/features/conversation/` green (receipt + handle-incoming + custody suites);
  `flutter analyze` 0 new issues.
- **Device evidence (the enabler):** with Phase 0 live, reproduce the stuck clock on two phones and
  read `idevicesyslog -m DELIVERY_RECEIPT` — confirm which dead-end fires
  (`MINT_SKIPPED reason=…` vs receiver `STORE_FAILED`/`LIVE_SEND_ERROR`).
- **Device proof to flip Phase 1 on:** with `kConfirmatoryDirectLanReceiptEnabled = true`, send a
  direct/LAN message under a dropped-ack condition and confirm the sender converges to ✓✓
  (`DELIVERY_RECEIPT_APPLIED` on the sender).

## Explicitly NOT doing
- **Do NOT paint `inboxed` the same as `delivered`** in `letter_card.dart` — that makes the indicator
  lie. The fix belongs in the receipt/ack reconciliation layer.
- **Do NOT** remove the amber clock or down-rank its meaning — `pending`/`inboxed` is a truthful state;
  the goal is to make genuinely-delivered rows *converge off* it, not to hide it.
- No change to the optimistic `sending` creation or the `acknowledged`→`delivered` fast path.

## Rollback
- Phase 0: remove the one flow event (or it's harmless — leave it).
- Phase 1: `kConfirmatoryDirectLanReceiptEnabled = false` (default) — zero behavior change.
- Phase 2 (if built): drop the runner wiring; migration is additive (empty table).
