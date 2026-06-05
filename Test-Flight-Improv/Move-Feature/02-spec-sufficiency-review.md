# Spec Sufficiency Review — Move Account To A New Device

**Reviewed document:** `Test-Flight-Improv/Move-Feature/01-move-account-to-new-device-pr.md`
**Date:** 2026-06-04
**Method:** Multi-agent codebase audit (30 agents): 12 subsystem explorers + 5 cross-cutting critics, each with an adversarial verify pass that re-opened cited files, plus a synthesis pass. 121 candidate gaps raised, **121 survived verification**. Every finding below cites code that was actually opened, not the spec's own "Evidence:" lines.

---

## Verdict: `needs-revision`

The spec is **exceptionally thorough on the hard part most specs get wrong** — the cutover state machine and the "never two active devices" invariant. But it has a **load-bearing factual blind spot**: its single manifest-completeness mechanism — *"enumerate every secure-storage key referenced by database rows"* (line 85) — **provably enumerates almost nothing**, because almost no secret is referenced by a DB row. Combined with two inaccurate current-state claims (it targets WAL journal mode when the DB runs in DELETE mode; it treats whole-file AES helpers as a usable building block when they load the entire file into memory), a *literal* implementation of this spec risks **undecryptable media, broken push decryption, lost social-feed data, and a torn DB snapshot** — while passing the spec's own acceptance tests.

These are fixable with spec edits, not a redesign. The cutover/invariant scaffolding is sound; the gaps are about **completeness of the inventory** and **feasibility of three reused primitives**.

---

## What the spec gets right (keep these)

1. **Cutover/handoff invariants are rigorous.** Lines 104–123 enumerate every interruption ordering (before/after durable old-migrated-out, before/after commit), assert the core invariant *"no state where both devices can start normal P2P"* (line 112), and add the zero-active-device fallback (line 113). This is the part of migration most likely to create two active devices, and the state-machine reasoning is correct.
2. **The central product premise is accurate.** Mnemonic restore is *not* a full move because `restore_identity_use_case.dart` calls `callMlKemKeygen()` fresh and stores **new** ML-KEM material. Verified.
3. **Transport stance is correct.** Forbidding relay/cloud/iCloud for the bundle, and noting (line 32) that the bundle "still needs its own encrypted session" rather than naively trusting the existing local transport — verified that the existing local transport is fully plaintext (`ws://` + `http://`).
4. **Relay/push competition rationale is correct.** `go-relay-server/push_token_store.go` stores tokens `map[string]tokenEntry` keyed by peerId; rendezvous/inbox are peerId-keyed. The line-37 reasoning for why two active phones would compete is accurate.
5. **Named primitives that DO exist are cited correctly:** `db_encryption_key` (`encrypted_db_opener.dart:9`), the three identity secret keys, the relative media path prefixes `media/`, `post_media/`, `pending_uploads/`.
6. **Test-matrix scaffolding is comprehensive.** The Release-Blocking, Simulator, and Existing-Coverage-Gaps sections already name most categories an implementer must prove — which makes the gaps below *additive* rather than structural.

---

## P0 — must fix before this spec goes to implementation

### P0-1. The manifest discovery rule enumerates almost nothing
The load-bearing completeness mechanism (line 85) is *"every secure-storage key referenced by database rows."* But **only two key families are row-referenced**: `secure:media_attachment_encryption_key:<id>` and `secure:group_key_material:<id>:<gen>`. Every other secret is a **fixed string constant referenced by no row** and named nowhere in the spec:
- `secrets_migrated` (sentinel) — `migrate_secrets_to_secure_storage.dart:11`
- `push_fcm_token`, `push_fcm_platform` — `push_token_store_impl.dart:4-5`
- `background_preference`, `image_quality_preference`, `video_quality_preference`
- the two iOS App-Group keychain mirror families (see P0-2)

`db_encryption_key` and the 3 identity secrets are saved only because the spec *also* names them explicitly — the **rule itself finds none of them**. An implementer following the rule literally builds an under-complete manifest.
**Fix:** Replace the discovery rule with *"enumerate the full secure-storage namespace across **both** keychain access groups and classify each key,"* and list every non-row-referenced key explicitly. (Affects lines 85, 89.)

