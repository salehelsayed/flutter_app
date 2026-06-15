# 112 — 1:1 Media End-to-End Encryption (TDD Plan)

Date: 2026-06-12 · Branch: 121-improvements · Status: **IMPLEMENTED (all phases 1–6, host-proven 2026-06-12; uncommitted)** — pending: relay deploy (Phase 6, same binary as the 111 ack-delete deploy), real-device evidence (§8 items 2–5), and the Section-4 receiver-first release hold before shipping any Phase-2/4 sender build. Closure log at the end of this doc. · Amended 2026-06-12: relay metadata sidecar brought into scope (owner decision — OQ-1 resolved; new G7 + Phase 6, see Amendment log)

Source: 6-agent graph-first recon (sender-path, receiver-path, crypto-inventory, media-types-transports, tests-landscape, compat-wire), all findings file:line-verified against the uncommitted 121-improvements working tree on 2026-06-12. Re-verify anchors before each session (Caveat 9.5).

---

## 1. Problem statement and impact

1:1 media blobs are exchanged and stored in **plaintext** on two transports, while 1:1 message TEXT is already fail-closed ML-KEM-768 v2 encrypted (`send_chat_message_use_case.dart:241-257`, Report 76):

- **Relay path.** `uploadMedia` runs blob keygen + AES-256-GCM encryption (`callBlobKeygen`/`callBlobEncrypt`, scheme `kMediaAttachmentEncryptionSchemeBlobAesGcmV1`, SHA-256 contentHash) **only when `isGroupUpload`** (`upload_media_use_case.dart:180, 247-281`). The 1:1 branch uploads the raw file (`encryptedUploadPath ?? localFilePath` at `:288`); Go `Node.MediaUpload` streams the bytes verbatim (`go-mknoon/node/media.go:327-417`); the relay stores them unmodified at `dataDir/<to>/<id>.enc` — the `.enc` suffix is cosmetic (`go-relay-server/media.go:263-265, 429-500`) — with a 7-day TTL (`media.go:21`) — alongside a **plaintext JSON metadata sidecar** `mediaMeta{id, from, to, mime, size, created_at}` (`media.go:33-41, 482-490`) that leaks the content type and persists the sender→recipient social graph at rest for the blob's lifetime.
- **LAN path.** When the peer is on the same Wi-Fi, the composer ALSO ships the raw file over plain HTTP PUT `http://host:port/media/<id>` with `ws://` signaling, no TLS (`conversation_wired.dart:1864-1873`; `local_media_sender.dart:153-173`; `local_ws_server.dart:96, 526`), and the LAN `media_offer` leaks mime/size/sha256/waveform/filename in cleartext (`local_media_sender.dart:107-122`). The relay upload still happens in addition ("durable recovery copy", `conversation_wired.dart:1883-1894`), so same-LAN sends leave a plaintext relay copy too.

**Impact:** every 1:1 photo, video, and voice note sits **readable by the relay operator (and anyone with relay disk access) for up to 7 days**, and is readable by any on-path LAN observer during local transfer. This directly violates the product requirement: **no plaintext exchange in 1:1 messaging — text, images, videos, voice — on any transport.** All **four** 1:1 sender entry points are affected: composer attachments (`conversation_wired.dart:1883-1894`), voice (`send_voice_message_use_case.dart:110-119`), background retry (`retry_incomplete_uploads_use_case.dart:186-196`, wired from `pending_message_retrier.dart:439-449`), and **OS share-sheet batches** (`share_batch_delivery_coordinator.dart:270-333` `_sendToContact`, production-wired via `share_target_picker_wired.dart` → `DefaultShareBatchDeliveryCoordinator` and `ShareIntentService` in `main.dart`). The share path is the worst of the four — and unlike the composer it is **LAN-XOR-relay**: it streams the RAW shared file over the plaintext LAN transport (`p2pService.sendLocalMedia(filePath: media.file.path)`, `:284-293`), and on LAN success builds a `MediaAttachment` with NO encryptionKey/nonce/scheme/contentHash and `continue`s (`:295-312`), **skipping `uploadMedia` entirely**; only the non-LAN branch calls `uploadMedia` (`:314-324`). Left unfixed, Phase 2's G5 fail-closed gate would hard-reject every same-Wi-Fi share AFTER the plaintext already crossed the wire (Phase 2.4 fixes this).

---

## 2. Goals / Non-goals

### Goals
- **G1** Every 1:1 media blob (image, video, voice — the attach sheet offers gallery/camera-photo/camera-video only, `conversation_wired.dart:2294-2361`, and there is no separate thumbnail blob; OS share-sheet batches can additionally carry arbitrary shared-file mimes via `_mimeFromPath`, which is fine — blob encryption is mime-agnostic) is AES-256-GCM encrypted with a fresh random per-blob key before leaving the device, on **both** the relay transport and the LAN transport, from **all four** sender entry points (Section 1).
- **G2** The per-blob key/nonce/scheme/contentHash travel **inside the existing ML-KEM v2 encrypted message payload** (zero wire-format change — `MediaAttachment.toJson` already serializes them and `MessagePayload.toInnerJson` already includes `media`, `media_attachment.dart:195-212`, `message_payload.dart:208-220`).
- **G3** Receiver decrypts per-attachment, keyed on attachment metadata — never on the group policy flag — and keeps every 1:1-only durability behavior (ack-based relay delete, `.part`/staged-artifact adoption from the 111 P0-C fix, status repair).
- **G4** Legacy plaintext 1:1 blobs (old senders, in-flight relay blobs draining over ≤7 days) keep working during the skew window; mixed-version behavior is explicit and tested.
- **G5** Outbound 1:1 sends fail closed if any attachment lacks encryption metadata (mirror of `_sanitizeGroupMediaAttachments`, `send_group_message_use_case.dart:505-596`), matching the text path's `encryptionRequired` precedent.
- **G6** No new crypto primitives, no DB migration (migration 059 columns + migration 058 `content_hash` already exist on DB v75), no wire-envelope change; the only relay change is G7(b)'s at-rest sidecar minimization (isolated, client-invisible, Phase 6).
- **G7** *(amendment 2026-06-12)* Relay metadata sidecar minimized: **(a)** encrypted 1:1 uploads advertise an **opaque mime** (`application/octet-stream`, new constant `kOpaqueMediaTransportMime` — defined in `lib/features/conversation/domain/models/media_attachment.dart` next to `kMediaAttachmentEncryptionSchemeBlobAesGcmV1`; shared home with doc 113, whichever doc lands first creates it there, the other imports it) to the transport/relay — the real mime travels only inside the ML-KEM v2 envelope as `attachment.mime`; **(b)** the relay **stops persisting `from`** in the media sidecar — the field is write-only (`media.go:484`); download/delete authorization keys on `To`/`AllowedPeers` (`media.go:519-531, 577-587`), and the only API that returns it (`media:list`) has no app callers (`callP2PMediaList`, `p2p_bridge_client.dart:908`, is dead code). `to`, `size`, `created_at` remain — routing/auth, exact-size transfer enforcement (`io.CopyN`, `media.go:459`), and the TTL sweep respectively — accepted residual, rationale in Non-goal 3.

### Non-goals (deferred, with justification)
- **Profile avatars** (`profile:upload` raw file + v1 PLAINTEXT `profile_update` envelope, `upload_profile_picture_use_case.dart:41-45, 101-105`) — different ACL/product semantics (avatars are semi-public profile data); needs its own owner decision and doc. Tracked as open question OQ-5.
- **Posts media** (`attach_post_media_use_case.dart:222-253` bypasses `uploadMedia` entirely: `callP2PMediaUpload` with `allowedPeers` but zero blob encryption) — broadcast-to-contacts surface, same template applies but separate scope; follow-up doc. Note for that follow-up: this is the ONLY plaintext posts upload — the pass-along re-upload (`pass_post_along_use_case.dart:578-594`) already does `callBlobKeygen`/`callBlobEncrypt` and uploads the `encryptedPath`.
- **Full relay metadata privacy** — G7 now minimizes the sidecar (opaque mime, no persisted `from`), and Phase 4 drops waveform/filename AND the real mime from enc-flagged LAN offers (plus ciphertext sha256). What REMAINS by design: relay `to` (store-and-forward routing + download/delete auth), blob `size` (exact-size transfer enforcement; ciphertext length is observable from the stream regardless), `created_at` (TTL sweep), LAN offer `size`, and **live** connection metadata — the relay always sees which authenticated peer uploads and which downloads, so removing the at-rest record does not blind a live observer. Blinded-mailbox routing and size padding are protocol redesigns, deferred.
- **Streaming/chunked blob crypto** — Go `EncryptFile`/`DecryptFile` are whole-file-in-RAM (`file_crypto.go:35, 55, 83, 98`). Groups already live with this for the same size caps; reusing the move-feature chunked AEAD (`migration.go`) would need a new non-session blob profile. Stated limitation, follow-up if device evidence shows pressure.
- **`requireVerifiedContentHash` UI gating for 1:1 surfaces** (`media_grid_cell.dart:83-95`) — AES-GCM auth tag + download-time encrypted-blob hash check is the v1 integrity story; flipping render gates on for 1:1 would block legacy plaintext rows.
- **Fail-closed RECEIVE of plaintext 1:1 media** — cannot land in the same release: receivers still accept v1 envelopes and ≤7-day-old plaintext relay blobs exist at upgrade. Revisit after the TTL drain window (Section 4).
- **Re-encrypting historical local media / already-delivered messages**, and **TLS on the LAN server** (rejected alternative, Section 3).

---

## 3. Design decision

