> Part of the **[Group Chat Improvement Review](./README.md)** · Priority **P0** · [Findings appendix](./appendix-findings.md)

---

# Eliminate permanently-undecryptable messages around membership/key changes

**Priority: P0** &nbsp;|&nbsp; **Theme owner: group-chat crypto/transport** &nbsp;|&nbsp; **Effort: large (multi-layer: Go pubsub + Dart application + DB migration)**

> One-liner: Widen the grace/epoch retention, add an active key-pull, and make decryption-failure placeholders resolve or self-clear instead of sitting next to the real message forever.

---

## Why this matters (user experience)

A post-quantum messenger's core promise is that delivered messages are readable by exactly the people who should read them. The single deepest trust break is a message that is **present and readable for some members but a permanent "could not be decrypted" stub for others** — and this is precisely what happens today in the window right after a membership or key change.

The current design assumes a key rotation is observed by all members within a tight 30-second wall-clock window and that recovery is "passive" (a missing key eventually arrives via an unrelated future rotation). Mobile reality violates both assumptions constantly:

- Phones are backgrounded/offline for minutes to hours, not 30 seconds.
- `group_key_update` messages get lost or arrive out of order.
- Two membership changes can land close together.

The observable failures are:

1. **Silent live fanout drop after a change.** A member still on the previous epoch publishes; every recipient's live validator rejects it as `bad_signature_or_epoch`. The reliable send path can still place the envelope in the relay group inbox, and validation feedback can later mark the sender row failed, but the live fanout is dropped/penalized and the user can still observe a misleading transient "sent" state until durable replay or feedback catches up.
2. **Permanent unreadable placeholders.** A member who missed a key sees `Waiting for a newer group key to decrypt this message.` that **never resolves**, because nothing actively fetches the missing key.
3. **Stuck placeholder + duplicate.** After the race resolves via the live path, the user sees the stuck placeholder *and* the real message side by side.
4. **Eager terminal failure.** A single transient error during replay permanently brands a message `Message could not be decrypted.` even when the device already holds the correct key.

These are not edge cases; they are the normal-mobile-offline path. The fix is high effort in places but non-negotiable.

---

## Current behaviour & evidence

### A. 30-second wall-clock grace window (Go)

- `KeyRotationGracePeriod = 30 * time.Second` — `go-mknoon/node/config.go:46`.
- `hasKeyRotationGrace()` gates on `now.Before(keyInfo.GraceDeadline)` — `go-mknoon/node/pubsub.go:1247-1252`.
- `GraceDeadline` is stamped `time.Now().Add(KeyRotationGracePeriod)` **at the moment each receiver applies the new key** — `UpdateGroupKey` (`pubsub.go:799`) and `RefreshJoinedGroupStateIfNewer` (`pubsub.go:860`). A member who learns of the rotation late still gets only 30s relative to *its own* clock.
- The grace bound is checked in both `verifyGroupEnvelopeSignature` (`pubsub.go:1265`) and `decryptGroupEnvelopePayload` (`pubsub.go:1282`).
- Out-of-grace previous-epoch envelopes fail verification → `logPubSubValidationReject("bad_signature_or_epoch", …)` → `pubsub.ValidationReject` — `pubsub.go:1546-1547`. GossipSub treats `ValidationReject` as malicious: no re-delivery, no re-fetch, and the peer is penalized.

### B. Only one previous epoch retained in-memory (Go)

