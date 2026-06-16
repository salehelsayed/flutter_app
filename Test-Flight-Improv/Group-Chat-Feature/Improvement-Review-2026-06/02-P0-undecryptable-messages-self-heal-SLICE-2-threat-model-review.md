> Part of the **[Group Chat Improvement Review](./README.md)** · Priority **P0** · **Slice 2** threat-model REVIEW for **[02-P0-undecryptable-messages-self-heal.md](./02-P0-undecryptable-messages-self-heal.md)**. Companion to the Slice-2 TDD plan **[02-...-SLICE-2-TDD-plan.md](./02-P0-undecryptable-messages-self-heal-SLICE-2-TDD-plan.md)**. Reviews the **landed** UDM-E / UDM-G code on the working tree (`124-harness-refactor`, on top of `3b657723`) and the **plan-only** state of UDM-F.

---

# Slice 2 Threat-Model Review — Go held-key ring + active key-pull (UDM-E / UDM-F / UDM-G)

**Scope of this review.** A security posture review of the Slice-2 self-heal mechanisms as they actually exist in the working tree on 2026-06-16. The objective is forward-secrecy and removal-fails-closed preservation (Finding-03) while widening the *legitimate* decrypt window and adding an inbound key-pull path. Every claim below is anchored to source I read; `file:line` citations are to the working-tree revision.

**Implementation status as found in the tree (load-bearing — read first):**

| Session | Plan intent | Found in working tree | Verdict |
|---|---|---|---|
| **UDM-E** | held-key ring (K epochs), clock-free receive, configurable grace | **IMPLEMENTED** — `GroupEpochKey`/`GroupKeyInfo.Keys` (`node/group.go:61-83`), `rotateGroupKeyRing`/`heldGroupKeyForEpoch`/`heldGroupKeyRing` (`node/pubsub.go:815-843`, `:1307-1333`), `RetainedEpochKeys = 5` + `KeyRotationGracePeriod = 10*time.Minute` + per-node override (`node/config.go:51-55`, `:164-173`) | **LANDED — reviewed here** |
| **UDM-F** | future-epoch `ValidationIgnore` + `group:key_epoch_behind` + additive `messageId` | **NOT IMPLEMENTED** — validator still returns `ValidationReject`/`bad_signature_or_epoch` for an unheld (future) epoch (`node/pubsub.go:1620-1622`); the reject is **locked by a test** (`node/pubsub_key_rotation_grace_test.go:729-765`, `TestGroupTopicValidator_RejectsUnknownFutureEpochBeforeDelivery` expects `reject:bad_signature`); `grep -n "ValidationIgnore\|key_epoch_behind" node/*.go` returns **zero non-test hits** | **PLAN-ONLY — NOT YET LANDED** |
| **UDM-G** | signed `group_key_repair_request`, verify+authz+rate-limit responder, ML-KEM single-device redelivery | **IMPLEMENTED** — `GroupKeyRepairRequestSender` + `buildSignedGroupKeyRepairRequestEnvelope` (`lib/.../group_pending_key_repair_service.dart:97-337`), `GroupKeyRepairResponderListener` (`lib/.../group_key_repair_responder_listener.dart:40-274`), `distributeGroupKeyAtEpochToPeer` (`lib/.../rotate_and_distribute_group_key_use_case.dart:758-843`) | **LANDED — reviewed here** |

> **Reviewer note (must reach sign-off):** the task framing assumed UDM-F was landed in `node/pubsub.go`. It is **not** in this tree — it remains a PLAN-ONLY session (the Slice-2 TDD plan §3 explicitly carries it as "Status: PLAN ONLY"). I therefore review UDM-F as the *current* (reject) posture plus the *intended* posture, and flag the discrepancy as a sign-off item rather than asserting a mitigation that does not exist.

---

## Session UDM-E — held-key ring (K=5, clock-free receive)

### (1) Posture delta vs HEAD

Pre-Slice-2 (HEAD), the receive path accepted at most the current epoch and a single previous epoch, and that prev-epoch acceptance was **clock-gated** by `GraceDeadline` (a 30s window per the old `KeyRotationGracePeriod`). After the grace clock expired, a legitimately-held prior-epoch message became permanently undecryptable → "Message unavailable" placeholders after any rotation that out-raced the clock.

Post-UDM-E: the receive path anchors to a **ring of the last K epochs the node legitimately held** with **no clock gate** at all (`decryptGroupEnvelopePayload`/`verifyGroupEnvelopeSignature` consult `heldGroupKeyForEpoch`, `node/pubsub.go:1352-1362`, `:1335-1350`). The clock (`GraceDeadline`) now governs **only** which prior epoch a node will *sign/publish* under (`hasKeyRotationGrace`, `:1291-1300`; doc-comment `node/group.go:67-83`). The grace default was widened 30s → 10m (`node/config.go:46-51`).

