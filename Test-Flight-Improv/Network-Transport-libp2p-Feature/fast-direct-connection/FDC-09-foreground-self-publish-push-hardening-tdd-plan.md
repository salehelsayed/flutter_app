# FDC-09 — Foreground self-publish + push-to-wake hardening  (New Feature)

Status: awaiting-review

Spec: Network-Arch/Fast-Direct-Connection-Architecture-Proposal.md (§6.3 presence self-publish; §12 "Push-to-wake hardening" verbatim borrow)

---

## ⚠ DRAFT — finalize after FDC-S3

**This plan is a DRAFT gated by `FDC-S3` (presence-signal decision).** It is written against
FDC-S3's *Expected Output* (read = Option A `presence_get` owned by FDC-08; **self-publish =
Option C `presence_set` status-push**, Option B gossipsub beacon **REJECTED**), but the final
mechanism, TTL/heartbeat constants, and the additive-action wire shape are only **confirmed** when
FDC-S3 closes its device measurements (Method 1/2/3). Every value that S3 must lock is tagged
`<from FDC-S3>`. The **host-testable Go + Dart tiers below carry full RED detail and can be authored
now**; the **device/relay rows are the closure gate** and are explicitly flagged device-only.
Do **not** start implementation until FDC-S3 is `closed` and this banner is removed during finalize.

What finalize-after-S3 must resolve before this leaves DRAFT:
1. Confirm self-publish transport = **Option C `presence_set`** (vs a reopened Option B). FDC-S3
   already records C; re-confirm no reopen.
2. Lock the starting constants S3 proposes (presence TTL ≈ 180 s, fg heartbeat ≈ 60 s) against
   Method-1 connectedness-lag numbers.