- `GroupKeyInfo` carries only `Key`/`PrevKey` (+ epochs + `GraceDeadline`) — `go-mknoon/node/group.go:61-68`.
- `UpdateGroupKey` (`pubsub.go:828-836`) and `RefreshJoinedGroupStateIfNewer` (`pubsub.go:764-776`) overwrite `PrevKey` with the immediately-prior key on each advance, discarding older epochs.
- `decryptGroupEnvelopePayload` returns `"no group key available for epoch %d"` for anything outside `{current, prev-within-grace}` — `pubsub.go:1274-1287`.
- **Mitigation already present (do not regress):** the *live* path is the only caller of `decryptGroupEnvelopePayload` (`pubsub.go:1596`). Inbox/offline replay decrypts in Dart via `getKeyByGeneration` against the persisted per-generation `group_keys` table (`group_repository.dart:62`), so historical epochs *are* retained for replay within the bounded Dart retention window (currently 8 generations: `group_key_retention_policy.dart:1`; pruning starts in `group_repository_impl.dart:383`; stale replay is skipped in `drain_group_offline_inbox_use_case.dart:1757`). The 30s/single-prev limit constrains **only the in-memory live path.**

### C. Future-epoch live message rejected (Go)

- `verifyGroupEnvelopeSignature` accepts only `env.KeyEpoch == KeyEpoch` or `== PrevKeyEpoch` within grace; a future epoch (`env.KeyEpoch > keyInfo.KeyEpoch`) falls through to `return false` → `ValidationReject` (`pubsub.go:1254-1271`, `1546-1547`). The reliable send path still stores the envelope to the relay group inbox, so it can self-heal via inbox replay — but on the live path the peer is penalized and the message is dropped.

### D. Live decrypt-fail recovery is reactive only (Go → Dart)

- On missing key / decrypt error / parse error, `handleGroupSubscription` emits a diagnostic (`group:decryption_failed` / `group:payload_parse_failed`) and `continue`s — `pubsub.go:1590-1591`, `1600-1601`, `1631-1632`. No in-Go key/config re-request.
- `emitGroupDecryptionFailed` carries `groupId/senderId/keyEpoch/error/decryptMs` (+ optional `localKeyEpoch`) and **never the ciphertext or messageId** — `pubsub.go:1690-1702`. (Its Go signature now also takes the `env` param, but the emitted event payload is unchanged — still no ciphertext/messageId.)

### E. Key-repair is fully passive; no active pull (Dart)

- Every `RequestGroupKeyRepair` callsite is wired to `emitGroupKeyRepairRequest`, which only calls `emitFlowEvent('GROUP_KEY_REPAIR_REQUESTED')` — `group_pending_key_repair_service.dart:58-69`. **It sends nothing over the wire.** A repo-wide grep for `group_key_request` / `requestMissingKey` / `key_repair_pull` returns no implementation.
- One current retry trigger fires from `GroupKeyUpdateListener._retryPendingGroupKeyRepairs` after a *new* `group_key_update` is saved (`group_key_update_listener.dart:534`), scoped to one `(groupId, keyEpoch)`. Accepted-invite materialization has a second narrow retry path; see section F.

### F. Pending repairs only retried by narrow epoch triggers — not on resume or timer (Dart)

- The repository exposes **only** `getPendingRepairsForGroupEpoch` (`group_pending_key_repair_repository.dart:20-24`); there is no `getAllPendingRepairs` / `getPendingRepairsForGroup`.
- Current retry triggers are limited to a freshly saved `group_key_update` for one `(groupId, keyEpoch)` (`group_key_update_listener.dart:534-539`) and accepted-invite materialization for one accepted group/epoch (`accept_pending_group_invite_use_case.dart:297`, `:866-869`). There is still no all-pending scan.
- `handleAppResumed` runs `rejoinGroupTopics` then `drainGroupOfflineInbox` (`handle_app_resumed.dart:159-196`); the drain only enqueues *new* repairs from inbox messages — it never re-runs already-persisted pending repairs whose key may now exist.
- No `Timer.periodic` / `retryAllPending` path exists for the repair runner.

### G. Live placeholder can never resolve, and duplicates the real message (Dart)