Net: the legitimate decrypt window widens from "current + 1 prev, ≤30s" to "any of the last 5 epochs I held, no time limit (until evicted)".

### (2) Bound / mitigation actually implemented

- **K=5 ring, newest-first, append-evict.** `rotateGroupKeyRing` prepends the incoming epoch, copies forward prior entries, and **stops at `RetainedEpochKeys`** (`node/pubsub.go:818-829`); the 6th-oldest epoch is dropped. `RetainedEpochKeys = 5` (`node/config.go:52-55`).
- **The ring only ever contains epochs the node actually held.** Entries are added solely through `rotateGroupKeyRing` / `joinedGroupKeyInfo`, both reached **only** from the key-ingest paths (`UpdateGroupKey` `:878-896` and `applyJoinedGroupKeyInfo` `:799-805`). There is no path that injects a wire-supplied epoch into the ring without it first being a key this node received and stored. A removed member is never *delivered* the new epoch (see Finding-03 below), so that epoch never enters their ring.
- **Epoch-monotonic guard.** `UpdateGroupKey` returns early when `keyInfo.KeyEpoch <= current.KeyEpoch` (`:891-892`); `rotateGroupKeyRing`'s contract requires the caller to have already established strict-newer (`:811-814`), and it defensively skips a duplicate incoming epoch (`:821-824`). A replayed *old* key-update cannot rewind the head or re-add an evicted epoch.
- **Signature still required per epoch.** Holding the ring key for an epoch is necessary but not sufficient: `verifyGroupEnvelopeSignature` still runs `mcrypto.VerifyPayload` over `BuildGroupSignatureData(groupId, env.KeyEpoch, ciphertext)` (`:1347-1349`). A held key lets you *attempt* verification; a forged signature still fails.
- **Deep-copy on read.** `cloneGroupKeyInfo` copies the ring slice so `GetGroupKeyInfo` callers cannot mutate stored state (`:905-914`) — closes a data-race / aliasing foot-gun.

### (3) Residual risk

- **The decrypt window is genuinely wider.** Any of the last 5 epochs a node held remains decryptable indefinitely (no time bound), bounded only by *how many further rotations occur*. In a low-rotation group the K-epoch window is effectively unbounded in wall-clock time. This is the deliberate trade and is a human sign-off item (below).
- **Eviction is rotation-count-driven, not time-driven.** Forward secrecy past K depends on the group continuing to rotate. If an attacker compromises a device's stored ring, they obtain up to 5 epochs' worth of keys, not 2. Disk-at-rest exposure of `GroupKeyInfo.Keys` is correspondingly wider.
- **Legacy/wire back-compat ring synthesis.** `heldGroupKeyRing` reconstructs a 2-entry ring from legacy `Key`/`PrevKey` fields when `Keys` is empty (`:1307-1322`) — for stale Dart/wire payloads that predate the ring field. This is bounded (≤2 entries) and only ever yields keys already present in those legacy fields, so it cannot manufacture an epoch the node didn't have.

### (4) What an attacker can / can't do

- **Removed member can't decrypt the new epoch.** They are never delivered the post-removal key, so it never enters their ring; `heldGroupKeyForEpoch` returns `false` and decrypt/verify both fail closed. **Finding-03 removal-fails-closed is preserved** — the ring only widens acceptance among epochs the node *legitimately held while a member*, never grants a never-held epoch.
- **Attacker can't widen their own window by replay.** The epoch-monotonic guard + per-epoch signature check mean a replayed old key-update is a no-op, and a forged envelope at a held epoch still fails signature.
- **Attacker who already compromised the device** gains a wider key set (up to K epochs) than pre-UDM-E (2). That is the accepted forward-secrecy bound, not a new remote attack surface.

---

## Session UDM-F — future-epoch handling (PLAN-ONLY; current posture = Reject)

### (1) Posture delta vs HEAD

**No delta — UDM-F is not in this tree.** A strictly-future, member-signed envelope (`env.KeyEpoch > localKeyEpoch`) whose epoch the node does not yet hold is still rejected: `verifyGroupEnvelopeSignature` returns `false` because `heldGroupKeyForEpoch` misses (`node/pubsub.go:1343-1345`), and the validator maps that to `ValidationReject` + `bad_signature_or_epoch` (`:1620-1622`). This reject is **intentionally locked** by `TestGroupTopicValidator_RejectsUnknownFutureEpochBeforeDelivery` (`node/pubsub_key_rotation_grace_test.go:729-765`, asserts `reject:bad_signature`). There is no `group:key_epoch_behind` emit and `messageId` is not yet additively attached to `group:decryption_failed` (`emitGroupDecryptionFailed`, `:1765-1777`, carries `keyEpoch` only).