**Reuse the group blob scheme verbatim, minus group policy:** fresh random AES-256-GCM key per blob via `blob:keygen`/`blob:encrypt`/`blob:decrypt` (`bridge.dart:687-773` → `go-mknoon/bridge/bridge.go:2726-2810` → `mcrypto.GenerateSymmetricKey`/`EncryptFile`/`DecryptFile`), scheme string `kMediaAttachmentEncryptionSchemeBlobAesGcmV1` set **explicitly always**, contentHash = SHA-256 of the **encrypted** blob (group convention, `contentHashScope 'relay_blob'`), key+nonce+scheme+hash carried inside the ML-KEM v2 encrypted payload as fields of each `media[]` entry — exactly how the group transports them inside the group-key-encrypted payload (`send_group_message_use_case.dart:920, 941, 959, 963-984`). Receiver branching is **per-attachment on TWO predicates** (never on `enforceGroupMediaPolicy`): a NEW scheme-agnostic `hasEncryptionKeyMaterial` (key+nonce non-empty, **ignores scheme**) selects ciphertext custody (`.enc` staging, fail-closed handling, no ack), while the existing `hasEncryptionMetadata` whitelist (null-or-v1, `media_attachment.dart:88-96`; `isEncrypted` is its alias at `:96`) strictly means "decryptable with v1 logic". Keying everything on `isEncrypted` alone would be **unimplementable for discriminator case 3** (Section 4): the whitelist returns FALSE for key+nonce+unknown-scheme, which would route future-scheme ciphertext into the legacy plaintext promote+ack path and destroy the only relay copy. The same ciphertext artifact is sent on both relay and LAN (encrypt once).

The recon's crypto-inventory dimension verified end-to-end that this needs **no new primitives, no envelope change, no model change, no DB migration**: `toJson`/`fromJson`/`toMap`/`fromMap` already round-trip the four fields, `handleIncomingChatMessage` already persists them (`handle_incoming_chat_message_use_case.dart:384-404`), and posts already prove `callBlobDecrypt` works outside groups (`download_post_media_use_case.dart:46`).