### P0-2. The iOS App-Group SHARED keychain mirror is omitted → push decryption silently breaks
On iOS the app maintains a **second keychain partition** in Apple Access Group `group.com.mknoon.app.share` (constructed iOS-only at `main.dart:310-312`, injected into `IdentityRepositoryImpl` and `GroupRepositoryImpl`). It mirrors `identity_ml_kem_secret_key` on every load/save, and **every group key under a *different* name** `group_key:<rawGroupId>:<generation>` (no `secure:` prefix, **not** URI-encoded — so the name cannot be derived by string-transforming the DB reference). The iOS **Notification Service Extension** reads exactly these items to decrypt push payloads (`NotificationPreviewResolver.swift:332-363`).

None are row-referenced, so a manifest built from DB references copies **zero** shared-group items. Result: the migrated phone decrypts *foreground* messages but the NSE **cannot decrypt incoming 1:1 or group push** until the next key rotation re-mirrors — a silent degradation the spec's verification invariants would not catch.
**Evidence:** `flutter_secure_key_store.dart:5,17-24`; `main.dart:310-312,632,974,976`; `identity_repository_impl.dart:162-180`; `group_repository_impl.dart:11-12,463-490`; `ios/NotificationService/NotificationPreviewResolver.swift:332-363`.
**Fix:** Manifest must enumerate and migrate the shared access group. The iCloud-Keychain invariant (line 99) must independently verify *its* accessibility/backup behavior too.

### P0-3. db_encryption_key ordering + `secrets_migrated` sentinel must be made explicit
Post-migration the identity row has **NULL secret columns** (secrets live only in secure storage). On first launch the new app opens the encrypted DB **before** migrating secrets. Two ordering hazards:
1. If `db_encryption_key` isn't imported **before** `openEncryptedDatabase`, the opener generates a **brand-new random key** (`encrypted_db_opener.dart:40-44`) and either fails to open the imported DB or encrypts an empty one → **data loss**.
2. `migrateSecretsToSecureStorage` fast-exits on the `secrets_migrated` sentinel (line 23) and **sets the sentinel even when secret columns are NULL** (lines 44, 83). If the DB (NULL secrets) is presented before secrets are committed, migration copies nothing, sets the sentinel, and `loadIdentity` returns null **forever** → un-loadable identity.

The spec lists `db_encryption_key` but never specifies the required order: **db-key import → DB open → secret import → sentinel carry**.
**Fix:** Add the strict ordering + sentinel handling to lines 94, 100–103.

### P0-4. DB consistency invariant targets WAL, but the DB runs in DELETE journal mode
Line 86 is premised on WAL (*"checkpoint and quiesce writes"*). But the app **never sets `PRAGMA journal_mode`** (zero hits in `lib/`) and the iOS `sqflite_sqlcipher` plugin doesn't enable WAL on open → SQLite uses its **DELETE/rollback-journal default**. There are no `-wal`/`-shm` sidecars at rest, so a "checkpoint WAL" step is a **no-op giving false assurance**. The real hazard is copying `identity.db` while a DELETE-mode write txn is in flight (transient `identity.db-journal`). The **correct primitive** — `sqlcipher_export` to a fresh encrypted file, *already used* at `encrypted_db_opener.dart:126,148` — is never mentioned.

Compounding this: the DB lives under **`getDatabasesPath()`** (`identity.db`), a **separate root** from `getApplicationDocumentsDirectory()` where media lives. "Copy the documents directory" misses the DB entirely; the spec never states the two-root split.
**Fix:** Mandate `sqlcipher_export` (or proven consistency) rather than WAL checkpointing; state the two distinct base directories. (Affects lines 86–88, 186, 225.)