- `queueLiveGroupDecryptionFailureRepair` persists a placeholder + repair with `replayEnvelopeJson: null` and a **synthetic** id `live:groupId:senderId:keyEpoch:localKeyEpoch` used as both `repair.id` and `message.id` — `group_pending_key_repair_service.dart:248-310`.
- `_retryOne` short-circuits at `'waiting for replay envelope'` whenever `replayEnvelopeJson` is null — `group_pending_key_repair_service.dart:427-444`. A live placeholder can **never** decrypt via retry.
- The only supersede call is inside the durable-offline path (`queueMissingGroupReplayKeyRepairFromEnvelope` → `_supersedeLiveDiagnosticRepairForDurableReplay`, line 148, gated by `_isLiveDiagnosticRepairForSender` requiring `id.startsWith('live:')` && `replayEnvelopeJson == null`, `_supersedeLiveDiagnosticRepairForDurableReplay` lines 202-236 and `_isLiveDiagnosticRepairForSender` lines 238-246).
- The **live** receive path `_handleMessage` calls `_emitGroupMessage(result)` on success (`group_message_listener.dart:833`) but **never supersedes** the live placeholder. The real message persists under its real wire `messageId`, which never matches the synthetic `live:` id → **stuck placeholder + duplicate** whenever the real message arrives via the live/membership-flush/push-loss path rather than the durable inbox drain.

### H. Single replay failure → permanent "undecryptable" (Dart)

- `_retryOne`'s catch block (`group_pending_key_repair_service.dart:543-556`) re-queues (`recordAttempt`, return false) **only** when `key == null` AND the error string contains `'Missing group replay key'`. For **any** other error it immediately calls `_finalizeUndecryptable`, rewriting the message to `Message could not be decrypted.`
- The happy path throws `StateError('replay validation rejected')` (`:517`), `StateError('replay did not replace pending placeholder')` (`:529`), `StateError('missing reaction repository')` (`:462`), reaction rejections (`:476`) — all terminal on first occurrence even when `getKeyByGeneration` would return the key. `repair.attempts` is tracked (`group_pending_key_repair.dart:19`) but never gates the terminal transition.

---

## Root cause(s)

| # | Root cause | Layer |
|---|-----------|-------|
| R1 | Decryption/verification eligibility on the **live** path is anchored to a tight wall-clock timer + a single in-memory previous epoch, instead of to the keys the node actually holds. | Go |
| R2 | "Sender is ahead of me" (future epoch) is conflated with "sender is malicious" (`ValidationReject`). | Go |
| R3 | There is **no outbound key-fetch**: a member that misses a key never asks anyone for it. `requestGroupKeyRepair` is a log-only stub. | Dart |
| R4 | Repair retries are triggered only by narrow epoch-scoped events (a fresh `group_key_update`, or accepted-invite materialization for the accepted group/epoch). No resume sweep, no timer, no "retry all groups". | Dart |
| R5 | Live decryption-failure placeholders have **no replay envelope** (Go never sends the ciphertext) and **no reconciliation against the real message**, so they neither resolve nor self-clear. | Go + Dart |
| R6 | The terminal "undecryptable" transition fires on transient/non-crypto errors, with no attempts/backoff threshold and no distinction between "decrypt failed with correct key" and "processing hiccup". | Dart |

---

## Proposed improvements

The improvements are layered so each can land and ship independently; together they close the hole. Each notes wire/DB/migration impact.

### 1. Widen the live grace window and make it configurable (R1) — Go, effort small

- Raise `KeyRotationGracePeriod` from `30 * time.Second` to a mobile-realistic default (proposed **10 minutes**) in `go-mknoon/node/config.go:46`.
- Add a per-group override plumbed through `GroupConfig` (optional `keyRotationGraceSeconds`), falling back to the constant. This lets high-churn groups tighten and offline-heavy groups widen.
- This is a one-line stop-gap that immediately reduces silent send-drops; it does **not** fully solve the problem and must ship alongside #2.
- **Wire impact:** optional new `GroupConfig` field (backward compatible — empty = default). **No DB migration** for the constant change.

### 2. Anchor live decryption/verification to retained epoch keys, not a timer (R1, R2) — Go, effort medium

Replace the "current + single-prev-within-grace" model on the live path with a **bounded ring of recent epoch keys** keyed by epoch.

