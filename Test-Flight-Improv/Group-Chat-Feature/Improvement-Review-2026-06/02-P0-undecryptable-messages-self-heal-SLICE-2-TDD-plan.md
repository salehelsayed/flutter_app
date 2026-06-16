> Part of the **[Group Chat Improvement Review](./README.md)** · Priority **P0** · **Slice 2** TDD plan for **[02-P0-undecryptable-messages-self-heal.md](./02-P0-undecryptable-messages-self-heal.md)**. Companion to the Slice-1 plan **[02-...-TDD-plan.md](./02-P0-undecryptable-messages-self-heal-TDD-plan.md)** (Dart quartet UDM-A..D, **landed**, migration 080/v80, host-green, and now device-proofed — see §0).

---

# Slice 2 TDD Plan — Go epoch/grace + active key-pull (UDM-E / UDM-F / UDM-G)

**Status: PLAN ONLY.** Decomposes the Slice-1 plan's §3 deferred 3-row table (UDM-E/F/G) into execution-ready, test-first sessions. Verified against HEAD `124-harness-refactor` (working tree on top of `3b657723`) by a 4-agent recon workflow (graphify + raw Go/Dart source + `git diff`), every anchor re-confirmed in source on 2026-06-16.

> **Why this is its own plan.** Slice 1 was Dart-only, security-neutral, host-test-only. Slice 2 **changes the crypto/security posture**, requires a `gomobile bind` rebuild for the Go halves, and needs a real two-device matrix. Each session below carries its own **threat-model gate**. The Slice-1 plan sequenced these last on purpose; this plan makes the steps concrete.

---

## 0. Pre-state (is Slice 1 ready to build Slice 2 on?)

**Yes.** Slice 1 (UDM-A..D) is landed on the uncommitted tree: `groups` suite **2100 green**, migration **080 / DB v80** (`app_database_version.dart:1` → `80`; `full_migration_chain_test.dart` imports 079+080). As of this plan it is also **device-proofed** with real Go ML-KEM: `integration_test/group_undecryptable_selfheal_converge_proof_test.dart` passes on **Pixel 6 (`21071FDF600CSC`)** and **iPhone 17 Pro sim** — the missing-key case stays pending (non-terminal), the arriving key heals the real AES-256-GCM/ed25519 envelope with no duplicate, and a confirmed ed25519 authenticity failure finalizes undecryptable only after the attempt budget.

The three Slice-2 gaps remain **fully open** (re-confirmed in source):

| § | Gap | Anchor proof (HEAD) | Rebuild? | Migration? |
|---|-----|---------------------|----------|------------|
| **UDM-E** | 30 s wall-clock grace + single retained prev epoch (no ring) | `KeyRotationGracePeriod = 30 * time.Second` (`config.go:46`); `GroupKeyInfo{Key,KeyEpoch,PrevKey,PrevKeyEpoch,GraceDeadline}` (`group.go:62-68`) | **gomobile** | none |
| **UDM-F** | future-epoch live envelope → `ValidationReject` (peer penalty); no `key_epoch_behind`; `messageId` omitted | `ValidationIgnore` 0 uses in `node/pubsub.go`; reject at `pubsub.go:1554-1556`; `emitGroupDecryptionFailed` omits `messageId` (`:1699-1711`) | **gomobile** | none |
| **UDM-G** | active key-pull is a **log-only stub** | `emitGroupKeyRepairRequest` emits only `GROUP_KEY_REPAIR_REQUESTED` (`group_pending_key_repair_service.dart:72`); **no `group_key_repair_request` wire type anywhere** in `lib/` or `go-mknoon/` | **none** (Dart-only) | none |

**No DB migration for any of E/F/G** — head is `currentIdentityDatabaseVersion = 80`; the repair queue table shipped in 063; the 078/079/080 contention from Findings 03/09/self-heal does **not** apply (Go struct + transient wire type only). Giving Slice 2 a migration would *collide* with the already-shipped 080 — keep it schema-free.

