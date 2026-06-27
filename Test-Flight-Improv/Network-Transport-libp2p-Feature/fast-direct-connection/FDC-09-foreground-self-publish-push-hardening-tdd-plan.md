# FDC-09 — Foreground self-publish + push-to-wake hardening  (New Feature)

Status: **ready (host tiers) — finalized against FDC-S3 (closed 2026-06-27); device push-proof (TC-09-20..24) + device-tuning of TTL constants remain. Lands AFTER FDC-08 (rebases on its presence_store.go / bridge_presence.go / HandleInboxStream host injection).**

Spec: Network-Arch/Fast-Direct-Connection-Architecture-Proposal.md (§6.3 presence self-publish; §12 "Push-to-wake hardening" verbatim borrow)

---

## ✅ FINALIZED against FDC-S3 (was: DRAFT — finalize after FDC-S3)

> **FDC-S3 is CLOSED (decided 2026-06-27).** The mechanism this plan was gated on is **resolved** —
> every `<from FDC-S3>` placeholder is now locked. Locked decisions consumed here:
> - **WRITE / self-publish = Option C `presence_set`** client→relay status-push (the **only**
>   mechanism that carries an explicit foreground/background *label*; the relay provably cannot infer
>   it). **Option B (gossipsub beacon) REJECTED** — no reopen (pubsub stays group-only).
> - **Constants (device-tunable, inherited from FDC-S3):** presence-entry TTL ≈ **180 s**; foreground
>   heartbeat/refresh ≈ **60 s**. *(The client `presence_get` cache 10–15 s is FDC-08's read side, NOT
>   this plan's.)*
> - **Additive PR pair + shared store:** `presence_get` (FDC-08 read) and `presence_set` (FDC-09 write)
>   ship as a pair over **one** TTL'd `presence_store.go` map. **FDC-08 OWNS creation** of
>   `presence_store.go` + `bridge_presence.go` + the `HandleInboxStream` host/store injection; **FDC-09
>   REBASES onto them and adds the WRITE** (the `presence_set` arm + heartbeat that enriches the same
>   map). Landing order **FDC-10 → FDC-08 → FDC-09** (serial on `inbox.go`; FDC-00 Track E / roadmap
>   Phase 2). The shared map's `sync.Map`/mutex guard + `go test -race` is added by FDC-08 (R6,
>   UNCONDITIONAL); **FDC-09 is a NEW co-writer on it → must keep it race-clean** (see Scope Guard).
> - **Push-hardening (§12) confirmed in FDC-09 scope** (access-token gate, opaque routing, visible push)
>   — *not* S3-gated (implementation-ready from source today), but it co-edits the same `inbox.go` push
>   path so it rides this plan. It is **independent of the presence_set write** and may be sequenced as a
>   separate sub-PR if desired (they only share the push-path edits).
>
> **What still gates closure (NOT the mechanism):** the **device push-proof** rows TC-09-20..24 (real
> 2-device pair + real relay + APNs — visible-wake-not-throttled, pause-publish-lands, anti-spam wake
> gate) and the **device-tuning** of the TTL constants (FDC-S3 Methods 1/2 inherited). These need a
> deployable relay (FDC-09 stands it up per the FDC-S3 risk note); they are NOT a mechanism decision.
>
> **Anchor drift note (re-grounded 2026-06-27 on shared `new-orbit`):** concurrent FDC-03/05/06 landed
> and restructured the lifecycle + send paths; **every anchor below was re-grounded against live
> source.** Notably: the relay store→push is **conditional on `metadata.ShouldNotify`** (`inbox.go:866-868`),
> **not** unconditional; the pause path is **no longer local-DB-only** — FDC-06 pause-flush ships ON and
> does bounded network work in the NEW `lib/core/lifecycle/handle_app_paused.dart`; `registerPushToken`
> moved `:3889→:4220`; the resume gate is `:121-133` and FDC-05's parallel re-prime block is `:174-240`.
> Re-verify by **symbol**, not line, before editing.

---

## Source Of Truth