### P0-5. Must copy ALL retained group-key generations (up to 8) + pending rotation drafts, not just current
"Required group keys" (line 85) is never quantified. Per group there are **up to 8 live generations** (`group_key_retention_policy.dart:1`, retention=8), each present in **both** keychain stores, **plus** uncommitted drafts in `group_key_rotation_drafts` (migration 070). Historical group messages decrypt by their **specific stored `key_generation`** via `getKeyByGeneration`, not the latest. If export copies only `getLatestKey()` material — the natural mistake, and exactly what `rejoinGroupTopics` does (`rejoin_group_topics_use_case.dart:102`) — every pre-rotation message and queued offline-replay envelope becomes **permanently undecryptable** while the UI claims full history migrated.
**Evidence:** `group_repository_impl.dart:383-414,463-490`; `drain_group_offline_inbox_use_case.dart:1552`; `group_offline_replay_envelope.dart:288-289`.
**Fix:** Manifest must enumerate every `(groupId, generation)` from `group_keys` **and** `group_key_rotation_drafts`, mirror both keychains, and checksum each generation's **resolved bytes** (not the reference strings).

### P0-6. Old-phone gating list omits GossipSub subscriptions, rejoinGroupTopics, and per-group discovery loops
The gating list (lines 122–123) — send/receive/retry/upload/local-discovery/inbox-drain/push/rendezvous — omits the group real-time surfaces:
- **Live GossipSub topic subscriptions** (the node receives/validates while subscribed).
- **`groupPeerDiscoveryLoop` goroutines**, started inside `joinGroupTopic` and stopped only by `LeaveGroupTopic`/`StopNode` (`go-mknoon/node/pubsub.go:194,201,240-242`) — "skip rendezvous-registration" does **not** stop an already-running loop.
- **`rejoinGroupTopics`**, re-driven from app-resume **and push handlers**, which would **re-subscribe** a migrated-out account to all topics.

Critically, **no per-account active/migrated-out gate exists anywhere** (0 grep hits for `migratedOut`/`activeAccount`/`networkBlocked` in `lib/`) for any entry point to observe. Blocking only the named surfaces leaves the old phone an active group pubsub peer — violating line 112.
**Fix:** Lines 122–123 must add GossipSub leave/unsubscribe, suppression of `rejoinGroupTopics` from **all** callers (startup, resume, push, retrier), and cancellation of discovery-loop goroutines — and the spec must introduce a **persisted per-account active/migrated-out state** (none exists today).

### P0-7. DB scope omits the entire Posts/social-feed and introductions subsystems
The DB has **56 `CREATE TABLE` statements (~51 distinct tables)**. The in-scope wording (line 49) lists only "message history, contacts, groups, media metadata." A literal reading omits:
- The **Posts/social-feed subsystem** (~22 tables: `posts`, `post_passes`, `post_recipients`, `post_media_attachments`, `post_comments`, `post_reactions`, `post_pins`, `post_privacy_state`, …) — which has its **own media tree under `post_media/`**.
- **Introductions** (`introductions`, `introductions_new`, `introduction_outbox_deliveries`, `pending_introduction_responses`) and `inbox_staging_entries`.
- ~14 group sub-tables beyond `groups`/`group_messages`.

Copying the whole DB file captures all tables — **but** the manifest *verification* and the per-category test matrix (which assert only messages/contacts/groups/media) will **pass while silently losing social-feed and introductions data**, and any selective export would drop them. The second media root `post_media/` is also never named.
**Fix:** Enumerate all tables and **both** media trees in the in-scope list (line 49) and test matrix (lines 165, 273).

### P0-8. QR payload has no version/type discriminator and no single-use/replay primitive
Two coupled gaps:
1. The contact QR payload has **no version/type/kind field**, and the scanner hands every raw string to a hardcoded contact-add path (`qr_scanner_wired.dart:136-154,199-217` → `addContact` + `sendContactRequest` + `downloadProfilePicture`). Adding a migration QR safely **requires** a discriminator and forking the **shared** scanner dispatch — directly contradicting the regression "contact QR behavior unchanged" (line 208) and non-goal "no broad redesign of the contact QR flow" (line 136).
2. The spec requires a "single-use, expiring, authenticated migration session" (line 75) and rejection of reused QR (lines 80, 178), but **nothing tracks QR consumption** — this machinery must be built from scratch.
3. The new phone has **no identity yet** (import runs only when no active account exists, line 81), so it **cannot sign** a pairing QR via `buildQRPayload` (which returns `noIdentity` when `identity==null`). The new-phone QR authentication model is undefined.