---

## 1. Scope & sequencing

**Land order: UDM-E → UDM-F → UDM-G.** UDM-E widens the local *held-keys* acceptance window (a ring of recent epochs); UDM-F keeps future-epoch messages alive (Ignore + re-pull) instead of dropping them. Together they **reduce how often an active pull is needed**, so UDM-G — the largest, most protocol-invasive piece — ships last against the smallest residual gap. UDM-E lands before UDM-F because both edit the **same** decrypt/verify switch (`pubsub.go:1283`/`:1263`); F builds on E's generalized ring lookup rather than the 1-deep prev.

- **UDM-E + UDM-F are pure Go** (`node/group.go`, `node/config.go`, `node/pubsub.go`) → host `go test ./node` gates the logic, but a `make all` + `pod install` rebuild is **mandatory before any device proof**.
- **UDM-G is Dart-led and needs NO Go rebuild** — the request rides the existing opaque typed-envelope transport (`sendP2PMessage`/`storeP2PMessageInInbox`); only the Dart `IncomingMessageRouter` learns a new `case`. (Old peers route the unknown type to `unknownMessageStream` → harmless drop, so backward-compat is free.)

Each session must keep the **Finding-03 removal-fails-closed invariants (R1..R5)** intact: the ring TTL/eviction must never re-grant a *removed* member's expired epoch.

---

## 2. Session UDM-E (#1 + #2) — configurable grace + retained epoch-key ring

**Root cause (§A/§B).** The live grace is a hardcoded 30 s wall clock (`hasKeyRotationGrace`, `pubsub.go:1256-1261`) and only **one** prior epoch is retained (`PrevKey`/`PrevKeyEpoch`); each rotation **overwrites** `current.Key` into `PrevKey` (`UpdateGroupKey` `pubsub.go:847-872`; `RefreshJoinedGroupStateIfNewer` `:799-811` — byte-identical struct literals), so the 3rd-oldest epoch is silently dropped → permanently-undecryptable old messages. Decrypt/verify anchor to the **timer**, not to **keys held**.

**Goal.** Give `GroupKeyInfo` a retained epoch-key **ring (K=5)**; anchor live decrypt+verify to keys held (drop the grace gate on the *receive* path); make the grace **configurable** (default ~10 min) and demote the timer to constrain only which epoch a node will **sign/publish** under.

**RED tests first** — `go-mknoon/node/pubsub_key_rotation_grace_test.go` (host `go test ./node`):

| Test | Mirrors | Assertion |
|---|---|---|
| `TestUDME_DecryptAcceptsThirdOldestEpochStillInRing` | `:887` `gk020SequentialRotationKeyInfo` + `:513` | After `Join(epoch0) → UpdateGroupKey(1) → UpdateGroupKey(2)`, an envelope at **epoch0** MUST decrypt (today dropped: `PrevKey` only held epoch1). Ring retains 3rd-oldest within K=5 regardless of `GraceDeadline`. |
| `TestUDME_ValidatorAcceptsHeldOldEpochAfterGraceExpired` | `:63` `..._RejectsPreviousEpochAfterGraceExpires` (invert) + harness `group_security_harness_test.go:115` | The existing deadline-negative **reject** flips to **accept** when the prior epoch is still in the ring — proves the timer no longer gates receive. |
| `TestUDME_RingEvictsBeyondK_OldestRejected` | `:804` `TestGK020...KeepsOnlyEpoch1AsPrevious` | After K+1 (=6) rotations, the evicted oldest epoch fails decrypt (`no group key available`); the 5 most-recent held epochs decrypt. Bounds retention (forward-secrecy bound). |
| `TestUDME_ConfigurableGrace_DefaultTenMin_OverrideHonored` | `:760`/`:780-784` `GraceDeadline` range assert | `NodeConfig.KeyRotationGracePeriod` unset → `GraceDeadline ∈ [now+default, now+default+slack]` (default ~10 min); explicit override (e.g. 1 s) honored. Locks `EffectiveKeyRotationGracePeriod()`. |

