# 217 - CV-14 Wake-Token Dark Landing (activation-ready foundation, flips deferred)  (Feature Improvement)

Status: **execution-ready** (revised per `217-review-fixlist.md` 9-agent audit; then RE-REVIEWED 2026-07-06 via 10-agent `/tdd-review` — 2 must-fix applied [A13a sim-emission carve-out; A16 reclassified green-default-lock] + 5 tightenings [A03/A04 gate, A17 production-factory, per-slice GREEN gates, C4 denominator, C2 CI dep]; core bet source-confirmed SOUND, all load-bearing anchors re-verified exact)
Spec: free-text intent (no formal spec) — surfaced by the go-libp2p 1:1-connectivity survival audit (2026-07-06).

> **Scope note (title is literal):** this plan lands **all** the code for the CV-14 wake-token loop, but the two behaviour-changing flips ship **DARK** and are deferred: (1) sender `wt` **emission** (a compile-time `--dart-define`, default OFF) and (2) relay **gate enforcement** (`wakeTokenGateEnforced`, a separate relay-ops slice). "Dark Landing" = an activation-ready, inert foundation; the fleet flips happen later behind a measurable saturation trigger (§C4). It is NOT "full activation" — that word overstated an inert foundation (fix-list F1).
> **Part B (feature-flag decode-seam guard) has been SPLIT OUT** into `219-feature-flag-decode-seam-merge-guard-tdd-plan.md` (verified orthogonal — Part A sends no featureFlags and edits no `bridge.go`). 219 closes host-side today; this plan is wake-token-only.

## Planning Progress
| Time | Role | Files inspected | Decision/blocker | Next action |
|---|---|---|---|---|
| 2026-07-06 | Evidence Collector | inbox.go, bridge.go, bridge_wake.go, go-relay-server/{inbox.go,wake_token_store.go}, issue_wake_tokens_use_case.dart, wake_token_store{,_impl}.dart, send_contact_request_use_case.dart, handle_incoming_message_use_case.dart, retry_incomplete_key_exchanges_use_case.dart, mlkem_reannounce_marker.dart, p2p_bridge_client.dart, p2p_service_impl.dart, startup_router.dart, main.dart | Two legs + distribution mapped; Go/bridge/relay/native complete; only Dart wiring + distribution missing | design verify→refute (wf_3aa586b1-383) |
| 2026-07-06 | Planner | design workflow (5 design + 5 adversarial) | distribution initially sound=False (signed-field break) → corrected TC-A02 | emit matrix |
| 2026-07-06 | Reviewer (9-agent) | `217-review-fixlist.md` (3 verify → 5 dimension → critic) | ready-with-tightening; core bet SOUND; 4 material fixes + splits | apply fix-list |
| 2026-07-06 | Arbiter | this revision | fix-list §A–§F applied; TC-A13 split; Part B → 219 | hand off to execution |

## Execution Progress
| Time | Phase | Files touched | Command/evidence | Decision/blocker | Next |
|---|---|---|---|---|---|
| | contract extraction (git status --short) | | | scope confirmed | |
| | RED tests added | | (cmd proving they FAIL) | RED for expected reason | |
| | implementation | | | scoped files only | |
| | direct GREEN | | (exact cmd) | reds now green | |
| | preservation GREEN | | (exact cmd) | sentinels green | |
| | named gates | | (exact cmd + counts) | gate green | |
| | QA (independent) | | (re-run cmds) | blocking: none/list | verdict |