**Fix:** Scope a payload-type discriminator, acknowledge the scanner dispatch must change, specify the single-use store, and define how the identity-less new phone authenticates its QR.

### P0-9. AES helpers load whole files into memory; transport has no chunking/resume/encryption
The spec requires the whole bundle (full DB + all media) E2E-encrypted (lines 49, 85, 164, 221) and frames the bridge's AES-GCM file helpers (line 33) as a building block. But:
- **Whole-file in memory:** `go-mknoon/crypto/file_crypto.go:35,50-55,58` does `os.ReadFile` → `gcm.Seal(nil, …)` over the full buffer → `os.WriteFile`. For a GB bundle, plaintext + ciphertext are both fully resident (2–3× bundle size in the Go heap) → **iOS jetsam kills the app**. A streaming/chunked AEAD must be built.
- **No resume:** the local transport is a **single HTTP PUT** of one file (`local_media_sender.dart:117-123`, full `Content-Length`, no `Range`, no offset, no resume token). On interruption the receiver deletes the temp file and restarts from byte 0. For a minutes-long GB transfer across an iOS lifecycle, interruption is near-certain — yet the spec implies resume (lines 181–184, 199, 246). Zero hits for `range|resume|offset|checkpoint|partial` in `lib/core/local_discovery`.
- **Plaintext + MIME allowlist:** transport is `ws://`/`http://` with the bearer token in the plaintext WS offer; `LocalMediaServer` rejects any MIME outside `image/`,`video/`,`audio/`,`application/pdf` (`local_media_server.dart:86-96`) — it would **reject an opaque encrypted bundle**.

**Fix:** Design a streaming/chunked AEAD bundle format, a resume/segment-manifest protocol, an authenticated encrypted session over the sockets, and a non-media transfer endpoint. Only mDNS discovery + the bound listener are reusable.

---

## P1 — important; resolve before implementation lands

1. **Local push tokens** (`push_fcm_token`/`push_fcm_platform`) are device-bound; spec never says migrate/clear/re-register. Carrying the stale token points the relay's per-peerId token at the dead device. *Recommend: do not carry; force fresh registration on the new phone.* (`push_token_store_impl.dart:4-5`.)
2. **No schema/app-version compat mechanism exists** for the "unsupported future schema fails before commit" invariant (lines 91–93). Only `version:73` exists; no stored app version, no manifest `schemaVersion`, no `onDowngrade` (default **throws**). Net-new mechanism required. (`main.dart:319`; `encrypted_db_opener.dart:26-32`.)
3. **"Paths are relative and portable" is only partly true** (line 30). `uploadMedia` rewrites to relative only when `mediaFileManager` is non-null; the fallback stores the **raw absolute** OS/gallery path into `media_attachments.local_path` (`upload_media_use_case.dart:199,236`). Such rows point at non-existent files after migration → silent media loss.
4. **Per-attachment decryption needs 3 pieces across 2 stores**: secure-storage key **+** plaintext `encryption_nonce` **+** `encryption_scheme` (in-DB columns). `_hydrateRow` silently nulls the key if absent; `download_media` force-unwraps → undecryptable-but-present media with no error. (`media_attachment_repository_impl.dart:234-269`.)
5. **DB root ≠ media root** (restates the P0-4 corollary as its own scope item): `identity.db` under `getDatabasesPath()`, media under `getApplicationDocumentsDirectory()`. Staging/copy code must handle two roots; `-journal` sidecars live with the DB.
6. **`media/avatars/` and `media/group_avatars/` have NO DB blob fallback.** `contact_model` stores only `avatar_path`/`avatar_version`, no blob (`contact_model.dart:24,100-101`). A row-driven manifest built from the 3 listed dirs silently drops **all contact/group avatars**.
7. **Video thumbnails (`.thumb.jpg`) are on-disk-only with no DB row** (`video_thumbnail_cache.dart:17-21`). A row-driven copy drops them; spec doesn't classify them as regenerable.
8. **Test gap:** no test asserts all retained group-key generations + push-mirror keys survive export/import and multi-epoch history stays decryptable. The likely real bug (copy-latest-only) passes every currently-listed test.
9. **Existing QR expiry is FAIL-OPEN and replayable** (`parse_qr_payload_use_case.dart:92-111`): a malformed/absent `ts` is *accepted*; the signature authenticates the minting identity, not a session, and is replayable within 24h. Reusing it for export authorization is a security regression.
10. **Migration QR field-set conflict:** `parseQRPayload` hard-requires `pk/ns/rv/ts/sig`; a migration QR needs different fields (session id, ephemeral pubkey, LAN endpoint) → separate parser or touching the contact gate. Plus the identity-less new phone can't sign via `buildQRPayload`.
11. **`LocalMediaServer` reuse is blocked** for an opaque bundle: MIME allowlist rejects `application/octet-stream`; `persistMedia` routes into `media/<contactPeerId>/` (chat semantics). A migration-specific endpoint is required.