**Metadata minimization (G7, amendment).** The opaque transport mime is sender-side only and MUST stay gated to `!isGroupUpload`: the group download path cross-checks the relay-returned mime against the envelope mime and quarantines on `relay_mime_mismatch` (`download_media_use_case.dart:1330-1371`) — opaquing group uploads without changing that check in the same release would quarantine every group download (Alternatives rejected #7). The 1:1 receive path never reads the relay-returned mime (that block is its ONLY consumer and it is group-gated); everything 1:1 — canonical extension, rendering, the in-flight dedup key — derives from `attachment.mime` inside the encrypted envelope. The `from` removal is relay-side and invisible to every client version: the field is write-only (`media.go:484`), auth keys on `To`/`AllowedPeers`, and dead `media:list` is the only API returning it. Legacy sidecar JSONs containing `from` still decode (unknown fields are ignored by `encoding/json`).

### Alternatives rejected
1. **New scheme string for 1:1** — identical cipher mechanics; a different string would only flip old apps' `hasEncryptionMetadata` to false (its whitelist is null-or-v1, `media_attachment.dart:88-94`) and add compat-matrix rows for zero crypto benefit.
2. **Flip `enforceGroupMediaPolicy` on for 1:1 downloads** — would drag in group mime/size policy, the missing-metadata quarantine (`download_media_use_case.dart:669-679`, fatal to legacy plaintext rows), and would LOSE 1:1-only behaviors: ack-based relay delete (`:582-621`), `.part` adoption (`:789-866`, the 111 P0-C fix), canonical-orphan adoption (`:710-775`), status repair (`:684`).
3. **Reuse the group `uploadMedia` branch wholesale** — drags `GroupMediaMimePolicy`/`GroupMediaSizePolicy` into 1:1, which supports arbitrary mimes and different caps. Take the crypto block only.
4. **Move-feature session-KEM chunked AEAD for blobs** — session-bound HKDF (`info = sessionId|bundleId|direction`, `migration.go:33-44`); needs a new profile; overkill for v1, group precedent already accepts whole-file crypto.
5. **TLS on the LAN HTTP/WS server instead of app-level encryption** — leaves the relay copy plaintext (LAN sends ALSO upload to relay), requires cert/trust infrastructure between peers, and fixes only one transport. App-level ciphertext fixes both transports with one artifact.
6. **Capability negotiation / runtime sender flag** — no capability channel exists in the 1:1 protocol; a device-local flag reintroduces the move-feature G3 cutover-flag bug class. Rollout control is **release sequencing** (Section 4).
7. **Opaque mime for GROUP uploads in this doc** — would trip the group `relay_mime_mismatch` quarantine on every group download (`download_media_use_case.dart:1336-1370`) unless the group receive check flips in the same release; group blobs are already encrypted and group scope belongs to a follow-up doc.

### Key-coherence contracts (new, must be pinned by tests)
- **KC-1 (ordering):** encryption + upload fully complete — attachment row carries final key/nonce/scheme/hash — **before** `sendChatMessage` builds and persists the wire envelope (`send_chat_message_use_case.dart:348-354`). Already true for composer and voice flows (upload returns before send); the gate in G5 enforces it.
- **KC-2 (retry):** a re-upload that re-encrypts MUST mint a **fresh key+nonce**, persist the new values to the attachment row, and **invalidate/rebuild** any previously persisted wire envelope that references the old key before re-send. **Primary, code-verified hazard:** the persisted-envelope replay contract (`:348-354`, replayed "without re-serializing or re-encrypting") plus stable `blobId` retries (`retry_incomplete_uploads_use_case.dart:195`) mints stale-envelope/blob key mismatches — undecryptable media. **Secondary (defense-in-depth):** `EncryptFile` draws a fresh random 12-byte nonce on every call (`go-mknoon/crypto/file_crypto.go:50-53`), so same-key re-encryption does NOT deterministically reuse a nonce; the fresh-key rule additionally caps the residual ~2^-96 random-nonce-collision bound.
- **KC-3 (custody):** ack-based relay delete (`ackRelayBlobDeletion`, `download_media_use_case.dart:582-621, 1583`) fires **only after decrypt + durable commit succeed**. Decrypt failure or unknown scheme NEVER acks — the relay copy stays alive within TTL for retry. (Extension of 111's INV-1.)

---

## 4. Backward / version-skew compatibility

**Discriminator:** per-attachment tri-state via the two Section-3 predicates, pinned by tests —
1. no key material (`hasEncryptionKeyMaterial == false`) → **legacy plaintext** path (today's `.part` staging + rename, unchanged);
2. key material present AND `hasEncryptionMetadata` true (scheme ∈ {null, `blob_aes_256_gcm_v1`}) → **decrypt** (sender always writes the scheme explicitly; null is tolerated on receive only because the whitelist allows it — pin this);
3. key material present AND scheme outside the whitelist → **fail closed**: `integrity_failed`, staged artifact preserved, NO ack-delete (a future v2 scheme must never be decrypted with v1 logic). NOTE: `hasEncryptionMetadata`/`isEncrypted` is FALSE here (`media_attachment.dart:93-94`), so case-3 routing MUST key on `hasEncryptionKeyMaterial` — branching on `isEncrypted` alone would silently route case 3 into case 1's promote+ack destruction.

**Old app ← new sender (the dangerous direction):** an old receiver downloads ciphertext into `.part`, renames it to a canonical `.jpg`/`.mp4`, marks `done`, **ack-DELETES the relay blob**, and renders garbage (`download_media_use_case.dart:1543-1583`) — the only ciphertext copy is destroyed. The LAN direction fails analogously on a receiver without LAN ciphertext support: the offer sha256 check passes (ciphertext hash vs ciphertext bytes), `persistMedia` promotes the raw bytes to a canonical media path (`local_media_server.dart:428-462`), `linkIncomingLocalMedia` links + completes the pending row (`main.dart:1764-1782`), and the local-ready shortcut (`download_media_use_case.dart:682-688`) then skips relay decrypt forever — `done`-status garbage with no repair trigger. There is no capability handshake. **Mitigation: receiver-first two-release rollout covering BOTH transports.** Phase 1 (the FULL receiver capability: relay decrypt-adopt AND LAN enc-flagged ciphertext staging + deferred decrypt, Phases 1.5/1.7) ships in build N; ALL sender flips (Phase 2 relay incl. the share coordinator, Phase 4 LAN) ship in later builds and are **held until build N is the deployed floor** (TestFlight population — confirm via OQ-3). Because the LAN receiver capability is IN build N, the single hold genuinely covers the Phase-4 LAN flip too — do NOT move the LAN receiver work back into Phase 4 (that would make the hold's floor build incapable on the LAN path). No runtime flag (rejected alternative 6).

**New app ← old sender / in-flight plaintext blobs:** per-attachment branching keeps legacy plaintext rows fully working. Do NOT port the group missing-metadata quarantine to 1:1 in this plan; the plaintext receive branch can only be retired after the 7-day relay TTL drain plus v1-envelope deprecation (deferred, Non-goals).

**Size semantics:** `attachment.size` stays the **plaintext** size on wire/DB (group convention). Ciphertext = plaintext + 16-byte GCM tag (nonce travels separately in metadata). Go `MediaUpload` stats the actual file for the relay's exact-size enforcement (`go-relay-server/media.go:459-473`), so uploads are unaffected; receiver-side staged-size checks must use `size + 16` for encrypted artifacts, and post-decrypt validation uses `size` (mirror `plaintext_size_mismatch`, `download_media_use_case.dart:1503-1510`). Watchdog budgets scaled from plaintext size are off by 16 bytes — negligible, pin with a comment.

**MIG-012 lesson:** contentHash is ALWAYS the encrypted-relay-blob hash; plaintext-hash validation stays explicitly skipped (`group_feed_media_verification.dart:79-99` precedent). No verifier may compare an encrypted-blob hash against decrypted bytes.

**Metadata-minimization skew (G7):** zero new skew rows. The opaque mime ships only on encrypted 1:1 uploads — already held behind the Phase-1 floor — and even an un-floored old receiver is unaffected because no 1:1 code path reads the relay-returned mime (the sole consumer is group-gated, `download_media_use_case.dart:1330-1331`). The relay `from` removal is server-side and invisible to every client version (write-only field; dead `media:list`); legacy sidecars with `from` still load after the relay upgrade.

---

## 5. TDD phases

Each phase lands independently shippable. Order matters: **1 → 2 → 3 → 4 → 5**; Phase 1 must be the deployed floor before ANY sender flip (Phase 2 relay/share, Phase 4 LAN) ships (Section 4). Phase 6 (relay sidecar `from` removal, G7b) is server-side and order-independent — it can deploy at any point. All new test files get classified in `test-gate-definitions.md` with `./scripts/run_test_gates.sh completeness-check` kept green (rules at `test-gate-definitions.md:5, 117-122`). RED honesty rule: tests that are green-on-arrival are explicitly labeled **pins** below — the RED count per phase is only the tests that genuinely fail when written.

---

### Phase 1 — Receiver capability on BOTH transports (forward compatibility)

**Why first:** makes every receiver able to handle encrypted blobs — relay decrypt-adopt AND LAN ciphertext staging — before any sender produces them; pure addition, legacy plaintext path untouched. This phase defines the build-N rollout floor (Section 4).

#### 1.1 RED — model predicates
File: `test/features/conversation/domain/models/media_attachment_test.dart` (extend; create if absent).
- `'hasEncryptionKeyMaterial: absent/empty key or nonce = false; key+nonce non-empty = true regardless of scheme (null, v1, unknown)'` — **genuinely RED: the predicate does not exist yet** (new getter, Section 3). This is the scheme-agnostic ciphertext-custody discriminator.
- `'hasEncryptionMetadata tri-state: absent keys=false, key+nonce+null-scheme=true, key+nonce+v1-scheme=true, unknown scheme=false'` — **green-on-arrival pin** (the getter ALREADY whitelists null-or-v1, `media_attachment.dart:88-96`; no test pins it today). The pin's value is blocking any future widening of the whitelist (9.4).

#### 1.2 RED — direct download decrypts on metadata
File: `test/features/conversation/application/download_media_use_case_test.dart`. Reuse the existing fake-crypto kit: `_encryptedBytes`/`_encryptedGroupAttachment` (`:25-49, 80-108`) and the prefix-verifying `blob:decrypt` stub — build a **direct** (no `enforceGroupMediaPolicy`) attachment with encryption metadata.
- `'direct download decrypts encrypted attachment and commits plaintext'` — canonical file bytes == original plaintext; `commandLog` contains `blob:decrypt`. **Fails today:** the direct branch never decrypts; it renames the ciphertext `.part` to canonical (`download_media_use_case.dart:1543-1556`), so the byte-equality assertion fails.
- `'direct encrypted download stages to .enc, never promotes ciphertext to canonical'` — on decrypt failure (fake returns `ok:false`): canonical path absent, staged `.enc` preserved, status `kMediaDownloadStatusIntegrityFailed`, **zero `media:delete`**. Fails today (ciphertext is promoted + acked).
- `'ack delete fires only after decrypt and durable commit'` (KC-3 ordering pin) — assert `media:delete` recorded AFTER `updateLocalPath`; fails today only in the encrypted case.
- `'cross-object key reuse fails closed for direct media'` — mirror of the group test at `:1380-1424` without the group flag.
- `'unknown encryptionScheme fails closed without ack delete'` (discriminator case 3) — only implementable via the new `hasEncryptionKeyMaterial` predicate (1.1/1.7): `isEncrypted` is FALSE for unknown schemes, so any `isEncrypted`-keyed branch would route this into the plaintext promote+ack path.
- `'content hash mismatch on encrypted direct blob fails before decrypt'` — mirror the group fail-closed template `'group policy rejects spoofed downloaded bytes before marking done'` (`:1219-1257`: asserts `integrity_failed`, no canonical file, no localPath update). (NOT `:1259-1285` — that is the success-path hash check.) Relay copy kept.
- `'transient bridge failure during decrypt keeps .enc and stays retryable'` — `blob:decrypt` throws → status retryable-`failed` (NOT integrity_failed), artifact preserved (MEDIA_DOWNLOAD_PART_PRESERVED analog).
- `'legacy plaintext direct attachment stays decrypt-free'` — green pin guarding regression: no `blob:decrypt` command, `.part` staging, done + ack as today.

#### 1.3 RED — adoption shortcuts become ciphertext-aware
Same file (templates: `.part` adoption `:789-866`, canonical orphan `:710-775`).
- `'retry adopts complete encrypted staged artifact via decrypt-then-promote'` — pre-place `.enc` sized `attachment.size + 16`; retry commits done with **zero `media:download`** sends and one `blob:decrypt`; ack fired post-commit. **Fails today:** adoption requires staged bytes == plaintext `attachment.size` (`:800, :721-722`), so the encrypted artifact is never adopted.
- `'adoption ignores encrypted artifact with wrong staged size'` — re-downloads (PL-013 genuine-partial behavior preserved).

#### 1.4 RED — duplicate-replay metadata change invalidates stale staged artifacts
File: `test/features/conversation/application/handle_incoming_chat_message_use_case_test.dart`.
- `'duplicate replay carrying new key/nonce invalidates stale staged artifacts before reset to pending'` — `_repairDuplicateReplayMedia` (`handle_incoming_chat_message_use_case.dart:431-469`) re-saves wire metadata over `integrity_failed`; a stale `.enc` from the OLD key must be deleted so the new key never decrypts old bytes. Fails today (no invalidation exists).

#### 1.5 RED — LAN receiver: enc-flagged offers stage ciphertext, decrypt deferred to envelope arrival
Receiver-side LAN capability ships HERE (build N), NOT in Phase 4 — this is what makes the single Section-4 hold cover both transports. (A Phase-4-only LAN receiver would leave floor builds promoting LAN ciphertext to canonical `done` media with no repair trigger; see Section 4.)

File: `test/core/local_discovery/local_media_server_test.dart`:
- `'enc-flagged upload persists as staged ciphertext artifact, not promoted to canonical media'` — fails today (`handleUpload`/`persistMedia` promote raw bytes, `local_media_server.dart:234-246, 428-462`).
- `'audio/mp4 maps to .m4a extension'` — fixes the voice `.bin` bug (`:506-519`); fails today.
- `'unflagged legacy plaintext LAN upload still promotes as today'` — green pin.

Adoption seam (where `linkIncomingLocalMedia` wires the stream, `main.dart:1497-1505, 1775-1781`): extend the existing LAN-link suite (or add cases to `local_media_integration_test.dart`) —
- `'LAN ciphertext arriving BEFORE the message is adopted and decrypted once attachment metadata lands'` — the ordering hazard test: place staged artifact at `'$absolutePath.enc'` so 1.3's adoption decrypt-promotes it when `downloadMedia` runs; assert zero `media:download` bridge sends (LAN copy wins) and the relay ack fires after commit.
- `'linkIncomingLocalMedia never links or completes an enc-staged artifact'` — deferral pin: completion happens only via decrypt-adopt; fails today (`main.dart:1764-1782` links + completes while pending).
- `'LAN/relay dedupe rule still holds for encrypted artifacts'` (re-validate `main.dart:1770-1781`).

#### 1.6 Coverage pins — Go blob bridge handlers (green-on-arrival, no behavior change)
File: `go-mknoon/bridge/bridge_test.go`.
- `TestBlobKeygenEncryptDecryptRoundTrip` and `TestBlobDecryptWrongKeyFails` — the handlers at `bridge.go:2726-2810` have zero direct tests (only the scheme string appears, `bridge_test.go:3006`). These are NOT RED tests — they pass immediately by design; they exist as pins for Phase 4/5 reuse.

#### 1.7 GREEN
`lib/features/conversation/domain/models/media_attachment.dart`:
- Add `hasEncryptionKeyMaterial` (key+nonce non-empty, scheme-agnostic). `hasEncryptionMetadata`/`isEncrypted` keep the null-or-v1 whitelist and now strictly mean "decryptable with v1 logic".

`lib/features/conversation/application/download_media_use_case.dart`:
- Staging suffix at `:701-703`: `.enc` when `enforceGroupMediaPolicy || attachment.hasEncryptionKeyMaterial`, else `.part` (scheme-agnostic — unknown-scheme ciphertext must never stage as `.part`).
- Extract the group decrypt+promote block (`:1408-1492`) into a policy-parameterized helper `decryptAndPromoteStagedBlob(...)`; the direct call path uses it with: decrypt only when `hasEncryptionMetadata`; key material WITHOUT the whitelist (unknown scheme, discriminator case 3) → `kMediaDownloadStatusIntegrityFailed` + artifact preserved + NO ack; encrypted-blob hash check when `contentHash != null` (mirror `:1373-1377`), post-decrypt plaintext-size check (mirror `:1494-1510`), **no** group mime policy, **no** group quarantine of missing metadata, ack via existing `ackRelayBlobDeletion` only after commit (KC-3). Cryptographic failure → `integrity_failed` + artifact preserved + no ack; thrown/transient failure → retryable `failed` + artifact preserved.
- Adoption helpers `:710-775` and `:789-866`: expected staged size = `attachment.size + 16` when `attachment.hasEncryptionKeyMaterial`; adopt = decrypt-then-promote via the new helper (which itself enforces the case-3 fail-close).
- Encrypted-companion restore guard `:877-879`: allow when `attachment.hasEncryptionKeyMaterial` (not group-only).
- `_repairDuplicateReplayMedia` (`handle_incoming_chat_message_use_case.dart:431-469`): delete staged `.enc`/`.part` artifacts when incoming key/nonce differ from the stored row.
- Refactor note: include the encryption discriminator in `_MediaDownloadInFlightKey` (`p2p_bridge_client.dart` dedup at `download_media_use_case.dart:23-60` region) so mixed-policy concurrent calls don't share a future.
- Call sites unchanged (no new flag — metadata-keyed): `chat_message_listener.dart:168-174`, `conversation_wired.dart:1181-1187, 1400-1406`.

LAN receiver (moved here from Phase 4 so the rollout floor includes it — Section 4):
- `local_media_server.dart:234-246, 428-462, 506-519`: enc-flagged payloads staged (not promoted); place/forward the staged artifact so `linkIncomingLocalMedia` + the adoption path complete the decrypt; add `audio/mp4 → .m4a`.
- `main.dart` `linkIncomingLocalMedia` (`:1764-1782`): defer linking/completion for enc-staged artifacts — completion happens only via decrypt-adopt.
- `p2p_service_impl.dart:3538-3566` / `local_p2p_service.dart:115-140` / `local_ws_server.dart:455-503`: thread the offer's enc metadata (pass-through only). Note: no sender emits the enc flag until Phase 4 — this is pure forward capability, exactly like the relay decrypt path above.

#### 1.8 Gate
`flutter test test/features/conversation/application/download_media_use_case_test.dart test/features/conversation/application/handle_incoming_chat_message_use_case_test.dart test/features/conversation/domain/ test/core/local_discovery` green; `./scripts/run_test_gates.sh 1to1` green (download suite is a member, `test-gate-definitions.md:261`); `cd go-mknoon && make test` green. No gomobile rebuild needed (Go change is test-only). Changed/new local_discovery test files classified + `completeness-check` green.

---

### Phase 2 — Sender: encrypt all 1:1 relay uploads (THE FLIP — hold until Phase 1 receivers are deployed)

#### 2.1 RED — rewrite the two plaintext-contract tests (red-first, not parallel tests)
File: `test/features/conversation/application/upload_media_use_case_test.dart`. Use the in-file content-transforming `_FakeBridge` (`:34-62`) — NOT the shared `FakeBridge`, whose `blob:encrypt` copies bytes unchanged (`fake_bridge.dart:204-219`) and cannot detect plaintext leaks.
- REWRITE `'sends correct command to bridge'` (`:185-200`): assert `commandLog` `containsAllInOrder(['blob:keygen','blob:encrypt','media:upload'])` and `payload['filePath']` `endsWith('.enc')` and is NOT `tempFile.path`. **Fails today:** 1:1 sends the raw path (`upload_media_use_case.dart:288`).
- REWRITE `'returns MediaAttachment on success'` (`:161-183`): `contentHash` == sha256 of the encrypted artifact (currently `isNull` at `:182`), `encryptionKeyBase64`/`encryptionNonce` non-null, `encryptionScheme == kMediaAttachmentEncryptionSchemeBlobAesGcmV1` (explicit, never null).
- `'distinct key, nonce, and contentHash per 1:1 object'` — mirror group test `:537-549`.
- `'1:1 encrypted upload advertises opaque mime to the transport'` (G7a) — `media:upload` `payload['mime'] == kOpaqueMediaTransportMime` (`application/octet-stream`) while the returned attachment keeps the REAL `mime`. **Fails today:** the real mime is passed straight through (`upload_media_use_case.dart:283-293`).
- `'group upload still advertises the real mime to the relay'` — **green-on-arrival pin** protecting the group `relay_mime_mismatch` cross-check (`download_media_use_case.dart:1330-1371`) from the G7a change (Alternatives rejected #7).
- `'1:1 upload skips group mime/size policy'` — **green-on-arrival pin** (mime/size policy is already group-gated: `upload_media_use_case.dart:217-239` and `:247-268` sit inside `if (isGroupUpload)`); its value is guarding the GREEN-step hoist of the crypto block from dragging policy along with it.
- `'encrypted temp deleted after successful 1:1 upload; plaintext durable copy retained'` — mirror group cleanup `:295-307` + durable copy `:330-353`.
- `'transient source file deleted after durable copy and successful upload when deleteSourceWhenDone'` — new optional param (default false; composer passes true for picker temps since the durable copy at `:330-353` is the sender's render source). Document in-code: secure-delete/overwrite is NOT meaningfully achievable on flash/APFS — best-effort `File.delete` only.
- `'1:1 upload fails closed when blob keygen/encrypt fails'` — no `media:upload` issued, no plaintext fallback.

#### 2.2 RED — outbound fail-closed gate
File: `test/features/conversation/application/send_chat_message_use_case_test.dart`.
- `'send fails closed when an attachment lacks encryption metadata'` — new result value (e.g. `SendChatMessageResult.mediaEncryptionRequired`), no envelope persisted, no transport attempted. **Fails today:** attachments are embedded regardless (`send_chat_message_use_case.dart:266-289`). Mirror `_sanitizeGroupMediaAttachments` reason codes (`missing_media_encryption_metadata`).
- `'send proceeds for attachment with full encryption metadata'` (green companion).

#### 2.3 RED — voice inherits
File: `test/features/conversation/application/send_voice_message_use_case_test.dart` (upload stubbed via `responses['media:upload']` at `:88` — switch the relevant cases to the content-transforming stub).
- `'voice upload produces encrypted attachment metadata and passes the send gate'` — uploaded path `.enc`, attachment carries key/nonce/scheme, `sendChatMessage` invoked with it. Fails today (null fields).
- `'voice temp recording deleted after durable copy and successful upload'` — voice passes `deleteSourceWhenDone: true`. Same plaintext-residue class as the composer temps: the recorder writes `${tempDir.path}/voice_<ts>.m4a` (`record_audio_recorder_service.dart:228-231`) and nothing deletes `recording.filePath` today. Safe because the voice LAN send is awaited BEFORE `sendVoiceMessageFn` runs (`conversation_wired.dart:2708-2718`) and the durable copy (`upload_media_use_case.dart:330-353`) is the sender's render source. Fails today.

#### 2.4 RED — OS share-sheet path (fourth sender; LAN-XOR-relay today)
File: `test/features/share/application/share_batch_delivery_coordinator_test.dart` (exists — extend with the content-transforming bridge stub).
- `'share to a LAN peer still relay-uploads and the attachment carries encryption metadata'` — **fails today:** on LAN success `_sendToContact` builds a metadata-free attachment and `continue`s past `uploadMedia` (`share_batch_delivery_coordinator.dart:295-312`). Without this fix, 2.2's G5 gate would hard-REJECT every same-Wi-Fi share AFTER the plaintext already crossed the LAN — i.e. both a leak and a functional break.
- `'share to a non-LAN contact produces encrypted attachment via uploadMedia'` — inherits 2.1's rewrite through the real `uploadMedia` (`:314-324`).
- `'share send passes the outbound fail-closed gate'` — end-to-end with 2.2's gate (green companion once both land).

#### 2.5 RED — fake-network round trip (authored HERE so it transitions red→green inside this phase)
File (new): `test/features/conversation/integration/one_to_one_media_encryption_round_trip_test.dart` (pattern: `media_attachment_flow_test.dart:16-66` — `FakeP2PNetwork` + `TestUser` + `InMemoryMediaAttachmentRepository`; crypto via the content-transforming stubs).
- `'sender encrypts, key rides the v2 envelope, receiver decrypts to byte-identical media'` — full upload→send→hydrate (`handle_incoming_chat_message_media_hydration_test.dart` companion update for key-field hydration)→download→decrypt; assert uploaded bytes ≠ plaintext AND received canonical bytes == plaintext. RED against the Phase-1 tree (receiver can decrypt, but the sender still uploads plaintext, so `uploaded bytes ≠ plaintext` fails); goes green with 2.6. Authoring it here (not Phase 1) avoids carrying a known-red classified integration file across the deploy-hold window, which `test-gate-definitions.md:121-122` forbids hiding.
- `'legacy plaintext message from old sender still round-trips'` — mixed-version matrix cell, green pin.

#### 2.6 GREEN
- `lib/features/conversation/application/upload_media_use_case.dart`: hoist the keygen/encrypt/hash block (`:247-281`) out of `if (isGroupUpload)` — encryption is unconditional; `GroupMediaMimePolicy`/`GroupMediaSizePolicy` (`:217-268` region) stay group-gated; encrypted-temp cleanup (`:295-307`) applies to both branches; returned attachment (`:415-432`) always populated; `payloadSizeBytes: fileSize` stays plaintext-size (comment the +16 delta); the `media:upload` `mime` becomes `kOpaqueMediaTransportMime` for the 1:1 branch ONLY — `isGroupUpload` keeps the real mime (G7a / Alternatives rejected #7) — while the returned attachment keeps the real mime. **Delete the `?? localFilePath` fallback at `:288` outright** — the upload call must be structurally incapable of receiving a plaintext path (the fail-closed tests only exercise thrown keygen/encrypt failures; the null-coalescing fallback is the one seam through which a future regression could silently upload plaintext while the suite stays green). Add `deleteSourceWhenDone` param + best-effort delete after durable copy + upload success.
- `lib/features/conversation/application/send_chat_message_use_case.dart`: `_sanitizeDirectMediaAttachments` fail-closed gate before payload build (`:266-289`), new result value, flow event `DIRECT_MEDIA_ENCRYPTION_REQUIRED`.
- `lib/features/share/application/share_batch_delivery_coordinator.dart` `_sendToContact` (`:280-333`): drop the LAN-XOR-relay `continue` — ALWAYS call `uploadMedia` and use its returned encrypted attachment (composer semantics: LAN best-effort, relay durable copy). The raw `sendLocalMedia` bytes stay plaintext until Phase 4 (same as the composer), but the relay copy + message metadata are encrypted from this phase and the G5 gate passes.
- `lib/features/conversation/presentation/screens/conversation_wired.dart:1883-1894, 2363-2459`: pass `deleteSourceWhenDone: true` for picker/camera temps.
- Voice: one-line call-site change in `send_voice_message_use_case.dart:110-119` — pass `deleteSourceWhenDone: true` (2.3). Background retry (`retry_incomplete_uploads_use_case.dart`) needs **no call-site change** — it calls `uploadMedia` and inherits (retry coherence is Phase 3); it must NOT pass `deleteSourceWhenDone` (its source IS the durable copy).

#### 2.7 Gate
`flutter test test/features/conversation test/features/share` green; `./scripts/run_test_gates.sh 1to1` and `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh baseline` green. **Add `upload_media_use_case_test.dart` to the 1:1 gate** in `test-gate-definitions.md` (it is currently in no named gate — tests-landscape finding); classify the new round-trip integration file; `completeness-check` green. **Release hold:** do not ship a TestFlight build containing this phase until the Phase-1 build is the deployed receiver floor (this hold also pre-gates Phase 4 — Section 4).

---

### Phase 3 — Retry/replay key coherence (KC-2)

#### 3.1 RED
File: `test/features/conversation/application/retry_incomplete_uploads_use_case_test.dart` (note: existing tests stub at the `uploadMediaFn` typedef level, `:37`, and will stay green while behavior changes underneath — these new tests must wire the REAL `uploadMedia` with the content-transforming `_FakeBridge`).
- `'retry re-encrypts with a fresh key and persists updated metadata to the attachment row'` — two uploads of the same `blobId`: second run's key/nonce differ from the first AND the row was updated. **Green-on-arrival pin in plan order (1→2→3):** after Phase 2, the real `uploadMedia` mints a fresh key per call (`callBlobKeygen` per invocation; no key-reuse path exists) and retry already persists the re-uploaded attachment (`uploaded.copyWith` → `saveAttachment`, `retry_incomplete_uploads_use_case.dart:246-250`). Written through the REAL `uploadMedia` because the typedef-stubbed suite cannot observe either fact.
- `'retry never reuses a prior key for a new blob:encrypt call'` — **green-on-arrival pin**, same reasoning (KC-2 defense-in-depth).
- `'successful re-upload with changed key invalidates the persisted wire envelope of the parent message'` — **the genuine RED of this phase:** assert `messages.wire_envelope` is cleared (or rebuilt) so the replayed envelope cannot reference the dead key. **Fails after Phase 2 too:** the envelope persisted at `send_chat_message_use_case.dart:348-354` is replayed verbatim while retry re-encrypts the relay blob under a new key.

File: `test/core/services/pending_message_retrier_test.dart` (Step 7 wiring, `pending_message_retrier.dart:439-449`).
- `'re-sent message after media re-upload carries the attachment row's current key in its envelope'` — **genuine RED**; the observable KC-2 contract end-to-end: decrypt the rebuilt v2 envelope with the test recipient key and compare `media[0].encryptionKeyBase64` to the row.

#### 3.2 GREEN
Scope is **envelope invalidation only** — attachment-metadata persistence already exists (`retry_incomplete_uploads_use_case.dart:246-250`, the `uploaded.copyWith` → `saveAttachment` block; do not re-implement it). After a successful re-upload whose key/nonce changed, invalidate the parent message's `wire_envelope` (via the injected message repo) so the send path rebuilds it from current rows. Document KC-1/KC-2 as code comments at both sites.

#### 3.3 Gate
`flutter test test/features/conversation/application/retry_incomplete_uploads_use_case_test.dart test/core/services/pending_message_retrier_test.dart test/features/conversation/integration/media_retry_smoke_test.dart` green; `./scripts/run_test_gates.sh 1to1` green.

---

### Phase 4 — LAN path: ciphertext on the local transport (SENDER flip only)

In scope per the product requirement (recon confirmed raw bytes over `http://`/`ws://`, no TLS). Design: **encrypt once, send the same ciphertext artifact on both transports.** This phase is **sender-only**: the LAN receiver capability (enc-flagged staging, deferred decrypt, `.m4a` mapping, enc-metadata pass-through) shipped in Phase 1 / build N (1.5/1.7) — deliberately, so the Section-4 hold genuinely covers this flip. **LAN floor statement:** the build whose deployed floor gates this flip is build N (Phase 1), the same floor the Phase-2 hold enforces; since plan order puts this phase at or after the Phase-2 build, no additional hold is needed — but do NOT reorder the LAN receiver work back into this phase, and do NOT flip the LAN sender in any build whose deployed receiver floor predates Phase 1.5.

#### 4.1 RED
File: `test/core/local_discovery/local_media_integration_test.dart` — REWRITE the `'Local Media E2E'` plaintext pin (`:55-58` asserts sha256 equality of raw bytes):
- `'LAN transfer ships ciphertext; receiver-staged bytes differ from plaintext; decrypt-adopt restores byte equality'` — **fails against the Phase-1/2/3 tree** (receiver staging exists since 1.5/1.7, but the sender still streams plaintext, so the staged-bytes-differ assertion fails); goes green with 4.2.

File: `test/core/local_discovery/local_media_sender_test.dart`:
- `'sendMedia streams the encrypted artifact and advertises ciphertext sha256 in the offer'` — fails today (raw `file.openRead()` at `local_media_sender.dart:153-173`, plaintext sha256 in offer).
- `'media_offer omits waveform and filename, carries enc flag + scheme, and advertises an opaque mime'` — fails today (`:107-122`). Enc-flagged offers never need the real mime: the receiver stages `.enc` and takes the real mime from the envelope at decrypt-adopt time (Phase 1.5/1.7); the `.m4a` mapping in 1.5 applies to legacy plaintext offers only.

File: `test/features/share/application/share_batch_delivery_coordinator_test.dart`:
- `'share LAN send streams the encrypted artifact, never the raw shared file'` — fails today (`p2pService.sendLocalMedia(filePath: media.file.path)`, `share_batch_delivery_coordinator.dart:284-293`; Phase 2.4 fixed the metadata/relay-skip side but left the LAN bytes plaintext, like the composer).

File: `test/features/conversation/application/voice_local_wifi_recovery_test.dart` — update for ciphertext on the wire + deferred decrypt (receiver staging itself was pinned in 1.5).

#### 4.2 GREEN
- `conversation_wired.dart:1862-1894` (images/video) and `:2706-2765` (voice): encrypt once — extract `prepareEncryptedMediaArtifact(bridge, localFilePath)` (keygen+encrypt+hash) from `uploadMedia`; `uploadMedia` gains an optional pre-built-artifact param (and uses it instead of re-encrypting); composer builds the artifact first, then fires `sendLocalMedia(filePath: artifact.encryptedPath, ...)` and the relay upload concurrently. ⚠️ The `UploadMediaFn` typedef changes — update all four declared sites + fakes in the same step (`conversation_wired.dart:211`, `group_conversation_wired.dart:147`, `retry_incomplete_uploads_use_case.dart:37`, voice direct call) per the implements-no-default-bodies memory. The share coordinator calls the top-level `uploadMedia` directly (no typedef field), but its `SendToContactFn`-injected fakes and `share_batch_delivery_coordinator_test.dart` join the same-step update (R5).
- `share_batch_delivery_coordinator.dart:284-293`: LAN send uses the pre-built encrypted artifact (`prepareEncryptedMediaArtifact`); the always-on relay upload from Phase 2.6 consumes the same artifact (encrypt once).
- `local_media_sender.dart:107-173`: offer gains `enc: true` + `scheme`, sha256 over ciphertext, opaque mime (`kOpaqueMediaTransportMime`), drop `waveform`/`filename`.
- (Receiver-side `local_media_server.dart` / `linkIncomingLocalMedia` / enc-metadata pass-through: already landed in Phase 1.7 — no receiver change in this phase.)

#### 4.3 Gate
`flutter test test/core/local_discovery test/features/share test/features/conversation/application/voice_local_wifi_recovery_test.dart` green; `./scripts/run_test_gates.sh 1to1` + `baseline` green; new/changed LAN test files classified + `completeness-check` green. Rollout precondition re-checked: Phase-1 build is the deployed floor (Section 4).

---

### Phase 5 — End-to-end integration, Go harness, and device evidence

#### 5.1 Round-trip matrix completion (file authored in Phase 2.5 — no cross-phase red file)
File: `test/features/conversation/integration/one_to_one_media_encryption_round_trip_test.dart` (created red→green inside Phase 2; see 2.5). Extend here with the remaining matrix cells, labeled per the pin convention:
- `'voice round trip: encrypted m4a decrypts byte-identical'` — green-on-arrival pin (Phases 2+1).
- `'share-built attachment round-trips through the same decrypt path'` — green-on-arrival pin (Phase 2.4).
- LAN-leg round trip stays covered by `local_media_integration_test.dart` (Phase 4.1) — do not duplicate.

#### 5.2 RED — Go two-device proof harness
File: `go-mknoon/cmd/testpeer/commands.go` (`:112-122, 874-892`) + its test: add `blob_encrypt`/`blob_decrypt` commands so the standalone CLI harness can produce/verify ciphertext through the real `media_upload`/`media_download` path. RED: a harness-level script case asserting `media_download` output of an encrypted upload does NOT equal the plaintext fixture until `blob_decrypt` is applied. (No relay change: opacity already pinned by `TestE2EBlobOpacity`, `go-relay-server/media_test.go:448-477`; node privacy pins extend `PL014`'s exact-key-set pattern in `go-mknoon/node/media_test.go` if event payloads change — they should not.)

#### 5.3 GREEN + rebuild
testpeer commands only (no library behavior change). **Any go-mknoon change requires the full rebuild chain before device/simulator runs: `cd go-mknoon && PATH="$PATH:$(go env GOPATH)/bin" make all && cd ../ios && pod install` — `flutter run` alone does NOT rebuild Go; Android needs Go < 1.25 or patched wlynxg/anet.**

#### 5.4 Device/simulator evidence
- Extend `integration_test/media_message_journey_e2e_test.dart` (`:27-50`) with an encrypted-1:1 journey leg.
- Real-device run per Section 8.

#### 5.5 Gate
`flutter test test/features/conversation/integration` green; `cd go-mknoon && make test`; `cd go-relay-server && go test ./...`; `go test -tags integration ./integration/...` (auto-skips without relay); gate doc updated; `completeness-check` green.

---

### Phase 6 — Relay sidecar at-rest minimization (G7b — server-side, order-independent)

#### 6.1 RED
File: `go-relay-server/media_test.go` (harness: `setupTestEnv`, `:68`; restart pattern: `TestMediaStoreSurvivesRestart`, `:150`).
- `TestMediaSidecarAtRestOmitsSender` — upload a blob, read the persisted sidecar JSON from disk (`metaPath`, `media.go:267`), assert it carries no `from` value; then re-open the store over the same dataDir (`NewMediaStore` restart) and assert the recipient can still download AND ack-delete (proves auth never used `From`). **Fails today:** `From: remotePeer` is persisted (`media.go:484`).
- `TestMediaStoreLoadsLegacySidecarWithFromField` — green companion: a hand-written legacy sidecar containing `from` still loads and serves (`encoding/json` unknown-field tolerance).

#### 6.2 GREEN
`go-relay-server/media.go`: drop `From` from `mediaMeta` (`:35`) and the upload persist (`:484`) — the field is write-only; download/delete auth uses `To`/`AllowedPeers` (`:519-531, 577-587`); `handleMediaList` payloads shrink accordingly (no app callers). Operator visibility at upload time is unchanged — the live log at `:503` still prints the authenticated peer; this change removes only the **at-rest** sender→recipient linkage.

#### 6.3 Gate + deploy
`cd go-relay-server && go test ./...` green. Requires a relay deploy — coordinate with the pending 111 ack-delete relay deploy (same binary). No client-release coupling (Section 4); deployable before, between, or after the client phases.

---

## 6. Test matrix (media type × transport × direction)

| Media | Transport | Direction | Covering test file (phase) |
|---|---|---|---|
| image/video | relay | send | `test/features/conversation/application/upload_media_use_case_test.dart` (P2) |
| image/video | relay | receive (fresh download) | `test/features/conversation/application/download_media_use_case_test.dart` (P1) |
| image/video | relay | receive (adoption/orphan/retry) | `download_media_use_case_test.dart` adoption cases (P1) |
| voice | relay | send | `test/features/conversation/application/send_voice_message_use_case_test.dart` (P2) |
| voice | relay | receive | `download_media_use_case_test.dart` (P1) + `voice_local_wifi_recovery_test.dart` (P4) |
| any | relay | send retry (key coherence) | `retry_incomplete_uploads_use_case_test.dart`, `pending_message_retrier_test.dart` (P3) |
| any shared mime | relay + metadata | send via OS share sheet | `test/features/share/application/share_batch_delivery_coordinator_test.dart` (P2.4) |
| any shared mime | LAN | send via OS share sheet | `share_batch_delivery_coordinator_test.dart` LAN-ciphertext case (P4.1) |
| image/video/voice | LAN | send | `test/core/local_discovery/local_media_sender_test.dart` (P4) |
| image/video/voice | LAN | receive: ciphertext staging + deferred decrypt | `local_media_server_test.dart` + adoption-seam cases (P1.5); end-to-end `local_media_integration_test.dart` (P4) |
| any | LAN | mixed-version (floor receiver vs new LAN sender) | must never occur — Phase-1 floor gates the flip (Section 4); device evidence §8 item 5 documents the failure mode |
| key metadata | wire (v2 envelope) | both | `media_attachment_flow_test.dart`, `handle_incoming_chat_message_media_hydration_test.dart`, model test (P1/P2.5) |
| legacy plaintext | relay | receive (mixed-version) | `download_media_use_case_test.dart` legacy pins (P1) + round-trip test legacy case (P2.5) |
| any | full round trip | both | `test/features/conversation/integration/one_to_one_media_encryption_round_trip_test.dart` (P2.5, extended P5), `integration_test/media_message_journey_e2e_test.dart` (P5) |
| blob at rest on relay | relay store | — | testpeer harness case (P5) + device evidence (§8); opacity baseline `go-relay-server/media_test.go:448` |
| sidecar mime (opaque, 1:1) | relay store at rest | send | `upload_media_use_case_test.dart` opaque-mime case + group real-mime pin (P2.1); at-rest inspection (§8 #2) |
| sidecar `from` (removed) | relay store at rest | — | `go-relay-server/media_test.go` sidecar tests (P6) |
| blob crypto primitives | Go bridge | — | `go-mknoon/bridge/bridge_test.go` round-trip (P1); `go-mknoon/crypto/file_crypto_test.go` (existing) |

---

## 7. Risks and open questions carried forward

### Risks (actively mitigated by this plan; verify at each phase)
- **R1** Old-app garbage rendering + ack-delete destruction of the only ciphertext copy → receiver-first rollout (Section 4); residual risk if a stale build lingers — confirm population (OQ-3) before the Phase-2 flip.
- **R2** Ciphertext-size mismatch silently disabling the 111 P0 `.part`/orphan adoption fixes, or naive relaxation promoting ciphertext as a `.jpg` → Phase 1.3 pins `size + 16` adoption + decrypt-then-promote.
- **R3** Retry re-encryption vs persisted envelope = stale-envelope/blob key mismatch → undecryptable media (primary, code-verified); fresh-key rule additionally bounds the random-nonce-collision residual (`file_crypto.go:50-53` draws a fresh nonce per call) → KC-2 + Phase 3 pins.
- **R4** Group-policy bleed-through (mime/size/quarantine semantics, MIG-012 hash-scope class) into 1:1 → metadata-keyed decrypt, policy-parameterized helper, hash always `relay_blob`-scoped (Phase 1.7, Section 4).
- **R5** `UploadMediaFn` typedef / fake-fleet breakage (implements-no-default-bodies) → Phases 2.6/4.2 update all declared sites + fakes in the same step, including the share coordinator's `SendToContactFn` fakes and `share_batch_delivery_coordinator_test.dart` (the coordinator calls top-level `uploadMedia` directly, so the typedef change misses it but `prepareEncryptedMediaArtifact` adoption does not).
- **R6** Retry suites stubbing at `uploadMediaFn`/`responses['media:upload']` stay green while behavior changes underneath → Phase 3 wires the real `uploadMedia`; shared `FakeBridge.blob:encrypt` copies bytes unchanged and cannot detect plaintext leaks → content-transforming stub mandated (Phases 2.1, 2.4, 2.5, 3.1).
- **R7** `integrity_failed` enters 1:1 UX for the first time; `MediaGridCell` treats it as retryable (`:88-104`) against a relay copy that KC-3 guarantees is still alive within TTL — but TTL-expired retries need defined UX (carried to OQ-6).
- **R8** Decrypt runs outside the media-transfer watchdog with its own flat 5-min timeout (`bridge.dart:750`); large-video decrypt on old devices untested → device evidence item E4.
- **R9** 121-improvements is an uncommitted moving baseline (ack-delete/stall-watchdog work) — pin tests against branch state, re-verify anchors per session.

### Open questions (unresolved — owner input needed)
- **OQ-1 — RESOLVED (owner decision, 2026-06-12): relay metadata sidecar is in scope.** Disposition: relay-stored mime → opaque, 1:1 only (G7a, Phase 2.1/2.6); persisted `from` → removed relay-side (G7b, Phase 6); LAN enc-flagged offer mime → opaque (Phase 4.1/4.2); `to`/`size`/`created_at` and LAN offer `size` → accepted residual, rationale enumerated in Non-goal 3 (routing/auth, exact-size enforcement + stream-observable ciphertext length, TTL sweep).
- **OQ-2** "Should 1:1 adopt the full group integrity contract (contentHash + integrity_failed quarantine + render gating), or only encrypt-without-render-gating?" — this plan chooses: contentHash YES (encrypted-blob hash, checked at download when present), render gating NO (Non-goals). Confirm.
- **OQ-3** "What is the actual deployed-app population (TestFlight-only?) — can a forced-upgrade or sequenced two-release rollout eliminate the old-app-renders-garbage window, or must the plan add a wire-level capability hint?" (compat-wire, verbatim)
- **OQ-4** "What is the intended interop window: hard fail-closed (reject incoming plaintext 1:1 blobs immediately, mirroring the text path's encryptionRequired) or a grace period accepting legacy plaintext blobs already sitting on the relay (up to 7 days old)?" — plan assumes grace period; retirement date needs an owner decision. (media-types-transports, verbatim)
- **OQ-5** "Should profile avatars (Node.ProfileUpload) and posts media be covered by the same no-plaintext mandate, since they share the relay MediaStore?" — both are explicit Non-goals here; follow-up docs needed. (sender-path, verbatim)
- **OQ-6** Retry semantics for `integrity_failed` 1:1 media after relay TTL expiry (7 days) — permanent unavailable state + UX copy, or sender re-upload request protocol? Out of scope here; needs a small follow-up once Phase 1 telemetry exists.
- **OQ-7** "Does the Go media:upload/media:download direct phone-to-phone stream (servedByPhone=true) bypass relay storage entirely for online peers, and does blob encryption change any size/mime checks in go-mknoon/node/media.go?" — Dart-side keys verified; Go internals to confirm during Phase 2 (expected: none, Go stats the actual file). (media-types-transports, verbatim)

---

## 8. Evidence bar for closure (per project closure-bar convention)

1. **Suites:** all phase gates green — `flutter test test/features/conversation test/core/local_discovery test/core/services test/core/bridge`; `./scripts/run_test_gates.sh 1to1`; `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh baseline`; `./scripts/run_test_gates.sh completeness-check`; `cd go-mknoon && make test`; `cd go-relay-server && go test ./...`; `go test -tags integration ./integration/...`.
2. **Relay-at-rest ciphertext + sidecar (required):** operator-run relay + real-device 1:1 send (image, video, voice); inspect `dataDir/<to>/<id>.enc` and prove bytes ≠ original file (`cmp`), AND inspect the sidecar JSON — `mime == application/octet-stream`, no `from` field (on a post-Phase-6 relay) — then receiver renders the decrypted media correctly. The testpeer harness case (Phase 5.2) is the repeatable form.
3. **Device evidence — relay path:** real Pixel6 → iPhone13 (profile mode on iPhone per the iOS 26.5 JIT memory) both directions: image + ≥50 MB video + voice note + one OS share-sheet image batch; verify decrypt-commit, ack-delete only after commit, and a mid-transfer kill + retry adopting the encrypted staged artifact (R2 proof).
4. **Device evidence — LAN path:** same-Wi-Fi pair; capture or server-side inspection proving LAN bytes are ciphertext (staged artifact ≠ plaintext) for composer AND share-sheet sends, and that a LAN-first arrival decrypts once the message lands (Phase 1.5/4 ordering proof); voice lands as `.m4a`, not `.bin`.
5. **Mixed-version, BOTH transports:** one old-build receiver test against a new sender on the relay direction (expected: garbage render + ack-destroyed relay copy — documents WHY the hold exists) AND one on the LAN direction (expected: floor-without-1.5 receiver persists ciphertext as canonical `done` media — documents why the LAN receiver capability lives in build N); plus one new-build receiver consuming a legacy plaintext blob.
6. **Docs:** `test-gate-definitions.md` updated (new files classified; `upload_media_use_case_test.dart` added to the 1:1 gate); this doc updated with closure verdicts per phase.

---

## 9. Verified caveats

### 9.1 No DB migration needed
`media_attachments` already carries `content_hash`/`thumbnail_hash` (migration 058) and `encryption_key_base64`/`encryption_nonce`/`encryption_scheme` (migration 059) as nullable TEXT on DB v75 (`app_database_version.dart:1`). The 1:1 path merely stops writing NULLs.

### 9.2 Relay change is Phase 6 only; no Go library change required for the core
Relay is content-agnostic for blob bytes (verified `media.go:429-500` + `TestE2EBlobOpacity`); the core encryption path needs no relay change. The single relay change in this plan is the Phase-6 sidecar `from` removal (G7b) — isolated, client-invisible, deployable independently. Blob bridge commands exist for both platforms; go-mknoon work is test/harness-only (Phases 1.6, 5.2) — but ANY go-mknoon edit still requires `make all` + `pod install` before device runs (Caveat in 5.3).

### 9.3 `implements`-based fakes
Touched seams: `UploadMediaFn` typedef (P2/P4), share coordinator `SendToContactFn`/test fakes (P2.4/P4), possible message-repo param on `retryIncompleteUploads` (P3). No `Bridge` interface change is expected (all helpers are top-level functions). Update `test/shared/fakes/` + per-feature fakes in the same step as any signature change.

### 9.4 Predicate split: hasEncryptionMetadata vs hasEncryptionKeyMaterial
`hasEncryptionMetadata`'s null-scheme tolerance is kept for legacy/group compat on receive, but the 1:1 sender ALWAYS writes the scheme explicitly. Because the whitelist returns FALSE for unknown schemes, ciphertext ROUTING must key on the new scheme-agnostic `hasEncryptionKeyMaterial` (Section 3) — Phase 1.1 pins both predicates and Phase 1.2 pins unknown-scheme=fail-closed-without-ack. Do not ship Phase 2 without those pins.

### 9.5 Line-number re-check
All file:line anchors verified 2026-06-12 against the UNCOMMITTED 121-improvements tree (contains the 111 P0 fixes, move-scale, and voice-wake-lock work). Re-verify before each session; re-run the recon agents if the tree shifts materially.

### 9.6 Using the arch graph during implementation
Arch-graph coverage was spot-verified 2026-06-12 against this plan's full change surface: every Phase 1–6 production file, its test files, and the fake fleet are noded with line numbers — including `go-relay-server/media.go`/`media_test.go` (Phase 6) and `go-mknoon/cmd/testpeer/commands.go` (Phase 5.2, `handleCommand()` at `:31`). Two disciplines for implementation sessions:
1. **Anchor `graphify query` on 1–2 exact symbol names** (e.g. `graphify query "uploadMedia isGroupUpload"`), never prose: natural-language or many-anchor queries dilute into junk nodes (bare imports, `where`/`calls`). Go symbols anchor case-insensitively (`handlecommand` resolves `handleCommand()`); a query that comes back empty means RE-ANCHOR on a different symbol, not "the code doesn't exist" — testpeer was briefly misdiagnosed as un-graphed for exactly this reason.
2. **Refresh the graph after every edit batch:** `./graphify-arch/refresh_arch_graph.sh` from the repo root for the arch graph (NEVER run graphify build/update with cwd inside `graphify-arch/` — it clobbers the graph with its own meta files), plus `graphify update .` for the full graph per CLAUDE.md. Each phase shifts the next phase's line numbers; 9.5's per-session anchor re-verification is only meaningful against a current graph.

---

## Review resolution log

Adversarial review 2026-06-12 (11 findings: 1 blocker, 3 major, 7 minor). All claims re-verified against source before acting.

**Blocker — missing share-sheet sender (LAN-XOR-relay plaintext): FIXED.** Verified `share_batch_delivery_coordinator.dart:284-324` (raw `sendLocalMedia`, metadata-free attachment + `continue` past `uploadMedia` on LAN success). Section 1 now names four entry points; new Phase 2.4 (RED) + 2.6 GREEN drop the relay-skip and make the share attachment carry encryption metadata (G5-gate safe); Phase 4.1/4.2 flip the share LAN bytes to ciphertext; matrix rows, R5, 9.3, and Evidence #3/#4 updated.

**Major — Phase 4 violates receiver-first ordering on LAN (duplicate findings, tdd-rigor + compat-security): FIXED** by moving the entire LAN receiver capability (enc-flagged staging, `linkIncomingLocalMedia` deferral, `.m4a` mapping, enc-metadata pass-through, adoption-seam tests) into Phase 1 (new 1.5 RED + 1.7 GREEN), making build N the floor for BOTH transports; Phase 4 is now sender-only with an explicit LAN floor statement; Section 4 documents the floor-receiver ciphertext-as-done failure chain (`local_media_server.dart:428-462`, `main.dart:1764-1782`, `download_media_use_case.dart:682-688`); mixed-version LAN cell added to the matrix and Evidence #5.

**Major — fake-RED tests (1.1, 2.1 policy-skip, two 3.1 retry tests): FIXED.** Verified each: `media_attachment.dart:93-94` already whitelists null-or-v1; mime/size policy already inside `if (isGroupUpload)` (`upload_media_use_case.dart:217-239, 247-268`); retry already persists via `uploaded.copyWith` → `saveAttachment` (`retry_incomplete_uploads_use_case.dart:246-250`). All four relabeled as explicit green-on-arrival pins; 1.1 regained a genuine RED (the new `hasEncryptionKeyMaterial` predicate); 3.2 GREEN scoped to envelope invalidation only with a pointer to the existing `:246-250` persistence.

**Major — discriminator case 3 unimplementable on `isEncrypted`: FIXED.** Verified `isEncrypted == hasEncryptionMetadata` returns FALSE for unknown schemes, which would route case 3 into the plaintext promote+ack path. Added the scheme-agnostic `hasEncryptionKeyMaterial` predicate (Section 3, 1.1 RED, 1.7 GREEN, Section 4 discriminator, 9.4): key material routes custody; the whitelist gates v1 decrypt; key material + unknown scheme → `integrity_failed`, artifact preserved, no ack.

**Minor — posts second plaintext upload site (`pass_post_along_use_case.dart:589`): REJECTED.** The claim of "zero blob encryption" misreads the code: that site runs `callBlobKeygen` (`:578`) + `callBlobEncrypt` (`:580-584`) and uploads `filePath: encryptedPath` (`:589-594`). `attach_post_media_use_case.dart:246` remains the only plaintext posts upload. Added a clarifying note to the Posts non-goal so the follow-up doc doesn't mis-scope.

**Minor — voice temp residue: FIXED** (2.3 RED test + 2.6 one-line call-site `deleteSourceWhenDone: true`; safe because the voice LAN send is awaited before upload, `conversation_wired.dart:2708-2718`).

**Minor — 1.5 RED mislabel + 5.1 cross-phase red file: FIXED** (Go pins renamed "Coverage pins" as 1.6; round-trip file authoring moved to Phase 2.5 so it transitions red→green inside one phase; 5.1 is now matrix completion with labeled pins).

**Minor — 1.2 mirror anchor mis-cite: FIXED** (re-pointed to the fail-closed template at `download_media_use_case_test.dart:1219-1257` with inline expected assertions; `:1259-1285` is the success path).

**Minor — 1.1 'fails today' inversion: FIXED** (folded into the fake-RED + predicate fixes above).

**Minor — KC-2 nonce-reuse overstatement: FIXED** (KC-2 + R3 reworded: stale-envelope/blob key mismatch primary, nonce-collision bound secondary — `file_crypto.go:50-53` draws a fresh nonce per call; 2.6 additionally deletes the `?? localFilePath` fallback at `upload_media_use_case.dart:288`).

---

## Closure log (2026-06-12, host evidence)

All six phases implemented TDD on 121-improvements (uncommitted). Per-phase verdicts:

- **Phase 1 — CLOSED (host).** `hasEncryptionKeyMaterial` predicate + pins; direct decrypt-adopt with `.enc` staging, fail-closed unknown-scheme (case 3), KC-3 ack-after-commit, transient-vs-cryptographic failure split; adoption gate `size + 16` + decrypt-then-promote; duplicate-replay stale-artifact invalidation (threaded through `ChatMessageListener`); LAN receiver: `MediaOffer`/`LocalMediaReady` `enc`/`encScheme` fields, enc offers exempt from the mime whitelist, `.enc` staging in `LocalMediaServer`, `linkIncomingLocalMedia` `stagedForDecrypt` deferral (never links/completes enc artifacts; moves them to the download seam's `$absolutePath.enc`), `audio/mp4 → .m4a`; Go blob bridge pins (`TestBlobKeygenEncryptDecryptRoundTrip` incl. the plaintext+16 size relationship, `TestBlobDecryptWrongKeyFails`). Deviation from plan 1.7: `restoreEncryptedCompanionIfAvailable` stays group-only — the direct `.enc` artifact is handled by the (policy-free) adoption seam instead, avoiding group mime/size policy bleed-through (R4); the 1.5 ordering seam is pinned compositionally (link test pins exact staging-path placement; the 1.3 adoption test pins zero-`media:download` decrypt-promote + post-commit ack).
- **Phase 2 — CLOSED (host).** `uploadMedia` encrypts unconditionally (`?? localFilePath` fallback deleted; structurally ciphertext-only), opaque transport mime for 1:1 (`kOpaqueMediaTransportMime`) with the group real-mime pin, `deleteSourceWhenDone` (durable-copy-guarded best-effort unlink; voice + composer pass true), G5 fail-closed send gate (`SendChatMessageResult.mediaEncryptionRequired`, `DIRECT_MEDIA_ENCRYPTION_REQUIRED`), share coordinator LAN-XOR-relay `continue` removed (always relay-uploads), round-trip integration file authored red→green (`one_to_one_media_encryption_round_trip_test.dart`). `upload_media_use_case_test.dart` + the round-trip file added to the 1to1 gate (script + doc), completeness-check 826/826.
- **Phase 3 — CLOSED (host).** KC-2: re-upload with changed key invalidates the parent message's persisted `wire_envelope` (via `saveMessage(copyWith(wireEnvelope: null))` — no repo-interface change, fake fleet untouched), `RETRY_INCOMPLETE_UPLOAD_WIRE_ENVELOPE_INVALIDATED` telemetry; green-on-arrival pins for fresh-key-per-upload + distinct-keys-per-blob through the REAL uploadMedia; end-to-end pin: rebuilt envelope carries the row's current key.
- **Phase 4 — CLOSED (host).** Encrypt-once: `EncryptedMediaArtifact` + `prepareEncryptedMediaArtifact`; `uploadMedia` `preparedArtifact` param; composer (images/video + voice) and share coordinator build the artifact, stream it on the LAN leg (`enc: true`, scheme, opaque mime, ciphertext sha256 via the streamed file, no waveform/filename in the cleartext offer) and reuse it for the relay upload; LAN-leg failures fail closed (never raw bytes). `sendLocalMedia` chain (P2PService → impl → LocalP2PService → LocalWsServer → LocalMediaSender) threaded with `enc`/`encScheme`. `UploadMediaFn`/`SendVoiceMessageFn` typedef + fake fleet updated in the same step (R5).
- **Phase 5 — CLOSED (host; device legs open).** Matrix cells: voice + share round trips (pins), enc LAN E2E (server-to-server ciphertext staging, `.enc` persist), legacy plaintext round trip; testpeer `blob_keygen`/`blob_encrypt`/`blob_decrypt` + `TestHandleCommandBlobRoundTrip` opacity pin; `media_message_journey_e2e_test.dart` 1:1 leg now runs full encrypted metadata + receiver decrypt-adopt. go-mknoon change is CLI/test-only (no gomobile rebuild required for host runs; rebuild chain required before device runs).
- **Phase 6 — CLOSED (code + DEPLOYED).** `mediaMeta.From` removed (struct + persist); `TestMediaSidecarAtRestOmitsSender` (incl. restart + recipient download + ack-delete auth proof) and `TestMediaStoreLoadsLegacySidecarWithFromField`; full `go-relay-server` suite green. **Deployed 2026-06-12 19:50:31 UTC** to the EC2 relay (mknoun.xyz / 13.60.15.36, `relay-server.service`): linux/amd64 build from this branch (also carries the 111 ack-delete relay behavior), previous binary backed up on-host (`~/relay-server-backup-pre-<stamp>`), service active, legacy sidecars loaded cleanly. Verified at rest: pre-deploy sidecars contain `"from"`, post-deploy sidecars (written by the live `go test -tags integration` media run) do NOT.

Gates (2026-06-12): `flutter test test/features/conversation test/features/share test/core` green; `./scripts/run_test_gates.sh 1to1` green (gate now includes the two new members); `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh baseline` green; `completeness-check` 826/826; `cd go-mknoon && make test` green; `cd go-relay-server && go test ./...` green. Groups suite: **2016/2016 green** after fixing three failures that were verified pre-existing against a HEAD worktree (none were 112 regressions):
1. **PL-013** (`group_media_fanout`) — pinned the pre-111 "delete partial on failure" contract. Resolution: production improvement + test update — `restoreEncryptedCompanionIfAvailable` now treats an under-sized staged companion (< plaintext + 16) as a stale partial: deletes it and falls through to a fresh relay download instead of quarantining the row as `integrity_failed`; the test now pins preserve-on-transient (INV-1) + single-retry cleanup-and-complete.
2. **`group_list_wired` bridgeError-accept** — stale pin of the pre-106 contract; rewritten to the 106/GCA-004 contract (inline invite consumed + group materialized for background recovery on relay-side join failure; key-package invites keep the rollback path).
3. **`group_conversation_screen` media rows** — the pre-session `media_grid_cell` change gates the video overlay on the local file existing on disk; the fixture now uses a done attachment with a real (sync-written) temp file.
Also: the in-flight dedup test passes `enforceGroupMediaPolicy: true` on its pre-flight call (the 112 dedup key is policy-aware by design) with a validation-coherent JPEG fixture, and PL-012 gained a durable all-rows-done wait (it asserted `done` after only the download COMMANDS were issued — a load-timing flake).

**Still open (per Section 4/8):** TestFlight sequencing — Phase 1 (receiver capability) must be the deployed floor before any build containing the Phase-2/4 sender flips ships (OQ-3 population confirmation); device evidence §8 items 2–5 (relay-at-rest `cmp` + sidecar inspection, Pixel6↔iPhone13 both directions incl. ≥50 MB video + mid-transfer kill/adopt, LAN ciphertext capture, mixed-version documentation runs); relay deploy for Phase 6.

---

## Amendment log

**2026-06-12 — Relay metadata sidecar brought into scope (owner decision; resolves OQ-1).** Added G7 (opaque transport mime for encrypted 1:1 uploads + relay stops persisting `from`), Phase 2.1 opaque-mime RED + group real-mime pin, Phase 2.6 GREEN mime gating, Phase 4 opaque mime on enc-flagged LAN offers, new Phase 6 (relay-side `from` removal, order-independent), two matrix rows, evidence #2 sidecar inspection, and rewrote Non-goal 3 to enumerate the accepted residual metadata (`to`, `size`, `created_at`, LAN offer `size`, live connection metadata). Verified before amending: the relay-returned mime is consumed ONLY by the group-gated `relay_mime_mismatch` cross-check (`download_media_use_case.dart:1330-1371`) so opaque mime is skew-free for 1:1 but MUST stay group-excluded (Alternatives rejected #7); `mediaMeta.From` is write-only (`media.go:484`; download/delete auth uses `To`/`AllowedPeers` at `:519-531, 577-587`); `media:list` has no app callers (`callP2PMediaList`, `p2p_bridge_client.dart:908`, is dead code).