**GREEN edits:**
- `node/group.go:62-68` — add `Keys []GroupEpochKey` (newest-first) where `GroupEpochKey{Key string; KeyEpoch int}`. Keep `Key`/`KeyEpoch` as the **current** epoch (send path + back-compat). Keep `PrevKey`/`PrevKeyEpoch` **populated as a derived view over ring head** for any external/Dart JSON consumer (don't break the wire), but make decrypt/verify read the **ring**.
- `node/pubsub.go:847-872` (`UpdateGroupKey`) + `:799-811` (`RefreshJoinedGroupStateIfNewer`) — replace the lossy `PrevKey:current.Key` overwrite with **append-then-evict-past-K**. **Factor the two byte-identical struct literals into one ring-append helper** or they will diverge. Preserve the epoch-monotonic guard. `GraceDeadline = now + effectiveGrace`, now governing sign/publish only.
- `node/pubsub.go:1283-1296` (`decryptGroupEnvelopePayload`) + `:1263-1281` (`verifyGroupEnvelopeSignature`) — iterate the held-keys ring (current epoch first for the hot path); **no grace gate for held keys**. **Update BOTH** receive sites (validator `:1546-1557` and subscription decrypt `:1579-1611`) — missing one leaves a half-migrated gate.
- `node/pubsub.go:1256-1261` (`hasKeyRotationGrace`) — demote to **send/sign-constraint only** (publish path `:480-488`, reaction `:707`); receive accepts any epoch still in the ring.
- `node/pubsub.go:881-887` (`cloneGroupKeyInfo`) + `:1248-1254` (`joinedGroupKeyInfo`) — **deep-copy** the ring slice (`append([]GroupEpochKey(nil), src.Keys...)`); the shallow `*keyInfo` aliases the backing array and would let `GetGroupKeyInfo` callers mutate stored state (data race).
- `node/config.go:46` + `:126-152` — keep the const as the **default value** (don't rename — it's referenced at ~18 test sites) bumped to ~10 min; add `NodeConfig.KeyRotationGracePeriod time.Duration` (0 ⇒ default) + accessor `EffectiveKeyRotationGracePeriod()` mirroring `PersonalRendezvousRefreshEvery()` (`:147-152`); add `const RetainedEpochKeys = 5`.
- `node/node.go` / `Start()` — thread effective grace into the two write methods via `n.lastConfig.EffectiveKeyRotationGracePeriod()` (both are `*Node` methods; `n` in scope).

**Must relax in the SAME commit:** `assertGK020SequentialRotationKeyInfo` (`:916-942`, esp. `:928`) hard-asserts epoch0 MUST NOT survive `0→1→2` — directly contradicts K=5 retention. Relax/fork it (epoch0-retained) **with** the ring change so `main` never goes red. Audit the whole GK019/GK020 family (`:329,:386,:467,:513,:787,:804` + helpers `:810`,`:887`).

**Threat model / gate.** A node may now decrypt/verify any of the last **K=5** epochs it *already held* (decoupled from the clock). Forward secrecy preserved: (a) the ring only ever holds epochs the node legitimately received while a member — no future/post-removal key is added; (b) eviction past K hard-drops the oldest (bounded, no hoarding); (c) a removed member still can't obtain the **new** post-rotation key (distribution unchanged). Bound = K=5 ∧ ~10 min grace governs only old-epoch **send/sign** tolerance. **Closure gate:** full `go test ./node` green incl. the forked GK020 + the 4 new RED→GREEN tests; device-matrix sequential-rotation decrypt (below). **Watch:** any external JSON consumer of `GroupKeyInfo.prevKey` must not regress when it becomes a derived view.

**Migration:** none. **Rebuild:** `make all` + `pod install` before device proof.

---

## 3. Session UDM-F (#5b) — future-epoch `ValidationIgnore` + privacy-safe `messageId`

**Root cause (§C/§D).** `groupTopicValidator` (`pubsub.go:1471-1561`) only ever returns `ValidationReject` (8 branches) or `ValidationAccept` (1). A future/key-behind envelope dies at step 8 (`:1554-1556`, `bad_signature_or_epoch`) — **indistinguishable from a forged signature** because both collapse to `verifyGroupEnvelopeSignature → false`. That triggers libp2p peer-score penalties **and** a reject-feedback stream against an honest sender on a newer epoch. Separately, `emitGroupDecryptionFailed` (`:1699-1711`) omits `messageId` despite `env` carrying it (`internal/group_envelope.go:28`), so the Dart self-heal can't bind the failure to a message.

**Goal.** A **strictly-future** (`env.KeyEpoch > keyInfo.KeyEpoch`), known-group, member-signed envelope → `pubsub.ValidationIgnore` (silent drop, **no peer penalty**) + a new `group:key_epoch_behind` diagnostic. Additively attach `messageId` to `group:decryption_failed`. (Optional buffer + re-process after `UpdateGroupKey` advances — **DEFER**.)

**RED tests first** — `go-mknoon/node/pubsub_decryption_failure_test.go`:

| Test | Mirrors | Assertion |
|---|---|---|
| `TestFutureEpochResolvesToIgnoreNotReject` | `pubsub_delivery_test.go:5080` + validator `:1471` | local epoch N, authentic envelope at **N+1** → validator returns `ValidationIgnore` (not Reject), emits `group:key_epoch_behind`, sends **no** `group:validation_rejected/bad_signature_or_epoch` and **no** reject-feedback stream. |
| `TestSameEpochBadSignatureStillRejects` | `pubsub.go:1554-1556` | envelope at `KeyEpoch==N` with a corrupted signature still → `ValidationReject` (`bad_signature_or_epoch`). Proves the Ignore split is scoped to strictly-future epochs; forgery still penalized. |
| `TestKeyEpochBehindDiagnosticCarriesMessageIdNoSecrets` | `:283-296` privacy sweep | `group:key_epoch_behind` carries `messageId==env.MessageId`, `groupId`, `senderId`, `keyEpoch`, `localKeyEpoch`; `rawEvents` excludes plaintext/groupKey/ciphertext/nonce/signature/senderPriv. |
| `TestDecryptionFailedIncludesMessageIdWithoutLeak` | `:257-296` | `group:decryption_failed` now also carries `messageId==env.MessageId` while keeping the `:283-296` secret-exclusion sweep **and** the `:262-281` positive-key asserts green. |
| `TestBufferedFutureEpochReprocessesAfterUpdateGroupKey` *(OPTIONAL/DEFER)* | `:807` + `handleGroupSubscription:1604-1654` | an Ignored N+1 envelope is re-decrypted and emits `group_message:received` after local key advances to N+1. Ship only if device evidence justifies the new mutable state. |

**GREEN edits** (`node/pubsub.go`):
- Validator step 8 (`~:1545-1557`) — split on epoch **before** the signature math: if `env.KeyEpoch > keyInfo.KeyEpoch` (clamp to a small window `N+1 .. N+K` to avoid grief loops) → emit `group:key_epoch_behind` + `return pubsub.ValidationIgnore`. Keep `verifyGroupEnvelopeSignature` Reject for same-epoch-bad-signature **and** stale-past epochs (those stay `bad_signature_or_epoch` → Reject).
- New `emitGroupKeyEpochBehind(groupId, env, localEpoch)` mirroring `logPubSubValidationReject` privacy posture — emit `groupId, senderId, envelopeType, env.KeyEpoch, localKeyEpoch, messageId`; **never** ciphertext/nonce/signature/key.
- `emitGroupDecryptionFailed` (`:1699-1711`) — additively `data['messageId'] = env.MessageId` when non-empty (covers both call sites `:1599` no-key and `:1609` decrypt-error; both already pass `env`).
- For the Ignore branch, **do NOT** call `sendGroupValidationRejectFeedback` (that path is for genuine rejects); the `key_epoch_behind` diagnostic is the replacement signal.

**Threat model / gate.** Future-epoch traffic moves Reject → Ignore (no peer-score penalty, no reject-feedback) so an honest newer-epoch sender isn't punished for our key-lag. **Risk boundary:** the split is gated strictly on the integer compare `env.KeyEpoch > keyInfo.KeyEpoch` (pre-signature). All existing Reject branches stay Reject (`not_v3_envelope`, `invalid_envelope ×3`, `group_mismatch`, `peer_mismatch`, `unknown_group`, `non_member`, `unbound_device`, `unauthorized_writer`, `missing_key`, and same-epoch-bad-sig / stale-past). Never verify a signature against a key we don't hold; never Accept future-epoch traffic — **Ignore only**. An attacker can claim a high `KeyEpoch` to dodge a penalty, but Ignore is a silent drop (no acceptance, no decrypt, no peer credit) — only a missed penalty — and steps 1-7 already Reject structurally/membership-invalid junk; the `N+1..N+K` clamp caps grief. **Privacy gate (must pass before closure):** `pubsub_decryption_failure_test.go:283-296` stays green **with** `messageId` attached, **and** the new `group:key_epoch_behind` event is added to that same exclusion sweep.

**Migration:** none. **Rebuild:** `make all` + `pod install` before device proof.

---

## 4. Session UDM-G (#3) — real signed `group_key_repair_request` (active pull)

**Root cause (§E, load-bearing).** `emitGroupKeyRepairRequest` is a no-op stub (`group_pending_key_repair_service.dart:72`) — it logs `GROUP_KEY_REPAIR_REQUESTED` and sends nothing. The already-firing producer `_requestReceivedMessageKeyRepairIfLocalEpochIsBehind` (`group_message_listener.dart:1032`, fired `:946`→`:1060`) therefore never pulls a missing key. There is **no `group_key_repair_request` wire type** anywhere.

**Goal.** Real **outbound signed** `group_key_repair_request {groupId, keyEpoch, requesterPeerId, requesterDeviceId, sig}` over the existing direct/inbox fallback transport; admin responder = a **targeted re-run** of single-device key delivery for the **exact requested epoch** (never mint a new epoch), gated by member-at-epoch authz + per-`(requester,groupId,epoch)` rate-limit. **Dart-only; no Go rebuild** (opaque typed envelope on the existing transport).

**Wiring census to reconcile (12 sites):** 9 direct `requestGroupKeyRepair: emitGroupKeyRepairRequest` (`main.dart:2207,2244,2375,2404,2491,3803,3954`; `startup_router.dart:685`; `prepare_notification_route_target_use_case.dart:57`) → swap to the real sender. 3 `?? emitGroupKeyRepairRequest` defaults (`group_message_listener.dart:197`, `group_membership_update_listener.dart:172`, `drain_group_offline_inbox_use_case.dart:418`) + `GroupTestUser` → keep the **log-only fallback**. *(A partial swap silently no-ops the pull — lock with a source-text wiring test, mirror 120 G1.)*

**RED tests first:**

| Test (path) | Mirrors | Assertion |
|---|---|---|
| `group_key_repair_request_sender_test.dart` — *requester emits a signed request, falls back to inbox* | `group_key_update_listener_test.dart:353` | the real `RequestGroupKeyRepair` sends **one** `type:'group_key_repair_request'` envelope to the admin transportPeerId via `sendP2PMessage`; payload has `requesterPeerId/requesterDeviceId/keyEpoch` + non-empty signature; `bridge.commandLog` contains `payload.sign`; on send-false/timeout `storeP2PMessageInInbox` is called with the same envelope. (Today: nothing sent — RED.) |
| `group_key_repair_responder_listener_test.dart` — *admin re-delivers EXACT epoch, mints none* | `group_key_update_listener_test.dart:274` | a valid signed request for `keyEpoch=N` → exactly one `group_key_update` whose `keyGeneration==N` and `encryptedKey==getKeyByGeneration(groupId,N)`; `bridge.commandLog` does **not** contain `group:updateKey`; `getLatestKey` epoch unchanged. |
| `..._responder` — *rejects non-member-at-epoch / bad sig* | `group_key_update_listener_test.dart` UNAUTHORIZED_SENDER | request from a non-entitled peer (or failing `callVerifyPayload`) → **no** `group_key_update`, FLOW `GROUP_KEY_REPAIR_RESPONDER_UNAUTHORIZED`. |
| `..._responder` — *rate-limits per (requester, groupId, epoch)* | `group_key_update_listener.dart:358` idempotency map | N identical valid requests in-window → ≤1 (capped) re-deliveries; the rest emit a rate-limited FLOW event and send nothing; distinct `(groupId,epoch)` not throttled against each other. |
| `group_resume_recovery_test.dart` — *behind-epoch receiver PULLS end-to-end* | existing `GROUP_KEY_REPAIR_REQUESTED` scenario | two `GroupTestUser`s: receiver lacks epoch N → real sender fires → responder re-delivers N → receiver's `group_key_update` listener applies N → the pending placeholder repairs (status flips off `pending_key`). |

**GREEN edits:**
- `group_pending_key_repair_service.dart` — add `buildSignedGroupKeyRepairRequestEnvelope(...)` → `{type:'group_key_repair_request', version:'1', payload:{groupId,keyEpoch,requesterPeerId,requesterDeviceId, signatureAlgorithm, signedPayload, signature}}` where `signedPayload` = canonicalized `{groupId,keyEpoch,requesterPeerId,requesterDeviceId}` signed via `callSignPayload`. New `GroupKeyRepairRequestSender` (bridge, identity getters, `sendP2PMessage`, `storeP2PMessageInInbox`, `getMembers`→admin transportPeerId) implementing `RequestGroupKeyRepair`, targeting the admin/creator transportPeerId via `_sendDirectWithInboxFallback` semantics. **Keep** `emitGroupKeyRepairRequest` as the FLOW-log fallback.
- `core/services/incoming_message_router.dart` — add `case 'group_key_repair_request': _groupKeyRepairRequestController.add(message);` (near `:199`) + controller + `groupKeyRepairRequestStream` getter (mirror `:62`) + dispose. Old/unknown peers keep hitting default `:226` → `unknownMessageStream` (no-op).
- **New** `group_key_repair_responder_listener.dart` — subscribe to `groupKeyRepairRequestStream`; (1) verify sig via `callVerifyPayload` against the requester's bound device signing key; (2) **authz** — requester is/was a member entitled to `keyEpoch` and self holds rotate/creator rights; (3) **rate-limit** per-`(requester,groupId,epoch)` (in-memory map, mirror `_acceptedSignedTransitionAuditHashesBySourceId`); (4) `getKeyByGeneration(groupId, keyEpoch)` — if null, no-op; (5) re-run **single-device** delivery for the requester's device(s) with `newEpoch=keyEpoch`. FLOW telemetry for accepted/rejected/rate-limited.
- `rotate_and_distribute_group_key_use_case.dart` — expose a targeted `distributeGroupKeyAtEpochToPeer({peerId, int keyEpoch})` that loads `getKeyByGeneration(groupId,keyEpoch)` and reuses `_distributeRotatedKeyToDeviceWithRetry` (clone `distributeCurrentGroupKeyToDeferredPeer` `:591` but swap `getLatestKey`→`getKeyByGeneration`, pass `keyEpoch` as `newEpoch`). **Mint NO new epoch** (no `callGroupUpdateKey`/draft/promote).
- `main.dart` — construct `GroupKeyRepairRequestSender` (with `p2pService.sendMessage`/`storeInInbox` + identity getters), use it at the 9 direct sites; construct `GroupKeyRepairResponderListener` subscribed to `messageRouter.groupKeyRepairRequestStream` alongside `groupKeyUpdateListener` (`~:2366`).
- `startup_router.dart:685` → threaded real sender. `prepare_notification_route_target_use_case.dart:57` → threaded sender **but degrade to log-only** in NSE/background where send closures are unavailable (never throw).
- `test/shared/fakes/group_test_user.dart` — add injectable requester-sender + admin responder hook so two users complete a request→re-deliver round-trip over `FakeGroupPubSubNetwork`.

**Threat model / gate.** New inbound key-distribution surface, mitigated by 4 gates: (1) **signed** request, responder-verified against the requester's bound device key; (2) **authz** — admin only re-delivers to an entitled member-at-epoch and only epochs it holds (`getKeyByGeneration`), never outsiders, never a fresh epoch; (3) **rate-limit** per-`(requester,groupId,epoch)`; (4) responder reuses ML-KEM-encrypt-to-recipient-device delivery so a replayed request can't extract key to a wrong device. Backward-compat = no-worse-than-today (old peers drop the type; requesters fall back to inbox if admin offline). **Watch the audit-binding asymmetry trap** (B4-dissolve class): `signGroupTransitionAudit` conditionally omits `deviceId/transportPeerId/keyPackageId` when empty (`signed_group_transition_audit.dart:136-142`) — bind the same device fields the original rotation bound, or `verifyGroupTransitionAudit` yields device/transport_mismatch and the re-delivered key is rejected. **Closure gate:** the 5 RED→GREEN host tests + the 2-device real-ML-KEM round-trip (behind-epoch member pulls exact epoch, placeholder repairs, no new epoch minted, non-member rejected, duplicates rate-limited).

**Migration:** none. **Rebuild:** none (Dart-only; envelope rides existing transport).

---

## 5. Cross-cutting gates & verification

| Gate | Requirement |
|------|-------------|
| Go unit (E/F) | `cd go-mknoon && go test ./node -run 'GroupTopicValidator\|HandleGroupSubscription\|GroupKey\|KeyRotation'` green, incl. the **forked GK020** (epoch0-retained) and the new UDM-E/F RED→GREEN tests |
| Go privacy/leak | `pubsub_decryption_failure_test.go` GO-004/GO-008 leak scans (`:200`/`:302`/`:283-296`) green with `messageId` added **and** `group:key_epoch_behind` added to the exclusion sweep |
| Bridge bindings | `make verify-bindings` (+ `make testpeer`) after the Go struct change — confirm `GroupKeyInfo` JSON stays backward-compatible across the bridge (`bridge.go:1766/1925/2446`, `GetGroupKeyInfo :2385`) |
| Dart host (G) | new `group_key_repair_request_sender_test.dart`, `group_key_repair_responder_listener_test.dart`, updated `group_message_listener_test.dart`, `group_resume_recovery_test.dart`; `./scripts/run_test_gates.sh groups` stays green; source-text wiring lock for the 9 swapped sites |
| FLOW assertions | presence of `GROUP_KEY_REPAIR_RESPONDER_*` (accepted/unauthorized/rate-limited) and `group:key_epoch_behind`; **no** new-epoch mint (`group:updateKey` absent) on a repair response |
| gomobile rebuild | after **any** E/F Go edit: `cd go-mknoon && PATH="$PATH:$(go env GOPATH)/bin" make all && cd ../ios && pod install` (keep `-checklinkname=0` for Android; Go 1.25 needs it). `flutter run` alone will NOT pick up node-package changes |
| graphify | after Go edits run `./graphify-arch/refresh_arch_graph.sh` then `graphify update .` (per project rules) |
| Device matrix | real-ML-KEM 2-device matrix on **iPhone17Pro-sim + Pixel6 (`21071FDF600CSC`)**, mirroring the Finding-03 / Slice-1 proof pattern (`integration_test/group_removal_rotation_*_proof_test.dart`, `group_undecryptable_selfheal_converge_proof_test.dart`): **UDM-E** rotate K times, assert a message under an epoch N-rotations-ago (within K=5) still decrypts on a peer that held it, and a message under an evicted (>K) epoch **fails closed**; **UDM-F** background >10 min then foreground → future-epoch message recovers (no permanent placeholder/duplicate); **UDM-G** behind-epoch member pulls the exact epoch → placeholder repairs |
| Gate definitions | extend `Test-Flight-Improv/test-gate-definitions.md` (Group Messaging Gate) with the "zero permanently-undecryptable messages after a membership change, incl. background >10 min then foreground" criterion |

**Harnesses to reuse (no new infra for E/F):** `pubsub_key_rotation_grace_test.go` (`validateGroupEnvelope`, `decryptGroupEnvelopePayload`), `group_security_harness_test.go:115` (`buildGroupKeyInfoWithGrace`, `publishRawGroupEnvelope`, `connectLocalGroupNodes`), `pubsub_test.go:1658` (`buildTestEnvelope`), `pubsub_decryption_failure_test.go:41` two-node collector pattern, `mcrypto.GenerateGroupKey()`. For G: `GroupTestUser`, `FakeGroupPubSubNetwork`, the `repairRequests` collector (`group_message_listener_test.dart:933`), `FakeBridge` (`payload.sign`/`payload.verify`).

---

## 6. Risks & rollout order

**Order (each independently shippable, lowest-risk first):**
1. **UDM-E** (grace/ring) — Go. Fork GK020 in the same commit. `make all` + device sequential-rotation decrypt proof.
2. **UDM-F** (future-epoch Ignore + `messageId`) — Go, builds on E's ring lookup. `make all` + privacy sweep.
3. **UDM-G** (active pull) — Dart-only, no rebuild. Closes finding #3 against the residual gap.

**Top risks:**
- **GK020 contradiction** — `assertGK020SequentialRotationKeyInfo:928` asserts epoch0 is dropped; relax/fork it **with** the ring change or `main` goes red. Audit the whole GK019/GK020 family.
- **Shallow-copy aliasing** — `cloneGroupKeyInfo:881-887` + `joinedGroupKeyInfo:1248-1254` both do `*keyInfo`; deep-copy the ring slice or `GetGroupKeyInfo` hands out shared backing arrays (data race).
- **Two divergent rotation literals** — `UpdateGroupKey:847-872` and `RefreshJoinedGroupStateIfNewer:799-811` are byte-identical; factor ring-append into one helper.
- **Two receive sites** — validator `:1546-1557` and subscription decrypt `:1579-1611` both pass `time.Now()`; update both or the grace gate is half-migrated.
- **JSON back-compat** — `GroupKeyInfo` crosses the bridge both ways; the `keys` field is additive but verify the Dart `GroupKeyInfo` mapper tolerates it and `prevKey` stays a valid derived view (stale in-flight key-updates must still parse mid-rollout).
- **UDM-F over-broad Ignore** — gate strictly on `env.KeyEpoch > keyInfo.KeyEpoch`, clamp to `N+1..N+K`; keep every other Reject branch; Ignore alters gossipsub propagation (not re-forwarded/penalized like Reject) — verify mesh-scoring impact.
- **UDM-G exact-epoch / audit binding** — use `getKeyByGeneration` (not `getLatestKey`); bind the device fields or hit the B4-dissolve mismatch; reconcile all 12 census sites (a stray stub silently no-ops the pull); rate-limit is in-memory (resets on restart — keep window small).
- **No migration** — head is v80; giving Slice 2 a migration collides with the shipped 080. Keep schema-free.
- **Android build caveat** — keep `-checklinkname=0` (Go ≥1.23 `//go:linkname` / `wlynxg/anet`); a toolchain bump can break the `.aar`.

**What Slice 2 closes.** UDM-E/F shrink how often recovery is needed (wider held-key window, no peer penalty, future-epoch kept alive); **UDM-G** makes a member who genuinely missed a key *actively* recover it — the residual the Slice-1 plan explicitly left open. Only after UDM-G + the device matrix is the finding **fully closed** ("zero permanently-undecryptable messages after a membership change").