---

## P2 — minor; worth a line in the spec

1. **Three preference keys** (`background_preference`, `image_quality_preference`, `video_quality_preference`) are missed by the row scan — UX degradation, not corruption. Spec promises "local account data" (lines 49, 118, 145) but doesn't list them.
2. **Keychain accessibility doc-comment is wrong** (`flutter_secure_key_store.dart:10-11` says `WhenUnlocked`; code uses `first_unlock_this_device` = `AfterFirstUnlockThisDeviceOnly`). The non-syncing/`ThisDeviceOnly` property **holds** (good for the line-99 invariant), but `AfterFirstUnlock` means staged secrets are readable while locked and **persist across reboots until explicitly deleted** — relevant to the line-98 cleanup requirement.
3. **Contact-add side effects fire unconditionally** in the scanner (`qr_scanner_wired.dart:199-217`). A misrouted migration QR could pollute contacts and emit a P2P contact request. Spec covers only one direction (contact QR not authorizing export), not the reverse. Needs a type guard before any side-effect path.
4. **Transient artifacts** (`.enc`, `.download.jpg`, `.raw.*.jpg`) inside the media tree could be carried into the bundle on a wholesale `media/` copy — bloat + potential ciphertext leak. Needs an explicit exclude/cleanup rule (relates to line 98).
5. **Spec's secure-storage Evidence citations are accurate but incomplete** (lines 26–29): the cited files also contain the App-Group mirrors and the sentinel. Inaccuracy-by-omission; the canonical key list at line 85 inherits it.

---

## Inaccurate current-state claims (correct these in Section 4 / Section 5)

| # | Spec claim | Reality | Evidence |
|---|-----------|---------|----------|
| 1 | Line 86: assumes WAL / "checkpoint WAL" | DB runs in **DELETE** mode; no `PRAGMA journal_mode` anywhere; checkpoint is a no-op. `sqlcipher_export` is the correct primitive and is unmentioned. | `encrypted_db_opener.dart:78,126,148` |
| 2 | Line 85: "every secure-storage key referenced by database rows" as the completeness mechanism | Only 2 families are row-referenced; the rule enumerates almost nothing. | `secret_storage_references.dart:12-16` |
| 3 | Line 29: group keys at `secure:group_key_material:<groupId>:<gen>` | `groupId` is **URI-encoded**, and this is only **one of two** stores — the NSE mirror uses `group_key:<rawId>:<gen>` in the shared access group. | `secret_storage_references.dart:15-16`; `group_repository_impl.dart:11-12` |
| 4 | Line 33: AES-GCM file helpers as a building block | Whole-file in-memory (`os.ReadFile`+`gcm.Seal`+`os.WriteFile`); unusable at bundle scale. | `go-mknoon/crypto/file_crypto.go:35,50-55,58` |
| 5 | Lines 92–93: version-compat presented as existing-behavior reliance | No app/schema-version mechanism exists; higher `user_version` hits sqflite's default `onDowngrade` **throw**, not a controlled fail. | `main.dart:319`; `encrypted_db_opener.dart:26-32` |
| 6 | Line 30: media paths relative & portable | Only when `mediaFileManager` non-null; fallback stores raw absolute paths into `local_path`. | `upload_media_use_case.dart:199,236` |

