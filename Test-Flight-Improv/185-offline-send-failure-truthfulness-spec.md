# 185 - Offline-send failure truthfulness: keep offline sends in the self-healing lane + name the real cause  (Bug — Spec)

Status: awaiting-review (spec only — problem + current state + test cases; no solution design).

Relation to earlier work:
- Reconnects to the **ACK-based delivery** machinery from `90651699` (the `retryUnacked` + delivery-receipt convergence lane) that already self-heals unacked sends to `delivered`. This spec restores a message path that an architecture change routed around.
- Depends on **182**'s connectivity source (`connectivity_plus` → `networkChangeSignal` / `connectivityRestoredSignal`) already live in prod — the sender-offline signal both bugs need.
- Same family as the **114–116 send-truthfulness** program and **155** transport-status-glyph work.

---

## Problem Statement

When the **sender** has a bad/absent connection, the send is stamped terminally **`failed`** — which (a) shows a red "Retry" that never clears even after the message is delivered, and (b) raises a snackbar blaming the *contact*. Both were reproduced and captured on device (Pixel 6 on degraded mobile data → iPhone 11 on WiFi, 2026-07-01).

**Bug 1 — a delivered message keeps its "Retry" forever.** The user sends while offline; the row is stamped `failed` (red Retry + error glyph). The connection recovers, the message **does reach the peer**, the peer sends a delivery receipt back — but the sender's row **stays `failed`** and Retry never clears.

**Bug 2 — the snackbar blames the wrong party.** The same send raises *"Contact appears offline. Message saved."* The contact is **not** offline — the **sender** is. It should reflect the real cause ("no internet connection; will send when back online").

**Root cause (unified):** an offline send is dropped **out of an existing, still-wired self-healing lane** by being marked `failed`, when it should stay in the retriable `sent`/unacked lane that already converges such messages to `delivered`.

---

## Verified current state (file:line)

### The existing self-healing lane (still wired — but the offline send is routed around it)

`90651699`'s ACK-based delivery established a convergence lane that carries an **unacked** outgoing message to `delivered` without any permanent failure:

1. **`retryUnackedMessages`** (`lib/features/conversation/application/retry_unacked_messages_use_case.dart:7-11,43-108`) loads outgoing rows stuck at `status='sent'` (with a wire envelope), re-stores them to the relay inbox, and on success moves them `sent → 'inboxed'` (`:98`). It is **wired**: on app-resume (`lib/core/lifecycle/handle_app_resumed.dart:672-676`, "Step 8d: retryUnackedMessages") and via the pending-message retrier / connectivity transitions.
2. The candidate query **`getUnackedOutgoingMessages`** picks up **only** `status='sent'` rows: `messages_db_helpers.dart:645-666` — `WHERE status = 'sent' AND is_incoming = 0 AND wire_envelope IS NOT NULL AND timestamp < ?`.
3. **`handleDeliveryReceipt`** (`lib/features/conversation/application/handle_delivery_receipt_use_case.dart:63-89`) then flips `inboxed → 'delivered'` (`:68`) or `sent → 'delivered'` (`:76`) on the peer-authenticated receipt (auth guard `:55`), else emits `DELIVERY_RECEIPT_NO_TRANSITION` (`:82`) leaving the row unchanged. **There is no `failed → delivered` arm.**

So a message that stays `sent` self-heals: `sent → (retryUnacked) inboxed → (receipt) delivered`. A message stamped `failed` is invisible to **both** step 2 (query is `sent`-only) and step 3 (transitions from `inboxed`/`sent` only) — it can never reconcile.

### How the offline send is evicted from the lane

- The 1:1 send-failure handler stamps **any** non-success result terminal `failed`: `conversation_wired.dart:2461-2463` — `fallbackStatus = switch(result){ success => 'sent', _ => 'failed' }` — then persists it (`:2478-2480`). When the sender's relay/network is down, the FDC race returns `peerNotFound` (device: `result:"peerNotFound"`, `elapsedMs≈6150`, with `RELAY_OUTAGE_TIMING totalOutageMs:24826` and inbox-drain `failureReason:"all 1 relays failed … i/o deadline reached"`) — so a **sender-offline** send is stamped `failed` and leaves the lane.
- The row **already carries its wire envelope** (persisted BEFORE the race — the Section-4 crash-safety contract, `send_chat_message_use_case.dart:507-508`, envelope set at e.g. `:1148/:1194/:1311`). So the row is *eligible* for the `retryUnacked` lane on every count **except its status.** Only the status is wrong.

**Device evidence (smoking gun):** message `fe008fce` was stamped `failed` during the sender's relay outage; the iPhone received it and sent receipts, but the Pixel logged `DELIVERY_RECEIPT_NO_TRANSITION status:"failed"` **6×** and Retry persisted. In the same batch **17** rows logged `DELIVERY_RECEIPT_APPLIED` (they were `sent`/`inboxed`). The split confirms only the `failed`-stamped rows are stranded.

### Bug 2: the snackbar keys off the result, never off the sender's own connectivity

