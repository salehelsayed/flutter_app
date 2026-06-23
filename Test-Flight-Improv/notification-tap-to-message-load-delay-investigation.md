# Why tapping a 1:1 notification opens the chat but takes seconds to show the messages

**Type:** Diagnostic report (report-only — no code changes)
**Date:** 2026-06-23
**Branch:** `new-feed`
**Scope:** The lag between tapping a 1:1 message notification and the just-received message(s) actually appearing in the conversation screen.
**Method:** graphify-first trace of the full flow (OS tap → route → screen → relay drain → render), fanned out across 6 stages by 12 agents, every latency contributor adversarially re-verified against real source. File:line references below are verified.
**Revision:** v2 (2026-06-23) — corrected the warm-path framing per review (see *Corrections in this revision* at the end). The original draft over-generalized "screen opens stale, then drain catches up"; that is true for some cases but **not** the successful warm path, where the message is already persisted before the screen appears.

---

## TL;DR

The underlying cause is always the same: **the just-pushed messages are not on the device yet** — their encrypted bytes are still in the relay's offline inbox (`relay:inbox`), and the app must do a **relay round-trip → fetch → decrypt → write to the encrypted DB** before they can render. But *how the delay is experienced depends on the launch state*, and there are two genuinely different failures:

- **Warm (app backgrounded), pre-route drain succeeds — the common, "successful" case.** The route handler **awaits a relay inbox fetch _before it even pushes the conversation screen_** (`prepare_notification_open_use_case.dart:29`, up to 3s). So you tap, sit on the previous screen / a transition for a beat, and then the conversation opens **already populated** (the messages were persisted by that pre-route drain, so `_loadInitialPage` reads them straight from the DB). **Here the bug is _delay before the screen appears_, not stale content.**
- **Cold launch, an already-open conversation, or when that pre-route drain is slow / times out / the message is beyond inbox page 1.** Now the screen opens on **stale local history** missing the new messages, and they pop in a beat later when a *second* drain (the screen's own `_drainAndReloadOnce`, or the resume drain) completes — **with no spinner or "catching up…" indicator**, so it reads as "the app froze then caught up." That is the "feels buggy / can't load the messages" impression.

Aggravating factors common to both: the per-message replay loop is **fully serial** and (newly found) does a **live delivery-receipt network send back to the sender for each message** inside the loop — so with 4 messages the *drain's completion* (and thus the route delay / reload) trails into a multi-second tail. On a cold launch it is worse still: the relay fetch can't even begin until the whole app + Go p2p node + relay connection finish booting.

> The original report's "opens stale then pops in" describes the *second* bullet. For the *first* (successful warm) bullet the experience is a dead pause **before** the conversation appears — a different fix priority (kill the pre-route await) than the missing-affordance fix.

**The single highest-leverage UX fix is small:** show a "catching up…" affordance while the drain is in flight (today the in-flight flag exists but is never shown to the UI). **The highest-leverage latency fixes** are: don't await the relay drain _before_ pushing the screen, parallelize the per-message replay, and stop blocking the visible render on the per-message delivery-receipt send. **The big swing** (eliminate the drain entirely for small text) is feasible — the iOS notification extension already decrypts the message — but is a large, careful piece of work.

---

## The flow, and where the time goes

### Warm resume (app was backgrounded, Go node still running) — the common case

```
OS delivers tap
  → FCM onMessageOpenedApp                              main.dart:4414
  → _routeRemoteNotificationOpen                        main.dart:3673
       dedupe gate + markRecentAnnouncement (awaited)   main.dart:3674, 3690
  → dispatch awaits onBeforeRouteTarget FIRST           notification_route_dispatch.dart:70
       _prepareNotificationRouteTarget                  main.dart:4118
         await loadIdentity()                           main.dart:4121
         prepareNotificationOpen(kind=conversation):
           ★ await drainOfflineInbox()  ◄── up to 3s    prepare_notification_open_use_case.dart:29
  → THEN onRouteTarget → _handleNotificationRouteTarget main.dart:3715, 3931
       getContact(peerId)  (local SQLCipher, cheap)     main.dart:3956
       _openConversationForContact → navigator.push     main.dart:4033
         ConversationWired(... NO initialMessages ...)   main.dart:4035
  → ConversationWired.initState                         conversation_wired.dart:477
       _loadInitialPage()  → renders STALE history       conversation_wired.dart:516
       _startListeningForMessages() (no replay)          conversation_wired.dart:518
       ★ unawaited(_drainAndReloadOnce('notif_tap'))     conversation_wired.dart:531
            await drainOfflineInbox()  ◄── up to 3s AGAIN conversation_wired.dart:1194
            _reloadLatestPageForRecovery → setState       conversation_wired.dart:1196
```

So on warm resume the new message is gated behind **two** awaited relay drains (`★`), each with a 3s budget. The crucial detail: the **first** drain runs *before* the screen is pushed and **persists inbox page 1**, so by the time `_loadInitialPage` reads the DB the messages are usually already there — the screen opens **populated**, and the user-visible cost is the pre-screen route delay. The **second** drain (inside the screen) is then largely redundant for page-1 messages (it re-fetches, finds nothing new, no visible change). The stale-then-pop-in experience only appears when this first drain did *not* land the message first: it timed out (3s budget), failed, the conversation was already-active (no fresh screen pushed — the resume drain surfaces it), or the message was on a later inbox page (see A5).

### Cold launch (app was killed) — worse

The conversation route is **not dispatched until the Go p2p node has fully started**: the FCM "launch" message (`getInitialMessage`) is only read at `startup_router.dart:659`, _inside_ `_doStartP2P()`, _after_ `await startP2PNode()` returns (`startup_router.dart:635`). Before any of that, `main()` must finish its serial bootstrap (Firebase init, SQLCipher open + key derivation) before `runApp` (`main.dart:386-465, 3072`), and the route is then held until the Feed home is up (`_startupHomeReady`, ~1-2s per the in-code comment at `main.dart:3803-3804`). Worse still, the Go node reports `isStarted=true` **before the relay is actually connected** (`node.go:406`, relay dial is fired into a background goroutine and `Start` returns at `node.go:467`), so the first drain pays a **cold relay dial + Noise handshake to the EC2 relay** inside `InboxRetrievePendingWithTimeout` (`inbox.go:414`).

> Note (corrected v2): on the cold `getInitialMessage` path the screen-level `_drainAndReloadOnce('notif_tap')` does **not** hit the `!isStarted` early-return. That route is dispatched from *inside* `_doStartP2P()` only **after** `await startP2PNode()` succeeds (`startup_router.dart:635 → 659`), so by the time the screen mounts and runs its drain the node is already `started` — it runs a **real** drain that pays the cold relay dial (C4), fetch, decrypt, persist, reload. The screen shows stale history and the messages "pop in" some seconds later with **no affordance**. (The `!isStarted` defer + `_scheduleStartupDrain` latch — issue 141 — applies to drains kicked off *during* the startup window, e.g. the FeedWired init drain, not to this post-node-start screen drain. That belt-and-suspenders startup drain may independently have persisted page 1 around node-start time, but it is not what this screen path depends on.)

---

## Ranked latency contributors (verified)

### A. Warm-resume costs (the everyday case)

| # | Contributor | Evidence | Cost |
|---|---|---|---|
| A1 | **Pre-push relay drain blocks the screen from appearing.** The route dispatch `await`s `drainOfflineInbox()` in the `onBefore` hook *before* the conversation screen is pushed. | `prepare_notification_open_use_case.dart:29` (awaited via `notification_route_dispatch.dart:70`, wired at `main.dart:3714`) | **Up to ~3s** (`foregroundInboxTimeout = 3s`, `p2p_service_impl.dart:252`), network-RTT-bound |
| A2 | **The screen then does a SECOND awaited drain** before the new rows render. | `conversation_wired.dart:1194` (from `initState:531`) | **Up to ~3s again** |
| A3 | **Per-message replay is strictly serial**, and (newly found) each message does an **awaited live delivery-receipt SEND back to the sender** (`sendMessageWithReply` = a full network round-trip) inside the loop, plus **3 serial SQLCipher writes** (stage INSERT → messages INSERT → stage DELETE). *Nuance (v2):* the receipt send runs **after** `saveMessage` (`handle_incoming_chat_message_use_case.dart:507` then `:510`), so for an **already-open screen** the message renders via the repo-change stream at `saveMessage` time, **ahead of** its own receipt — the receipt does **not** block that first row's render. But because the loop is serial, message N+1's `saveMessage` (and thus its render) is gated behind message N's receipt round-trip; and the **whole drain future** (which gates the *pre-route screen appearance* on warm, and `_reloadLatestPageForRecovery`) only resolves after **all** receipts. | replay loop `p2p_service_impl.dart:1070-1118`; repo-change render `conversation_wired.dart:1485-1497`; receipt send `:510` → `send_delivery_receipt_use_case.dart:109`; staging `inbox_staging_repository_impl.dart:62`, delete `p2p_service_impl.dart:1316` | **Hundreds of ms → seconds**, dominated by per-message network/bridge round-trips, *not* the ML-KEM crypto (decap is sub-ms). Heaviest where it gates the drain future (route delay) and inter-message spacing. |
| A4 | **Drain ACK-deletes relay entries via a second awaited round-trip BEFORE replay** — the ack sits on the path to message *visibility*, not just cleanup. | `p2p_service_impl.dart:1488-1538` (ack at `:1511`, replay at `:1536`) | +1 relay RTT |
| A5 | **Drain is single-flighted + paged, but only page 1 is awaited** (corrected v2). `drainOfflineInbox()` (`waitForAllPages=false`) awaits **page 1 only**; later pages continue in the **background** (`_continueDrainingOfflineInboxDurably`, unawaited) unless `drainOfflineInboxFully()` is used. So a message **beyond inbox page 1** (large backlog ahead of it) is *not* awaited — it surfaces later asynchronously via the background continuation + repo-change stream, not via an awaited multi-RTT block. For 4 small text messages (Limit 50/page) all 4 are on page 1, so this is an edge case. Separately, a tap drain can still block on an unrelated **in-flight** drain (boot/30s-health-check) before starting (coalescing). | coalesce `p2p_service_impl.dart:1557-1569`; first-page await `:1651`; background continuation `:1592, 1666`; `maxInboxPages` `:712` | page 1: ≤3s budget; pages 2+: background (not on the awaited path) |
| A6 | **No `initialMessages` on the notif-tap path** → forces a `_loadInitialPage()` DB read before anything paints; screen shows stale history (skeleton only shows while the list is empty). | `main.dart:4035` (no `initialMessages`); branch `conversation_wired.dart:515-517`; skeleton gate `conversation_screen.dart:303-304, 371` | tens of ms + a stale-content flash |

### B. The "feels buggy" UX gap (highest perceived impact, lowest fix cost)

| # | Contributor | Evidence |
|---|---|---|
| B1 | **No progress affordance during the drain.** `_drainReloadInFlight` exists but is **read/written only inside `_drainAndReloadOnce`** — it is never passed to `build()` / `ConversationScreen`, so nothing renders a spinner/banner while the relay fetch is in flight. The only spinner in the list is the *older-message pagination* indicator (`isLoadingMore`), unrelated to the drain. The user sees a static, stale list, then messages abruptly appear. | flag `conversation_wired.dart:1165`, used only at `:1183/1187/1221`; `build()` forwards `initialLoadDone/isLoadingMore/isSending` but not the drain flag, `conversation_wired.dart:4032`; pagination-only spinner `conversation_screen.dart:430, 645-646` |
| B2 | **Then a 300ms animated scroll-to-bottom** fires after the dead pause, reinforcing the "janky catch-up" feel. | `conversation_wired.dart:3954-3963` (from `_reloadLatestPageForRecovery:1253`) |
| B3 | **A resume during the in-flight drain coalesces a second blocking pass**, extending the no-affordance window. | `didChangeAppLifecycleState` `conversation_wired.dart:4022-4028`; pending-pass loop `:1190-1219` |

### C. Cold-launch-only costs (app was killed)

| # | Contributor | Evidence | Cost |
|---|---|---|---|
| C1 | `main()` bootstrap blocks `runApp`: Firebase init + `getApplicationDocumentsDirectory` + Keychain wipe + **SQLCipher open/key-derivation** (+ migrations on version bumps only). | `main.dart:386-465, 3072` | hundreds of ms → seconds |
| C2 | **FCM launch message only read AFTER full Go node start.** | `startup_router.dart:635 → 659` | seconds (gated on `startP2PNode`) |
| C3 | Route held until Feed home is up (`_startupHomeReady`). | `main.dart:3804` (comment cites ~1-2s at `:3803`) | ~1-2s |
| C4 | **Drain fires at `isStarted=true` but before the relay is connected**, so it pays a cold relay dial + Noise handshake to EC2 instead of reusing a warm connection. | Go `node.go:406` (isStarted) / `:429-439` (relay dial backgrounded) / `:467` (returns); cold dial in `inbox.go:414`; defer latch `p2p_service_impl.dart:3889` | network-RTT-bound, can be seconds on a flaky link |
| C5 | P2P start is itself deferred a frame (`deferredStartupMode`) to protect first-frame rendering. | `startup_router.dart:615-624`, `startup_config.dart:7` | ~frame(s) |

### What is **not** a meaningful contributor (ruled out)

- `getContact(peerId)` on the dispatch path is a **local SQLCipher read**, not network (`main.dart:3956` → `contacts_db_helpers.dart:37`). Cheap.
- `loadIdentity()` is **cache-first** and a local read (`identity_repository_impl.dart:46-58`). Cheap.
- The body `AnimatedSwitcher` 400ms cross-fade is paid **once** (empty/loading → messages), **not** on every drain merge (the key doesn't change) — `conversation_screen.dart:301-306, 407`.
- The ML-KEM-768 decapsulation math is **sub-millisecond** — the per-message cost is the bridge/network round-trips around it, not the crypto.

---

## Improvement options (ranked)

### Quick wins (small effort, high impact)

1. **Show a "catching up…" affordance while `_drainReloadInFlight` is true.** Thread the flag from `_ConversationWiredState` into `build()`/`ConversationScreen` (a new `isSyncingNewMessages` bool) and render a lightweight header throbber or top banner. Today the flag is a plain field mutated without `setState`, so it must be wrapped in `setState` (toggle points `conversation_wired.dart:1187, 1221`). **This is the most direct fix for the "feels buggy" complaint** and is the cheapest change here.
   - *Target:* `conversation_wired.dart` / `conversation_screen.dart` · *Risk:* ensure the banner doesn't shift scroll or retrigger pagination.

2. **Don't `await` the relay drain before pushing the conversation screen.** The pre-push drain (`prepare_notification_open_use_case.dart:29`) is redundant for the conversation kind — the screen already fires its own `_drainAndReloadOnce('notif_tap')`. Make the conversation branch fire-and-forget so the screen appears immediately, up to ~3s sooner on a slow relay. Keep the group-kind targeted drain.
   - **Explicit tradeoff (v2):** because the pre-route drain currently persists page 1 *before* the screen opens, the successful warm case opens **already populated**. Removing the await flips that case from "pre-screen pause, then populated" to "instant screen showing stale history, then catch-up." That is only a net win **paired with #1** (the "catching up…" affordance) — otherwise you trade a pre-screen pause for a no-affordance stale-then-pop-in. Decide the two together.
   - *Target:* `prepare_notification_open_use_case.dart` · *Risk:* verify the already-active suppression path still self-heals (it relies on the mounted screen's resume drain — parity preserved).

3. **Don't block the visible render on the ACK round-trip.** `callP2PInboxAck` is awaited *before* replay (`p2p_service_impl.dart:1511`); since staged entries are deduped on a later drain, the ack can run *after* replay or fire-and-forget, removing one relay RTT from the user-visible path.
   - *Target:* `p2p_service_impl.dart` · *Risk:* slightly widens the window where a crash leaves relay copies undeleted (harmless dups, deduped by staging). Preserve the migration-gate re-check at the ack boundary.

### Medium

4. **Parallelize the per-message replay.** Decrypt the page's entries concurrently (bounded pool) instead of the strict serial `for`-loop (`p2p_service_impl.dart:1070-1118`); keep DB writes ordered/transactional. For 4 messages this collapses 4 serial bridge round-trips into roughly one. *Pair with:* move the **per-message delivery-receipt send** (A3, `handle_incoming_chat_message_use_case.dart:510`) off the visible critical path — it's a live network round-trip per message that currently blocks the render.
   - *Risk:* must preserve per-conversation ordering, the stage→commit→delete durability contract, and notification-suppression semantics.

5. **Batch the staged INSERTs into one SQLCipher transaction per page** to amortize encrypted-write/fsync overhead (currently one transaction per message).
   - *Risk:* per-message savepoints so one bad envelope doesn't roll back siblings.

6. **Pass `initialMessages` on the notif-tap entry** so the screen paints cached history in the first frame (synchronous fast path `conversation_wired.dart:504-514`) instead of the `_loadInitialPage` flash. Must be paired with #1 (the affordance) since cached history still misses the new message.

7. **Start the FCM-launch route dispatch in parallel with node start on cold launch**, rather than strictly after `await startP2PNode()` (`startup_router.dart:635→659`). The push only needs the local contact + home; the drain self-defers cleanly until the node is up (`_pendingStartupDrain` latch).
   - *Risk:* must preserve the home-ready clobber guard (issue 133) so the conversation isn't replaced by the Feed `pushReplacement`.

### Large — the "make it instant" swing

8. **Persist the message from the push so no drain is needed (small-text 1:1).** The raw material and the hard part (background decryption) already exist:
   - The relay's FCM push **already carries the full encrypted envelope** (`kem`+`ciphertext`+`nonce`) in the `data` map when it fits under `maxPushDataBytes=4000` (`go-relay-server/inbox.go:284-309, 536-554`). Small text fits; **media/long text is stripped to a content-free fallback** (`preview_unavailable=1`, `:476-526`) — so this fix is structurally limited to small text.
   - The **iOS Notification Service Extension already decrypts the envelope** out-of-process — it reads the ML-KEM secret from the shared Keychain group and calls the linked Go `BridgeDecryptMessage` (`NotificationPreviewResolver.swift:160-233`, `BridgePushDecryptor.swift:565-600`) — **and then throws the plaintext away** after rendering the banner. Capturing that output is nearly free.
   - **What's missing:** nothing persists it. Proposed lowest-risk path: NSE writes the decrypted message (or, for security, just the envelope) to a file in the **shared app-group container** (where `AppGroupPushDedupeStore` already writes); on next foreground a Dart "spool drain" inserts it via the existing dedup'd insert path, idempotent by `message_id`. The relay drain stays as the durable backstop (it is also the only thing that ACK-purges `relay:inbox`).
   - **Blockers/risks:** the main SQLCipher DB lives at `getDatabasesPath()` (app-private), **unreachable by the iOS NSE** (`encrypted_db_opener.dart:54`) — hence spool-then-commit rather than NSE-writes-DB. Android can open the DB from the background isolate but **currently isn't wired with a decrypt fn** (`background_message_handler.dart:165` → generic fallback). Must replicate the live receive path's **dedup/ordering** to avoid double-cards (cf. the F8 id-only-dedup / forward-share `dedupKey` prerequisites), and the relay entry is purged only by a real `Retrieve` (`go-relay-server/inbox.go:879-896`), so the drain remains non-eliminable for *purge* even if rendering is made local.

---

## You can't currently measure this in production

The instrumentation to confirm where the seconds go is **debug-only and points at the wrong milestone**:

- `NOTIFICATION_TAP_TO_MESSAGE_TIMING` stops at the **stale-history render**, not the post-drain render that shows the new message (`notification_tap_timing.dart:9`; emitted at `conversation_wired.dart:512, 1149`; the drain at `:1179` is never timed — its `CONV_FL_NOTIF_DRAIN_REFETCH` carries only before/after **counts**, no duration).
- `tappedAt` is **app-process time** (`DateTime.now()` in the Dart handler, `main.dart:3688/3776`), not the OS tap time — so cold-start engine-boot seconds are excluded.
- **No cold-vs-warm tag**, and the cold local-notification path never sets `tappedAt` at all (`main.dart:3758`).
- **All FlowEvents are off in release builds** — `flowEventLoggingEnabled = kDebugMode` (`flow_event_emitter.dart:6`); the only non-debug sink is `@visibleForTesting`.
- The **relay round-trips are untimed** (`callP2PInboxRetrievePending:1399`, `callP2PInboxAck:1511` have no Stopwatch); node-start cost lives in a disconnected `TIME_TO_ONLINE_BADGE` metric with no correlation id linking it to the blocked tap.

**Recommendation:** add a release-safe sampled sink, re-anchor the metric to the post-drain render (emit `staleRenderMs` + `liveRenderMs` from the same `tappedAt`), wrap the drain/retrieve in Stopwatches, thread the OS tap timestamp + a cold/warm tag, and add a correlation id tying the tap → node-start-wait → drain → render. (Pure-additive telemetry; details in the per-stage findings.)

---

## Open questions (need a device / real network to answer)

- Real wall-clock of `startP2PNode()` and the cold relay dial on a mid-tier device — that sets the cold-tap floor.
- On warm resume with a healthy relay, how often does the pre-push drain actually cost the full 3s vs a fast RTT?
- Per-message: is the **delivery-receipt send** (A3) actually the dominant cost, vs the bridge decrypt and the 3 SQLCipher writes? `INBOX_DELIVERY_TIMING` (`deliveryMs`, `p2p_service_impl.dart:1107`) and Go `decryptMs` would quantify it.
- What fraction of real 1:1 traffic is small enough text to benefit from push-prefetch (≤ ~2.5KB envelope after the ~1.4KB ML-KEM `kem`)?
- iOS APNs MethodChannel bridge path: does `_ensureRuntimeServicesReady()` add a fixed ~500ms retry on first probe (`main.dart:3636-3670`)?

---

## Corrections in this revision (v2, 2026-06-23, from review)

Four accurate corrections to the original draft, all verified against source:

1. **Warm-success is route-delay, not stale content.** The pre-route drain is *awaited before the screen is pushed* and persists inbox page 1, so on the successful warm path the conversation opens **already populated** after a pre-screen pause. "Opens stale, then drain catches up" is only the cold / already-active / drain-timed-out / message-beyond-page-1 cases. (TL;DR, Warm-flow section, fix #2.)
2. **Only page 1 is awaited.** `drainOfflineInbox()` awaits page 1; later pages continue in the background unless `drainOfflineInboxFully()` is used. The original A5 overstated "rendering waits on several sequential page RTTs." (A5.)
3. **Delivery receipt doesn't block an open screen's first render.** Receipts block the *pre-route drain* and the drain future / reload, but a mounted screen renders each message via the repo-change stream at `saveMessage` time — *before* its own receipt send. The serial loop still gates *subsequent* messages behind the prior message's receipt. (A3.)
4. **Cold `getInitialMessage` does not early-return on `!isStarted`.** That route is dispatched after `startP2PNode()` succeeds, so the screen-drain is a real started-path drain (paying the cold relay dial), not the issue-141 defer. (Cold-flow blockquote.)

These refine *where* the delay is felt and tighten the fix priorities; they do not change the root cause (messages live in `relay:inbox` and require a relay round-trip + decrypt + persist before they can render) or the headline fixes (affordance, drop the pre-route await *together with* the affordance, parallelize replay, push-prefetch).

---

## Appendix — key files

| Concern | File |
|---|---|
| Notification routing / dispatch | `lib/main.dart` (`:3673, 3714, 3931, 4033`) |
| Pre-push drain hook | `lib/features/push/application/prepare_notification_open_use_case.dart:29` |
| Conversation screen (init, drain, reload) | `lib/features/conversation/presentation/screens/conversation_wired.dart` (`:477, 531, 1179, 1230`) |
| Conversation view (skeleton / spinner gates) | `lib/features/conversation/presentation/screens/conversation_screen.dart` (`:303, 371, 645`) |
| Relay drain / staging / replay / ack | `lib/core/services/p2p_service_impl.dart` (`:252, 1070, 1394, 1488, 1592, 3885`) |
| Per-message receive + receipt send | `lib/features/conversation/application/handle_incoming_chat_message_use_case.dart` (`:164, 507, 510`); `send_delivery_receipt_use_case.dart:109` |
| Cold-launch startup | `lib/features/identity/presentation/startup_router.dart` (`:615, 635, 659`) |
| Go node start / relay dial | `go-mknoon/node/node.go` (`:361, 406, 467`); `go-mknoon/node/inbox.go` (`:394, 414, 468`) |
| Relay push payload (4KB limit) | `go-relay-server/inbox.go` (`:284, 476, 536, 879`) |
| iOS push decrypt (already decrypts, discards) | `ios/NotificationService/NotificationPreviewResolver.swift` (`:160`); `BridgePushDecryptor.swift:565` |
| Timing telemetry | `lib/core/utils/notification_tap_timing.dart:9`; `lib/core/utils/flow_event_emitter.dart:6` |