## Source Of Truth
- Spec / intent: inline (audit finding).
- Gate definitions: `scripts/run_test_gates.sh`, `scripts/run_host_test_gates.sh` (script wins over prose).
- Discovery/registration: `scripts/check_reliability_simulation_discovery.sh`.
- Numbering / index: `Test-Flight-Improv/00-INDEX.md` (#217; Part B split → #219).
- Go toolchain: **all Go commands require `GOTOOLCHAIN=go1.25.0`** (local 1.26.4 panics quic-go).

## Session Classification
implementation-ready — with two intentionally-dark flip points: sender emission behind `--dart-define=MKNOON_EMIT_WAKE_TOKEN` (default OFF, §C2), and relay `wakeTokenGateEnforced` (deferred relay-ops slice, §C4). Closure = the gate-INDEPENDENT cross-device proof **TC-A13a**, runnable now.

---

## Exact Problem Statement
CV-14 (FDC-09 §12) is an **access-token wake gate**: a recipient mints an opaque per-contact token, registers the SET with the relay, and a sender must present the recipient's token on `inbox:store` so the relay authorizes waking that recipient ("only contacts can wake you"). Go/bridge/relay/**native** are complete + host-tested, but the loop is **DORMANT**: `IssueWakeTokensUseCase`/`WakeTokenStoreImpl` are constructed **nowhere** in `lib/`; there is **no distribution transport** for a recipient's token T_C to reach contact C, **no sender-side received-token store**, and `callP2PInboxStore` sends **no** `wakeToken`.

Who experiences it: nobody today (the relay gate `wakeTokenGateEnforced=false` fail-opens — every push wakes). Why it matters: the anti-abuse gate the §12 work paid for is unreachable, and a naive future relay flip would hard-silence 1:1 pushes.

What must improve: land the full loop as an inert, forward-compatible foundation — recipient register → distribute T_C over an authenticated per-contact-private channel (incl. backfill of existing contacts) → sender stores + attaches on `inbox:store` — with both flips deferred behind a saturation trigger.
What must stay unchanged (→ preserved-green sentinels): existing v1/v2 **contact_request signature verification** (a signed `wt` must NOT break no-`wt` or old-peer requests); **NET-REL-07 byte-identity** of an empty-token `store` frame; all 1:1 send/reaction/delete/retry paths (funnel through the single attach point); the relay gate + emission both **staying OFF at rest**.

## Root Cause (verify → refute confirmed)

**A1 (recipient register) — dormant wiring.** `IssueWakeTokensUseCase.issueForContacts` mints+persists+registers but is constructed nowhere (`issue_wake_tokens_use_case.dart:38-71`). Register transport + native dispatch exist and the checked-in binaries carry the symbols: `callP2PRegisterWakeTokens` (`p2p_bridge_client.dart:391`) → `bridge_wake.go:20-50` → `RelayRegisterWakeTokens` FanOut (`inbox.go:856`) → relay `register_wake_tokens` subjecting the set to the authenticated `remotePeer` (`go-relay-server/inbox.go:1694-1700`); native already wired (iOS `GoBridge.swift:165-166`, Android `GoBridge.kt:140`, xcframework exports `BridgeRegisterWakeTokens`). **⚠ register is UNCONDITIONAL:** `issue_wake_tokens_use_case.dart:60` calls `registerWakeTokens` (a relay FanOut) on every non-empty map (only `:56` empty short-circuits; `:53 if(minted)` guards only the WRITE) — so calling `issueForContacts` **per send** = one full-set relay re-registration per send (see §Scope / the N² hazard).

**A2 (distribution) — the load-bearing unbuilt leg, with a confirmed break hazard.** Carrier = the **v2 (encrypted) contact_request envelope** — the only 1:1 channel that is per-contact-private (X25519 ECDH + AES-256-GCM to the recipient's public key, `bridge.dart:454-462`), authenticated (inner Ed25519 signature — *required*, since anyone can craft a valid ciphertext to a public key), and already re-reaches existing contacts (ML-KEM re-announce backfill). **CONFIRMED BREAK:** the receive-side signature reconstruction is a **closed allowlist** `{mlkem?, ns, pk, rv, ts, un?}` (`handle_incoming_message_use_case.dart:277-284`, `SplayTreeMap`→`jsonEncode`→`callVerifyPayload`, false ⇒ `invalidMessage` `:294-300`). Signing a new `wt` on send WITHOUT adding it to that allowlist ⇒ `dataToVerify != dataToSign` ⇒ **every** `wt`-carrying request dropped; after backfill that is every contact-add + key rotation. Fix locked in TC-A02. **ROLLOUT (see §C3):** the conditional-inclusion *idiom* is precedented (`mlkem`, `un`), but neither demonstrates a receiver-first-with-env-gate rollout — `mlkem` shipped send+receive **atomically** (commit `ff2c094c`, protected null-until-identity-migration), `un` was greenfield both sides. Because `wt`'s wire-presence is a single env flip with no organic staggering, the env gate (§C2) is MORE load-bearing than any precedent required.

**A3 (sender store + attach) — Go-ready, Dart-missing, ASYMMETRIC by design.** No sender-side received-token store exists (`WakeTokenStore` is recipient-only `{contact→token}`, flat `Map<String,String>`, `wake_token_store.dart:6-15`). The single attach funnel is `P2PServiceImpl.storeInInboxDetailed` (`p2p_service_impl.dart:4642`, sole caller of `callP2PInboxStore` at `:4658`; wrapper `storeInInbox:4627-4639`). **The funnel also serves ~13 enumerated non-1:1 callers** (of ~32 total `storeInInbox`/`storeInInboxDetailed` call sites — the load-bearing point is the SINGLE bridge funnel `callP2PInboxStore:4658`, not the exact count): group invite `send_group_invite_use_case.dart:432`, config-resync `on_join_group_config_resync_use_case.dart:262`, decline-ack `send_group_invite_decline_ack_use_case.dart:164`, revoke `revoke_pending_group_invite_use_case.dart:242`, `group_info_wired.dart:766/1184`, introductions `introduction_outbound_delivery.dart:173/352`, posts `post_follow_on_delivery.dart:152/170`+`post_delivery_runner.dart:699`, profile-pic `upload_profile_picture_use_case.dart:195`, receipts `send_delivery_receipt_use_case.dart:132`). A `wt` is looked up by `toPeerId` and attached **only** when that peer has a token in `ReceivedWakeTokenStore` — i.e. only for 1:1 contacts. So the attach is **deliberately asymmetric**, and this drives an OPEN DECISION for the enforcement slice (§Accepted Differences). `callP2PInboxStore` (`p2p_bridge_client.dart:738`, payload `:752-756`) carries no `wakeToken`; the Go bridge `InboxStore` already reads `params.WakeToken` (`bridge.go:1145`) → `InboxStoreDetailedWithWakeToken` (`inbox.go:148`), `omitempty` keeps an empty token byte-identical (NET-REL-07, `inbox.go:42,130,207`).

**A4 (backfill) — reuse ML-KEM re-announce.** `recordMlKemReannouncePending` seeds all active non-blocked contacts (`mlkem_reannounce_marker.dart:47`, key `kMlKemReannouncePendingKey='mlkem_reannounce_pending'` `:12`); `retryIncompleteKeyExchanges` unions the marker and drains a peerId only after send success (`:57-63, 77-107`); triggers fire on online-transition / resume / restore.

**A5 (relay enforcement) — no production flip seam.** `wakeTokenGateEnforced` is a bare `var false` with **zero** production assignment (`go-relay-server/wake_token_store.go:34`; only mutated in `inbox_test.go:933`). Reaching enforcement needs a later relay code edit (env wiring in `server_config.go`) — **out of this plan** (§C4), gated behind sender saturation.

**Refuted / corrected / do-NOT-re-introduce:**
- ✗ "Native register/store dispatch is deferred to a device closure" (`go_bridge_client.dart:156-159` comment) — **STALE**; native is already wired both platforms. No native change.
- ✗ "`issueForContacts` returns the token" — it returns `Future<bool>` (relay ack). The **per-send resolver is read-only**: `resolveWakeToken(peerId) => wakeTokenStore.readTokens()[peerId]`; minting/registering happens once per cycle (§A1 fix).
- ✗ "Reuse the ML-KEM `:342-344` anti-rollback guard for `wt`" — that guard is inside the already-contact branch keyed off contact-table state absent on the new-contact/intro-recovery paths; `wt` needs its **own** ts comparison in the received store (§D1).
- ✗ "Wiring alone gives a behaviour change" — it is an **inert foundation** until the two flips land (fail-open unchanged).
- ✗ "The funnel attach is symmetric / all callers inherit it uniformly" — **wrong** (§A3); only 1:1 contacts carry a token.

## Real Scope
**In scope:**
- Recipient leg constructed at `main.dart:~469` + invoked once-per-cycle at node-start; **read-only** per-send resolver.
- New `ReceivedWakeTokenStore` (+impl, key `fdc09_received_wake_tokens`, schema `{peerId: {"tok","ts"}}`, in-memory cache).
- Signed conditional `wt` on v2 contact_request **send + receive-reconstruction**, emission gated by `--dart-define=MKNOON_EMIT_WAKE_TOKEN` (default OFF).
- Receive-side extract+store **immediately after signature check (`:301`, before `:303`)** with own anti-rollback ts.
- `callP2PInboxStore` + `storeInInboxDetailed` attach.
- Backfill via a **distinct** `wake_token_pending` marker (§D2) + coalesced stream re-issue (§A2 fix-list).
- Reconcile-down prune (archived/blocked/removed contacts lose their minted token).
- Binary-freshness gate (§B4).

**Out of scope (owner):**
- **Relay `wakeTokenGateEnforced` env seam + gate-enforced authorized-vs-suppressed proof (TC-A13b)** → later relay-ops slice; deferred behind saturation (§C4). **Do not flip in 217.**
- **Flipping `MKNOON_EMIT_WAKE_TOKEN` ON** → rollout step after receiver-tolerant builds saturate (§C4).
- **Enforcement asymmetry decision** (group/intro/post store recipients present no token → wake suppressed under enforcement) → relay-ops slice OPEN DECISION (§Accepted Differences).
- **Part B feature-flag guard** → `219-*`.
- **Relay in-memory set durability** (FDC-10) → post-enforcement only.

## Files To Inspect Next
Production: `lib/features/push/application/issue_wake_tokens_use_case.dart`, `.../domain/wake_token_store.dart`, `.../infrastructure/wake_token_store_impl.dart`, **NEW** `.../domain/received_wake_token_store.dart` + `.../infrastructure/received_wake_token_store_impl.dart`, `lib/features/contact_request/application/{send_contact_request_use_case,handle_incoming_message_use_case,contact_request_listener,accept_and_reciprocate_use_case,retry_incomplete_key_exchanges_use_case,mlkem_reannounce_marker}.dart`, `lib/core/services/p2p_service_impl.dart` (`storeInInboxDetailed:4642`, ctor `:385/:406`), `lib/core/bridge/p2p_bridge_client.dart` (`callP2PInboxStore:738`), `lib/features/identity/presentation/startup_router.dart` (`_doStartP2P:645/:684`), `lib/main.dart` (`:465/:469` composition root, **`:946` = `ContactRepositoryImpl` construction / contact-list source**, `:2195-2309` P2PServiceImpl build, `:3217/:3224` re-issue streams).
Direct tests + integration: `test/features/push/**`, `test/features/contact_request/application/**`, `test/core/bridge/p2p_bridge_client_test.dart`, `go-mknoon/node/{inbox_wake_token_test,inbox_presence_test}.go`, `go-relay-server/{inbox_test,wake_token_store_test}.go`, **NEW** `integration_test/wake_token_distribution_proof_test.dart`.
Dependency-only: `go-mknoon/bridge/bridge_wake.go`, `go-relay-server/wake_token_store.go`, `scripts/{run_test_gates,run_host_test_gates,check_reliability_simulation_discovery}.sh`.

## Existing Tests Covering This Area
- `test/features/push/application/issue_wake_tokens_use_case_test.dart` — TC-09-14 mint/register/persist/reload, TC-09-15 old-relay degrade (**exists**; recipient leg; auto-glob). Note: `issue_wake_tokens_use_case.dart:60` has **no** try/catch today ("Never throws" is aspirational) → TC-A08's RED is genuine.
- `test/features/push/infrastructure/wake_token_store_impl_test.dart` — recipient flat-map roundtrip/corrupt-clear (**exists**).
- `go-mknoon/node/inbox_wake_token_test.go` — `AttachesTokenToStoreFrame` (synthetic literal), `OmitsWakeTokenWhenAbsent` (NET-REL-07) (**exists**).
- `go-mknoon/node/inbox_presence_test.go` — `RelayRegisterWakeTokens_SendsRegisterAction` / `_OldRelayErrors` (**exists**).
- `go-relay-server/inbox_test.go` — `TestWakePush_AccessTokenGate_OnlyContactsWake` (**flips the gate in-test at `:933`**, single-process synthetic tokens — proves the MECHANISM, not the shipped default), `_UnregisterClearsWakeTokens` (**exists**).
- `connectivity_restore_inbox_drain_proof_test.dart` — the in-body `--dart-define` host/CI skip-guard pattern to mirror for TC-A13a.
Missing gaps: distribution (`wt` nowhere), receive-side signed-`wt`, received-token store + attach, backfill of `wt`, register-count-per-cycle guard, gate/emission-stay-OFF-at-rest locks, binary freshness, cross-device directionality.
Curated arrays: recipient-leg Dart tests run only via `feature-host-all`/`host-all` globs; `p2p_bridge_client_test.dart` is in `ONE_TO_ONE_HOST_TESTS:46`.

---

## RED Test Catalog  (add BEFORE any production code — INV-RED-FIRST)

1. `test/features/contact_request/application/send_contact_request_use_case_test.dart`::**"v2 send embeds signed wt inside the encrypted envelope (emission-gated); v1 plaintext never carries wt; per-send resolver is read-only"**
   - Tier: unit/application. RED on HEAD: no `resolveWakeToken` seam, no `wt`.
   - GREEN asserts: with a read-only resolver returning a token AND `recipientPublicKey != null`, the `SplayTreeMap` at `:102` includes `'wt'` **before** `dataToSign` (`:110`), inside `encrypted{}` (v2); `recipientPublicKey == null` (v1) ⇒ **no** `wt`; the resolver does **not** call `issueForContacts` (spy asserts zero register calls on the send path).
   - Mutation re-reds: remove the `'wt'` add → red; make the resolver call `issueForContacts` → the "zero register on send" assertion reds.
   - Discriminator: `signedMap.containsKey('wt')` AND `!v1Envelope.contains('wt')`.

2. `test/features/contact_request/application/handle_incoming_message_use_case_test.dart`::**"reconstruction includes wt"**  *(CANONICAL name — use this exact `--plain-name` string in catalog, matrix, and gate; §F2)*
   - Tier: unit/application. RED on HEAD: reconstruction allowlist `:277-284` omits `wt`; a request whose signature covers `wt` ⇒ `callVerifyPayload` false ⇒ `invalidMessage`.
   - GREEN asserts: `wt`-carrying v2 request → `isValid==true`, proceeds past `:301`; **no-`wt`** legacy request → still `isValid==true` (conditional inclusion preserves old shape).
   - Mutation re-reds: revert the added `if (payload['wt'] != null) 'wt': payload['wt'],` in the reconstruction map → the `wt` case reds.
   - **PROD-CRITICAL preservation:** the no-`wt` legacy case staying green guards "don't break contact-add / key rotation."

3. `test/features/contact_request/application/handle_incoming_message_use_case_test.dart`::**"stores wt for new, already-contact, AND silent-intro-recovered peers"**  *(§D3)*
   - Tier: unit/application (inject fake `ReceivedWakeTokenStore`). RED on HEAD: no store threaded; extract placed after the early-returns would drop `wt`.
   - GREEN asserts: extract+store runs **immediately after `:301`, before `attemptSilentIntroRecovery` `:303`**, so `received[peerId]==wt` for (a) a new-contact request, (b) an already-contact key-rotation request `:359/:378`, AND (c) a **silent-intro-recovered** request that returns at `:320`.
   - Mutation re-reds: move the extract to after the intro-recovery block → the intro-recovered case reds.

4. `test/features/contact_request/application/handle_incoming_message_use_case_test.dart`::**"anti-rollback: an older-ts wt does not overwrite a newer stored token"**
   - Tier: unit/application. RED on HEAD: no anti-rollback (no store).
   - GREEN asserts: store holds `{tok, ts=T2}`; inbound `ts=T1<T2` leaves it unchanged; `ts=T3>T2` overwrites. ts source = `payload['ts']` (ISO8601 UTC string), compared via `String.compareTo` (newer strictly greater) — identical to the key-rotation guard `:342-343`.
   - Mutation re-reds: drop the `payloadTs.compareTo(storedTs) > 0` guard (unconditional write) → stale-write case reds; swap ts source to `DateTime.now()` → the fixed-ts replay case reds.

5. `test/features/push/infrastructure/received_wake_token_store_impl_test.dart`::**"schema {peerId:{tok,ts}} roundtrip + corrupt-blob-clears + clear + distinct storage key"**  *(§D1)*
   - Tier: unit/infrastructure (fake `SecureKeyStore`). RED on HEAD: file absent.
   - GREEN asserts: `writeTokenFor(peer, tok, ts)` / `readTokenFor(peer)→{tok,ts}` roundtrip; persisted JSON is `{peerId:{"tok":..,"ts":..}}` (NOT the flat `Map<String,String>` of `WakeTokenStoreImpl`); storage key `fdc09_received_wake_tokens` ≠ recipient `fdc09_wake_tokens`; corrupt blob → reads empty; `clear()` empties.
   - Mutation re-reds: reuse the recipient key → distinct-key assertion reds; persist a flat string map → schema assertion reds.

6. `test/core/bridge/p2p_bridge_client_wake_attach_test.dart`::**"callP2PInboxStore attaches wakeToken when present, omits it (byte-identical) when absent/empty"**
   - Tier: unit (fake `Bridge`, capture JSON). RED on HEAD: no `wakeToken` param.
   - GREEN asserts: `wakeToken:'tok'` ⇒ payload has `'wakeToken':'tok'`; `null`/`''` ⇒ **no** `wakeToken` key (NET-REL-07).
   - Mutation re-reds: always inject `wakeToken` → omit case reds.

7. `test/core/services/p2p_service_impl_wake_attach_test.dart`::**"storeInInboxDetailed threads the received token by toPeerId; empty when absent; served from in-memory cache (no per-message SecureKeyStore read)"**
   - Tier: unit (concrete `P2PServiceImpl` ctor-injected fake received store + counting fake secure store). RED on HEAD: no lookup, no ctor param.
   - GREEN asserts: send to B with `received[B]=tok` ⇒ `callP2PInboxStore` gets `wakeToken:tok`; no-token peer ⇒ empty; a second send does **not** increment the SecureKeyStore read counter (cache loaded once, invalidated on write).
   - Mutation re-reds: remove cache (read per call) → read-counter assertion reds; remove lookup → attach assertion reds.

8. `test/features/push/application/issue_wake_tokens_use_case_wiring_test.dart`::**"register callback is total (bridge throw ⇒ false, never throws) and reconcile-down prunes archived/blocked tokens"**  *(§F4)*
   - Tier: unit/application. RED on HEAD: no live wiring; a throwing register callback propagates.
   - GREEN asserts: the callback wrapper `(tokens) async { try { return (await callP2PRegisterWakeTokens(...))['ok']==true; } catch(_) { return false; } }` — a throwing bridge ⇒ `issueForContacts` returns false, persists minted tokens, emits `WAKE_TOKEN_REGISTER_UNSUPPORTED`, does not throw; passing an active list excluding a previously-minted (now-archived) contact ⇒ that token is removed from the persisted map AND the re-registered set (reconcile DOWN).
   - Mutation re-reds: unwrap the try/catch in the **callback wrapper** (not the use-case — its `:60` is unchanged) → throw-path reds; remove the prune → stale-token assertion reds.

9. `test/features/identity/presentation/startup_router_wake_token_wiring_test.dart`::**"_doStartP2P invokes issueForContacts ONCE with all active contact peerIds after StartNodeResult.success"**  *(§A1 cycle-start)*
   - Tier: widget/integration (`WidgetTester`, fake use-case + fake contact repo). RED on HEAD: never invoked.
   - GREEN asserts: on success, `issueForContacts` called **exactly once** with `getActiveContacts().map(peerId)` (the whole-cycle mint+register); not called on failure.
   - Mutation re-reds: remove the invocation → red; call per-contact → the "exactly once / full list" assertion reds.

10. `test/features/contact_request/application/retry_incomplete_key_exchanges_use_case_test.dart`::**"wake_token_pending (distinct key) contacts drained only after send success; partial failure keeps remainder"**  *(§D2)*
    - Tier: unit/application. RED on HEAD: no `wake_token_pending` in the eligibility union.
    - GREEN asserts: marker key `kWakeTokenPendingKey='wake_token_pending'` ≠ `kMlKemReannouncePendingKey`; seeding [A,B,C] and failing B ⇒ A,C drained, B retained; each drained peer's `sendContactRequest` was invoked (carrying the read-only resolver); the wake drain is its **own block**, not merged with the mlkem drain.
    - Mutation re-reds: reuse the mlkem key → distinct-key assertion reds; drain before send success → partial-failure assertion reds.

11. `go-mknoon/node/inbox_wake_token_test.go`::**`TestInboxStore_WakeTokenRoundTripsByteEqual`** (NEW) + reuse `TestInboxStoreDetailedWithWakeToken_AttachesTokenToStoreFrame`
    - Tier: Go node unit (`GOTOOLCHAIN=go1.25.0`). New RED on HEAD: no assertion that a registered-set member and the presented `store` token compare byte-equal.
    - GREEN asserts: register set `{tok}`, present `tok` on store frame, assert raw `wakeToken` bytes == the registered member exactly.
    - Mutation re-reds: base64-re-encode the presented token → byte-equal assertion reds.

12. `go-mknoon/node/inbox_wake_token_test.go`::**`TestInboxStoreDetailed_OmitsWakeTokenWhenAbsent`** (EXISTS — preservation sentinel, NET-REL-07)
    - Tier: Go node unit. Mutation: n/a (preservation). Locks empty-token byte-identity.

13a. `integration_test/wake_token_distribution_proof_test.dart`::**"cross-device mint→register→distribute→store→attach with STORAGE-DIRECTIONALITY"** — **PROD-CRITICAL closure (relay-gate-INDEPENDENT, runnable now on the fail-open relay; requires a sim-local emission define)**  *(§B1/§B2)*
    - Tier: reliability-sim / device-proof (two real nodes, real bridge, real native register dispatch, deployed/local **fail-open** relay). RED on HEAD: nothing distributes/attaches a token.
    - **EMISSION ENABLEMENT (required — distribution is emission-gated):** the A13a proof build passes a **sim-local** `--dart-define=MKNOON_EMIT_WAKE_TOKEN=true` so A actually emits `wt` on the v2 envelope. This is the **sender-emission** flip only — NOT the relay `wakeTokenGateEnforced` gate (which stays OFF; A13a runs on the fail-open relay). Release/production builds MUST NOT pass this define (§C2 / Scope Guard carve-out); the override is local to the proof invocation. Without it the real resolver returns `null` (A17) and B stores nothing ⇒ the directionality assertion is unsatisfiable and the closure cannot go green.
    - GREEN asserts (all observable, greppable): A mints T_A-for-B → **real** `inboxRegisterWakeTokens` dispatch fires → A distributes over the v2 envelope → B persists `ReceivedWakeTokenStore[A]` whose value **equals the token A registered** (load-bearing = **storage directionality**) → B's `inbox:store` frame to A carries that `wakeToken`.
    - Observable: B's persisted `ReceivedWakeTokenStore[A]` + the captured `inbox:store` frame's `wakeToken`.
    - Mutation re-reds: store B's OWN token instead of A's (invert directionality) → the `received[A]==A-registered` assertion reds. *(This runs today and exercises the first-time native register path + the v2 crypto envelope — a genuine discriminator that does NOT need the gate flipped.)*

13b. *(DEFERRED to the relay-ops enforcement slice — NOT in 217)* gate-ENFORCED authorized-vs-suppressed: with `wakeTokenGateEnforced=true` (via the future env-seam), a member token authorizes the wake and a wrong token is suppressed-but-still-stored. Observable = a relay-side signal (a wake-dispatch counter / GoLog `wake authorized|suppressed` / delivered-vs-silent). Not runnable in 217 (Scope Guard forbids the flip; sims hit the fail-open relay where authorized==suppressed).

14. `go-relay-server/inbox_test.go`::**`TestWakePush_AccessTokenGate_OnlyContactsWake`** (EXISTS — **mechanism-preservation only**)  *(§C1 downgrade)*
    - Tier: Go relay unit. Flips the gate in-test (`:933`) to prove the ON-behaviour (authorized wakes / unauthorized suppressed-but-stored). **Does NOT prove the shipped default stays OFF** — that is TC-A16. Mutation: n/a (preservation).

15. `test/features/contact_request/application/retry_incomplete_key_exchanges_use_case_test.dart`::**"stream-triggered re-issue registers at most once per cycle (coalesced)"**  *(§A2 — NEW)*
    - Tier: unit/application. RED on HEAD: nothing coalesces stream-triggered `issueForContacts`; each `contactKeyUpdatedStream`/`autoAddedStream` event would re-register the full set.
    - GREEN asserts: firing N stream events within one short window ⇒ `registerWakeTokens` invoked **exactly once** (debounce/dirty-flag). 
    - Mutation re-reds: register per event → the invocation-count assertion reds.

16. `go-relay-server/wake_token_store_test.go`::**`TestWakeTokenGate_DefaultDisabledAtRest`** (NEW)  *(§C1a — locks the shipped default OFF)*
    - Tier: Go relay unit. **NOT RED-first — a green default-lock** (like A12/A18): on HEAD no `TestWakeTokenGate` exists so `-run` matches 0 tests, and `wake_token_store.go:34` is already `false`, so the test passes the instant it is added. It is **mutation-verified, not RED-verified**.
    - GREEN asserts: on a fresh process (no in-test mutation), `wakeTokenGateEnforced == false`.
    - Mutation re-reds: set `wakeTokenGateEnforced = true` at `:34` → red. *(This is the ONLY thing that reds it — do not list it in the RED phase.)*

17. `test/features/push/application/emission_gate_default_off_test.dart`::**"the REAL resolver returns null / emits no wt when MKNOON_EMIT_WAKE_TOKEN is unset"**  *(§C1b — locks emission OFF with the real wiring, not a fake)*
    - Tier: unit/application. RED on HEAD: no emission gate exists.
    - **PIN — production-owned factory (avoids a fake lock):** the gate is a SINGLE production factory `bool shouldEmitWakeToken() => const bool.fromEnvironment('MKNOON_EMIT_WAKE_TOKEN', defaultValue:false);` called by BOTH the `main.dart:~469` wiring AND this test — the test **imports** the production factory; it must NOT reconstruct a test-local `bool.fromEnvironment(...)` copy (a local copy passes regardless of production's default = a fake lock).
    - GREEN asserts: with the define unset ⇒ `shouldEmitWakeToken()==false` ⇒ the real `resolveWakeToken` wiring returns `null` ⇒ `sendContactRequest` emits no `wt`.
    - Mutation re-reds: change the **production** factory's `defaultValue` to `true` → the "no wt emitted" assertion reds. *(If the production mutation is applied and the test still passes, A17 is a FAKE LOCK — it is asserting a test-local copy, not the production seam.)*

18. `scripts/check_wake_token_binary_freshness.sh` → asserted by **`test/core/bridge/wake_token_binary_freshness_test.dart`** (or a CI step)  *(§B4 — the one silent-failure path)*
    - Tier: host/CI (shells `nm`/`strings` over the checked-in binaries). RED on HEAD if a binary is stale: assert `ios/.../GoMknoon.xcframework` (+ macos mirror) and Android `libgojni.so` contain `InboxStoreDetailedWithWakeToken` **and** `RegisterWakeTokens`.
    - Why: `params.WakeToken` at `bridge.go:1145` changes **no exported header symbol**, so a stale gomobile rebuild would silently drop the sender-attached token with zero failing functional test. Binaries are fresh today (verified) — this converts the prose caveat into a real gate.
    - Mutation re-reds: point the check at a pre-FDC-09 binary → symbols absent → red.

## Test Coverage Matrix  (zero empty cells in tier / mutation / gate / registration)

| Spec case | Behavior props | Tier | Test file::name | RED reason on HEAD | Mutation revert | Acceptance gate cmd | Harness registration |
|---|---|---|---|---|---|---|---|
| A01 send-signs-wt (gated, read-only resolver) | serialization + gating | unit | send_contact_request_use_case_test.dart::"v2 embeds signed wt; v1 never; resolver read-only" | no resolver/no wt | remove wt add / resolver mints | `flutter test test/features/contact_request/application/send_contact_request_use_case_test.dart` | AUTO (feature glob) + `ONE_TO_ONE_TESTS` |
| A02 receive-verifies-wt (anti-break) | signature reconstruction | unit | handle_incoming_message_use_case_test.dart::"reconstruction includes wt" | allowlist :277-284 omits wt | revert wt in reconstruction | `flutter test .../handle_incoming_message_use_case_test.dart --plain-name 'reconstruction includes wt'` | AUTO (feature glob) + `ONE_TO_ONE_TESTS` |
| A03 receive-stores-wt (new/already/intro-recovered) | placement + persistence | unit | handle_incoming_message_use_case_test.dart::"stores wt for new, already-contact, AND silent-intro-recovered peers" | no store; early-return drops wt | move extract after :303 | `flutter test test/features/contact_request/application/handle_incoming_message_use_case_test.dart` (**whole file — NO `--plain-name`**; A02's plain-name gate matches 0 of A03) | AUTO (feature glob) |
| A04 anti-rollback ts | ts comparator | unit | handle_incoming_message_use_case_test.dart::"anti-rollback: an older-ts wt does not overwrite a newer stored token" | no anti-rollback | drop compareTo guard / DateTime.now ts | `flutter test test/features/contact_request/application/handle_incoming_message_use_case_test.dart` (**whole file — NO `--plain-name`**) | AUTO (feature glob) |
| A05 received-store schema | infra + SecureKeyStore | unit | received_wake_token_store_impl_test.dart::"schema {tok,ts} roundtrip/corrupt/clear/distinct-key" | file absent | reuse recipient key / flat map | `flutter test test/features/push/infrastructure/received_wake_token_store_impl_test.dart` | AUTO (feature glob) |
| A06 bridge attach/omit | serialization + NET-REL-07 | unit | p2p_bridge_client_wake_attach_test.dart::"attaches present, omits absent" | no wakeToken param | always inject wakeToken | `flutter test test/core/bridge/p2p_bridge_client_wake_attach_test.dart` | AUTO (core glob) + `ONE_TO_ONE_HOST_TESTS` |
| A07 funnel attach + cache | service wiring + hot-path | unit | p2p_service_impl_wake_attach_test.dart::"threads token, cached" | no lookup/ctor param | remove cache / remove lookup | `flutter test test/core/services/p2p_service_impl_wake_attach_test.dart` | AUTO (core glob) |
| A08 recipient-leg total + reconcile-down | robustness + revocation | unit | issue_wake_tokens_use_case_wiring_test.dart::"total callback + prune archived" | no wiring; throw propagates | unwrap callback try/catch; drop prune | `flutter test test/features/push/application/issue_wake_tokens_use_case_wiring_test.dart` | AUTO (feature glob) |
| A09 startup invocation once | lifecycle wiring | widget/integration | startup_router_wake_token_wiring_test.dart::"_doStartP2P calls issueForContacts once" | never invoked | remove/ per-contact | `flutter test test/features/identity/presentation/startup_router_wake_token_wiring_test.dart` | AUTO (feature glob) |
| A10 backfill drain (distinct key) | marker + drain-on-success | unit | retry_incomplete_key_exchanges_use_case_test.dart::"wake_token_pending drained on success" | no marker in union | reuse mlkem key / drain-before-success | `flutter test test/features/contact_request/application/retry_incomplete_key_exchanges_use_case_test.dart` | AUTO (feature glob) + `ONE_TO_ONE_TESTS` |
| A11 store-frame byte-equality | Go serialization | Go node unit | inbox_wake_token_test.go::TestInboxStore_WakeTokenRoundTripsByteEqual | no round-trip assert | base64-re-encode token | `(cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test ./node -run 'WakeToken' -count=1)` | Go synthetic-path (PINNED, 5 sites): `GO_NODE_WAKETOKEN` const + `_RUN` const + is_*() + print/run branches + host-all line |
| A12 NET-REL-07 byte-identity (preserve) | Go serialization (existing) | Go node unit | inbox_wake_token_test.go::TestInboxStoreDetailed_OmitsWakeTokenWhenAbsent | — (green sentinel) | n/a — preservation | (same Go cmd as A11) | same synthetic-path entry |
| A13a e2e distribute+attach+directionality (PROD-CRITICAL) | real bridge + native register + v2 crypto | reliability-sim / device-proof | wake_token_distribution_proof_test.dart::"mint→register→distribute→store→attach, storage directionality" | no distribute/attach | invert stored directionality | `./scripts/check_reliability_simulation_discovery.sh` then `/sims 1to1 --only N` (proof build passes **sim-local `--dart-define=MKNOON_EMIT_WAKE_TOKEN=true`** — emission override, never a release config) | `record "1to1" ... "test"` case arm in check_reliability_simulation_discovery.sh; name `*_proof_test.dart` ⇒ run_test_gates `:758` auto-classify; **in-body `--dart-define` skip-guard** (mirror connectivity_restore_inbox_drain_proof_test.dart); **do NOT add to `ONE_TO_ONE_TESTS`** (a real-node proof would hang the host 1to1 batch) |
| A13b gate-enforced authorized-vs-suppressed | relay enforcement | (DEFERRED) | relay-ops slice — env-seam | out of 217 scope | — | (owned by relay-ops slice) | DEFERRED — not registered in 217 |
| A14 relay gate MECHANISM (preserve) | relay auth (existing) | Go relay unit | inbox_test.go::TestWakePush_AccessTokenGate_OnlyContactsWake | — (green sentinel; flips gate in-test) | n/a — preservation | `(cd go-relay-server && GOTOOLCHAIN=go1.25.0 go test . -run 'TestWakePush_' -count=1)` | MANUAL (relay module un-gated) — documented manual command |
| A15 stream re-issue coalesced | debounce/dirty-flag | unit | retry_incomplete_key_exchanges_use_case_test.dart::"stream re-issue registers once per cycle" | no coalescing | register per event | `flutter test test/features/contact_request/application/retry_incomplete_key_exchanges_use_case_test.dart` | AUTO (feature glob) + `ONE_TO_ONE_TESTS` |
| A16 relay gate default-OFF at rest | ship-order lock | Go relay unit | wake_token_store_test.go::TestWakeTokenGate_DefaultDisabledAtRest | **green default-lock, NOT RED** (-run matches 0 tests on HEAD, :34 already false) | set var=true at :34 | `(cd go-relay-server && GOTOOLCHAIN=go1.25.0 go test . -run 'TestWakeTokenGate' -count=1)` (runs in Direct-GREEN) | MANUAL (relay module) — documented manual command |
| A17 emission gate default-OFF (real wiring) | ship-order lock | unit | emission_gate_default_off_test.dart::"real resolver null when flag unset" | no emission gate | default flag ON | `flutter test test/features/push/application/emission_gate_default_off_test.dart` | AUTO (feature glob) |
| A18 binary freshness | build integrity | host/CI | wake_token_binary_freshness_test.dart::"binaries carry InboxStoreDetailedWithWakeToken+RegisterWakeTokens" | (green if fresh; red if stale binary) | point at pre-FDC-09 binary | `bash scripts/check_wake_token_binary_freshness.sh` (+ CI step) | MANUAL/CI host command (documented); optionally a `test/core/**` wrapper (AUTO core glob) |

> **Matrix naming note (F2):** the `::"…"` strings in this matrix are descriptive **labels**. The ONLY acceptance gate that uses `--plain-name` is **A02** (`'reconstruction includes wt'`, byte-identical in catalog/matrix/gate). Every other row runs its **whole test file** (no `--plain-name`), so abbreviated matrix labels vs the longer catalog names (A01/A05/A07) cannot cause a 0-test green-pass. A03/A04 were switched to the explicit whole-file cmd for exactly this reason.

## Blind-Spot Sweep
- **Lifecycle / derived-state durability:** the in-memory received-token cache (A07) reconstructs on a fresh service instance (load-once, invalidate-on-write) — asserted in A07. The recipient set is not durable on the relay, so A09 re-mints+re-registers once per node-start (re-register after bounce/restart).
- **Sibling-surface consistency — DELIBERATE ASYMMETRY (corrected, §A3):** the `wt` attach at the funnel `storeInInboxDetailed` fires **only** for peers present in `ReceivedWakeTokenStore` (1:1 contacts). The funnel's ~13 enumerated non-1:1 callers (group invite/config-resync/decline/revoke, introductions, posts, profile-pic, receipts) attach **nothing**. This is correct pre-enforcement (all fail-open) but means **post-enforcement a store to a non-1:1-contact recipient → wake suppressed** (message still stored) — an OPEN DECISION owned by the relay-ops slice (§Accepted Differences). No hidden asymmetry; the attach is intentionally 1:1-only.
- **Destructive-action side-effects:** contact archive/block/delete removes the minted token (reconcile-down, A08) and the received token (`clear`/prune) — asserted as *what is removed* + set re-registered. No contact-removed stream, so `issueForContacts` reconciles the persisted map DOWN to the active list each run (A08).
- **Invariant re-verification under new transitions:** identity-restore / re-pair re-fires the re-announce drain (re-mint + re-distribute); A04 anti-rollback prevents a replayed OLD token clobbering a newer one; A02 guarantees the new signed field never breaks the pre-transition invariant "no-`wt` request still verifies."

## Invariants (locked by tests)
- **INV-1 (no-break):** signed `wt` never invalidates a no-`wt` or old-peer contact_request → **A02**.
- **INV-2 (ship-order / stays-OFF-at-rest):** the relay gate AND sender emission both ship OFF and are proven OFF with the **real** wiring → **A16** (relay default false at rest, no in-test flip) + **A17** (real resolver null when the dart-define is unset, asserted against the **production-owned `shouldEmitWakeToken()` factory** — not a test-local copy). *(A14 proves only the ON-behaviour mechanism — it is NOT the defaults-off lock.)* **Residual (owned by the emission-flip slice, NOT the dark landing):** A17 locks the compile-time *default*; it cannot prove a given release binary was not compiled with `=true`. The §C2 "release configs MUST omit `MKNOON_EMIT_WAKE_TOKEN`" CI check is required **before the emission flip** — see §C2 / Dependency Impact.
- **INV-3 (byte-identity):** empty `wakeToken` ⇒ store frame byte-identical (NET-REL-07) → **A06/A12**.
- **INV-4 (directionality):** the token A registers == the token B stores as `received[A]` and presents to wake A → **A13a** (sim; unit tests cannot catch inversion).
- **INV-5 (register-once-per-cycle):** mint/register happens once per cycle, never per-send/per-event → **A09** (startup once) + **A15** (stream coalesced) + **A01** (send resolver is read-only).
- **INV-6 (private+authenticated distribution):** `wt` rides only the v2 encrypted, Ed25519-signed envelope; never v1 → **A01**.
- **INV-7 (build integrity):** shipped binaries carry the wake-token symbols → **A18**.
- INV-RED-FIRST + INV-MUTATION-VERIFIED apply to every row.

## Step-By-Step Implementation Plan
1. **Add RED tests per slice as you reach it** (Catalog 1–18 — you need NOT author all 18 up front; add each slice's REDs immediately before its production edit and confirm each fails for the documented reason). A12/A14 are green preservation; **A16 is a green default-lock (never RED — see Known-Failure)**; A18 green-if-fresh. **Each slice below carries a GATE that must be green before the next slice starts — do not batch all edits then verify once** (this restores the per-slice checkpoint / early-payoff property; the dark ship keeps every slice inert).
2. **A3 seam (Go-ready):** new `ReceivedWakeTokenStore` (+impl, key `fdc09_received_wake_tokens`, schema `{peerId:{tok,ts}}`, in-memory cache, §D1); add `String? wakeToken` to `callP2PInboxStore` (`if (wakeToken?.isNotEmpty ?? false) 'wakeToken': wakeToken`); inject the store into `P2PServiceImpl` ctor (nullable, mirror `_pushTokenStore` — **NOT** the `P2PService` interface; ~31 fakes) and look it up in `storeInInboxDetailed:4642`.
3. **A2 receive-first (safe half):** add `if (payload['wt'] != null) 'wt': payload['wt'],` to the reconstruction map `:277-284`; extract+store `wt` **immediately after `:301`, before `attemptSilentIntroRecovery:303`** with own anti-rollback ts (`payload['ts']`, `String.compareTo`); thread `ReceivedWakeTokenStore` through `ContactRequestListener` (`main.dart:2345`). Ships tolerant, **no** emission yet. **→ GATE-1 (early value-proof + riskiest slice in isolation):** A02 (no-`wt` legacy stays green — the anti-break payoff), A03, A04, A05 all green before starting the recipient leg. This is the first observable payoff (receiver-tolerance) and the only signature-touching slice — review it alone.
4. **A1 recipient leg (once-per-cycle):** construct `WakeTokenStoreImpl` + `IssueWakeTokensUseCase` at `main.dart:~469`; **total callback wrapper** (try/catch → false, §F4); invoke `issueForContacts(getActiveContacts().peerIds)` **once** in `startup_router._doStartP2P` success block; **coalesce** `contactKeyUpdatedStream`/`autoAddedStream` re-issue (debounce/dirty-flag, §A2); add reconcile-down prune. **Register triggers = startup (A09) + coalesced streams (A15) ONLY — the backfill drain (Step 5) is a *distribution* path (drives `sendContactRequest`, read-only resolver) and must NOT call `issueForContacts`/`registerWakeTokens`** (keeps INV-5 register-once-per-cycle intact across all three triggers). **→ GATE-2:** A08 (total callback + reconcile-down), A09 (issueForContacts once), A15 (stream coalesced) green before the send/backfill slice.
5. **A2 send + A4 backfill (ships DARK):** add a **read-only** `resolveWakeToken(peerId) => wakeTokenStore.readTokens()[peerId]` to `sendContactRequest`, wired to a real reader **only** when the production-owned `shouldEmitWakeToken()` factory (`=> const bool.fromEnvironment('MKNOON_EMIT_WAKE_TOKEN', defaultValue:false)` — the SAME seam A17 asserts against) returns true (§C2); wire callers (accept_and_reciprocate, retry). Add the **distinct** `wake_token_pending` marker (`kWakeTokenPendingKey`, §D2) + its **own** drain block union'd into `retryIncompleteKeyExchanges` (this drain **distributes only** — read-only resolver, no register); **do NOT** call `issueForContacts` per send (§A1). *(QR initial adds carry no `wt` and rely on backfill — §F5.)* **→ GATE-3:** A01 (send read-only + gated), A10 (backfill distinct-key, drain-on-success), A17 (emission-off default via the production factory) green before the sim leg.
6. **A18 binary-freshness:** add `scripts/check_wake_token_binary_freshness.sh` + wire into CI + the host acceptance batch.
7. **A13a sim:** author `wake_token_distribution_proof_test.dart` with an in-body `--dart-define` skip-guard; the sim/proof build passes a **sim-local `--dart-define=MKNOON_EMIT_WAKE_TOKEN=true`** (distribution is emission-gated — see Scope Guard carve-out; without it B stores nothing and the directionality assertion is unsatisfiable); register the discovery case arm (NOT `ONE_TO_ONE_TESTS`).
8. Rerun **direct → preservation → named gates**. **Stop-if:** any `contact_request` suite reds (A02 break) → the reconstruction/allowlist is wrong, replan; do not hack the signature.

## Risks And Edge Cases
- **Signed-field rollout skew** (new sender → old receiver breaks verification) → receiver-tolerance ships first + emission gated OFF (INV-1/INV-2); pinned by A02+A17. *(Capability-gating — "only emit `wt` to peers already in `ReceivedWakeTokenStore`" — was CONSIDERED and REJECTED: it deadlocks on bootstrap (A won't emit until B does, and vice-versa). The `--dart-define` + measured saturation trigger (§C4) is the workable control.)*
- **N² relay register on backfill** — eliminated: register once per cycle (A09/A15), per-send resolver read-only (A01).
- **Hot-path SecureKeyStore read** on every `store` → in-memory cache (A07).
- **Stale token after archive/block** → reconcile-down prune (A08).
- **Directionality inversion** silently breaks auth while unit-green → only A13a catches it.
- **Stale gomobile binary** silently drops the attached token (no exported-symbol change) → A18 binary-freshness gate.
- **testpeer / relay set non-durability** → out of scope (owned elsewhere).

## Device/Relay Proof Profile
Requires **sim + device** for closure. Host tiers prove every seam except the cross-device distribute→store→attach loop and the binary-build dependency.
- Closure scenario: `/sims 1to1 --only N` (**TC-A13a**, relay-gate-INDEPENDENT — runnable now on the fail-open relay; the invert-directionality mutation re-reds without any gate flip). The proof build passes a **sim-local** `--dart-define=MKNOON_EMIT_WAKE_TOKEN=true` so A actually emits `wt` (distribution is emission-gated; without it the real resolver returns null per A17 and B stores nothing). Do NOT flip the relay `wakeTokenGateEnforced` gate, and do NOT default `MKNOON_EMIT_WAKE_TOKEN` ON in any fleet/release build (the emission define is a **sim-only override**, never a release config).
- Binary dependency: A18 asserts the checked-in xcframework/`.so` carry the wake-token symbols.
- **Deferred → relay-ops enforcement slice (§C4):** wire `wakeTokenGateEnforced` to an env flag in `go-relay-server/server_config.go`; add TC-A13b (gate-enforced authorized-vs-suppressed, observable = a named relay wake-dispatch counter / GoLog). **FLIP TRIGGER (measurable, owner = relay-ops):** the emission flip and then the gate flip are permitted only when a named relay counter shows ≥95% of **1:1-contact** `inbox:store` sends carry a non-empty `wakeToken` over a defined window — "fleet saturated." **Denominator = 1:1-contact stores only** (`store_wake_token_present_total / store_1to1_total`), NOT all stores: per §A3 the ~13 non-1:1 funnel callers (group/intro/post/receipt) deliberately attach no `wt`, so an all-stores denominator can never reach 95% and the trigger would never fire. Without this ratio, "safe to flip" is undecidable.
- Relay defaults if needed: `/dns/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g` (see `/sims`).

## Acceptance Gates  (literal — copy/paste)
```bash
# --- record baseline BEFORE edits (§F3) ---
git status --short > /tmp/217_dirty_snapshot.txt
./scripts/run_test_gates.sh 1to1 2>&1 | tail -3    # record the current NNNN/NNNN 1to1 baseline for the post-add delta

# --- RED (before production edits) — must FAIL for the documented reason ---
flutter test test/features/contact_request/application/handle_incoming_message_use_case_test.dart --plain-name 'reconstruction includes wt'
flutter test test/features/push/infrastructure/received_wake_token_store_impl_test.dart
# NOTE: A16 (TestWakeTokenGate_DefaultDisabledAtRest) is NOT a RED test. On HEAD `-run 'TestWakeTokenGate'`
# matches 0 tests (exits PASS, not RED) and wake_token_store.go:34 is already `false`, so it is green from
# the moment it is added. It is a mutation-verified green default-lock (only :34→true reds it) and runs in
# the Direct-GREEN block below alongside TestWakePush_.

# --- Direct GREEN (after fix) ---
flutter test test/features/contact_request/application/send_contact_request_use_case_test.dart \
             test/features/contact_request/application/handle_incoming_message_use_case_test.dart \
             test/features/contact_request/application/retry_incomplete_key_exchanges_use_case_test.dart \
             test/features/push/infrastructure/received_wake_token_store_impl_test.dart \
             test/features/push/application/issue_wake_tokens_use_case_wiring_test.dart \
             test/features/push/application/emission_gate_default_off_test.dart \
             test/features/identity/presentation/startup_router_wake_token_wiring_test.dart \
             test/core/bridge/p2p_bridge_client_wake_attach_test.dart \
             test/core/services/p2p_service_impl_wake_attach_test.dart
(cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test ./node -run 'WakeToken' -count=1)                     # expect: ok
(cd go-relay-server && GOTOOLCHAIN=go1.25.0 go test . -run 'TestWakePush_|TestWakeTokenGate' -count=1) # expect: ok
bash scripts/check_wake_token_binary_freshness.sh                                                    # expect: symbols present

# --- Preservation sentinels (must stay green) ---
flutter test test/features/contact_request/                        # contact-add + key rotation unbroken
./scripts/run_host_test_gates.sh feature-host-all                  # expect: all pass (new wake/CR tests auto-globbed)
./scripts/run_host_test_gates.sh core-host-all                     # expect: all pass (bridge/service attach)
(cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test ./node -run 'InboxStoreDetailed_OmitsWakeTokenWhenAbsent' -count=1)  # NET-REL-07

# --- Named curated gate ---
./scripts/run_test_gates.sh 1to1                                   # expect: baseline + new (compare to /tmp snapshot)

# --- Simulator/device closure (TC-A13a) ---
./scripts/check_reliability_simulation_discovery.sh                # new proof MUST list under 1to1, 0 unclassified
# /sims 1to1 --list  → note --only N  → /sims 1to1 --only N   (resume: --start-at N)

# --- Hygiene ---
flutter analyze            # 0 new issues
git diff --check
```

## Known-Failure Interpretation
- **Expected RED:** A01/A02/A03/A04/A05/A06/A07/A08/A09/A10/A11/A15/A17 before their fixes.
- **Green sentinels (not fixes):** A12/A14 (preservation), A16 (default-off lock — green **from the moment it is added**: on HEAD no `TestWakeTokenGate` exists so `-run` matches 0 tests and `wake_token_store.go:34` is already `false`; **mutation-verified ONLY by `:34→true`, never RED-first**), A18 (green while binaries fresh).
- **Pre-existing dirty tree:** snapshot in `/tmp/217_dirty_snapshot.txt`; `Test-Flight-Improv/**`, `graphify-arch/**`, `first_time_experience_wired.dart`, `startup_router.dart` were modified before this plan — do not revert.
- **Environment blocker (NOT product):** missing 2 sims for A13a ⇒ host tiers still close everything except the cross-device leg.
- **Scope drift (BLOCKING):** any failure implying the relay gate was flipped, `MKNOON_EMIT_WAKE_TOKEN` defaulted ON, Part B edited here (owned by 219), or a native/Go/relay edit beyond the wake-token seam.

## Done Criteria
- [ ] RED added first, failed for the documented reason (incl. the A02 signature-break). **A16 is NOT a RED item — it is a green default-lock (mutation-verified only; see Known-Failure).**
- [ ] Mutation-verified (each fix has a named re-red revert per the matrix).
- [ ] Direct GREEN + preservation sentinels (contact_request suite, NET-REL-07, Go relay mechanism) + `1to1` gate pass (delta vs baseline recorded).
- [ ] No migration (SecureKeyStore, not SQLCipher) — N/A justified.
- [ ] **INV-2 locked by the REAL wiring:** A16 (relay default false at rest) + A17 (real resolver null) both green; A14 explicitly labelled mechanism-only.
- [ ] **TC-A13a** cross-device distribute→store→attach + directionality proven on sim/device (PROD-CRITICAL) — not a host fake; proof build sets the **sim-local emission define** so distribution actually fires (relay gate stays OFF).
- [ ] **A18** binary-freshness gate green (symbols present).
- [ ] Every new test's harness-registration done & verified (feature/core glob; Go PINNED synthetic-path; sim in `/sims` dry-run with `--only N`; relay + freshness = documented manual/CI).
- [ ] `flutter analyze` 0 new; `git diff --check` clean; no Scope Guard violations.

## Scope Guard (hard "Do not")
- **Do not** flip `go-relay-server/wake_token_store.go:34 wakeTokenGateEnforced` (owner: relay-ops slice; INV-2).
- **Do not** default `MKNOON_EMIT_WAKE_TOKEN` ON in fleet/release builds, and **do not** ship a release variant that defines it (§C2 — a mis-built release ships `wt` fleet-wide to un-saturated pre-217 receivers → drops their contact_request). **Carve-out (does NOT violate this rule):** the **A13a proof build alone** passes `--dart-define=MKNOON_EMIT_WAKE_TOKEN=true` **sim-locally** to exercise distribution — sender-emission flip only, relay gate stays OFF, never present in a release config. Fleet/release default-OFF and the sim-local override are distinct: A17 locks the *default*; the proof invocation supplies the *override*.
- **Do not** call `issueForContacts` inside `sendContactRequest` / per-send (N² register — the per-send resolver is READ-ONLY).
- **Do not** add `wt` to the v1 (plaintext) contact_request path (INV-6 leak).
- **Do not** add wake-token state to the `P2PService` interface (breaks ~31 fakes — ctor param only).
- **Do not** reuse `kMlKemReannouncePendingKey` for the wake marker (clobbers the ML-KEM drain).
- **Do not** edit native Swift/Kotlin (already wired) or Part B / feature-flag code (owned by 219).

## Accepted Differences / Intentionally Out Of Scope
- **OPEN DECISION for the relay-ops enforcement slice (§A3 asymmetry):** under enforcement, `inbox:store` to a **non-1:1-contact** recipient (group-only member, introduction target — not-yet-contact by definition, post recipient) presents no `wt` → the wake is suppressed (message still stored). The enforcement slice MUST decide: (a) exempt non-contact store message-types at the relay gate, or (b) seed group-co-member tokens. Landing 217 dark makes this decision explicit BEFORE any flip — mischaracterizing it would turn the flip into a silent group/intro/post-push regression.
- Relay enforcement env seam + TC-A13b (gate-enforced authorized-vs-suppressed) — relay-ops slice.
- `MKNOON_EMIT_WAKE_TOKEN` flip + fleet-saturation trigger measurement — relay-ops (§C4).
- QR-scan initial adds carry no `wt` (rely on backfill) (§F5).
- Relay in-memory set durability (FDC-10); testpeer partial-map (owned by 219 follow-up).

## Dependency Impact
- The later **relay-ops enforcement slice** depends on this: it must not flip `wakeTokenGateEnforced` until the saturation trigger (§C4) is met, and must resolve the §A3 asymmetry decision. Contract: sender saturation is measured by a named relay counter over **1:1-contact stores only** (`store_wake_token_present_total / store_1to1_total`), out-of-band.
- The **emission-flip slice** (turning `MKNOON_EMIT_WAKE_TOKEN` ON fleet-wide) depends on a concrete **CI/build-config check that release configs OMIT the define** (§C2). A17 locks only the compile-time default — this CI gate is what actually prevents a mis-built release shipping `wt` to un-saturated receivers. Required before the emission flip; NOT a blocker for the dark landing.
- **CV-19** ship-order is satisfied by A2 distribution + A3 attach being the fleet-saturation mechanism, with A16/A17 locking the OFF defaults.
- **Shared-file coordination with 219:** BOTH plans add Go synthetic-path blocks to `scripts/run_host_test_gates.sh` (217 → `GO_NODE_WAKETOKEN` const/matcher/branches, matrix A11; 219 → `GO_NODE_FEATUREFLAGS` + `GO_BRIDGE_FEATUREFLAGS`) and BOTH append to the same host-all plan block. Consts/branches are disjoint; the host-all block is shared. **Land 219 first (host-only), then 217 rebases its host-all line** — re-read the block before appending. On the shared dirty `new-orbit` worktree, snapshot `git status --short` first (see Known-Failure).

## Reviewer Findings
Applied verbatim from `217-review-fixlist.md` (9-agent source-verified, ready-with-tightening; core bet SOUND, zero factual drift):
- **§A1** N² register recipe killed (per-send resolver read-only; register once/cycle). **§A2** stream re-issue coalesced (A15). **§A3** "No asymmetry" corrected → deliberate 1:1-only attach + enforcement OPEN DECISION.
- **§B1/B2** TC-A13 split → A13a (gate-independent closure, storage-directionality observable) / A13b (deferred); **§B3** harness fixed (drop `ONE_TO_ONE_TESTS`, add `--dart-define` skip-guard, acceptance = discovery + `/sims`); **§B4** binary-freshness gate (A18).
- **§C1** two "stays-OFF" locks (A16 relay-default-at-rest + A17 real-resolver-null); A14 downgraded to mechanism-preservation; INV-2 rewritten. **§C2** emission mechanism pinned (`--dart-define` + release-omit CI; capability-gating rejected — bootstrap deadlock). **§C3** mlkem/un precedent framing corrected (idiom precedented, receiver-first-env-gate is new). **§C4** measurable saturation trigger added.
- **§D1** received-store schema `{peerId:{tok,ts}}`, ts=`payload['ts']` `String.compareTo`. **§D2** distinct `kWakeTokenPendingKey` + own drain block + distinct-key assertion. **§D3** `wt`-extract placed after `:301` before `:303` + A03 extended (intro-recovered/already-contact).
- **§F1** retitled "Dark Landing". **§F2** canonical TC-A02 `--plain-name`. **§F3** baseline capture step. **§F4** totality lives in the callback wrapper. **§F5** QR adds rely on backfill. **§F6** `main.dart:946` = ContactRepositoryImpl.
- **§D4/§E1/§E2** Part B split to `219-*` (Go registration pinned + behavioural completeness there).
Kept (do not regress): zero-drift factual scaffolding; adversarially-caught distribution break → A02; forward-compat-read-first ordering (disjoint new key, no rollback brick); INV-6 v1-leak lock; NET-REL-07 attributed to `node/inbox.go` omitempty.

## Arbiter Decision
Structural blockers: none. Deferred details: relay enforcement + emission flip are dark-by-design ship-order behind a measurable trigger, not omissions. Accepted differences: enforcement asymmetry decision named for the relay-ops slice. Verdict: **structurally sufficient — ready for execution.**

## Final Execution Verdict
Verdict: (pending execution) | Files changed: … | Tests run (+counts): … | Blocking: … | QA verdict: … | Non-blocking follow-ups (owner): relay enforcement env-seam + TC-A13b + saturation-trigger counter (relay-ops), §A3 asymmetry decision (relay-ops).