`conversation_wired.dart:2484-2494` maps `SendChatMessageResult` → copy: `nodeNotRunning → 'Network not connected. Message saved.'` (`:2485`), `peerNotFound → 'Contact appears offline. Message saved.'` (`:2487`), `dialFailed → 'Could not connect to contact. Message saved.'` (`:2489`). It consults the **send result only** — the send path reads **no** connectivity/online signal (grep of `lib/features/conversation/` for `connectivity|isOnline|hasConnection|networkChangeSignal` is empty). The sender-offline signal already exists in prod (182: `connectivity_signal.dart`, `networkChangeSignal`/`connectivityRestoredSignal`; plus node/relay health). It is simply never consulted at the failure site.

### Status vocabulary (context)

Outgoing 1:1 rows move `sending → sent → inboxed → delivered`, or `→ failed`. `failed` renders the Retry affordance + error glyph. `sent` renders the in-flight single tick. `conditionalTransitionStatus(id, fromStatus, toStatus)` (`handle_delivery_receipt_use_case.dart:68,76`; `verify_inbox_custody_use_case.dart:131`) is the atomic, snapshot-safe transition primitive.

---

## Test cases

### Group A — Bug 1 (primary): a sender-offline send stays in the self-healing lane and converges to delivered

- **TC-185-01** — a send that fails because the **sender is offline** is left in a **retriable** state that `getUnackedOutgoingMessages` picks up (i.e. `status='sent'` with wire envelope), **not** terminal `failed`.
- **TC-185-02** — a send that fails for a **non-connectivity** reason (e.g. `invalidMessage`, `encryptionRequired`, or a `peerNotFound` while the sender **is online**) is still stamped `failed` (Retry appropriate). The fix must not blanket-retry genuine failures.
- **TC-185-03** — an offline-failed row left as `sent` is carried by the **existing** `retryUnacked` lane to `inboxed` on the next resume/connectivity pass (no new re-send path introduced), then by the receipt to `delivered`.
- **TC-185-04 (device-proof, PROD-CRITICAL)** — reproduce the captured flow: sender relay down → send → row stays retriable (single tick, **no Retry**) → connection returns → message reaches the peer → row converges to `delivered`. The `DELIVERY_RECEIPT_NO_TRANSITION status:"failed"` symptom is gone.

### Group B — defensive receipt arm (belt-and-suspenders for rows that still reach `failed`)

- **TC-185-10** — a `failed` outgoing row that receives a **valid, peer-authenticated** receipt for its id transitions to `delivered` (today: `DELIVERY_RECEIPT_NO_TRANSITION`).
- **TC-185-11** — receiver-auth preserved: a receipt whose `from` ≠ the row's `contactPeerId` does **not** lift a `failed` row (`DELIVERY_RECEIPT_FOREIGN_PEER` still guards).
- **TC-185-12** — a genuinely-undelivered `failed` row with **no** receipt stays `failed`. Only a receiver confirmation lifts it.
- **TC-185-13** — idempotency: a duplicate receipt on an already-lifted row is a no-op; the existing `inboxed→delivered` and `sent→delivered` arms still fire (17-happy-path not regressed).

### Group C — Bug 2: the failure snackbar names the real cause

- **TC-185-20** — when the **device is offline** at send-failure time, the snackbar reads the sender-offline copy ("no internet connection / will send when back online"), regardless of whether the underlying result was `peerNotFound` or `dialFailed`.
- **TC-185-21** — when the **device is online** and the send fails `peerNotFound`, the snackbar still attributes to the contact ("Contact appears offline."). No over-correction.
- **TC-185-22 (device-proof)** — send while the sender is offline → snackbar shows the honest "no connection" message, not "Contact appears offline."

### Group D — UI + invariants / no-regress

- **TC-185-30 (UI)** — an offline send renders the in-flight **single tick** (retriable `sent`), **not** the red Retry/error glyph; and when its status later reaches `delivered`, the bubble shows the delivered glyph. (No Retry ever appears for a purely-offline send.)
- **TC-185-31** — "never falsely delivered": nothing here marks a row `delivered` without a receiver receipt; a still-optimistic/`sent` row is never auto-`delivered`.
- **TC-185-32** — the `failed→delivered` and offline-`sent` transitions ride `conditionalTransitionStatus` / atomic writes, so a racing custody sweep or late/duplicate receipt cannot downgrade or double-apply (D-6 consistency).

---

## Scope guard (non-goals)

- **Do NOT** fix the underlying cross-network reachability (DCUtR not hole-punching mobile↔WiFi; relay-outage recovery). Real but separate; 185 is about the UX/status telling the truth and reusing the existing convergence lane.
- **Do NOT** change transport budgets / the send race (the warm-send-budget investigation concluded: warm LAN ~170 ms; the cross-network 6 s was a relay outage, not a budget).
- **Do NOT** build a NEW retry/reconcile mechanism — reuse the existing `retryUnacked` + delivery-receipt lane. The change is (i) which status an offline send lands in, (ii) an honest snackbar, (iii) a defensive `failed→delivered` receipt arm.
- **Do NOT** keep a *genuinely* failed send (bad payload, unsupported encryption, or online-but-recipient-unreachable) retriable — those must still surface `failed`/Retry.
- 1:1 only (groups have their own receipt/status model).