---

## Additional test cases the spec should require

1. **Multi-generation group-key migration:** rotate a group through ≥8 generations, send under each epoch, queue an offline-replay envelope under an old epoch; after export/import assert **every** epoch decrypts AND both `group_key_material:*` (main) and `group_key:*` (shared) are populated.
2. **Shared App-Group keychain coverage:** after import, assert NSE-readable items (ML-KEM mirror + `group_key:<id>:<gen>` for every retained gen) exist in `group.com.mknoon.app.share`; simulate incoming 1:1 + group push and prove the NSE decrypts the preview **without** waiting for a rotation.
3. **db_encryption_key ordering:** importing the DB before the key fails cleanly (no new-key generation, no empty-DB encryption); the sequence never sets `secrets_migrated` against a NULL-secret row before secrets are committed.
4. **DELETE-mode torn-snapshot rejection:** force a concurrent write txn during export; assert export uses `sqlcipher_export` (not a raw copy capturing an in-flight `-journal`) and import rejects a deliberately torn snapshot.
5. **Full-table-set survival:** posts/social-feed (all `post_*`), introductions, and `inbox_staging_entries` rows present and rendering after migration — not just messages/contacts/groups/media.
6. **Avatar + thumbnail survival with no DB fallback:** downloaded contact avatars (`media/avatars/`), group avatars (`media/group_avatars/`), and `.thumb.jpg` thumbnails render on the new phone.
7. **Non-portable absolute `local_path` healing:** a row with a raw absolute path either heals or fails/flags — never silently "succeeds" with an unreachable attachment.
8. **Per-attachment 3-piece atomicity:** a row with missing secure key but present nonce/scheme fails/flags **before** commit.
9. **Old-phone group-networking teardown:** after cutover, all GossipSub topics unsubscribed, every `groupPeerDiscoveryLoop` cancelled, and `rejoinGroupTopics` suppressed when re-driven from app-resume, push handlers, and the retrier (an account-state gate observed by **all** entry points).
10. **Push-token policy:** migrated new phone forces fresh push registration; the stale old-device token does not win.
11. **QR discriminator + single-use:** contact QR rejected by migration flow and vice versa (no bogus `addContact`/P2P request fires); malformed-timestamp migration QR fails **closed**; second scan of a consumed QR rejected.
12. **Large-bundle feasibility:** streaming AEAD (no whole-file load) handles a multi-hundred-MB→GB bundle and **resumes** after mid-transfer interruption/backgrounding rather than restarting from byte 0.

---

## Open questions for the spec author

1. **Push-token policy on cutover** — clear + re-register on the new phone (recommended, relay is peerId-keyed) or carry? Must be decided explicitly.
2. **Bundle transfer design** — accept full-restart-on-interruption for a GB bundle, or mandate a chunked/resumable segment-manifest protocol? Materially changes transport scope.
3. **Migration QR auth model** — since the new phone has no identity, what authenticates the pairing QR: an ephemeral new-device keypair, the old phone signing a challenge, or an out-of-band confirmation code bound into the session?
4. **`sqlcipher_export` as canonical DB-export primitive?** — it resolves both the DELETE-mode torn-snapshot risk and the two-roots problem in one mechanism (and can re-key to a session key).

---

## Bottom line

The spec's **logic** (cutover, invariants, non-goals, test taxonomy) is strong and largely correct. Its **inventory and feasibility** are where it falls short: the secret-discovery rule must be rewritten, the App-Group keychain mirror and group-key generations must be added, the DB scope must name all tables + both media roots, the WAL/AES/transport assumptions must be corrected, and the QR/transport/version mechanisms it treats as "reuse existing" must be acknowledged as **net-new work**. Resolve the 9 P0 items (and ideally the QR/transport/version P1s) and this becomes a ship-ready spec.