- Extend `GroupKeyInfo` (or add a sibling map on `Node`) to hold the last **K = 5** generations: `map[int]string` epoch→key, plus `KeyEpoch` as the current. Update `UpdateGroupKey` (`pubsub.go:828-836`) and `RefreshJoinedGroupStateIfNewer` (`pubsub.go:764-776`) to **append** rather than overwrite, evicting only the oldest beyond K.
- `decryptGroupEnvelopePayload` (`pubsub.go:1274-1287`) and `verifyGroupEnvelopeSignature` (`pubsub.go:1254-1271`): allow **decrypt + verify of any retained epoch** the node holds, regardless of `GraceDeadline`. Security is enforced by the existing membership/permission check (`isAllowedWriter`, device-signature verify), **not** by the timer.
- Keep the grace timer only to constrain which epoch a node will **sign/publish** under (so the network converges forward), per the verifier's recommendation.
- **For future epochs (R2):** when `env.KeyEpoch > keyInfo.KeyEpoch` and the envelope is structurally plausible, return `pubsub.ValidationIgnore` (not `Reject`) so GossipSub does not penalize the peer, and emit a dedicated `group:key_epoch_behind` event (groupId + needed epoch) so Dart can trigger a key/config refresh. Optionally buffer the raw envelope keyed by epoch and re-process once `UpdateGroupKey` advances. (`pubsub.go:1254-1271`, `1546-1547`.)

### 3. Implement an actual outbound key-repair pull (R3) — Dart + relay, effort large

Turn `requestGroupKeyRepair` from a log stub into a real on-demand pull. Add a new signed P2P/inbox message type:

```
group_key_repair_request  { groupId, keyEpoch, requesterPeerId, requesterDeviceId, sig }
```