3. Confirm whether `presence_set` and `presence_get` ship as **one** additive-action PR pair
   (FDC-08 read + FDC-09 write) and the **store ownership** (shared TTL'd presence map) — collision
   with FDC-08 on `inbox.go` (see Collision).
4. Confirm the push-hardening pieces (access-token gate, opaque routing, visible push) are in
   FDC-09's scope vs split — they are **§12** items the roadmap assigns to FDC-09, not S3-gated by
   themselves, but they co-edit the same `inbox.go` push path, so they ride this plan.

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
- **FDC-S3 Expected Output** (this plan's gate): self-publish = Option C `presence_set`; B rejected;
  starting constants TTL 180 s / heartbeat 60 s / client cache 10–15 s; **presence is a HINT, never
  load-bearing — the inbox is always the guarantee** (hard acceptance gate, §6.3/§12).
- **FDC-00 roadmap** row FDC-09 + the GATING graph (`FDC-S3 → FDC-08, FDC-09`) and the
  **Collision map** (`inbox.go`/`push_token_store.go` shared with FDC-08, FDC-10; serialize).
- `scripts/run_test_gates.sh` wins over prose for any test-name/count claim (the arrays decide what
  the gate runs).

---

## Session Classification

**evidence-gated (DRAFT)** — blocked on FDC-S3 closure for mechanism + constants. The push-hardening
half (§12 access-token/opaque/visible) is implementation-ready from source *today*; the self-publish
half inherits S3's decided Option C but must wait for S3's device-confirmed constants and the
shared-`inbox.go` store-ownership decision with FDC-08.

---

## Exact Problem Statement

Two coupled gaps, both grounded in source:

**(1) The peer cannot announce foreground/background; the relay can only see a TTL-lagged socket.**
`go-relay-server/main.go:143-149` handles only `EvtPeerConnectednessChanged` (raw libp2p socket
connectedness), which *lingers seconds after iOS backgrounding* and **cannot express foreground**
(proposal §1 row 3, §6.3; FDC-S3 Background). There is **no presence-write action** today — the
inbox dispatch (`inbox.go:1530 switch req.Action`) has `store|retrieve|retrieve_pending|ack|
register_token|unregister_token|group_*` and a `default: "Unknown action"` (`:1712-1713`) — so a
peer has no way to self-publish "I am foregrounded" for the §6.3 emphasis branch FDC-08 consumes.

**(2) Push-to-wake is unhardened — coupled to the message path, ungated, and partly silent.**
Verified in source:
- **Coupled / linkable.** The push fires *from the inbox store* at `inbox.go:866-867`
  (`go is.push.SendNotification(ctx, toPeerId, entry.From, entry.Message)`), and
  `SendNotification` (`:135`) embeds the **sender peerId** into push `data["sender_id"]`
  (`buildPushMessage :289`). The push path is **not decoupled** from the message path — the wake
  signal carries the sender↔recipient linkage FCM/APNs can observe (proposal §12 "unlinkable").
- **Ungated (no access-token).** Any peer that can `store` to your inbox triggers a push;
  `SendNotification`/`LookupToken(toPeerId)` (`push_token_store.go:38`) applies **no per-recipient
  contact/access-token check** — there is no "only contacts can wake you" gate (proposal §12
  anti-spam).
- **Silent-leaning.** The `new_message` wake uses `buildCiphertextOnlyPushMessage` (`inbox.go:424`)
  with `ContentAvailable: true` (+ `MutableContent: true` for the NSE decrypt) — i.e. it **requests
  background/silent delivery** which iOS throttles to ~1–2/hr (proposal §12). It does carry an
  `Alert` block, so it is *not fully* silent today, but the wake does not *guarantee* a visible
  alert independent of the content-available path.

**Who feels it:** a backgrounded recipient (the common case the inbox exists for) gets a wake that
may be (a) throttled by iOS as silent, and (b) spammable by non-contacts; and the sender's `direct
vs inbox-first` emphasis (FDC-08) has **no foreground signal** to key off.

**What must improve:** a peer can self-publish fg/bg (`presence_set`); the wake push is **visible**,
**contact-gated** (access-token), and **decoupled/unlinkable** from the message path.

**What must stay unchanged (preserved sentinels):**
- **Presence is a HINT, never load-bearing** — a *wrong* presence value must STILL deliver via inbox
  + push (FDC-S3 hard gate). Preserve: `offline_inbox_roundtrip` delivery semantics.
- **NET-REL-07 back-compat** — a new client hitting an *old* relay gets `"Unknown action"` and
  degrades cleanly (skips self-publish, treats presence as `unknown`); a new relay must still serve
  *old* clients that never send `presence_set` and whose stores carry no access token.
- **Existing push delivery for contacts** — `register_token`/`SendNotification` for already-paired
  contacts keeps working (the `media >4 KB` visible-fallback from `142` at `inbox.go:295`/`:468`
  stays intact).
- **Dedup-by-`messageId`** store behavior unchanged (`backend_memory.go:121-142`,
  `backend_redis.go:272-295`, `inbox_store.go:7,14`) — do **not** touch.

---

## Root Cause (verify→refute confirmed)

| # | Mechanism (file:line, read from source) | Confirmed |
|---|---|---|
| RC1 | **No presence-write action.** Dispatch `inbox.go:1530` has no `presence_set`; relay presence is only the connectedness-lagged `main.go:143-149` map. | ✅ read |
| RC2 | **Push coupled to message path + linkable.** `inbox.go:866-867` fires push inside `store`; `buildPushMessage :289` puts `sender_id = entry.From` in `data`. | ✅ read |
| RC3 | **No access-token gate.** `SendNotification :135` → `LookupToken(toPeerId) :38` does no contact/token authorization; push fires for any successful store. | ✅ read |
| RC4 | **Wake leans silent.** `buildCiphertextOnlyPushMessage :424` sets `ContentAvailable:true` (silent/bg class, iOS-throttled) for `new_message`. | ✅ read |

**Refuted — do NOT re-introduce / do NOT re-scope:**
- ❌ **Do not build a gossipsub presence beacon** (Option B) — FDC-S3 **REJECTED** it (continuous
  churn/battery, net-new pubsub mesh, useless on iOS background). Pubsub stays **group-only**
  (`pubsub.go:105` joins only `GroupTopicPrefix+groupId`).
- ❌ **Do not make presence load-bearing** for delivery (S3 hard gate; §6.3/§12).
- ❌ **Do not rebuild store dedup/idempotency** — already present and correct (out of scope; owned by
  the durability hazard note, FDC-10).
- ❌ **Do not add reservation-exact tracking** via go-libp2p relay-service internals (S3: explicitly
  OUT; coarse connectedness + self-published state suffices for a HINT).
- ❌ **Do not infer foreground from connectedness** (`main.go:143-149` provably cannot — that is the
  whole reason for self-publish).

---

## Real Scope

**In scope (FDC-09):**
- **Self-publish WRITE** — additive `presence_set` inbox action (`<from FDC-S3>`: Option C) + a TTL'd
  presence store; Dart hooks on **resume** (`handle_app_resumed.dart:136-191`), best-effort on
  **pause** (`main.dart:4314-4316`, bounded by the FDC-S4 `beginBackgroundTask` window — advisory),
  + a slow foreground heartbeat; a `setPresence` bridge call on `P2PService`.
- **Push hardening (§12):** (a) per-recipient **access-token** gate so only contacts wake you;
  (b) **opaque-token routing** decoupling the wake from the sender↔message linkage; (c) **visible**
  wake push (alert-class, not content-available-only).
- **Move-feature gate (REQUIRED — account-migration safety):** the new `setPresence` `P2PService`
  primitive MUST route through `_allowsAccountNetworkSideEffects('p2p_set_presence')` (mirror `warmPeer`
  FDC-04 step 2 / `registerPushToken` `p2p_service_impl.dart:3889`) and no-op during an account-move.
  **CRITICAL:** the **pause** hook (`main.dart:4314-4316`) is on the **UNgated** pause path — without
  gating the primitive, `presence_set{background}` would announce the **moving** device as
  reachable/online to the relay during a move-export pause, contradicting move semantics (the device is
  ceding the account). The resume hook is already covered by the whole-resume gate
  (`handle_app_resumed.dart:114`), but gating the primitive makes BOTH paths safe (defense-in-depth).
  **Lock:** a RED test — gate-false on pause ⇒ no `presence_set` emitted; mutation = drop the gate ⇒
  background publish fires.

**Out of scope (owning FDC-xx):**
- Presence **READ** / `presence_get` + client short-TTL cache + retiring `probeRelay` → **FDC-08**
  (consumes the same shared presence store; co-edit `inbox.go` — serialize).
- The §6.3 send-emphasis branch (`reachable==true → inbox lazy`, etc.) → **FDC-08**.
- iOS pause-flush feasibility / `beginBackgroundTask` budget → **FDC-S4 → FDC-06** (this plan's
  pause-push *piggybacks* that window but does not resolve its feasibility).
- Durable Redis presence/token persistence + relay pool → **FDC-10** (this plan's stores default
  in-memory like the existing `push_token_store.go`; durability is FDC-10's single gap).

---

## Files To Inspect Next

**Production — relay (Go):**
- `go-relay-server/inbox.go` — dispatch `switch req.Action` (`:1530`), `register_token` (`:1616`),
  `default` (`:1712-1713`), `inboxRequest` struct (`:1424`), store→push trigger (`:866-867`),
  `SendNotification` (`:135`), `buildPushMessage` (`:284`), `buildCiphertextOnlyPushMessage` (`:424`),
  `buildOversizedFallbackPushMessage` (`:468`), `pushDataSize`/`maxPushDataBytes` (`:53`,`:460`).
- `go-relay-server/push_token_store.go` — `memoryPushTokenStore` (`:11`), `RegisterToken` (`:22`),
  `LookupToken` (`:38`), `UnregisterToken` (`:32`). (New presence store + wake-token store land here
  or in sibling `presence_store.go` / `wake_token_store.go` — `<from FDC-S3>` store-ownership.)
- `go-relay-server/main.go:143-149` (connectedness handler — read-only context; do not infer fg/bg).

**Production — client (Dart):**
- `lib/core/services/p2p_service.dart:167` (`registerPushToken` signature) + impl
  `p2p_service_impl.dart:3889` (`registerPushToken`), `:3751` — seam for a new `setPresence(...)` /
  wake-token bridge.
- `lib/features/push/application/register_push_token_use_case.dart` — token registration flow; the
  access-token issuance/registration rides alongside `PUSH_REGISTER_TOKEN_*` flow events.
- `lib/core/lifecycle/handle_app_resumed.dart:136-191` (resume → `presence_set{foreground}`).
- `lib/main.dart:4314-4316` (`handleAppPaused`, local-DB-only today → best-effort
  `presence_set{background}` under the bounded window).
- `lib/features/push/domain/push_token_store.dart` + `infrastructure/push_token_store_impl.dart`
  (local token persistence pattern to mirror for any client-held wake-token).

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
| presence_set / wake-token / visible-push direct tests | ❌ **MISSING** | **to add** (Go `inbox_test.go`; Dart `test/features/push/**` AUTO-glob; presence-ish → `POSTS_TESTS` if a curated headline is added) |

> Note: the project has **no dedicated `presence` gate**. The prompt's "posts (presence-ish)" maps to
> `POSTS_TESTS`, whose `post_presence_listener_test.dart` is the nearest presence regression floor.
> A new curated 1:1/transport presence headline must be **appended to the readonly array** in
> `scripts/run_test_gates.sh` or it will silently not run (harness rule).

---

## RED Test Catalog

Tiers: **Go-unit** (relay, `go test`), **Dart-unit/widget** (host, AUTO-glob), **integration**
(transport/posts host-fake), **device/sim** (closure gate — DRAFT-flagged, NOT host-provable).
Every behavior-bearing edit has a re-red mutation. Where the same observable (a push fires / a store
succeeds) is reachable by two paths, the discriminator is a **distinct flow-event / push-class**.

### A. Self-publish WRITE (`presence_set`) — `<from FDC-S3>` Option C

- **TC-09-01** · `go-relay-server/inbox_test.go::TestPresenceSet_AdditiveAction_StoresState`
  · **Tier:** Go-unit
  · **Setup:** dispatch `inboxRequest{Action:"presence_set", Metadata:{state:"foreground", ttlMs:…}}`
  from `remotePeer`; read back via the presence store.
  · **RED on HEAD because:** `presence_set` is unknown → falls to `default` (`inbox.go:1712-1713`),
  `Status:"ERROR", Error:"Unknown action: presence_set"`; no store exists.
  · **GREEN asserts:** `Status:"OK"`; presence store holds `{remotePeer → foreground, expiresAt=now+ttl}`.
  · **Mutation that re-reds:** drop the `case "presence_set"` arm → back to Unknown-action error.

- **TC-09-02** · `inbox_test.go::TestPresenceSet_TTLExpiry_DegradesToUnknown`
  · **Tier:** Go-unit
  · **Setup:** set `{foreground, ttlMs: T}` with an injected clock; advance clock past `T`; read.
  · **RED on HEAD:** no TTL store exists (compile/red).
  · **GREEN:** read after expiry returns `unknown` (never silently `offline`; FDC-S3 semantics).
  · **Mutation:** make the read ignore `expiresAt` (always return last-written) → expiry test re-reds.

- **TC-09-03** · `inbox_test.go::TestPresenceSet_BackCompat_OldRelayUnknownAction`
  · **Tier:** Go-unit (NET-REL-07)
  · **Setup:** call the *default* arm path for an action the relay does not implement (simulate an old
  relay by asserting the `default` arm copy is unchanged for unknown actions).
  · **RED/GREEN:** asserts `presence_set` on a build *without* the case yields the exact
  `"Unknown action: presence_set"` string a new client maps to `unknown`. (Locks the additive
  contract; client side TC-09-08.)
  · **Mutation:** change the `default` error text → client mapping test (TC-09-08) re-reds.

- **TC-09-04** · `test/features/push/application/set_presence_use_case_test.dart::publishesForegroundOnResume`
  · **Tier:** Dart-unit
  · **Setup:** fake `P2PService` capturing `setPresence(state, ttlMs)`; invoke the resume hook seam.
  · **RED on HEAD:** no `setPresence` on `P2PService` (`p2p_service.dart:167` has only
  `registerPushToken`) → compile-red.
  · **GREEN:** resume emits `setPresence('foreground', <ttl from FDC-S3>)` exactly once + flow event
  `PRESENCE_SELF_PUBLISH{state:foreground}`.
  · **Mutation:** drop the resume call → not-called assertion re-reds.

- **TC-09-05** · `…set_presence_use_case_test.dart::publishesBackgroundOnPause_bestEffort`
  · **Tier:** Dart-unit
  · **Setup:** invoke the pause seam (`handleAppPaused`); fake captures one best-effort
  `setPresence('background', …)`; assert it is **bounded / fire-and-forget** (does not block pause).
  · **RED on HEAD:** `handleAppPaused` is local-DB-only, no network (`main.dart:4314-4316`).
  · **GREEN:** exactly one best-effort background publish, unawaited; flow event
  `PRESENCE_SELF_PUBLISH{state:background, bestEffort:true}`.
  · **Mutation:** `await` the publish (block pause) → "does not block / fire-and-forget" assertion
  re-reds. **Discriminator vs TC-09-04:** `state` + `bestEffort` flag in the flow event.

- **TC-09-06** · `…set_presence_use_case_test.dart::foregroundHeartbeatRefreshesTTL`
  · **Tier:** Dart-unit
  · **Setup:** fake clock/timer; foreground for > heartbeat interval `<from FDC-S3 ≈ 60 s>`.
  · **RED on HEAD:** no heartbeat timer exists.
  · **GREEN:** a refresh `setPresence('foreground', …)` fires per heartbeat interval; stops on pause.
  · **Mutation:** never re-arm the timer → second-tick assertion re-reds.

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
  · **RED on HEAD:** `buildCiphertextOnlyPushMessage :424` sets `ContentAvailable:true` (silent/bg
  class) for the wake; assert "wake is a visible alert that does not rely on content-available-only"
  fails.
  · **GREEN:** wake message has `APNS.Headers["apns-push-type"]=="alert"`, a non-empty `Aps.Alert`,
  **and** does not depend on `ContentAvailable:true` for visibility (Android `Priority:"high"` with a
  `Notification` block). Preserve `MutableContent` for the NSE decrypt path.
  · **Mutation:** revert to content-available-only (drop the Alert/notification block) → re-reds.
  · **Note (DRAFT):** *whether* to keep `ContentAvailable` alongside a visible alert is an iOS-NSE
  interaction → **device row TC-09-20 is the real proof** (host asserts only message shape).

- **TC-09-11** · `inbox_test.go::TestWakePush_AccessTokenGate_OnlyContactsWake`
  · **Tier:** Go-unit
  · **Setup:** recipient registers an authorized wake-token set (contacts); store a message whose
  envelope presents (a) a valid wake token, then (b) an invalid/absent one.
  · **RED on HEAD:** push fires unconditionally at `inbox.go:866-867` (no gate) → the
  "no-push-for-non-contact" assertion fails.
  · **GREEN:** valid token → `SendNotification` invoked (counter `success`); invalid/absent →
  **no push**, counter `unauthorized_wake` (new label), message still **stored** (delivery preserved).
  · **Mutation:** remove the gate (always push) → non-contact assertion re-reds.
  · **Discriminator:** `pushSentCounter` label `success` vs `unauthorized_wake` (distinct from the
  existing `missing_token`).

- **TC-09-12** · `inbox_test.go::TestWakePush_OpaqueRouting_NoSenderLinkInPush`
  · **Tier:** Go-unit (unlinkability)
  · **Setup:** store a `new_message`; capture the assembled FCM `data` for the wake.
  · **RED on HEAD:** `buildPushMessage :289` sets `data["sender_id"]=fromPeerId` → linkable.
  · **GREEN:** the wake carries only an **opaque routing token** (no raw sender peerId; content pulled
  from inbox on open); the inbox `retrieve` path still resolves the real sender after E2E decrypt.
  · **Mutation:** re-add `sender_id` raw → linkability assertion re-reds.
  · **Preserved sentinel:** notif-open routing (`prepare_notification_open_use_case`) must still
  resolve the conversation from the opaque token (covered by TC-09-13).

- **TC-09-13** · `inbox_test.go::TestWakePush_StillDelivers_WhenPresenceWrong`
  · **Tier:** Go-unit (**FDC-S3 hard gate: presence never load-bearing**)
  · **Setup:** force presence store to `online` for a peer that is actually offline; store a message.
  · **RED on HEAD:** N/A as a gate today (no presence) — written as the **preservation lock** so a
  future presence-coupled mutation cannot pass.
  · **GREEN:** message is **stored** and a wake **push fires** regardless of the (wrong) presence
  value — presence does not gate delivery.
  · **Mutation:** gate the store/push on `presence==offline` → this test re-reds (proves the
  load-bearing rejection from S3 / §12).

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

### C. Device / relay closure rows (DRAFT — NOT host-provable; FDC-S3 Methods feed these)

- **TC-09-20** *(device)* — iOS visible-wake actually surfaces an alert for a **backgrounded** peer
  and is **not** silent-throttled (§12 ~1–2/hr). Two real devices + real relay + APNs.
- **TC-09-21** *(device)* — `presence_set{background}` on pause **lands before iOS suspends**
  (success rate over ~20 trials; FDC-S3 Method 2). Below 50% → C degrades to connectedness on iOS;
  Android still benefits.
- **TC-09-22** *(device)* — connectedness-lag vs self-published `background` (FDC-S3 Method 1) sets
  the final presence TTL (`<from FDC-S3>`).
- **TC-09-23** *(device)* — non-contact **cannot** wake a recipient over the live relay (access-token
  gate end-to-end).
- **TC-09-24** *(sim/relay)* — additive back-compat: a *new* client against an *old* relay build gets
  `"Unknown action: presence_set"` and degrades (FDC-S3 Method 3 / NET-REL-07).

---

## Test Coverage Matrix

| Spec case (proposal §) | Behavior property | Tier | Test file::name | RED reason on HEAD | Mutation revert | Acceptance gate cmd | Harness registration |
|---|---|---|---|---|---|---|---|
| §6.3 self-publish (S3 Opt C) | `presence_set` stores state | Go-unit | `inbox_test.go::TestPresenceSet_AdditiveAction_StoresState` | unknown action → `default` (`:1712`) | drop case arm | `cd go-relay-server && go test ./...` | go test (no array) |
| §6.3 / S3 TTL 180 s | TTL expiry → `unknown` | Go-unit | `inbox_test.go::TestPresenceSet_TTLExpiry_DegradesToUnknown` | no TTL store | ignore `expiresAt` | `go test ./...` | go test |
| NET-REL-07 | additive `Unknown action` | Go-unit | `inbox_test.go::TestPresenceSet_BackCompat_OldRelayUnknownAction` | n/a (locks contract) | change default text | `go test ./...` | go test |
| §6.3 resume publish | fg on resume | Dart-unit | `set_presence_use_case_test.dart::publishesForegroundOnResume` | no `setPresence` seam (`:167`) | drop resume call | `flutter test test/features/push/` | AUTO-glob `test/features/**` |
| §6.4 pause publish | bg best-effort, non-blocking | Dart-unit | `…::publishesBackgroundOnPause_bestEffort` | pause is DB-only (`4314-4316`) | `await` the publish | `flutter test test/features/push/` | AUTO-glob |
| §6.3 heartbeat (S3 60 s) | fg heartbeat refresh | Dart-unit | `…::foregroundHeartbeatRefreshesTTL` | no timer | no re-arm | `flutter test test/features/push/` | AUTO-glob |
| NET-REL-07 client | old-relay → skip | Dart-unit | `…::oldRelayUnknownAction_mapsToSkip` | no mapping | map to retry/fail | `flutter test test/features/push/` | AUTO-glob |
| §12 visible push | alert-class, not silent-only | Go-unit | `inbox_test.go::TestWakePush_VisibleAlert_NotSilentOnly` | content-available-only (`:424`) | revert to silent-only | `go test ./...` | go test |
| §12 access-token | only contacts wake | Go-unit | `inbox_test.go::TestWakePush_AccessTokenGate_OnlyContactsWake` | ungated push (`:866-867`) | remove gate | `go test ./...` | go test |
| §12 opaque/unlinkable | no sender_id in wake | Go-unit | `inbox_test.go::TestWakePush_OpaqueRouting_NoSenderLinkInPush` | `sender_id=fromPeerId` (`:289`) | re-add `sender_id` | `go test ./...` | go test |
| §6.3/§12 HINT-only (S3 gate) | wrong presence still delivers | Go-unit | `inbox_test.go::TestWakePush_StillDelivers_WhenPresenceWrong` | preservation lock | gate store on presence | `go test ./...` | go test |
| §12 access-token issuance | mint/persist wake tokens | Dart-unit | `register_push_token_use_case_test.dart::issuesWakeTokensToContacts` | no issuance | skip persistence | `flutter test test/features/push/` | AUTO-glob |
| NET-REL-07 token | old-relay token degrade | Dart-unit | `…::oldRelayRejectsAccessToken_gracefulDegrade` | no degrade path | hard-fail on missing support | `flutter test test/features/push/` | AUTO-glob |
| §12 visible (device) | alert surfaces, not throttled | device | `TC-09-20` | DRAFT/device-only | n/a | `/sims <scope> --only N` + 2-device smoke | classify_path() + dart-define case |
| §6.4 pause lands (device) | bg before suspend | device | `TC-09-21` | DRAFT/device-only | n/a | 2-device, FDC-S3 Method 2 | sim harness case |
| §6.3 TTL calibration (device) | connectedness-lag → TTL | device | `TC-09-22` | DRAFT/device-only | n/a | FDC-S3 Method 1 | n/a (measurement) |
| §12 anti-spam (device) | non-contact cannot wake | device | `TC-09-23` | DRAFT/device-only | n/a | 2-device + relay | sim harness case |
| NET-REL-07 (sim) | new-client/old-relay degrade | sim/relay | `TC-09-24` | DRAFT/device-only | n/a | FDC-S3 Method 3 | sim harness case |

*No empty cells. Device rows carry the DRAFT flag — their acceptance is the closure gate, not host.*

---

## Blind-Spot Sweep

- **Lifecycle / derived-state durability:** presence is TTL'd and **never silently `offline`** → falls
  to `unknown` on expiry (TC-09-02); wake-tokens persist client-side and survive reload (TC-09-14).
  Server presence/token stores are **in-memory** like `push_token_store.go` → a relay bounce loses
  them; **durability is FDC-10's gap**, not this plan's (presence is a HINT so loss only widens the
  `unknown` window; wake-token loss must **fail-open to existing push** for already-paired contacts so
  a bounce does not silence contacts — covered by TC-09-15 degrade semantics). **Open issue flagged.**
- **Sibling-surface consistency:** **group** push (`SendGroupNotification :148` / `group_store`
  `:1628`) shares the same `LookupToken`/visible-push concerns. DRAFT decision needed: does §12
  hardening apply to group wake too, or 1:1 first? → tracked as an open issue; group rows N/A until
  resolved (the `foreground_group_push_drain_test.dart` floor must stay green either way).
- **Destructive-action side-effects:** `unregister_token` (`:1624`) and the invalid-token auto-removal
  (`sendWithRetry :209`) must also clear any access-token/presence state for that peer (no orphaned
  wake authorization) — add a preservation assertion (rider on TC-09-11).
- **Invariant re-verification under new transitions:** the **dedup-by-messageId** store invariant and
  the **142 oversized-media visible fallback** (`:295`,`:468`) must remain green after the wake-builder
  change (TC-09-10 must not regress `media_test.go` / oversized-fallback) — regression floor, not a
  new test.
- **Bridge serialization (§10):** `setPresence`/heartbeat funnel through the **single Go bridge** with
  the user's send → must be cheap, off the send-critical path, and **never block a send** (TC-09-05
  asserts non-blocking pause; FDC-S5 contract). N/A-justified beyond that: read-side caching is FDC-08.

---

## Invariants (locked by tests)

1. **Presence is a HINT, never load-bearing** — wrong presence still delivers via inbox + push
   (TC-09-13). *(FDC-S3 hard gate; §6.3/§12.)*
2. **Additive / NET-REL-07** — `presence_set` + access-token are additive; old relay → `Unknown
   action` → client degrades to `unknown`/plain-token (TC-09-03/08/15).
3. **Only contacts can wake you** — non-contact wake is suppressed but the message is still stored
   (TC-09-11).
4. **Wake is unlinkable** — no raw sender peerId in the push payload; content pulled from inbox
   (TC-09-12).
5. **Wake is visible** — alert-class, not content-available-only (TC-09-10 host shape; TC-09-20
   device proof).
6. **Self-publish never blocks lifecycle** — pause publish is best-effort/bounded (TC-09-05).
7. **Pubsub stays group-only** — no presence beacon added (Option B rejected; no test needed, but
   `pubsub.go` must remain unedited).

---

## Step-By-Step Implementation Plan

> RED first for every step. Stop-if blockers noted. **Do not start until FDC-S3 is closed.**

1. **(RED)** Author Go `inbox_test.go` cases TC-09-01/02/03/10/11/12/13. **Seam:** `inbox.go` dispatch
   `switch req.Action` (`:1530`) + a new `presence_store.go` (TTL'd `map[peerId]presenceEntry`,
   injected clock) + a `wake_token_store.go` (authorized-token set). **Stop-if:** S3 has not confirmed
   store ownership shared with FDC-08 → coordinate so FDC-08's `presence_get` reads the **same**
   store (avoid two divergent presence maps in one `inbox.go`).
2. **(GREEN)** Add `case "presence_set"` (read `Metadata.state`/`ttlMs` from `inboxRequest :1424`,
   or add typed fields), write the presence store; expiry → `unknown`.
3. **(GREEN)** Harden the wake at the `store→push` seam (`:866-867`): gate `SendNotification` behind
   the wake-token check; route via opaque token (drop `sender_id` from `buildPushMessage :289` → an
   opaque key); make `buildCiphertextOnlyPushMessage :424` emit a visible alert (keep `MutableContent`
   for NSE). **Stop-if:** removing `sender_id` breaks `prepare_notification_open` routing → thread the
   opaque token through notif-open instead of re-adding `sender_id`.
4. **(RED)** Author Dart `set_presence_use_case_test.dart` TC-09-04/05/06/08 + extend
   `register_push_token_use_case_test.dart` TC-09-14/15. **Seam:** add `setPresence(state, ttlMs)` to
   `P2PService` (`p2p_service.dart:167`) + impl (`p2p_service_impl.dart:3889` neighborhood); a
   `SetPresenceUseCase`; hooks at `handle_app_resumed.dart:136-191` (resume) and `main.dart:4314-4316`
   (pause, best-effort + heartbeat timer).
5. **(GREEN)** Implement the Dart seams; access-token issuance rides `register_push_token_use_case`.
6. **(VERIFY)** Run every mutation in the catalog; confirm each re-reds. Then run host + Go gates.
7. **(DRAFT-DEFER)** Device rows TC-09-20..24 → execute under FDC-S3 Methods + `/sims` closure; do
   not block host-green on them, but do not mark Done without them (deferred-not-waived).

---

## Risks And Edge Cases

| Risk | Pinned by |
|---|---|
| Removing `sender_id` breaks notif-open routing | TC-09-12 + notif-open preservation rider |
| Access-token gate silences legit contacts on relay bounce (in-mem loss) | TC-09-15 fail-open degrade + open issue (FDC-10 durability) |
| iOS suspends before pause publish lands | TC-09-21 (device) — degrades to connectedness (acceptable, A backstops) |
| Visible-push change regresses 142 oversized-media fallback | `media_test.go` / oversized-fallback floor (TC-09-10 must not regress) |
| Presence accidentally made load-bearing | TC-09-13 hard gate |
| Bridge head-of-line block from heartbeat | TC-09-05 non-blocking + FDC-S5 contract |
| Group push parity ambiguous | open issue (sibling-surface sweep) |

---

## Device/Relay Proof Profile

**Host-only closes:** TC-09-01..15 (Go + Dart shape/semantics). A green host gate proves the
*message/store shape and the gating logic*, **not** that iOS surfaces a visible wake or that pause
publish beats suspension — those are device-only (host fakes cannot reproduce iOS background-kill or
APNs throttling; FDC-S3 Method note).

**Requires sim/device (closure):** TC-09-20..24 — real two-device pair + real relay + APNs, run under
FDC-S3 Methods 1/2/3. **Closure scenario:** `./scripts/check_reliability_simulation_discovery.sh`
then `/sims <scope> --only N` (new scenario needs a `classify_path()` case + dart-define case first).
Live relay env reproducibility is an **open dependency** (per MEMORY the relay env is gitignored;
FDC-S3 / FDC-09 must confirm a deployable relay before these run).

---

## Acceptance Gates

```bash
# Go (relay) — presence_set + push hardening unit tests
cd /Users/I560101/Project-Sat/mknoon-2/flutter_app/go-relay-server && go test ./...
cd /Users/I560101/Project-Sat/mknoon-2/flutter_app/go-relay-server && go test -race ./...   # data-race gate (concurrent presence store + push path)
cd /Users/I560101/Project-Sat/mknoon-2/flutter_app/go-relay-server && make lint            # relay lint gate (presence_set handler + wake-gate)
# expected: PASS (0 fail); new presence_set / wake-gate / visible / opaque cases GREEN. count: 191 pass / 0 fail / 2 skip
cd /Users/I560101/Project-Sat/mknoon-2/flutter_app/go-mknoon && go test ./...   # stays green (no host change here)
cd /Users/I560101/Project-Sat/mknoon-2/flutter_app/go-mknoon && make lint        # gomobile bridge lint gate (RelaySetPresence export)

# Dart host gates
cd /Users/I560101/Project-Sat/mknoon-2/flutter_app
./scripts/run_test_gates.sh transport    # TRANSPORT_TESTS (run_test_gates.sh:164-168). count: device/fixture-gated (skips on lone sim)
./scripts/run_test_gates.sh posts        # POSTS_TESTS incl post_presence_listener (presence-ish floor). count: device-gated suites (not captured this wave)
./scripts/run_test_gates.sh 1to1         # delivery preserved (offline_inbox_roundtrip). count: 1226 (prior ~1226)
./scripts/run_host_test_gates.sh feature-host-all   # push/* AUTO-glob picks up new set_presence tests. 0 fail
flutter test test/features/push/         # new set_presence_use_case_test + register_push_token extensions

# group-safety floor (wake-gate / push-visibility must not break group push — Scope Guard; pairs with the go-relay-server go test above)
./scripts/run_test_gates.sh groups       # expected: 0 fail (no group regression)

# Sims / device closure (Phase-2 + §12 device proof) — DRAFT closure gate
./scripts/check_reliability_simulation_discovery.sh
/sims <scope> --only N                   # <scope/N from FDC-S3 Methods; classify_path()+dart-define case first>

# Hygiene
flutter analyze                          # 0 new
git diff --check
```

Expected counts are **TODO** — capture the green baseline before FDC-09 starts (per FDC-00 closure
strategy; prior 1:1 ≈ 1226). Device/sim numbers are `<from FDC-S3>`.

---

## Known-Failure Interpretation

- A host-green Go/Dart gate with the device rows still open is **expected** for a DRAFT — it proves
  delivery + gating shape, **not** the iOS visible-wake / pause-landing (FDC-00 "host-testable ≠
  validated" caveat). Do not read host-green as closure.
- An old-relay run that returns `"Unknown action: presence_set"` is **success** (NET-REL-07), not a
  failure — the client must degrade silently (TC-09-08).
- Any `media_test.go` / oversized-fallback (142) regression after the wake-builder change is a **real**
  failure, not flake — the visible-wake edit must preserve the >4 KB fallback.

## Done Criteria

- [ ] FDC-S3 closed; banner removed; mechanism = Option C confirmed; constants locked (`<from FDC-S3>`).
- [ ] TC-09-01..15 authored RED-first, GREEN, every mutation re-reds.
- [ ] `go test ./...` (relay + go-mknoon) green; `transport` + `posts` + `1to1` + `feature-host-all` green.
- [ ] `flutter analyze` 0-new; `git diff --check` clean.
- [ ] Every new exported identifier (`RelaySetPresence`, `handlePresenceSet`, `SetPresenceUseCase`, `setPresence`, presence/wake-token store types) carries a doc-comment.
- [ ] `go-relay-server/NOTES.md` (and README if it enumerates dispatch actions) updated to list the new `presence_set` action.
- [ ] NET-REL-07 back-compat proven (TC-09-03/08/15/24).
- [ ] HINT-only load-bearing gate proven (TC-09-13).
- [ ] Device rows TC-09-20..24 executed under FDC-S3 Methods + `/sims` (deferred-not-waived if relay
      env unavailable — record explicitly).

## Scope Guard (hard Do-not)

- **Do NOT** let the access-token wake gate / push-visibility hardening break group push (`SendGroupNotification`) — group push + `foreground_group_push_drain_test.dart` must stay green. **Group-safety floor:** `./scripts/run_test_gates.sh groups` + `cd go-relay-server && go test ./...`.
- Do **not** add a gossipsub presence beacon (Option B rejected) or touch `pubsub.go` (stays group-only).
- Do **not** make presence load-bearing for delivery.
- Do **not** rebuild store dedup/idempotency (exists; FDC-10 owns durability only).
- Do **not** add reservation-exact relay-service-internal tracking.
- Do **not** infer foreground from connectedness (`main.go:143-149`).
- **Naming contract (apply consistently with FDC-08 / FDC-15):** WRITE action token = `presence_set`; move-feature gate token = `p2p_set_presence`; gomobile bridge export named explicitly `RelaySetPresence(paramsJSON string) (result string)` (or `InboxSetPresence`) riding the **JSON-string FFI contract** (params-JSON in / result-JSON out) — no struct-typed FFI.
- Do **not** co-edit `inbox.go` / `push_token_store.go` in a parallel agent with FDC-08 or FDC-10 —
  serialize (Collision map).
- The relay dispatch `case "presence_set"` (`inbox.go:1530`) **delegates to a named handler func** (`handlePresenceSet`) — no inline arm logic (mirror FDC-08's `handlePresenceGet`).
- Resolve the presence store to a **single named file `presence_store.go`** co-owned with FDC-08 (one TTL'd map; do **not** spawn two divergent presence maps in `inbox.go`) — **reaffirm serialize-with-FDC-08** on `presence_store.go` / `inbox.go`.
- **S3 race-lock (Stop-if):** the shared relay presence map (`presence_store.go`, co-owned with FDC-08) is concurrent state — the FDC-08 `presence_get` read, the FDC-09 `presence_set` write, and TTL expiry all race on the same map; it **MUST** be `sync.Map`/mutex-guarded and **covered by `cd go-relay-server && go test -race ./...`** (the data-race gate). **Stop-if:** the map is added without a guard ⇒ `go test -race` flags a data race; do **not** land until race-clean.

## Accepted Differences

- Server presence + wake-token stores default **in-memory** (mirrors `push_token_store.go`);
  durability is **FDC-10's** single gap, accepted here.
- Pause publish is **best-effort** on iOS (may lose to suspension) — accepted; A/connectedness +
  inbox backstop (FDC-S4 owns the bounded-window feasibility).
- Group-push §12 parity is **deferred** to an open issue (1:1 wake hardened first).

## Dependency Impact

- **Gated by FDC-S3** (mechanism + constants).
- **Co-owns the presence store with FDC-08** (read side) — both edit `inbox.go`; serialize and share
  one TTL'd map.
- **Shares `inbox.go` + `push_token_store.go` with FDC-10** (durable backend) — FDC-10 should land the
  durable backend before/alongside so presence + wake-tokens survive a relay bounce (durability-ordering
  hazard, FDC-00).
- Client seams touch `p2p_service(_impl).dart`, `handle_app_resumed.dart`, `main.dart`,
  `register_push_token_use_case.dart` — `handle_app_resumed.dart` collides with **FDC-05** (resume
  re-prime) and `p2p_service_impl.dart` with **FDC-04/05/08**; serialize per FDC-00 secondary collision.