### (2) The bound that *would* be implemented (intended; cited from plan, not from shipped code)

Per the Slice-2 plan §3 (`...-SLICE-2-TDD-plan.md:72-94`): split validator step 8 on the integer compare `env.KeyEpoch > keyInfo.KeyEpoch` **before** the signature math, clamped to a small window `N+1 .. N+K`, returning `pubsub.ValidationIgnore` (silent drop, no peer-score penalty, **no** `sendGroupValidationRejectFeedback`) and emitting `group:key_epoch_behind`. Every other Reject branch stays Reject; same-epoch-bad-signature and stale-past epochs stay `bad_signature_or_epoch`/Reject.

**This is the intended bound. It is NOT yet code.** I verified its absence (grep zero non-test hits for `ValidationIgnore`/`key_epoch_behind`).

### (3) Residual risk

- **Until UDM-F lands, the residual the plan targets remains open:** an honest newer-epoch sender (whose rotation out-raced this node's key delivery) is penalized via gossipsub peer-scoring on Reject, and their message is dropped with a generic `bad_signature_or_epoch` (indistinguishable from a forgery in telemetry). UDM-G is the *only* live recovery path for that case today.
- **When UDM-F lands**, the residual becomes: an attacker can label a forgery with a high `KeyEpoch` to dodge the peer-score penalty. The plan's bound contains this — see (4).

### (4) What an attacker can / can't do (under the *intended* bound)

- The Ignore branch is gated strictly on the **pre-signature integer compare** `env.KeyEpoch > keyInfo.KeyEpoch`. Crucially, Ignore is **not** Accept: no decrypt, no event emission, **no peer credit** — a silent drop. So mislabeling a forgery as a future epoch costs the attacker only a *missed penalty*; it never gains them delivery, decryption, or acceptance.
- Steps 1–7 of the validator already Reject structurally/membership-invalid junk (`not_v3_envelope`, `invalid_envelope`, `group_mismatch`, `peer_mismatch`, `unknown_group`, `non_member`, `unbound_device`, `unauthorized_writer`) *before* the epoch split, so the Ignore branch is reachable only by a known-group, bound-device, authorized-writer envelope. The `N+1..N+K` clamp caps grief loops.
- **This containment is contingent on the implementation matching the plan exactly** (Ignore-only, clamp, no reject-feedback). It must be re-reviewed against the actual diff when UDM-F lands — this review cannot sign it off from a plan.

---

## Session UDM-G — signed active key-pull (request + authorized responder)

### (1) Posture delta vs HEAD

Pre-UDM-G, a member who genuinely missed a key-update (offline during rotation, lost delivery) had **no active recovery** — only a log-only stub (`emitGroupKeyRepairRequest`) and hope for a future passive redistribution. Their messages at the missed epoch stayed undecryptable.

Post-UDM-G: the behind member sends a **signed** `group_key_repair_request` to the group admin/creator (`GroupKeyRepairRequestSender.call`, `lib/.../group_pending_key_repair_service.dart:187-275`); an admin-side `GroupKeyRepairResponderListener` verifies, authorizes, rate-limits, and **re-delivers the exact requested epoch** via ML-KEM-to-device (`group_key_repair_responder_listener.dart:95-252`). This is a new **inbound** key-pull surface — the security-relevant delta.

### (2) Bound / mitigation actually implemented

All four gates verified in `group_key_repair_responder_listener.dart:_handle`:

- **Gate #1 — signature over canonical payload, against the bound device key.** The responder rebuilds `canonicalGroupKeyRepairRequestSignedPayload(groupId, keyEpoch, requesterPeerId, requesterDeviceId)` (`group_pending_key_repair_service.dart:97-110`), requires the wire `signedPayload` to byte-match it (`:183-186`), checks `signatureAlgorithm == 'ed25519'` (`:172-175`), and verifies via `callVerifyPayload` against the **requester's bound device signing key looked up from group membership** — `requesterMember.findDeviceById(requesterDeviceId).deviceSigningPublicKey` (`:163-196`), **never** an arbitrary key from the wire. Invalid signature ⇒ `invalid_signature` reject (`:193-195`).
- **Gate #2 — member-at-epoch authorization (both sides).** (2a) Self must hold rotate/creator rights to act as responder at all (`selfCanRotate || group.createdBy == ownPeerId`, else `self_not_authorized`, `:139-149`). (2b) The requester must be a **current member** (`getMember` non-null, else `requester_not_member`, `:152-159`). Dissolved/absent group ⇒ `group_not_found_or_dissolved` (`:128-131`).
- **Gate #3 — per-`(requester, groupId, epoch)` rate-limit.** `rateKey = '$requesterPeerId:$groupId:$keyEpoch'`, capped at `maxRedeliveriesPerKey` (default **1**), counted **before** delivery so a flood is capped even if delivery returns 0 (`:198-227`). Over-cap ⇒ silent `RATE_LIMITED`, sends nothing.
- **Gate #4 — re-deliver only an epoch actually held; never mint; ML-KEM-to-device.** `getKeyByGeneration(groupId, keyEpoch)` null ⇒ `EPOCH_NOT_HELD` no-op (`:214-223`). Delivery runs `distributeGroupKeyAtEpochToPeer` which **also** re-checks `getKeyByGeneration` (`rotate_and_distribute_group_key_use_case.dart:775-779`), loads the **exact** requested epoch (never `getLatestKey`), targets only the requester's deliverable devices (`:781-793`), and encrypts the key per-device with the recipient's **ML-KEM public key** into a v2 envelope (`callEncryptMessage(recipientMlKemPublicKey: device.mlKemPublicKey!, ...)`, `:1087-1124`). Deliverable devices are filtered to those holding a usable ML-KEM key (`_deliverableDevicesForRotation`/`_hasUsableMlKemPublicKey`, `:1165-1177`). The responder doc-contract explicitly forbids `group:updateKey`/`rotateAndDistributeGroupKey`/`getLatestKey` (`group_key_repair_responder_listener.dart:38-39`); `distributeGroupKeyAtEpochToPeer`'s contract forbids `generateNextKey`/`updateKey`/`saveKey`/draft-promote (`:748-757`).

Supporting: the **requester** never sends an unsigned request — `buildSignedGroupKeyRepairRequestEnvelope` returns null on sign failure and the sender degrades to log-only (`group_pending_key_repair_service.dart:118-153`, `:236-246`); the responder never throws out of the producer chain (NSE/background-safe, `:245-251`).

### (3) Residual risk

- **Rate-limit is in-memory, per-process.** `_servedByKey` resets on restart (documented, `:47-50`). A requester who can force admin restarts could re-trigger one redelivery per restart per `(requester, groupId, epoch)`. Bounded (1 per cycle, only the held epoch, only to the requester's own ML-KEM devices), but not durable.
- **The delivered key target is the requester's own membership devices**, resolved from group config — not from the request. So even a fully-valid signed request can only cause redelivery **to the requester's bound, ML-KEM-capable devices**, never to a wire-supplied address. Good. Residual: correctness of that redelivery depends on group-config device bindings being accurate (the same trust root the rest of group messaging relies on).
- **Admin-target resolution for the request** picks creator-first, then first rotate-capable member, then their first device with a non-empty transport (`_resolveAdminTransportPeerId`, `:277-310`). A stale transport peer id in config sends the request to a dead address; it falls back to relay inbox (`_sendDirectWithInboxFallback`, `:312-336`). No security loss (the request itself carries no secret), only a possible missed recovery.
- **Request carries no secret** — only `(groupId, keyEpoch, requesterPeerId, requesterDeviceId, signature)`. Interception leaks group/epoch metadata but no key material.

### (4) What an attacker can / can't do

- **A replayed (captured) request can't exfiltrate a key to a wrong device.** Even a byte-perfect replayed valid request only ever causes redelivery to the **requester's own bound ML-KEM devices** (gate #4 target resolution), encrypted to those devices' ML-KEM public keys — the attacker, lacking the requester's ML-KEM secret, cannot decrypt the v2 envelope. And the per-`(requester,groupId,epoch)` rate-limit caps redeliveries to 1/process-cycle, so replay can't even amplify traffic.
- **A non-member or removed member can't pull a key.** `getMember` returns null ⇒ `requester_not_member` (gate #2b). Forward secrecy / Finding-03 preserved: a removed member is no longer in config, so the responder refuses; even if they forged membership, gate #1 (signature against the *bound* device key) and gate #4 (epoch must be held *and* the target's devices resolved from config) block it.
- **An attacker can't make the admin mint a new epoch or substitute a different key** — both the responder and the distribute function are contractually + structurally barred from `getLatestKey`/mint and load the *exact* requested epoch only (gate #4).
- **An attacker can't forge a request** without the requester's device signing private key (gate #1, canonical-payload match + bound-key verify). A malformed/unsigned/wrong-algorithm request is rejected pre-delivery.
- **Worst-case for a valid-but-malicious member**: trigger 1 redelivery per process-cycle of an epoch they're entitled to, to their own devices — i.e., a key they already get legitimately. No escalation.

---

## Cross-cutting invariants (status)

| Invariant | Status |
|---|---|
| UDM-E: ring holds only legitimately-held epochs (no wire-injected epoch) | **HOLDS** — entries added only via `rotateGroupKeyRing`/`joinedGroupKeyInfo` from real key-ingest (`pubsub.go:799-805`, `:878-896`) |
| UDM-E: removed member never gets the NEW epoch (Finding-03 fails-closed) | **HOLDS** — never delivered ⇒ never in ring ⇒ decrypt/verify fail closed |
| UDM-E: K=5 append-evict forward-secrecy bound | **HOLDS** — `RetainedEpochKeys=5`, eviction at `pubsub.go:826-828` |
| UDM-F: future-epoch `ValidationIgnore` strictly gated, no Accept/credit | **NOT IMPLEMENTED** — current posture is Reject; intended bound documented, must be reviewed at landing |
| UDM-G: signed + member-at-epoch authz + per-(requester,groupId,epoch) rate-limit | **HOLDS** — gates #1–#3 (`responder_listener.dart:151-227`) |
| UDM-G: ML-KEM-to-device delivery; replay can't exfiltrate to wrong device | **HOLDS** — gate #4 target = requester's own config devices, v2 ML-KEM envelope (`rotate_..._use_case.dart:781-1124`) |
| UDM-G: a repair response advances NO epoch (never mints) | **HOLDS** — contracts + `getKeyByGeneration`-only (`responder_listener.dart:38-39`, `:214-223`; `rotate_..._use_case.dart:748-779`) |

---

## Open sign-off items (human decisions required)

1. **Accept the widened decrypt window (UDM-E, K=5 / no clock bound).** The legitimate decrypt window moves from "current + 1 prev, ≤30s grace" to "any of the last 5 held epochs, no time limit (rotation-count eviction only)". In low-rotation groups this is effectively unbounded in wall-clock time, and a device-at-rest compromise exposes up to 5 epochs' keys instead of 2. **Decision needed:** accept K=5, or tune `RetainedEpochKeys` / add a time-based eviction backstop. (Note `KeyRotationGracePeriod` was also widened 30s → 10m, but that now governs sign/publish only, not receive.)
2. **Accept the inbound key-pull surface (UDM-G).** This adds a new admin-side path where a signed, member-authorized request causes the admin to re-deliver a held epoch. Mitigations (sig + member-at-epoch authz + 1/cycle rate-limit + ML-KEM-to-own-devices + never-mint) are in place, but the rate-limit is **in-memory/per-process** (resets on restart) and the surface is new. **Decision needed:** accept the surface as bounded, or require a durable rate-limit / explicit admin opt-in before device rollout.
3. **Resolve the UDM-F status discrepancy.** UDM-F (future-epoch Ignore + `key_epoch_behind` + additive `messageId`) is **plan-only**, not in the tree; the future-epoch Reject is test-locked. **Decision needed:** (a) land UDM-F before relying on its no-penalty behavior, then re-run this threat review against the real diff; or (b) explicitly accept that future-epoch honest senders are still peer-penalized and rely on UDM-G as the sole recovery path for Slice 2.

## Device-matrix evidence still required

Per the Slice-2 plan §"Device matrix", **none of the following has device evidence yet** — all UDM-E/G logic above is host-`go test` / Dart-host gated only, and a `make all` + `pod install` Go rebuild is mandatory before any device proof:

- **UDM-E:** real-ML-KEM 2-device matrix (iPhone17Pro-sim + Pixel6 `21071FDF600CSC`): rotate K times; assert a message under an epoch N-rotations-ago (within K=5) **still decrypts** on a peer that held it, and a message under an **evicted (>K)** epoch **fails closed**.
- **UDM-G:** a behind-epoch member pulls the **exact** epoch → placeholder repairs on-device; confirm the responder serves only its own ML-KEM devices, never mints (`group:updateKey` absent in logs), and the per-`(requester,groupId,epoch)` cap holds across a real send/retry burst. Mirror the Finding-03 / Slice-1 proof pattern (`integration_test/group_removal_rotation_*_proof_test.dart`, `group_undecryptable_selfheal_converge_proof_test.dart`).
- **UDM-F:** **N/A until landed** — if UDM-F ships, additionally prove background >10 min → foreground recovers a future-epoch message with no permanent placeholder/duplicate, and verify the gossipsub mesh-scoring impact of Ignore-vs-Reject.