- **Proposal §6.3** ("online-ish, never foreground" → foreground/background must be **self-published**
  by the peer, "either a lightweight gossipsub heartbeat beacon … or an explicit client→relay status
  push on pause/resume. Inferring it from connectedness will be wrong on iOS").
- **Proposal §12 → "Strongly-validated patterns to borrow" → "Push-to-wake hardening":** per-recipient
  **access-token** gate (only contacts can wake you — anti-spam); **opaque-token routing** with the
  push path **decoupled from the message path (unlinkable)**; a **visible** push (iOS throttles silent
  content-available pushes to ~1–2/hr, no execution guarantee). "The push is only a wake signal;
  content is pulled from the inbox."
- **FDC-S3 decision (CLOSED 2026-06-27)** — `FDC-S3-presence-signal-decision.md` §"Canonical contract
  consumed by FDC-08 / FDC-09" + §"Carry-forward to FDC-09 finalize (write side)". **This is now the
  binding write-side contract:** self-publish = Option C `presence_set` (bridge call `presenceSet`,
  move-gate token `p2p_set_presence`); B rejected; constants TTL 180 s / heartbeat 60 s; **presence is
  a HINT, never load-bearing — the inbox is always the guarantee** (hard acceptance gate, §6.3/§12);
  shared TTL'd presence store co-owned with FDC-08 (`sync.Map`/mutex + `go test -race`). FDC-S3's own
  carry-forward confirms FDC-09 **already encodes the decision correctly** — finalize is anchor
  re-grounding + naming/sequencing alignment, not a decision change.
- **Naming contract (canonical; symmetric with FDC-08 / FDC-15):** WRITE action token = `presence_set`;
  move-feature gate token = `p2p_set_presence`; gomobile bridge export = **`PresenceSet(paramsJSON string) string`**
  in the NEW `go-mknoon/bridge/bridge_presence.go` (symmetric with FDC-08's `PresenceGet`; **drop the
  earlier `RelaySetPresence`/`InboxSetPresence` names**); node fn `RelayPresenceSet(...)` in
  `go-mknoon/node/inbox.go`; Dart cmd `'relay:presence_set': _CmdSpec('relayPresenceSet', true)`;
  Dart bridge method `callP2PRelayPresenceSet`; `P2PService` method `setPresence(state, ttlMs)`;
  relay handler `handlePresenceSet` (named, not inline). All ride the JSON-string FFI contract
  (params-JSON in / result-JSON out) — no struct-typed FFI.
- **FDC-00 roadmap** row FDC-09 + the GATING graph (`FDC-S3 ✅ → FDC-08, FDC-09`); **Track E / Phase 2
  order: FDC-10 → FDC-08 → FDC-09** (serial on `inbox.go`); the **Collision map**
  (`inbox.go`/`push_token_store.go`/`presence_store.go` shared with FDC-08, FDC-10; serialize) and the
  **Move-feature interaction** (FDC-09 fix: `presence_set` gated `p2p_set_presence`).
- `scripts/run_test_gates.sh` wins over prose for any test-name/count claim (the arrays decide what
  the gate runs). **`GOTOOLCHAIN=go1.25.0` is MANDATORY for both Go modules** (go1.26.x panics
  `crypto/tls bug: where's my session ticket?`; known hazard).

---

## Session Classification

**implementation-ready (host tiers) + device-push-proof-gated (closure).** FDC-S3 is closed, so the
mechanism (Option C `presence_set`), the constants (TTL 180 s / hb 60 s), and the shared-store
ownership are **decided** — the host-testable Go + Dart tiers (presence_set dispatch + TTL store
write, the self-publish use-case + heartbeat, the §12 push-hardening shape) are **fully
implementation-ready now**, once FDC-09 **rebases onto FDC-08's `presence_store.go` /
`bridge_presence.go` / `HandleInboxStream` host injection** (land FDC-08 first). The remaining gate is
the **device push-proof** (TC-09-20..24: visible-wake-not-throttled, pause-publish-lands, anti-spam
wake-gate — real 2-device + relay + APNs) and **device-tuning** of the TTL constants — a
deploy/measurement task, **not** a mechanism decision.

---

## Exact Problem Statement

Two coupled gaps, both grounded in source:

**(1) The peer cannot announce foreground/background; the relay can only see a TTL-lagged socket.**
`go-relay-server/main.go:145-163` handles only `EvtPeerConnectednessChanged` (raw libp2p socket
connectedness; Connected branch `:149-154`, `RecordPeerSeen` `:152`), which *lingers seconds after iOS
backgrounding* and **cannot express foreground** (proposal §1 row 3, §6.3; FDC-S3 Background). There is
**no presence-write action** today — the inbox dispatch (`inbox.go:1530 switch req.Action`, 10 cases)
has `store|retrieve|retrieve_pending|ack|register_token|unregister_token|group_store|group_retrieve|
group_retrieve_cursor|group_history_repair_range` and a `default: "Unknown action: %s"` (`:1712-1713`)
— so a peer has no way to self-publish "I am foregrounded" for the §6.3 emphasis branch FDC-08
consumes. (Good news for the write shape: `inboxRequest` already carries a
`Metadata map[string]interface{}` field (`inbox.go:1429`), so `presence_set{state, ttlMs}` fits the
existing request struct with no new field — the `inboxResponse` (`:1447-1465`) has no `Metadata`, but
the write only needs `Status:"OK"`.)

**(2) Push-to-wake is unhardened — coupled to the message path, missing a contact gate, and
silent-leaning.** Re-grounded in source (2026-06-27):
- **The push is already conditional, NOT unconditional — but on the wrong axis.** The push fires from
  inside `InboxStore.Store` at `inbox.go:866-868`, gated on
  `if metadata := extractChatPushMetadata(entry.Message); metadata.ShouldNotify { go is.push.SendNotification(...) }`
  — and duplicates (`:846`) and rejected-full stores (`:854`) early-return *before* the push entirely.
  So a push fires for a *new, user-visible* store to a recipient **with a registered token**, with **no
  per-recipient contact / access-token check** (`SendNotification :135-146` → `LookupToken(toPeerId)`
  `push_token_store.go:38-46`, early-return on `missing_token`). The gap is the absence of a *"only
  contacts can wake you"* authorization (proposal §12 anti-spam) — **the access-token gate must LAYER
  ON TOP of the existing `ShouldNotify` condition, not replace it or invent a first gate.**
- **Coupled / linkable.** `buildPushMessage` embeds the **sender peerId** into push `data["sender_id"]`
  at **two** sites: `inbox.go:289` (cipher-only `new_message` path) **and** `:351` (visible-notification
  path). The wake carries the sender↔recipient linkage FCM/APNs can observe (proposal §12 "unlinkable")
  — opaque-token routing must scrub **both** sites.
- **Silent-leaning.** The `new_message` wake uses `buildCiphertextOnlyPushMessage` (`inbox.go:468`-built
  oversized fallback aside) with `ContentAvailable: true` + `MutableContent: true` (`inbox.go:426-427`,
  for the NSE decrypt) — i.e. it **requests background/silent delivery** which iOS throttles to ~1–2/hr
  (proposal §12). The >4 KB path already swaps to a visible fallback (`buildOversizedFallbackPushMessage`
  `:468`, trigger `pushDataSize > maxPushDataBytes(4000)` `:53`/`:295-308`), but the normal wake does
  not *guarantee* a visible alert independent of the content-available path.

**Who feels it:** a backgrounded recipient (the common case the inbox exists for) gets a wake that
may be (a) throttled by iOS as silent, and (b) spammable by any non-contact who can store a
user-visible envelope to their inbox; and the sender's `direct vs inbox-first` emphasis (FDC-08) has
**no foreground signal** to key off.

**What must improve:** a peer can self-publish fg/bg (`presence_set`); the wake push is **visible**,
**contact-gated** (access-token, layered on the existing `ShouldNotify` gate), and
**decoupled/unlinkable** (opaque routing) from the message path.

**What must stay unchanged (preserved sentinels):**
- **Presence is a HINT, never load-bearing** — a *wrong* presence value must STILL deliver via inbox
  + push (FDC-S3 hard gate). Preserve: `offline_inbox_roundtrip` delivery semantics.
- **NET-REL-07 back-compat** — a new client hitting an *old* relay gets `"Unknown action: presence_set"`
  and degrades cleanly (skips self-publish, treats presence as `unknown`); a new relay must still serve
  *old* clients that never send `presence_set` and whose stores carry no access token.
- **Existing push delivery for contacts** — `register_token`/`SendNotification` for already-paired
  contacts keeps working; the existing `ShouldNotify` envelope-type filter and the `media >4 KB`
  visible-fallback (`inbox.go:295`/`:468`) stay intact.
- **Dedup-by-`messageId`** store behavior unchanged (`backend_memory.go:121-142`,
  `backend_redis.go:272-295`, `inbox_store.go:7,14`) — do **not** touch.
- **FDC-06 graceful pause-flush** (LANDED, ships ON via `kFdcPauseFlushEnabled`,
  `handle_app_paused.dart`) — the best-effort `presence_set{background}` on pause **piggybacks** its
  bounded `beginBackgroundTask` window; do **not** widen FDC-06's budget or break its
  `handle_app_paused_pause_flush_test.dart` floor.

---

## Root Cause (verify→refute confirmed)

| # | Mechanism (file:line, re-grounded 2026-06-27) | Confirmed |
|---|---|---|
| RC1 | **No presence-write action.** Dispatch `inbox.go:1530` (10 cases) has no `presence_set`; relay presence is only the connectedness-lagged `main.go:145-163` map (`RecordPeerSeen :152` is HLL-only, discards the peer ID → a per-peer last-seen map is net-new, owned by FDC-08). | ✅ read |
| RC2 | **Push coupled to message path + linkable.** `inbox.go:866-868` fires push inside `InboxStore.Store`; `buildPushMessage` puts `sender_id = fromPeerId` in `data` at **`:289` (cipher-only) AND `:351` (visible path)**. | ✅ read |
| RC3 | **No per-recipient contact / access-token gate (push is gated on the WRONG axis).** The push *is* conditional — `if metadata.ShouldNotify` (`inbox.go:866`), and dup (`:846`)/rejected-full (`:854`) skip it — but `SendNotification :135-146` → `LookupToken(toPeerId) :38-46` does **no contact/access-token authorization**; a new user-visible store to any token-holder fires a push. The §12 anti-spam gate is missing and must layer **on top of** `ShouldNotify`. | ✅ read |
| RC4 | **Wake leans silent.** `buildCiphertextOnlyPushMessage` sets `ContentAvailable:true` + `MutableContent:true` (`inbox.go:426-427`; silent/bg class, iOS-throttled) for `new_message` — visible only via the `>4 KB` oversized fallback (`:468`), not guaranteed for the normal wake. | ✅ read |

**Refuted — do NOT re-introduce / do NOT re-scope:**
- ❌ **Do not build a gossipsub presence beacon** (Option B) — FDC-S3 **REJECTED** it (continuous
  churn/battery, net-new pubsub mesh, useless on iOS background). Pubsub stays **group-only**
  (`pubsub.go:105` joins only `GroupTopicPrefix+groupId`).
- ❌ **Do not make presence load-bearing** for delivery (S3 hard gate; §6.3/§12).
- ❌ **Do not rebuild store dedup/idempotency** — already present and correct (out of scope; owned by
  the durability hazard note, FDC-10).
- ❌ **Do not add reservation-exact tracking** via go-libp2p relay-service internals (S3: explicitly
  OUT; coarse connectedness + self-published state suffices for a HINT).
- ❌ **Do not infer foreground from connectedness** (`main.go:145-163` provably cannot — that is the
  whole reason for self-publish).

---

## Real Scope

**In scope (FDC-09):**
- **Self-publish WRITE** — additive `presence_set` inbox action (Option C, FDC-S3-locked) writing into
  **FDC-08's `presence_store.go` map** (FDC-09 **rebases**, does not author it) + the `PresenceSet`
  bridge fn (added to FDC-08's NEW `bridge_presence.go`) + node `RelayPresenceSet(...)`. Dart hooks on
  **resume** (`handle_app_resumed.dart`: slots into / after FDC-05's parallel re-prime block `:174-240`,
  under the whole-resume gate `:121-133`), best-effort on **pause** (the NEW
  `lib/core/lifecycle/handle_app_paused.dart`, **piggybacking FDC-06's already-landed bounded
  `beginBackgroundTask` window** — `callBgBegin`/`callBgEnd` `:448-509`, per-msg 3 s / ceiling 8 s — NOT
  re-implementing it), + a slow foreground heartbeat (≈60 s, FDC-S3); a `setPresence(state, ttlMs)`
  method on `P2PService` → `callP2PRelayPresenceSet` → `'relay:presence_set'`.
- **Push hardening (§12):** (a) per-recipient **access-token** gate so only contacts wake you —
  **layered on the existing `inbox.go:866` `ShouldNotify` condition**, not replacing it; (b)
  **opaque-token routing** decoupling the wake from the sender↔message linkage (scrub `sender_id` at
  **both** `:289` and `:351`); (c) **visible** wake push (alert-class, not content-available-only).
  *(This half is independent of the presence_set write — it may ship as a separate sub-PR; it only
  shares the `inbox.go` push-path edits.)*
- **Move-feature gate (REQUIRED — account-migration safety):** the new `setPresence` `P2PService`
  primitive MUST route through `_allowsAccountNetworkSideEffects('p2p_set_presence')` as its **first
  line** (mirror `registerPushToken` `p2p_service_impl.dart:4221` (`'p2p_register_push_token'`) /
  `probeRelay :4406` / FDC-08's `lookupRelayPresence`) and no-op during an account-move. **CRITICAL:**
  the **pause** hook (`handle_app_paused.dart`) is on a path whose CALLER is **UNgated** by the
  account-migration gate — `handleAppPaused()` has no gate parameter, unlike `handleAppResumed` which
  gates at `:121-133`. (FDC-06's own `storeInInbox` deposit self-gates at the primitive level — the
  pattern FDC-09 must follow.) Without self-gating the primitive, `presence_set{background}` would
  announce the **moving** device as reachable/online to the relay during a move-export pause,
  contradicting move semantics (the device is ceding the account). The resume hook is *also* covered by
  the whole-resume gate, but self-gating the primitive makes BOTH paths safe (defense-in-depth).
  **Lock:** a RED test — gate-false on pause ⇒ no `presence_set` emitted, returns/skips with a
  `P2P_SERVICE_ACCOUNT_MIGRATION_NETWORK_BLOCKED{operation:'p2p_set_presence'}` event; mutation = drop
  the gate ⇒ background publish fires. (Token is a **log label only** — no allowlist registration; the
  gate is 100% migration-state-driven.)

**Out of scope (owning FDC-xx):**
- Presence **READ** / `presence_get` + client short-TTL cache + retiring `probeRelay` → **FDC-08**
  (consumes the same shared presence store; co-edit `inbox.go` — serialize).
- **Creating `presence_store.go`, `bridge_presence.go`, and the `HandleInboxStream` host/store
  injection (`inbox.go:1497` + `main.go:117-118` wiring) → FDC-08** (it lands the read side + the
  shared TTL'd map first; FDC-09 **rebases** and adds the `presence_set` WRITE into the same map). The
  shared map's `sync.Map`/mutex guard + `go test -race` is established by FDC-08 (R6); FDC-09 keeps it
  race-clean as a co-writer.
- The §6.3 send-emphasis branch (`reachable==true → inbox lazy`, etc.) → **FDC-08**.
- iOS pause-flush feasibility + the bounded `beginBackgroundTask` budget → **FDC-S4 (closed) → FDC-06
  (LANDED, ships ON)**. FDC-09's pause-push *piggybacks* FDC-06's existing window; it does **not** widen
  the budget, re-implement the window, or own its feasibility.
- Durable Redis presence/token persistence + relay pool → **FDC-10** (this plan's stores default
  in-memory like the existing `push_token_store.go`; durability is FDC-10's single gap).

---

## Files To Inspect Next

> Anchors re-grounded on `new-orbit` 2026-06-27; concurrent dev drifts them — re-verify by **symbol**.

**Production — relay (Go):**
- `go-relay-server/inbox.go` — dispatch `switch req.Action` (`:1530`, 10 cases), `register_token`
  (`:1616`), `default: "Unknown action: %s"` (`:1712-1713`), `inboxRequest` struct (`:1424`; **has
  `Metadata map[string]interface{}` `:1429`** — `presence_set` carries `{state,ttlMs}` here),
  `inboxResponse` (`:1447-1465`, **no Metadata field** — write returns `Status:"OK"`), the
  **conditional** store→push (`:866-868`, `if metadata.ShouldNotify`; dup `:846`/rejected-full `:854`
  early-return), `extractChatPushMetadata` (the `ShouldNotify` source), `SendNotification` (`:135-146`,
  `LookupToken` early-return on `missing_token`), `buildPushMessage` (`sender_id = fromPeerId` at **both**
  `:289` and `:351`), `buildCiphertextOnlyPushMessage` (`ContentAvailable`/`MutableContent` `:426-427`),
  `buildOversizedFallbackPushMessage` (`:468`), `pushDataSize`/`maxPushDataBytes` (`:460-466`,`:53`=4000),
  `pushSentCounter` labels (`missing_token`/`success` — add `unauthorized_wake`).
- `go-relay-server/push_token_store.go` — `memoryPushTokenStore` (`:11-14`), `RegisterToken` (`:22-30`),
  `LookupToken` (`:38-46`), `UnregisterToken` (`:32-36`) — the pattern to mirror for a relay-side
  wake-token set.
- **`go-relay-server/presence_store.go` (created by FDC-08; FDC-09 adds the WRITE)** + the new
  wake-token store (sibling file or in `push_token_store.go`).
- `go-relay-server/main.go:145-163` (connectedness handler — read-only context; Connected branch
  `:149-154`, `RecordPeerSeen :152`; do not infer fg/bg). `HandleInboxStream` wiring (`:117-118`,
  currently 3 params — FDC-08 injects host/store).

**Production — Go host client / bridge:**
- `go-mknoon/node/inbox.go` — add `RelayPresenceSet(peerId, state, ttlMs)` next to FDC-08's
  `RelayPresenceLookup` (stream-action template `InboxStoreDetailed`/`h.NewStream(ctx, relay.ID,
  InboxProtocol)`).
- `go-mknoon/bridge/bridge_presence.go` (created by FDC-08 for `PresenceGet`) — add `PresenceSet(paramsJSON string) string`;
  **do NOT append to the 2880-line `bridge.go`** (template `RelayProbe` `bridge.go:899`).

**Production — client (Dart):**
- `lib/core/services/p2p_service.dart` — `registerPushToken` decl (`:166-173`), `probeRelay` (`:192`),
  `RelayProbeResult` enum (`:9-13`) — add `setPresence(state, ttlMs)` near these (and FDC-08's
  `lookupRelayPresence`/`RelayPresence` if it has landed).
- `lib/core/services/p2p_service_impl.dart` — `registerPushToken` impl (**`:4220`**, gate
  `'p2p_register_push_token'` `:4221` — the model), `_allowsAccountNetworkSideEffects` (`:447-464`),
  `probeRelay` gate (`:4406`), `callP2PInboxRegisterToken` call-site (`:4236`) — seam for `setPresence`
  + its `p2p_set_presence` gate.
- `lib/core/bridge/go_bridge_client.dart` — `_cmdMap` (`relay:probe` `:114`) → add
  `'relay:presence_set': _CmdSpec('relayPresenceSet', true)` (~`:115`).
- `lib/core/bridge/p2p_bridge_client.dart` — `callP2PRelayProbe` (`:157-184`) /
  `callP2PInboxRegisterToken` (`:487-513`) templates for `callP2PRelayPresenceSet` (request dict +
  `emitFlowEvent` pair + response parse).
- `lib/features/push/application/register_push_token_use_case.dart` — token registration flow +
  `PUSH_REGISTER_TOKEN_*` flow events; access-token / wake-token issuance rides alongside (none exists
  today → net-new).
- `lib/core/lifecycle/handle_app_resumed.dart` — whole-resume account-migration gate (`:121-133`);
  FDC-05's parallel re-prime block (`:174-240`) → slot the resume `presence_set{foreground}` + heartbeat
  start in/after it (Tertiary collision with FDC-04/05 — serialize).
- **`lib/core/lifecycle/handle_app_paused.dart` (NEW, FDC-06)** — `kFdcPauseFlushEnabled` (`:67`),
  `handleAppPaused()` signature (`:179-195`, **ungated by account-migration**), `_pauseFlushInFlightSends`
  (`:408-526`), `callBgBegin`/`callBgEnd` (`:448-509`), per-msg 3 s (`:85`) / ceiling 8 s (`:91`) →
  best-effort `presence_set{background}` rides this window + cancel the heartbeat timer here. main.dart
  `_onPaused()` (`:4365-4372`) delegates to it.
- `lib/features/push/domain/push_token_store.dart` + `infrastructure/push_token_store_impl.dart`
  (`writeToken`/`readToken`/`clearToken` on `SecureKeyStore`, `:14-42`) — the exact persistence pattern
  to mirror for a client-held wake-token store.

**Direct + integration tests (existing, to extend):**
- `go-relay-server/inbox_test.go` (Go push/dispatch unit tests live here).
- `go-relay-server/push_token_store.go` has no `_test.go` yet — add `presence_store_test.go` /
  `wake_token_store_test.go`.
- `test/features/push/application/register_push_token_use_case_test.dart`,
  `test/features/push/infrastructure/push_token_store_impl_test.dart`,
  `test/shared/fakes/fake_push_token_store.dart`.

**Dependency-only context:** `go-relay-server/inbox_dedup_test.go`, `inbox_dedup`/`backend_*` (do not
edit — dedup is out of scope); `lib/features/push/application/prepare_notification_open_use_case.dart`
(notif-open consumes the wake; unchanged here).

---

## Existing Tests Covering This Area

| Test | Exists? | In which gate array (`run_test_gates.sh`) |
|---|---|---|
| `go-relay-server/inbox_test.go` | ✅ | `cd go-relay-server && go test ./...` (Go gate) |
| `go-relay-server/inbox_dedup_test.go` | ✅ | Go gate (dedup — out of scope, regression floor) |
| `test/features/push/application/register_push_token_use_case_test.dart` | ✅ | feature-host-all AUTO-glob |
| `test/features/push/infrastructure/push_token_store_impl_test.dart` | ✅ | `OUT_OF_GATE_TESTS` (`run_test_gates.sh:235`) + feature-host-all |
| `test/features/posts/phase3/post_presence_listener_test.dart` | ✅ (presence-**ish**, posts) | `POSTS_TESTS` (`run_test_gates.sh:161`) — *presence-ish gate family* |
| `integration_test/posts_phase{1..5}_fake_test.dart` | ✅ | `POSTS_TESTS` (`:156-160`) |
| `integration_test/{background_reconnect,wifi_relay_fallback_smoke,transport_e2e,media_stable_id_smoke}_test.dart` | ✅ | `TRANSPORT_TESTS` (`:164-168`) |
| `integration_test/foreground_group_push_drain_test.dart` | ✅ | feature-host-all array (push drain context) |
| presence_set direct tests | ❌ **MISSING** | **to add to `inbox_presence_test.go`** (co-owned w/ FDC-08; auto-run by `GOTOOLCHAIN=go1.25.0 go test ./...`) |
| wake-token / visible-push / opaque direct tests | ❌ **MISSING** | **to add to `inbox_test.go`** (push-path tests live here; auto-run by the Go gate) |
| `set_presence_use_case_test.dart` (TC-09-04..08) + `register_push_token_use_case` extensions (14/15) | ❌ **MISSING** | `test/features/push/**` AUTO-glob → `feature-host-all` |

> Note: the project has **no dedicated `presence` gate**. The prompt's "posts (presence-ish)" maps to
> `POSTS_TESTS`, whose `post_presence_listener_test.dart` is the nearest presence regression floor.
> A new curated 1:1/transport presence headline must be **appended to the readonly array** in
> `scripts/run_test_gates.sh` or it will silently not run (harness rule).

---

## RED Test Catalog

Tiers: **Go-unit** (relay, `go test`), **Dart-unit/widget** (host, AUTO-glob), **integration**
(transport/posts host-fake), **device/sim** (closure gate — device / live-relay-env, NOT host-provable).
Every behavior-bearing edit has a re-red mutation. Where the same observable (a push fires / a store
succeeds) is reachable by two paths, the discriminator is a **distinct flow-event / push-class**.

### A. Self-publish WRITE (`presence_set`) — Option C (FDC-S3-locked)

- **TC-09-01** · `go-relay-server/inbox_presence_test.go::TestPresenceSet_AdditiveAction_StoresState`
  (co-owned file — FDC-08 creates it for R1–R6; FDC-09 appends the `presence_set` cases)
  · **Tier:** Go-unit
  · **Setup:** dispatch `inboxRequest{Action:"presence_set", Metadata:{state:"foreground", ttlMs:…}}`
  from `remotePeer` (the existing `Metadata map[string]interface{}` field at `inbox.go:1429` carries
  it — no new request field); read back via FDC-08's shared `presence_store.go` map.
  · **RED on HEAD because:** `presence_set` is unknown → falls to `default` (`inbox.go:1712-1713`),
  `Status:"ERROR", Error:"Unknown action: presence_set"`; no store exists.
  · **GREEN asserts:** `Status:"OK"`; presence store holds `{remotePeer → foreground, expiresAt=now+ttl}`,
  written so FDC-08's `presence_get` resolver prefers it (the "prefer self-published state" branch).
  · **Mutation that re-reds:** drop the `case "presence_set"` (named `handlePresenceSet`) arm → back to
  Unknown-action error.

- **TC-09-02** · `inbox_presence_test.go::TestPresenceSet_TTLExpiry_DegradesToUnknown`
  · **Tier:** Go-unit
  · **Setup:** set `{foreground, ttlMs: T}` with an injected clock (the relay presence TTL ≈ **180 s**,
  FDC-S3-locked, device-tunable); advance clock past `T`; read via `presence_get`.
  · **RED on HEAD:** no TTL store exists (compile/red).
  · **GREEN:** read after expiry returns `unknown` (never silently `unreachable`; FDC-S3 freshness rule
  `ageMs ≥ TTL ⇒ unknown` — the same rule FDC-08's R5 locks; FDC-09's write feeds the same `expiresAt`).
  · **Mutation:** make the read ignore `expiresAt` (always return last-written) → expiry test re-reds.

- **TC-09-03** · `inbox_presence_test.go::TestPresenceSet_BackCompat_OldRelayUnknownAction`
  · **Tier:** Go-unit (NET-REL-07)
  · **Setup:** call the *default* arm path for an action the relay does not implement (simulate an old
  relay by asserting the `default` arm copy is unchanged for unknown actions).
  · **RED/GREEN:** asserts `presence_set` on a build *without* the case yields the exact
  `"Unknown action: presence_set"` string a new client maps to `unknown`. (Locks the additive
  contract; client side TC-09-08.)
  · **Mutation:** change the `default` error text → client mapping test (TC-09-08) re-reds.

- **TC-09-04** · `test/features/push/application/set_presence_use_case_test.dart::publishesForegroundOnResume`
  · **Tier:** Dart-unit
  · **Setup:** fake `P2PService` capturing `setPresence(state, ttlMs)`; invoke the resume hook seam
  (the SetPresenceUseCase the FDC-05 parallel re-prime block `handle_app_resumed.dart:174-240` calls,
  under the whole-resume gate `:121-133`).
  · **RED on HEAD:** no `setPresence` on `P2PService` (`p2p_service.dart:166-173` has only
  `registerPushToken`) → compile-red.
  · **GREEN:** resume emits `setPresence('foreground', 180_000)` exactly once + flow event
  `PRESENCE_SELF_PUBLISH{state:foreground}`.
  · **Mutation:** drop the resume call → not-called assertion re-reds.

- **TC-09-05** · `…set_presence_use_case_test.dart::publishesBackgroundOnPause_bestEffort`
  · **Tier:** Dart-unit
  · **Setup:** invoke the pause seam in the NEW `lib/core/lifecycle/handle_app_paused.dart` (FDC-06,
  ships ON); fake captures one best-effort `setPresence('background', …)`; assert it is
  **bounded / fire-and-forget** and rides FDC-06's existing `beginBackgroundTask` window
  (`callBgBegin`/`callBgEnd`) **without** widening its 3 s/8 s budget or blocking the flush.
  · **RED on HEAD:** `handle_app_paused.dart` runs FDC-06's pause-flush (`storeInInbox` deposits,
  bounded bg window) but emits **no** `presence_set` — the "publishes background on pause" hook does
  not exist. *(NOTE: the old "pause is local-DB-only, no network" RED reason is STALE — FDC-06 landed;
  the pause path already does bounded network work. The RED is now "no presence_set hook on the pause
  path," not "no network on pause.")*
  · **GREEN:** exactly one best-effort background publish, unawaited; flow event
  `PRESENCE_SELF_PUBLISH{state:background, bestEffort:true}`; FDC-06 floor
  (`handle_app_paused_pause_flush_test.dart`) stays green.
  · **Mutation:** `await` the publish (block the flush) → "does not block / fire-and-forget" assertion
  re-reds. **Discriminator vs TC-09-04:** `state` + `bestEffort` flag in the flow event.

- **TC-09-06** · `…set_presence_use_case_test.dart::foregroundHeartbeatRefreshesTTL`
  · **Tier:** Dart-unit
  · **Setup:** fake clock/timer; foreground for > heartbeat interval **60 s** (FDC-S3-locked).
  · **RED on HEAD:** no heartbeat timer exists.
  · **GREEN:** a refresh `setPresence('foreground', 180_000)` fires per heartbeat interval; the timer is
  **cancelled on pause** (in `handle_app_paused.dart`, so it cannot fire while backgrounded/suspended).
  · **Mutation:** never re-arm the timer → second-tick assertion re-reds; never cancel on pause →
  "stops on pause" assertion re-reds.

- **TC-09-07** · `…set_presence_use_case_test.dart::accountMovePause_emitsNoPresenceSet`
  ⭐ **(move-feature safety — the lock named in Real Scope; mirrors FDC-08's C3b)**
  · **Tier:** Dart-unit
  · **Setup:** counting fake `P2PService`; put the migration authority in a pause state (e.g.
  `migrationExportingNetworkPaused` / fail-closed) so `_allowsAccountNetworkSideEffects('p2p_set_presence')`
  returns false; invoke the **pause** seam (the ungated-caller path) AND the resume seam.
  · **RED on HEAD:** `setPresence` (and its gate) does not exist → compile-red; once it exists, an
  un-gated impl would publish `background` mid-move.
  · **GREEN:** **zero** `setPresence` bridge calls on either path; emits
  `P2P_SERVICE_ACCOUNT_MIGRATION_NETWORK_BLOCKED{operation:'p2p_set_presence'}`. (A moving device must
  not announce itself reachable while ceding the account.)
  · **Mutation:** drop the `_allowsAccountNetworkSideEffects('p2p_set_presence')` first-line gate →
  background publish fires during the move → re-reds. (Token is a **log label only** — no allowlist
  registration needed.)

- **TC-09-08** · `…set_presence_use_case_test.dart::oldRelayUnknownAction_mapsToSkip`
  · **Tier:** Dart-unit (NET-REL-07 client half)
  · **Setup:** fake bridge returns `{Status:ERROR, Error:"Unknown action: presence_set"}`.
  · **RED on HEAD:** no such mapping exists.
  · **GREEN:** client treats it as "presence unsupported", **does not** retry/spam, emits
  `PRESENCE_SELF_PUBLISH_UNSUPPORTED`; the send path treats reachability as `unknown` (no crash).
  · **Mutation:** map the error to a hard failure / retry loop → re-reds.

### B. Push hardening — visible / access-token / opaque (§12)

- **TC-09-10** · `inbox_test.go::TestWakePush_VisibleAlert_NotSilentOnly`
  · **Tier:** Go-unit
  · **Setup:** build the `new_message` wake message via the hardened builder.
  · **RED on HEAD:** `buildCiphertextOnlyPushMessage` sets `ContentAvailable:true` + `MutableContent:true`
  (`inbox.go:426-427`, silent/bg class) for the wake; assert "wake is a visible alert that does not rely
  on content-available-only" fails.
  · **GREEN:** wake message has `APNS.Headers["apns-push-type"]=="alert"`, a non-empty `Aps.Alert`,
  **and** does not depend on `ContentAvailable:true` for visibility (Android `Priority:"high"` with a
  `Notification` block). Preserve `MutableContent` for the NSE decrypt path.
  · **Mutation:** revert to content-available-only (drop the Alert/notification block) → re-reds.
  · **Note (DRAFT):** *whether* to keep `ContentAvailable` alongside a visible alert is an iOS-NSE
  interaction → **device row TC-09-20 is the real proof** (host asserts only message shape).

- **TC-09-11** · `inbox_test.go::TestWakePush_AccessTokenGate_OnlyContactsWake`
  · **Tier:** Go-unit
  · **Setup:** recipient registers an authorized wake-token set (contacts); store a **user-visible**
  (`ShouldNotify==true`) message whose envelope presents (a) a valid wake token, then (b) an
  invalid/absent one.
  · **RED on HEAD:** the existing push gate (`inbox.go:866` `if metadata.ShouldNotify`) fires for **any**
  token-holder with **no per-recipient contact check** (`SendNotification :135-146` → `LookupToken`
  only) → the "no-push-for-non-contact" assertion fails. *(The gap is the missing contact gate, not a
  missing first gate — the new check LAYERS ON TOP of `ShouldNotify`.)*
  · **GREEN:** `ShouldNotify && valid token` → `SendNotification` invoked (counter `success`);
  `ShouldNotify && invalid/absent` → **no push**, counter `unauthorized_wake` (new label), message still
  **stored** (delivery preserved).
  · **Mutation:** remove the contact gate (push on any `ShouldNotify`) → non-contact assertion re-reds.
  · **Discriminator:** `pushSentCounter` label `success` vs `unauthorized_wake` (distinct from the
  existing `missing_token`).

- **TC-09-12** · `inbox_test.go::TestWakePush_OpaqueRouting_NoSenderLinkInPush`
  · **Tier:** Go-unit (unlinkability)
  · **Setup:** store a `new_message`; capture the assembled FCM `data` for the wake.
  · **RED on HEAD:** `buildPushMessage` sets `data["sender_id"]=fromPeerId` at **both** `inbox.go:289`
  (cipher-only) **and** `:351` (visible path) → linkable. (Assert BOTH builders.)
  · **GREEN:** the wake carries only an **opaque routing token** (no raw sender peerId at either site;
  content pulled from inbox on open); the inbox `retrieve` path still resolves the real sender after
  E2E decrypt.
  · **Mutation:** re-add `sender_id` raw at either site → linkability assertion re-reds.
  · **Preserved sentinel:** notif-open routing (`prepare_notification_open_use_case`) must still
  resolve the conversation from the opaque token (covered by TC-09-13).

- **TC-09-13** · `inbox_test.go::TestWakePush_StillDelivers_WhenPresenceWrong`
  ⭐ **(FDC-S3 Exit-Gate item 4 — the hard load-bearing gate; relay-side twin of FDC-08's C7)**
  · **Tier:** Go-unit (**FDC-S3 hard gate: presence never load-bearing**)
  · **Setup:** write the presence store to `foreground/reachable` (via `presence_set`) for a peer that
  is actually offline; store a fresh **user-visible** (`ShouldNotify==true`) `chat_message`.
  · **RED on HEAD:** N/A as a gate today (no presence) — written as the **preservation lock** so a
  future presence-coupled mutation cannot pass.
  · **GREEN:** message is **stored** and the wake **push fires via the existing `ShouldNotify` path**
  (`inbox.go:866`) — the store→push seam **never consults the presence store**, so a wrong `reachable`
  cannot suppress the wake. Assert push fired AND presence was not read in the store→push decision.
  · **Mutation:** add a `presence==reachable ⇒ skip SendNotification` (or skip store) branch → this
  test re-reds (proves the load-bearing rejection from S3 / §12).
  · **Cross-ref:** FDC-08's C7 is the read/send-side twin; both lock `PRESENCE_NEVER_LOAD_BEARING`.

- **TC-09-09** · `inbox_presence_test.go::TestPresenceStore_RaceClean` (+ `go test -race`)
  · **Tier:** Go-unit (concurrency)
  · **Setup:** spin the FDC-09 `presence_set` WRITE goroutine concurrently with FDC-08's `presence_get`
  READ and TTL expiry on the **same** shared `presence_store.go` map.
  · **RED on HEAD:** N/A until the write lands — this is the **co-writer preservation lock**. FDC-08's
  R6 only exercises connectedness-write + read; FDC-09's `presence_set` is a **net-new third concurrent
  accessor** R6 does not cover.
  · **GREEN:** `go test -race ./...` is clean with all three accessors live.
  · **Mutation:** drop the `sync.Map`/mutex guard (or write the map unguarded from `presence_set`) →
  `-race` flags a data race → re-reds. Locks `PRESENCE_STORE_RACE_SAFE` for the write path.

- **TC-09-14** · `…register_push_token_use_case_test.dart::issuesWakeTokensToContacts`
  · **Tier:** Dart-unit
  · **Setup:** fake bridge; a contact set; run the access-token registration seam.
  · **RED on HEAD:** no wake-token issuance exists in `register_push_token_use_case.dart`.
  · **GREEN:** client mints/registers a per-recipient opaque wake-token for each contact and persists
  it (mirrors `push_token_store_impl` pattern); flow event `WAKE_TOKEN_ISSUED`.
  · **Mutation:** skip persistence → reload-survives assertion re-reds.

- **TC-09-15** · `…register_push_token_use_case_test.dart::oldRelayRejectsAccessToken_gracefulDegrade`
  · **Tier:** Dart-unit (NET-REL-07)
  · **Setup:** fake old relay ignores/errs the access-token field.
  · **GREEN:** client still registers the plain token (existing `registerPushToken` path), push keeps
  working ungated against old relays; no crash. **RED on HEAD:** no degrade path because no feature.
  · **Mutation:** hard-fail registration on missing access-token support → re-reds.

### C. Device / relay closure rows (device / live-relay-env closure — NOT host-provable; FDC-S3 Methods feed these)

- **TC-09-20** *(device)* — iOS visible-wake actually surfaces an alert for a **backgrounded** peer
  and is **not** silent-throttled (§12 ~1–2/hr). Two real devices + real relay + APNs.
- **TC-09-21** *(device)* — `presence_set{background}` on pause **lands before iOS suspends**
  (success rate over ~20 trials; FDC-S3 Method 2). Below 50% → C degrades to connectedness on iOS;
  Android still benefits.
- **TC-09-22** *(device)* — connectedness-lag vs self-published `background` (FDC-S3 Method 1) sets
  the final presence TTL (device-tuned; starts 180 s).
- **TC-09-23** *(device)* — non-contact **cannot** wake a recipient over the live relay (access-token
  gate end-to-end).
- **TC-09-24** *(sim/relay)* — additive back-compat: a *new* client against an *old* relay build gets
  `"Unknown action: presence_set"` and degrades (FDC-S3 Method 3 / NET-REL-07).

---

## Test Coverage Matrix

> Go gate cmds require **`GOTOOLCHAIN=go1.25.0`** (go1.26.x crypto/tls panic). The relay store-write +
> read goroutines race on the shared map ⇒ the Go gate is **`GOTOOLCHAIN=go1.25.0 go test -race ./...`**.

| Spec case (proposal §) | Behavior property | Tier | Test file::name | RED reason on HEAD | Mutation revert | Acceptance gate cmd | Harness registration |
|---|---|---|---|---|---|---|---|
| §6.3 self-publish (S3 Opt C) | `presence_set` stores state | Go-unit | `inbox_presence_test.go::TestPresenceSet_AdditiveAction_StoresState` | unknown action → `default` (`:1712-1713`); state rides existing `Metadata` (`:1429`) | drop `handlePresenceSet` arm | `cd go-relay-server && GOTOOLCHAIN=go1.25.0 go test ./...` | go test (no array) |
| §6.3 / S3 TTL 180 s | TTL expiry → `unknown` | Go-unit | `inbox_presence_test.go::TestPresenceSet_TTLExpiry_DegradesToUnknown` | no TTL store | ignore `expiresAt` | `GOTOOLCHAIN=go1.25.0 go test ./...` | go test |
| NET-REL-07 | additive `Unknown action` | Go-unit | `inbox_presence_test.go::TestPresenceSet_BackCompat_OldRelayUnknownAction` | n/a (locks contract) | change default text | `GOTOOLCHAIN=go1.25.0 go test ./...` | go test |
| §6.3 resume publish | fg on resume | Dart-unit | `set_presence_use_case_test.dart::publishesForegroundOnResume` | no `setPresence` seam (`p2p_service.dart:166-173`) | drop resume call | `flutter test test/features/push/` | AUTO-glob `test/features/**` |
| §6.4 pause publish | bg best-effort, non-blocking | Dart-unit | `…::publishesBackgroundOnPause_bestEffort` | no presence_set hook on the FDC-06 pause path (`handle_app_paused.dart`) | `await` the publish | `flutter test test/features/push/` | AUTO-glob |
| Move-feature safety | pause/resume during move ⇒ no publish | Dart-unit | `…::accountMovePause_emitsNoPresenceSet` | no `setPresence`/gate | drop `_allowsAccountNetworkSideEffects('p2p_set_presence')` | `flutter test test/features/push/` | AUTO-glob |
| §6.3 heartbeat (S3 60 s) | fg heartbeat refresh + cancel-on-pause | Dart-unit | `…::foregroundHeartbeatRefreshesTTL` | no timer | no re-arm / no cancel | `flutter test test/features/push/` | AUTO-glob |
| NET-REL-07 client | old-relay → skip | Dart-unit | `…::oldRelayUnknownAction_mapsToSkip` | no mapping | map to retry/fail | `flutter test test/features/push/` | AUTO-glob |
| §12 visible push | alert-class, not silent-only | Go-unit | `inbox_test.go::TestWakePush_VisibleAlert_NotSilentOnly` | content-available-only (`:426-427`) | revert to silent-only | `GOTOOLCHAIN=go1.25.0 go test ./...` | go test |
| §12 access-token | only contacts wake (layered on ShouldNotify) | Go-unit | `inbox_test.go::TestWakePush_AccessTokenGate_OnlyContactsWake` | `ShouldNotify` push has no contact check (`:866`, `SendNotification :135-146`) | remove contact gate | `GOTOOLCHAIN=go1.25.0 go test ./...` | go test |
| §12 opaque/unlinkable | no sender_id in wake | Go-unit | `inbox_test.go::TestWakePush_OpaqueRouting_NoSenderLinkInPush` | `sender_id=fromPeerId` (`:289` AND `:351`) | re-add `sender_id` either site | `GOTOOLCHAIN=go1.25.0 go test ./...` | go test |
| §6.3/§12 HINT-only (S3 gate) | wrong presence still delivers | Go-unit | `inbox_test.go::TestWakePush_StillDelivers_WhenPresenceWrong` | preservation lock (push via `ShouldNotify`, presence never read) | gate store/push on presence | `GOTOOLCHAIN=go1.25.0 go test ./...` | go test |
| §12 access-token issuance | mint/persist wake tokens | Dart-unit | `register_push_token_use_case_test.dart::issuesWakeTokensToContacts` | no issuance | skip persistence | `flutter test test/features/push/` | AUTO-glob |
| NET-REL-07 token | old-relay token degrade | Dart-unit | `…::oldRelayRejectsAccessToken_gracefulDegrade` | no degrade path | hard-fail on missing support | `flutter test test/features/push/` | AUTO-glob |
| Relay shared-map race | write+read+expiry race-clean | Go-unit | `inbox_presence_test.go::TestPresenceStore_RaceClean` (co-writer of FDC-08's R6) | n/a (preservation; FDC-08 adds guard) | drop the mutex/`sync.Map` | `cd go-relay-server && GOTOOLCHAIN=go1.25.0 go test -race ./...` | go test -race |
| §12 visible (device) | alert surfaces, not throttled | device | `TC-09-20` | device-only (host proves shape) | n/a | `/sims <scope> --only N` + 2-device smoke | classify_path() + dart-define case |
| §6.4 pause lands (device) | bg before suspend | device | `TC-09-21` | device-only | n/a | 2-device, FDC-S3 Method 2 | sim harness case |
| §6.3 TTL calibration (device) | connectedness-lag → TTL | device | `TC-09-22` | device-only | n/a | FDC-S3 Method 1 | n/a (measurement) |
| §12 anti-spam (device) | non-contact cannot wake | device | `TC-09-23` | device-only | n/a | 2-device + relay | sim harness case |
| NET-REL-07 (sim) | new-client/old-relay degrade | sim/relay | `TC-09-24` | live-relay-env-gated | n/a | FDC-S3 Method 3 | sim harness case |

*No empty cells. Device / live-relay-env rows are the closure gate, not host.*

---

## Blind-Spot Sweep

- **Lifecycle / derived-state durability:** presence is TTL'd and **never silently `offline`** → falls
  to `unknown` on expiry (TC-09-02); wake-tokens persist client-side and survive reload (TC-09-14).
  Server presence/token stores are **in-memory** like `push_token_store.go` → a relay bounce loses
  them; **durability is FDC-10's gap**, not this plan's (presence is a HINT so loss only widens the
  `unknown` window; wake-token loss must **fail-open to existing push** for already-paired contacts so
  a bounce does not silence contacts — covered by TC-09-15 degrade semantics). **Open issue flagged.**
- **Sibling-surface consistency:** **group** push (`SendGroupNotification :148` / `group_store`
  `:1628`) shares the same `LookupToken`/visible-push concerns. OPEN decision needed: does §12
  hardening apply to group wake too, or 1:1 first? → tracked as an open issue; group rows N/A until
  resolved (the `foreground_group_push_drain_test.dart` floor must stay green either way).
- **Destructive-action side-effects:** `unregister_token` (`:1624`) and the invalid-token auto-removal
  (`sendWithRetry :209`) must also clear any access-token/presence state for that peer (no orphaned
  wake authorization) — add a preservation assertion (rider on TC-09-11).
- **Invariant re-verification under new transitions:** the **dedup-by-messageId** store invariant and
  the **142 oversized-media visible fallback** (`:295`,`:468`) must remain green after the wake-builder
  change (TC-09-10 must not regress `media_test.go` / oversized-fallback) — regression floor, not a
  new test. Also: the **existing `ShouldNotify` envelope-type filter** (`:866`,
  `extractChatPushMetadata`) must stay intact — the access-token gate **adds** a condition, it must not
  loosen the type filter so unknown envelope types start waking (rider on TC-09-11).
- **Lifecycle / derived-state durability (NEW — pause-flush interaction):** FDC-06's pause-flush ships
  ON and runs network on pause. The `presence_set{background}` rider must **(a)** ride FDC-06's bg
  window, **(b)** be cancelled-on-pause for the heartbeat timer (TC-09-06), and **(c)** never delay or
  starve FDC-06's `storeInInbox` flush within the 8 s ceiling — assert the FDC-06 floor
  (`handle_app_paused_pause_flush_test.dart`) stays green (regression floor).
- **Bridge serialization (§10):** `setPresence`/heartbeat funnel through the **single Go bridge** with
  the user's send → must be cheap, off the send-critical path, and **never block a send** (TC-09-05
  asserts non-blocking pause; FDC-S5 contract). N/A-justified beyond that: read-side caching is FDC-08.

---

## Invariants (locked by tests)

1. `PRESENCE_NEVER_LOAD_BEARING` — wrong presence still delivers via inbox + push (TC-09-13;
   relay-side twin of FDC-08's C7). *(FDC-S3 Exit-Gate item 4; §6.3/§12.)*
2. **Additive / NET-REL-07** — `presence_set` + access-token are additive; old relay → `Unknown
   action: presence_set` → client degrades to `unknown`/plain-token (TC-09-03/08/15).
3. **Only contacts can wake you (layered on `ShouldNotify`)** — non-contact wake is suppressed but the
   message is still stored, and the existing envelope-type filter is preserved (TC-09-11).
4. **Wake is unlinkable** — no raw sender peerId in the push payload at either build site (`:289`/`:351`);
   content pulled from inbox (TC-09-12).
5. **Wake is visible** — alert-class, not content-available-only (TC-09-10 host shape; TC-09-20
   device proof).
6. **Self-publish never blocks lifecycle** — pause publish is best-effort/bounded and rides FDC-06's
   window without widening it (TC-09-05); heartbeat cancels on pause (TC-09-06).
7. **Self-publish is move-gated** — `setPresence` no-ops during an account-move on BOTH pause and resume
   (TC-09-07; primitive self-gate because the pause caller is ungated).
8. **Shared presence map stays race-clean** — the `presence_set` write is a co-writer of FDC-08's
   guarded map; `go test -race` clean (TC-09-09).
9. **Pubsub stays group-only** — no presence beacon added (Option B rejected; no test needed, but
   `pubsub.go` must remain unedited).

---

## Step-By-Step Implementation Plan

> RED first for every step. Stop-if blockers noted. FDC-S3 is closed — the mechanism is locked; the
> only hard prerequisite is **FDC-08 landed first** (FDC-09 rebases on its store/bridge/injection).

0. **(PREREQ + snapshot)** Confirm FDC-08 has landed `presence_store.go`, `bridge_presence.go`
   (`PresenceGet`), and the `HandleInboxStream` host/store injection (`inbox.go:1497` + `main.go:117-118`).
   Snapshot the dirty tree (`git status --short`) — `new-orbit` has concurrent live dev (reaction /
   pause-flush uncommitted); scope `git diff` to FDC-09's own files; **no `git checkout`/`stash`-revert
   of shared files**. **Stop-if FDC-08 not landed:** do not author a second presence map — wait/rebase.
1. **(RED)** Author the Go presence-write cases in **`inbox_presence_test.go`** (co-owned; append to
   FDC-08's R-suite): TC-09-01/02/03 + TC-09-09 (race) + the push-hardening cases in `inbox_test.go`
   TC-09-10/11/12/13. **Seam:** `inbox.go` dispatch `switch req.Action` (`:1530`) gains a `presence_set`
   case delegating to a **named `handlePresenceSet`**; the write targets **FDC-08's** TTL'd
   `presence_store.go` map (clock-injected); + a new wake-token store (sibling file or `push_token_store.go`).
2. **(GREEN)** Add `case "presence_set"` → `handlePresenceSet`: read `Metadata.state`/`ttlMs` from
   `inboxRequest` (the existing `Metadata map[string]interface{}`, `:1429` — no new request field),
   write `{state, expiresAt=now+ttl}` into FDC-08's map (so its `presence_get` resolver prefers it);
   expiry → `unknown`. Keep the map's `sync.Map`/mutex guard (FDC-08's R6) — confirm `go test -race`.
3. **(GREEN)** Harden the wake at the **conditional** `store→push` seam (`:866-868`, inside
   `if metadata.ShouldNotify`): **add** the wake-token/contact gate **without loosening** the
   `ShouldNotify` type filter; route via opaque token (scrub `sender_id` from `buildPushMessage` at
   **both** `:289` AND `:351` → an opaque key); make the wake builder emit a visible alert
   (`:426-427`, keep `MutableContent` for NSE; preserve the `>4 KB` fallback `:468`). **Stop-if:**
   scrubbing `sender_id` breaks `prepare_notification_open` routing → thread the opaque token through
   notif-open instead of re-adding `sender_id`.
4. **(RED)** Author Dart `set_presence_use_case_test.dart` TC-09-04/05/06/07/08 + extend
   `register_push_token_use_case_test.dart` TC-09-14/15. **Seam:** add `setPresence(state, ttlMs)` to
   `P2PService` (`p2p_service.dart:166-173` neighborhood) + impl
   (`p2p_service_impl.dart:4220-4221` neighborhood, self-gating `'p2p_set_presence'` as first line); a
   `SetPresenceUseCase` (+ heartbeat timer); Dart cmd `'relay:presence_set': _CmdSpec('relayPresenceSet', true)`
   + `callP2PRelayPresenceSet`; hooks in FDC-05's resume parallel block (`handle_app_resumed.dart:174-240`,
   gated `:121-133`) and the FDC-06 pause path (`handle_app_paused.dart`, best-effort, ride bg window,
   cancel heartbeat).
5. **(GREEN)** Implement the Dart seams; access-token/wake-token issuance + persistence rides
   `register_push_token_use_case` (mirror `push_token_store_impl` `SecureKeyStore` pattern).
6. **(VERIFY)** Run every mutation in the catalog; confirm each re-reds. Then run host + Go gates
   **under `GOTOOLCHAIN=go1.25.0` (incl. `-race`)**.
7. **(DEVICE-DEFER)** Device/live-relay-env rows TC-09-20..24 → execute under FDC-S3 Methods 1/2 +
   `/sims` closure (register `classify_path()` + dart-define first); do not block host-green on them,
   but do not mark Done without them (deferred-not-waived; record if the relay env is unavailable).

---

## Risks And Edge Cases

| Risk | Pinned by |
|---|---|
| Scrubbing `sender_id` (at `:289` AND `:351`) breaks notif-open routing | TC-09-12 + notif-open preservation rider |
| Access-token gate loosens / breaks the existing `ShouldNotify` type filter | TC-09-11 (gate layers on top; rider asserts filter intact) |
| Access-token gate silences legit contacts on relay bounce (in-mem loss) | TC-09-15 fail-open degrade + open issue (FDC-10 durability) |
| iOS suspends before pause publish lands | TC-09-21 (device) — degrades to connectedness (acceptable, A backstops) |
| `presence_set{background}` rider starves / blocks FDC-06 pause-flush | TC-09-05 (non-blocking, rides window) + FDC-06 floor `handle_app_paused_pause_flush_test.dart` |
| Account-move announces the moving device as reachable | TC-09-07 (primitive self-gate `p2p_set_presence`, both pause + resume) |
| New `presence_set` write goroutine data-races the shared map | TC-09-09 + `GOTOOLCHAIN=go1.25.0 go test -race` |
| Visible-push change regresses 142 oversized-media fallback | `media_test.go` / oversized-fallback floor (TC-09-10 must not regress) |
| Presence accidentally made load-bearing | TC-09-13 hard gate |
| Bridge head-of-line block from heartbeat | TC-09-05 non-blocking + FDC-S5 contract |
| Group push parity ambiguous | open issue (sibling-surface sweep) |
| go1.26.x crypto/tls panic masks real Go results | `GOTOOLCHAIN=go1.25.0` (mandatory) |

---

## Device/Relay Proof Profile

**Host-only closes:** TC-09-01..15 (incl. 07 move-gate, 09 race; Go + Dart shape/semantics) via
`GOTOOLCHAIN=go1.25.0 go test [-race] ./...` (both modules) + host gates. A green host gate proves the
*message/store shape and the gating logic*, **not** that iOS surfaces a visible wake or that pause
publish beats suspension — those are device-only (host fakes cannot reproduce iOS background-kill or
APNs throttling; FDC-S3 Method note).

**Requires device / live-relay-env (closure):** TC-09-20..24 — real two-device pair + real relay + APNs,
run under FDC-S3 Methods 1/2. **Closure scenario:** `./scripts/check_reliability_simulation_discovery.sh`
then `/sims <scope> --only N` (new scenario needs a `classify_path()` case + dart-define case first).
Live relay env reproducibility is an **open dependency** (per MEMORY the relay env is gitignored;
FDC-09 must confirm a deployable relay before these run — it also stands up the env FDC-08's S1 needs).

---

## Acceptance Gates

> **`GOTOOLCHAIN=go1.25.0` is MANDATORY for both Go modules** — go1.26.x panics `crypto/tls bug:
> where's my session ticket?` in node/bridge/relay pkgs (FAILs with 0 `--- FAIL:` lines; known hazard).
> The declared toolchain passes. **go-mknoon DOES change** (adds the `PresenceSet` bridge fn +
> `RelayPresenceSet` node frame) — the earlier "no host change" note was wrong.

```bash
# Go (relay) — presence_set write + push hardening unit tests
cd /Users/I560101/Project-Sat/mknoon-2/flutter_app/go-relay-server && GOTOOLCHAIN=go1.25.0 go test ./...
cd /Users/I560101/Project-Sat/mknoon-2/flutter_app/go-relay-server && GOTOOLCHAIN=go1.25.0 go test -race ./...   # TC-09-09 data-race gate (presence_set WRITE + presence_get READ + TTL expiry on FDC-08's shared map)
cd /Users/I560101/Project-Sat/mknoon-2/flutter_app/go-relay-server && make lint            # relay lint (handlePresenceSet + wake-gate + opaque/visible builders)
# expected: PASS (0 fail); presence_set / wake-gate / visible / opaque cases GREEN. count: ~191 pass / 0 fail / 2 skip baseline + new (capture before start)
# Go host client + bridge — go-mknoon DOES change (PresenceSet bridge fn + RelayPresenceSet node frame)
cd /Users/I560101/Project-Sat/mknoon-2/flutter_app/go-mknoon && GOTOOLCHAIN=go1.25.0 go test ./...   # expect ok (all pkgs PASS, +node presence-set frame)
cd /Users/I560101/Project-Sat/mknoon-2/flutter_app/go-mknoon && make lint        # gomobile bridge lint (PresenceSet export in bridge_presence.go)

# Dart host gates
cd /Users/I560101/Project-Sat/mknoon-2/flutter_app
./scripts/run_test_gates.sh transport    # TRANSPORT_TESTS. count: device/fixture-gated (skips on lone sim)
./scripts/run_test_gates.sh posts        # POSTS_TESTS incl post_presence_listener (presence-ish floor). count: device-gated suites
./scripts/run_test_gates.sh 1to1         # delivery preserved (offline_inbox_roundtrip). count: ~1226 (prior ~1226), 0 reg
./scripts/run_host_test_gates.sh feature-host-all   # push/* AUTO-glob picks up new set_presence_use_case + register_push_token tests. 0 fail
./scripts/run_host_test_gates.sh core-host-all      # 0 fail (NOTE: pre-existing transport_metrics_privacy `sinceProcessStartMs` fail is FDC-S0/S1, NOT FDC-09 — prove via stash-revert)
flutter test test/features/push/         # new set_presence_use_case_test + register_push_token extensions

# group-safety floor (wake-gate / push-visibility must not break group push — Scope Guard)
./scripts/run_test_gates.sh groups       # expected: 0 fail (no group regression)
# FDC-06 pause-flush floor (presence_set{background} must not break it)
flutter test test/core/lifecycle/handle_app_paused_pause_flush_test.dart   # expected: 0 fail

# Device / live-relay-env closure (§12 device proof, TC-09-20..24) — deferred-not-waived
./scripts/check_reliability_simulation_discovery.sh
/sims <scope> --only N                   # <scope/N from FDC-S3 Methods 1/2; classify_path()+dart-define case first>

# Hygiene
flutter analyze                          # 0 new
git diff --check
```

Expected counts: capture the green baseline before FDC-09 starts (per FDC-00 closure strategy; prior
1:1 ≈ 1226, relay ≈ 191/0/2). Device/sim numbers are device-tuned (FDC-S3 Methods 1/2).

---

## Known-Failure Interpretation

- A host-green Go/Dart gate with the device rows still open is **expected** — it proves delivery +
  gating shape, **not** the iOS visible-wake / pause-landing (FDC-00 "host-testable ≠ validated"
  caveat). Do not read host-green as closure.
- An old-relay run that returns `"Unknown action: presence_set"` is **success** (NET-REL-07), not a
  failure — the client must degrade silently (TC-09-08).
- Any `media_test.go` / oversized-fallback (142) regression after the wake-builder change is a **real**
  failure, not flake — the visible-wake edit must preserve the >4 KB fallback.
- **Go suite FAILs with 0 `--- FAIL:` lines** = the go1.26.x `crypto/tls` session-ticket panic, NOT
  FDC-09 — re-run under `GOTOOLCHAIN=go1.25.0`. (A go test also rewrites `testdata/interop_vectors.json`
  each run — revert it.)
- A pre-existing `core-host-all` fail in `transport_metrics_privacy_test.dart` (`sinceProcessStartMs`
  privacy-allowlist) is **FDC-S0/S1**, not FDC-09 — prove via stash-revert before blaming this plan.
- **Shared-tree hazard:** `new-orbit` has concurrent live dev — scope `git diff` to FDC-09's own files;
  do **not** `git checkout`/`stash`-revert shared test fakes (MEMORY clobber-class hazard).

## Done Criteria

- [x] FDC-S3 closed (2026-06-27); DRAFT banner replaced; mechanism = Option C confirmed; constants
      locked (TTL 180 s / hb 60 s).
- [ ] **FDC-08 landed first** (presence_store.go + bridge_presence.go + HandleInboxStream injection);
      FDC-09 rebased onto it — one shared map, not two.
- [ ] TC-09-01..15 (incl. 07 move-gate, 09 race) authored RED-first, GREEN, every mutation re-reds.
- [ ] `GOTOOLCHAIN=go1.25.0 go test ./...` (relay + go-mknoon) green incl. `-race`;
      `transport` + `posts` + `1to1` + `feature-host-all` + `core-host-all` green; FDC-06 pause-flush
      floor green; `groups` 0-reg.
- [ ] `flutter analyze` 0-new; `git diff --check` clean; `make lint` (both Go modules) clean.
- [ ] Every new exported identifier (`PresenceSet` bridge fn, `RelayPresenceSet`, `handlePresenceSet`,
      `SetPresenceUseCase`, `setPresence`, wake-token store type) carries a doc-comment.
- [ ] `go-relay-server/NOTES.md` (and README if it enumerates dispatch actions) updated to list the new
      `presence_set` action.
- [ ] NET-REL-07 back-compat proven (TC-09-03/08/15/24); HINT-only load-bearing gate proven (TC-09-13);
      move-feature gate proven (TC-09-07); shared-map race-clean proven (TC-09-09).
- [ ] Device rows TC-09-20..24 executed under FDC-S3 Methods 1/2 + `/sims` (deferred-not-waived if relay
      env unavailable — record explicitly).

## Scope Guard (hard Do-not)

- **Do NOT** let the access-token wake gate / push-visibility hardening break group push (`SendGroupNotification`) — group push + `foreground_group_push_drain_test.dart` must stay green. **Group-safety floor:** `./scripts/run_test_gates.sh groups` + `cd go-relay-server && GOTOOLCHAIN=go1.25.0 go test ./...`.
- **Do NOT loosen the existing `ShouldNotify` envelope-type filter** (`inbox.go:866`, `extractChatPushMetadata`) — the access-token gate must **add** a condition (layer on top), never replace or widen it so unknown envelope types start waking.
- Do **not** add a gossipsub presence beacon (Option B rejected) or touch `pubsub.go` (stays group-only).
- Do **not** make presence load-bearing for delivery (TC-09-13 enforces; the store→push seam must never consult presence).
- Do **not** rebuild store dedup/idempotency (exists; FDC-10 owns durability only).
- Do **not** add reservation-exact relay-service-internal tracking.
- Do **not** infer foreground from connectedness (`main.go:145-163`).
- **Naming contract (apply consistently with FDC-08 / FDC-15; DROP the earlier `RelaySetPresence`/`InboxSetPresence`):** WRITE action token = `presence_set`; move-feature gate token = `p2p_set_presence`; relay handler `handlePresenceSet`; gomobile bridge export = **`PresenceSet(paramsJSON string) string`** (symmetric with FDC-08's `PresenceGet`); node fn `RelayPresenceSet(...)`; Dart cmd `'relay:presence_set': _CmdSpec('relayPresenceSet', true)`; Dart bridge method `callP2PRelayPresenceSet`; `P2PService` method `setPresence(state, ttlMs)`. All ride the **JSON-string FFI contract** (params-JSON in / result-JSON out) — no struct-typed FFI.
- **New bridge entrypoint isolation:** the `PresenceSet` bridge fn goes in the NEW `go-mknoon/bridge/bridge_presence.go` (created by FDC-08 for `PresenceGet`) — **do NOT append it to the 2880-line `bridge.go`**.
- Do **not** co-edit `inbox.go` / `push_token_store.go` / `presence_store.go` in a parallel agent with FDC-08 or FDC-10 — serialize (Collision map; order **FDC-10 → FDC-08 → FDC-09**).
- The relay dispatch `case "presence_set"` (`inbox.go:1530`, now 12 cases after FDC-08's `presence_get`) **delegates to a named handler func** (`handlePresenceSet`) — no inline arm logic (mirror FDC-08's `handlePresenceGet`).
- **Presence store: FDC-08 CREATES `presence_store.go` (one TTL'd map) + the `HandleInboxStream` host/store injection; FDC-09 REBASES and adds the WRITE** — do **not** author a second presence map or re-do the injection. Serialize-with-FDC-08 on `presence_store.go` / `inbox.go`.
- **Shared-map race (co-writer preservation, UNCONDITIONAL):** the shared presence map is concurrent state — FDC-08's `presence_get` read, FDC-09's `presence_set` write, and TTL expiry all race on it. FDC-08 establishes the `sync.Map`/mutex guard (R6); **FDC-09's write must keep it race-clean** under `cd go-relay-server && GOTOOLCHAIN=go1.25.0 go test -race ./...` (TC-09-09). **Stop-if:** the write is added unguarded ⇒ `-race` flags a data race; do **not** land until race-clean.

## Accepted Differences

- Server presence + wake-token stores default **in-memory** (mirrors `push_token_store.go`);
  durability is **FDC-10's** single gap, accepted here.
- Pause publish is **best-effort** on iOS (may lose to suspension) — accepted; A/connectedness +
  inbox backstop (**FDC-06 owns the bounded `beginBackgroundTask` window** this rides; FDC-S4 closed).
- Group-push §12 parity is **deferred** to an open issue (1:1 wake hardened first).
- The §12 push-hardening half (access-token / opaque / visible) is **independent** of the presence_set
  write and **may ship as a separate sub-PR** — they only share the `inbox.go` push-path edits.

## Dependency Impact

- **FDC-S3: RESOLVED** (closed 2026-06-27) — no longer a gate; mechanism + constants locked. Remaining
  external dependency = the **live-relay-env** for the device push-proof (FDC-09 stands it up per the
  FDC-S3 risk note).
- **Rebases on FDC-08** (read side): FDC-08 **owns the creation** of `presence_store.go` +
  `bridge_presence.go` + the `HandleInboxStream` host/store injection; FDC-09 adds the `presence_set`
  WRITE + heartbeat that enriches the **same** map. Both add a dispatch arm to `inbox.go` — serialize;
  **order FDC-10 → FDC-08 → FDC-09** (Track E / Phase 2). Do not run in parallel.
- **Shares `inbox.go` + `push_token_store.go` with FDC-10** (durable backend) — FDC-10 lands first so
  presence + wake-tokens survive a relay bounce (durability-ordering hazard, FDC-00). In-memory loss of
  a wake-token must **fail-open to existing push** for already-paired contacts (TC-09-15).
- Client seams touch `p2p_service(_impl).dart`, `handle_app_resumed.dart`, **`handle_app_paused.dart`**,
  `register_push_token_use_case.dart` — `handle_app_resumed.dart` collides with **FDC-04/05** (resume
  warm / re-prime; Tertiary collision), **`handle_app_paused.dart` collides with FDC-06** (pause-flush,
  LANDED — FDC-09 rides its window), and `p2p_service_impl.dart` with **FDC-04/05/07/08/12/13**;
  serialize per FDC-00 secondary/tertiary collisions (one writer at a time).