- **Requester side:** when a pending repair is created/retried and `groupRepo.getKeyByGeneration(groupId, epoch)` returns null, send the signed request to the group **admin(s)** (and/or the message's `senderPeerId`) via the existing `_sendDirectWithInboxFallback` store-and-forward path. Keep `emitGroupKeyRepairRequest` as the diagnostics-only default, but wire production to a new `sendGroupKeyRepairRequest` implementation.
- **Responder (admin) side:** handle it as a **targeted re-run of `_distributeRotatedKeyToDevice`** for that epoch, reusing the saved `GroupKeyInfo` for that generation — never minting a new epoch, just re-delivering the requested one to the requesting device binding.
- Guard with membership/permission checks (only deliver an epoch's key to a peer who was a member at that epoch) and rate-limit per `(requester, groupId, epoch)`.
- **Wire impact:** new envelope type + new admin-side handler. **No DB migration** (reuses `group_keys`).
- **Affected:** `group_pending_key_repair_service.dart`, `group_key_update_listener.dart`, `group_message_listener.dart`, `lib/main.dart` (replace the `emitGroupKeyRepairRequest` wiring at `:1788,1800,1900,1929,1988,3123,3252` — 7 callsites), `startup_router.dart:604`, and `prepare_notification_route_target_use_case.dart:47`, plus a new incoming handler use case.

### 4. Retry pending repairs on resume, after rejoin, and on a bounded timer (R4) — Dart, effort medium

- Add to the repository interface (`group_pending_key_repair_repository.dart`): `getAllPendingRepairs({int limit})` and/or `getPendingRepairsForGroup(String groupId)`, with the corresponding DB-helper query (`SELECT … WHERE status = 'pending_key'`). Existing DB access is group/epoch scoped (`group_pending_key_repairs_db_helpers.dart:67`) and existing indexes are group/epoch-led (`063_group_pending_key_repairs.dart:26`), so a global all-pending sweep should add a status-leading index/migration rather than relying on the current index shape.
- In `handleAppResumed` (`handle_app_resumed.dart`), **after** `rejoinGroupTopics` and `drainGroupOfflineInbox` (around `:159-196`), enumerate all pending repairs and call the runner's `_retryOne` for each where `groupRepo.getKeyByGeneration` now returns a key. This catches the "key arrived via a path other than a fresh `group_key_update` for that exact epoch" case.
- Add a bounded backoff `Timer` in the runner (e.g. retry online-created repairs at 5s, 30s, 2m, capped) so a repair gets a few attempts without waiting for a new key update or a resume.
- **DB impact:** new read query plus a status-leading index/migration if the implementation chooses a global `getAllPendingRepairs` sweep. No destructive schema change.

### 5. Supersede live placeholders from the real-message path + give them a TTL (R5) — Go + Dart, effort medium

Two complementary fixes:

- **(a) Dart — reconcile on live persist (the precise gap):** in `group_message_listener._handleMessage`, after a successful `_emitGroupMessage(result)` (`group_message_listener.dart:833`), call a supersede that deletes any `live:` pending-key placeholder/repair for the same `groupId + senderPeerId + keyEpoch`. Reuse `_supersedeLiveDiagnosticRepairForDurableReplay` logic (`group_pending_key_repair_service.dart:202-236`) but drive it from the live path, not only the durable-replay path. This removes the stuck-placeholder-plus-duplicate outcome. (Note: a new diagnostic hook `_requestReceivedMessageKeyRepairIfLocalEpochIsBehind` (`group_message_listener.dart:896-944`) already fires right after this live persist at `:834` when an incoming message's `keyEpoch` is ahead of the local latest key — but it routes to the **same log-only `emitGroupKeyRepairRequest` stub**, so proposal #3 should be framed as 'replace the stub that this new trigger already calls'.)
- **(b) Go — make live diagnostics privacy-safe and actionable:** add the wire `messageId` to `group:decryption_failed` (`emitGroupDecryptionFailed`, `pubsub.go:1690-1702`) while preserving the existing privacy contract that diagnostics do **not** include plaintext, keys, ciphertext, nonce, or signature (`pubsub_decryption_failure_test.go:283-292`). Note the function's Go signature already takes the `env` param, so this proposal is 'populate a safe event payload from the `env` it already receives' rather than 'thread `env` into the function'. `messageId` lets Dart dedupe/supersede live placeholders and route active key-pull requests against the eventual real message. If a future session wants fully replayable live diagnostics, that must be an explicit privacy-reviewed extension with updated Go privacy tests; do not silently add ciphertext to this diagnostic event.
- **(c) Fallback TTL:** for any live placeholder that still has no replay envelope, after a bounded TTL have the resume/timer sweep mark it self-cleared (delete, not "undecryptable") rather than looping forever — a missing-key diagnostic with no ciphertext should not become a permanent gravestone.
- **Wire impact:** `group:decryption_failed` gains an optional `messageId` field (additive, backward compatible). Any encrypted-envelope diagnostic field is out of scope unless the future implementation explicitly updates the privacy contract and tests.

### 6. Make "undecryptable" terminal only on confirmed-cryptographic failure after bounded attempts (R6) — Dart, effort small

Rework `_retryOne`'s catch block (`group_pending_key_repair_service.dart:543-556`):

- Classify the caught error: **crypto/auth failure with the correct key present** (`getKeyByGeneration != null` AND the error is a genuine decrypt/auth/MAC failure) is the *only* terminal class.
- Everything else — `StateError('replay validation rejected')`, `'replay did not replace pending placeholder'`, `'missing reaction repository'`, bridge/StateError/processing hiccups, or key-still-missing — is **retryable**: `recordAttempt` and keep the repair pending so resume/timer/key-pull can re-run it.
- Gate the terminal transition additionally on `repair.attempts >= N` (e.g. N = 5) for the crypto-failure class, so even a true decrypt failure gets a few attempts (covers a transient bridge fault that *looks* cryptographic).
- This converts "branded undecryptable on first hiccup" into "retried until genuinely unrecoverable".

---

## Affected files & components

| File | Change | Improvement(s) |
|------|--------|----------------|
| `go-mknoon/node/config.go` | Raise/parametrize `KeyRotationGracePeriod` (`:46`) | 1 |
| `go-mknoon/node/group.go` | Extend `GroupKeyInfo` to retain a ring of K epoch keys (`:61-68`) | 2 |
| `go-mknoon/node/pubsub.go` | Retained-epoch decrypt/verify (`:1254-1287`); future-epoch → `ValidationIgnore` + `group:key_epoch_behind` (`:1546-1547`); append-not-overwrite in `UpdateGroupKey`/`RefreshJoinedGroupStateIfNewer` (`:799`, `:860`); add privacy-safe `messageId` to `group:decryption_failed` (`:1690-1702`) | 1, 2, 5b |
| `lib/features/groups/application/group_pending_key_repair_service.dart` | Real outbound pull; live-path supersede; TTL self-clear; classify-and-bound `_retryOne` finalize (`:427-580`) | 3, 5a/c, 6 |
| `lib/features/groups/application/group_message_listener.dart` | Supersede live placeholder after real persist (`:833`); handle `group:key_epoch_behind` | 5a, 2 |
| `lib/features/groups/application/group_key_update_listener.dart` | Trigger pull when retry finds key still missing (`:534`) | 3, 4 |
| `lib/features/groups/domain/repositories/group_pending_key_repair_repository.dart` + DB helpers | Add `getAllPendingRepairs` / `getPendingRepairsForGroup` | 4 |
| `lib/core/lifecycle/handle_app_resumed.dart` | Sweep all pending repairs after rejoin/drain (`:159-196`) | 4 |
| `lib/main.dart`, `lib/.../startup_router.dart`, `lib/features/push/application/prepare_notification_route_target_use_case.dart` | Replace `emitGroupKeyRepairRequest` wiring with production pull (`main.dart:1788,1800,1900,1929,1988,3123,3252`; `startup_router.dart:604`; `prepare_notification_route_target_use_case.dart:47`) | 3 |
| **New:** incoming `group_key_repair_request` handler use case + admin re-distribute | Targeted re-run of `_distributeRotatedKeyToDevice` | 3 |

---

## Test & verification strategy

### Unit tests (Go)
- `pubsub` table tests: rewrite the current grace-window expectations so a previous-epoch envelope is **decryptable/verifiable beyond 30s** as long as the key is retained (the current `pubsub_key_rotation_grace_test.go:63` negative test should become "evicted/unretained epoch rejects", not "deadline expired rejects"); eviction past K generations correctly rejects.
- Future-epoch envelope returns `ValidationIgnore` (not `Reject`) and emits `group:key_epoch_behind`.
- `UpdateGroupKey` / `RefreshJoinedGroupStateIfNewer` append into the ring and evict oldest only.
- `group:decryption_failed` diagnostics may include `messageId`, but must continue to exclude plaintext, keys, ciphertext, nonce, and signature (`pubsub_decryption_failure_test.go:283-292`).

### Unit tests (Dart)
- `_retryOne` matrix: transient/non-crypto error → repair stays pending (not finalized); crypto failure with key present + attempts ≥ N → undecryptable; key missing → re-queued.
- Live placeholder supersede: real message via `_handleMessage` deletes the `live:` placeholder and finalizes its repair (no duplicate). Keep the durable replay supersede tests separate from the missing live-real-message supersede case.
- No-envelope live placeholder TTL: a `live:` repair without `replayEnvelopeJson` self-clears after the bounded TTL instead of looping forever or becoming `undecryptable`.
- Outbound pull: missing key triggers a signed `group_key_repair_request`; requester uses direct/inbox fallback; admin handler verifies membership-at-epoch, re-delivers the exact epoch, does not mint a new one, and rate-limits repeated requests.
- Resume/timer sweep: DB/helper/repo tests cover `getAllPendingRepairs`/group-scoped scans; persisted pending repair whose key now exists is repaired after `handleAppResumed` rejoin/drain; fake-clock tests cover bounded timer/backoff.

### Integration harnesses (`integration_test/`)
- Extend `group_recovery_e2e_test.dart` and the multi-device real harnesses (`group_multi_device_real_harness.dart`, `group_multi_party_device_real_harness.dart`, `group_invite_status_matrix_harness.dart`) with:
  - **Offline-across-rotation:** member offline > grace, comes back, missed message becomes readable (no permanent placeholder, no duplicate).
  - **Double-rotation under churn:** two membership changes close together; messages under the intermediate epoch remain readable.
  - **Future-epoch live race:** sender ahead, receiver behind; message self-heals once the key arrives, peer not penalized.
  - **Active-pull path:** drop the `group_key_update`, assert the requester pulls and the admin re-delivers.

### Device matrix & Test-Flight gates
- Add scenarios to the notification/recovery matrices (`Test-Flight-Improv/52-notification-journey-test-matrix.md`, `Group-Chat-Feature/test-inventory.md`) and a gate in `test-gate-definitions.md`: **"zero permanently-undecryptable messages after a membership change"** across the iPhone13 / Pixel6 two-device matrix, including background > 10 min then foreground.
- Greppable FLOW assertions: presence of `GROUP_PENDING_KEY_REPAIR_REPAIRED` and `GROUP_LIVE_DECRYPTION_REPAIR_SUPERSEDED`, and **absence** of lingering `GROUP_PENDING_KEY_REPAIR_WAITING_FOR_REPLAY_ENVELOPE` / `GROUP_PENDING_KEY_REPAIR_UNDECRYPTABLE` after convergence.

### Acceptance / regression gates for rollout handoff

| Gate | Required coverage |
|------|-------------------|
| Focused Dart unit/widget | `dart test`/`flutter test` on the group pending-key repair service, group message listener, group key update listener, pending-key repair DB helper/repository tests, and handle-app-resumed lifecycle tests touched by the implementation. |
| Focused Go | `go test ./node -run 'KeyRotation|Epoch|DecryptionFailed|Validation'` (or the exact new/renamed tests) plus any new requester/admin key-repair tests under `go-mknoon`. |
| Existing named group gate | `scripts/run_test_gates.sh groups` currently covers seven host group integration files (`scripts/run_test_gates.sh:51-59`); keep it green after the focused tests. |
| Matrix docs | Update `Group-Chat-Feature/test-inventory.md`, `test-gate-definitions.md`, and the notification/recovery matrix rows with the new zero-permanent-undecryptable gate. |
| Completeness/static | Run the repo completeness check used by the rollout pipeline and `git diff --check` before closure. |
| Manual/device | iPhone13 + Pixel6 two-device background/resume scenario: member offline beyond the widened grace, missed key update, foreground, no permanent placeholder and no duplicate after convergence. |

---

## Risks, trade-offs & rollout

| Risk / trade-off | Mitigation |
|------------------|------------|
| **Longer grace + retained keys widen the window where a removed member could still decrypt traffic encrypted under an epoch they held.** This is the central security trade-off. | Retention only allows decrypting epochs the member **already legitimately had**; forward secrecy after removal is preserved because the *new* epoch's key is never delivered to them, and #3's admin handler enforces "member-at-that-epoch" before re-delivering. Bound K small (5) and the grace to ~10 min, not unbounded. Document the threat-model delta explicitly. |
| **`ValidationIgnore` instead of `ValidationReject` for future epochs could reduce spam protection.** | Only applied when the envelope is structurally plausible and from a known member device; genuinely malformed/unauthorized envelopes still `Reject`. |
| **Active key-pull adds attack surface / amplification** (a malicious member spamming repair requests). | Sign requests; rate-limit per `(requester, groupId, epoch)`; admin only re-delivers epochs the requester was entitled to. |
| **Go struct change (`GroupKeyInfo` ring) requires `gomobile bind` rebuild** (`make all` + `pod install`). | Standard Go build flow; covered by existing build memory. No app-side persisted format depends on the in-memory ring. |
| **New `group_key_repair_request` wire type and additive `group:decryption_failed.messageId` field** must stay backward compatible during staged rollout. | All additions are optional/additive; older peers ignore unknown fields. The pull is best-effort — old admins simply won't answer, falling back to today's passive behaviour (strictly no worse). Preserve the diagnostic privacy test unless a later privacy-reviewed encrypted-envelope design explicitly changes it. |
| **DB query additions** (`getAllPendingRepairs`). | Read-only query plus a status-leading index if using a global sweep. No destructive migration. |

**Rollout order (each independently shippable, lowest-risk first):**
1. #1 grace-window bump + #6 finalize-classification (Dart-only, tiny, immediate relief).
2. #5a live-path supersede (kills the visible duplicate, Dart-only).
3. #4 resume/timer retry sweep (Dart + read query).
4. #2 retained-epoch live decrypt + future-epoch `Ignore` (Go rebuild).
5. #5b/c messageId-in-diagnostic + TTL (Go + Dart).
6. #3 active pull (largest; admin + requester + new wire type).

---

## Effort estimate

| Improvement | Effort | Layer |
|-------------|--------|-------|
| 1. Wider/configurable grace | Small | Go |
| 2. Retained-epoch live decrypt + future-epoch `Ignore` | Medium | Go |
| 3. Active outbound key-pull + admin re-distribute | **Large** | Dart + relay + new wire type |
| 4. Resume / rejoin / timer retry sweep | Medium | Dart + DB read query |
| 5. Supersede live placeholders + privacy-safe diagnostics + TTL | Medium | Go + Dart |
| 6. Bounded, classified "undecryptable" finalize | Small | Dart |

**Overall: large.** Items 1, 5a, and 6 are small/medium and deliver immediate user-visible relief (no more 30s cliff, no more duplicate, no more first-hiccup gravestone). Item 3 (active pull) is the largest single piece and the one that makes recovery truly robust rather than reactive; it should be sequenced last but is required to fully close the "permanently undecryptable" gap for the no-replay-envelope case.

---

## Handoff notes for `$implementation-doc-rollout-orchestrator`

This document is intended to be decomposed later, not implemented in this review session. The future decomposition should preserve these session boundaries so each slice can be planned, executed, and closed independently.

| Suggested session | Scope | Must prove before closure |
|-------------------|-------|---------------------------|
| UDM-001 Go live epoch eligibility | Configurable grace, retained epoch ring, retained-key verify/decrypt, eviction semantics | Old `pubsub_key_rotation_grace_test.go` deadline-negative behavior is replaced by retained-vs-evicted assertions; existing live-path accept/reject tests stay green. |
| UDM-002 Future-epoch live race | `ValidationIgnore` for plausible future epochs, `group:key_epoch_behind` diagnostic, no peer penalty | Future-epoch table test proves ignore + diagnostic; malformed/unauthorized envelopes still reject. |
| UDM-003 Active key-pull wire path | Signed requester message, direct/inbox fallback, admin handler, member-at-epoch authorization, rate limiting | Requester/admin tests prove exact-epoch re-delivery and no new epoch minted; old `emitGroupKeyRepairRequest` wiring is replaced everywhere listed above. |
| UDM-004 Resume/timer retry sweep | Repository/DB scan APIs, status-leading index if global, resume ordering after rejoin/drain, bounded timer/backoff | DB/repo tests cover scan ordering/limits; lifecycle and fake-clock tests prove pending repairs rerun without a new key update. |
| UDM-005 Live placeholder reconciliation | Live real-message supersede, privacy-safe `messageId` diagnostic, no-envelope TTL self-clear | Live `_handleMessage` test deletes `live:` placeholder and repair; diagnostic privacy tests still exclude ciphertext/nonce/signature/keys; FLOW absence assertions pass after convergence. |
| UDM-006 Bounded undecryptable finalization | Error classification and attempts threshold in `_retryOne` | Matrix proves transient/processing errors remain pending, key-missing requeues, and only confirmed crypto/auth failure after N attempts becomes `undecryptable`. |
