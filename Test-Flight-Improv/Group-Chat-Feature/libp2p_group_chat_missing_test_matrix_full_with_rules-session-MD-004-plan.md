# MD-004 Session Plan - Per-Media Encryption Key Separation

Session id: `MD-004`  
Source row id: `MD-004`  
Source doc: `Test-Flight-Improv/Group-Chat-Feature/libp2p_group_chat_missing_test_matrix_full_with_rules.md`  
Breakdown: `Test-Flight-Improv/Group-Chat-Feature/libp2p_group_chat_missing_test_matrix_full_with_rules-session-breakdown.md`  
Plan output: `Test-Flight-Improv/Group-Chat-Feature/libp2p_group_chat_missing_test_matrix_full_with_rules-session-MD-004-plan.md`

Final verdict: `evidence-gated`, safe to execute only as a proof-first implementation session. It is unsafe to mark `MD-004` `Covered` today. Current repo evidence shows group media descriptors have MIME, size, content hash, and optional thumbnail hash, but no first-class per-object media encryption key, media encryption nonce, derivation context, or decrypt-before-display path for group media blobs.

## evidence collector summary

- Source matrix row `MD-004` is P0/Open and requires proof that each media object uses a distinct encryption key or derivation context. Expected result: compromise or reuse of one media key does not decrypt unrelated media objects.
- Breakdown classifies `MD-004` as `repo_external_proof` / evidence-gated. The next execution must start with a row-specific proof/regression before adding production changes.
- `MD-001`, `MD-002`, and `MD-003` are now closed around MIME allowlist, size limits, and content/thumbnail hash verification only. They do not prove encryption key separation.
- `MediaAttachment` currently has `contentHash` and `thumbnailHash`, but no `isEncrypted`, `encryptionKeyBase64`, `encryptionNonce`, `derivationContext`, or equivalent media encryption metadata.
- `uploadMedia` computes a SHA-256 hash for group uploads, then calls `callP2PMediaUpload` with the original `localFilePath`. It does not call `callBlobKeygen`, `callBlobEncrypt`, HKDF, or any group-media-specific encryptor before relay upload.
- `downloadMedia` downloads the relay blob directly to the display path, then validates MIME, size, and content hash. It does not decrypt a downloaded group media blob with a per-object key or context.
- `sendGroupMessage` puts `MediaAttachment.toJson()` into live `group:publish` and encrypted offline replay payloads. That JSON contains `id`, MIME, size, media type, dimensions/duration, waveform, `contentHash`, and `thumbnailHash`; it does not contain media encryption material or derivation metadata.
- Go `PublishGroupMessage` encrypts the group message JSON envelope with the group epoch key and random nonce. That protects the descriptor JSON in PubSub and group inbox replay, but not the external media blob bytes referenced by descriptor `id`.
- Go `MediaUpload` streams raw file bytes from `filePath` into the relay media protocol. Go `MediaDownload` streams relay bytes back to `outputPath`.
- `go-relay-server/media.go` stores the received stream at `media.blobPath(meta.To, id)`, whose suffix is `.enc`, but there is no relay-side encryption. The suffix is not proof that stored group blobs are encrypted.
- Relay group media tests prove `allowedPeers` authorization and no auto-delete for group blobs, not per-object encryption or key separation.
- Existing blob crypto helpers exist: `callBlobKeygen`, `callBlobEncrypt`, `callBlobDecrypt`, Go `BlobKeygen`, `BlobEncrypt`, `BlobDecrypt`, and `go-mknoon/crypto/file_crypto.go`. Posts already use a fresh key and nonce per repost media blob. Group media does not use that path today.
- The older `Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-MD-004-plan.md` and `test-inventory.md` references to `MD-004` are for a different same-user/multi-device proof row and must not be used as closure evidence for this media key-separation row.

## real scope

Implement only group media object encryption/key separation for `MD-004`.

In scope:

- Add a row-specific failing proof/regression first.
- Ensure each group media object is encrypted before relay upload using either a fresh per-object key or a cryptographic derivation context that is unique per object.
- Ensure descriptor metadata needed to decrypt is protected inside the existing encrypted group message / encrypted group replay envelope and is not visible to the relay as plaintext.
- Ensure the receiver verifies the encrypted blob hash, decrypts with the correct object key/context, validates plaintext MIME/size, and only then marks media displayable.
- Preserve MD-001 MIME validation, MD-002 size validation, and MD-003 integrity validation in the new encrypted-blob flow.
- Update focused Flutter tests, Go crypto/bridge tests if the bridge contract changes, and relay/raw-protocol proof where useful.

Out of scope:

- Chunk resume (`MD-005`), content dedupe (`MD-006`), thumbnail privacy (`MD-007`), removed-member future-media access (`MD-011`), quarantine UI (`MD-012`), full simulator media matrix (`MD-014`), and relay-wide redesign.
- 1:1 chat media behavior and post media behavior except where an existing helper is reused without changing those contracts.
- MLS/key epoch redesign, group key rotation policy, or DB-wide secret-storage policy beyond fields needed for current media decryption.

## closure bar

`MD-004` can be marked `Covered` only when all of these are true:

- Every new group media upload encrypts the relay blob bytes before `media:upload`.
- Two media objects in the same message and two media objects in different messages cannot decrypt with each other's key/context.
- The sender and receiver descriptors carry enough authenticated/protected metadata to decrypt the correct blob and reject wrong-key/wrong-context attempts.
- Relay-visible media storage and media protocol traffic contain encrypted blob bytes, not the selected plaintext file bytes.
- `contentHash` semantics remain explicit and tested. Preferred closure is hash over the encrypted relay blob bytes, with plaintext MIME/size validation happening after decrypt.
- Live PubSub and encrypted group offline replay both carry the same per-object encryption metadata and preserve distinct object keys/contexts.
- Sender retry, incomplete upload retry, failed-message retry, group listener auto-download, foreground drain, new-member media onboarding, and group media fan-out all preserve encryption metadata.
- Existing MD-001, MD-002, and MD-003 protections still pass.

`MD-004` must remain `Partial` or blocked if:

- Group media still uploads plaintext relay blobs.
- Only the group message descriptor JSON is encrypted while media blob bytes remain plaintext.
- The implementation relies only on random AES-GCM nonces under one reusable media key and cannot prove distinct object keys or derivation contexts.
- Media encryption keys are stored or logged in a relay-visible field.
- The row has host-unit proof only but no integration proof that live/replay group descriptors preserve the encryption metadata.

## source of truth

- Current repo code and tests are authoritative when they disagree with stale prose.
- Primary source row: `Test-Flight-Improv/Group-Chat-Feature/libp2p_group_chat_missing_test_matrix_full_with_rules.md` row `MD-004`.
- Breakdown row: `Test-Flight-Improv/Group-Chat-Feature/libp2p_group_chat_missing_test_matrix_full_with_rules-session-breakdown.md` row `MD-004`.
- Test coverage inventory: `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`.
- Existing MD-001/MD-002/MD-003 closure evidence is authoritative only for MIME, size, and hash/integrity behavior. It must not be reinterpreted as key-separation proof.
- The unrelated `Discussion_and_announcement...MD-004` plan is not a source of truth for this row.
- Named gates come from `scripts/run_test_gates.sh`; `SMOKE-GAP-05` is a matrix label, not a shell target.

## session classification

`evidence-gated`.

Execution is safe only if the executor starts by adding/running a row-specific proof that fails against today's repo because group media lacks per-object key/context separation. If that proof unexpectedly passes with exact current-code evidence, stop and reclassify as `stale/already-covered` with file/test evidence. The expected outcome is that the proof exposes the current plaintext/no-key gap, after which targeted implementation and tests are warranted.

## exact problem statement

The app currently protects group media descriptors with group message encryption and protects relay downloads with `allowedPeers`, MIME, size, and content-hash checks. It does not encrypt each group media blob before relay upload and does not attach a distinct media encryption key or derivation context to each media object.

The user-visible and security risk is that relay-visible media blobs, local retry descriptors, and downloaded files are protected against corruption but not against object-level key compromise or plaintext relay storage. If a future or external path assumes media keys exist, that assumption is false today.

The behavior that must improve: each group media object must have cryptographic separation from unrelated media objects, so compromise of one media object key/context does not decrypt another. Existing send, receive, retry, replay, and display behavior must stay intact for valid image, GIF, video, and voice media.

## files and repos to inspect next

Production Flutter files:

- `lib/features/conversation/domain/models/media_attachment.dart`
- `lib/features/conversation/application/upload_media_use_case.dart`
- `lib/features/conversation/application/download_media_use_case.dart`
- `lib/features/groups/application/send_group_message_use_case.dart`
- `lib/features/groups/application/handle_incoming_group_message_use_case.dart`
- `lib/features/groups/application/group_offline_replay_envelope.dart`
- `lib/features/groups/application/group_message_listener.dart`
- `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`
- `lib/features/groups/application/retry_incomplete_group_uploads_use_case.dart`
- `lib/features/groups/application/retry_failed_group_messages_use_case.dart`
- `lib/features/groups/presentation/screens/group_conversation_wired.dart`
- `lib/core/bridge/bridge.dart`
- `lib/core/bridge/p2p_bridge_client.dart`
- `lib/core/bridge/bridge_group_helpers.dart`
- `lib/core/database/helpers/media_attachments_db_helpers.dart`
- `lib/core/database/migrations/010_media_attachments.dart`
- `lib/core/database/migrations/058_media_attachment_integrity_columns.dart`
- `lib/main.dart` if a new media migration is added.

Go and relay files:

- `go-mknoon/crypto/file_crypto.go`
- `go-mknoon/crypto/group.go`
- `go-mknoon/bridge/bridge.go`
- `go-mknoon/node/media.go`
- `go-mknoon/node/pubsub.go`
- `go-relay-server/media.go`
- `go-relay-server/media_test.go`

Tests to inspect/extend:

- `test/features/conversation/application/upload_media_use_case_test.dart`
- `test/features/conversation/application/download_media_use_case_test.dart`
- `test/features/conversation/domain/models/media_attachment_test.dart`
- `test/core/database/helpers/media_attachments_db_helpers_test.dart`
- New migration test if encryption columns are added.
- `test/features/groups/application/send_group_message_use_case_test.dart`
- `test/features/groups/application/handle_incoming_group_message_use_case_test.dart`
- `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`
- `test/features/groups/application/group_message_listener_test.dart`
- `test/features/groups/application/retry_incomplete_group_uploads_use_case_test.dart`
- `test/features/groups/application/retry_failed_group_messages_use_case_test.dart`
- `test/features/groups/presentation/group_conversation_wired_test.dart`
- `test/features/groups/integration/group_media_fanout_test.dart`
- `test/features/groups/integration/group_new_member_onboarding_test.dart`
- `test/features/groups/integration/announcement_new_reader_onboarding_test.dart`
- `test/features/groups/integration/group_resume_recovery_test.dart`
- `go-mknoon/crypto/file_crypto_test.go`
- `go-mknoon/bridge/bridge_test.go`
- `go-mknoon/node/media_test.go`

## existing tests covering this area

Covered adjacent behavior:

- `group_media_mime_policy_test.dart` and expanded upload/send/receive tests cover MD-001 MIME validation.
- `group_media_size_policy_test.dart` and expanded upload/send/receive tests cover MD-002 size validation.
- `group_media_integrity_policy_test.dart`, model/migration/helper tests, upload/download tests, listener tests, feed/group UI tests, foreground drain, and fake-network fan-out cover MD-003 hash and display eligibility.
- `group_media_fanout_test.dart` proves existing group media descriptors fan out through fake-network group paths and download triggers.
- `go-relay-server/media_test.go` proves group `allowedPeers` authorization and no auto-delete for group media.
- `go-mknoon/crypto/file_crypto_test.go` proves generic AES-GCM file encryption/decryption, wrong-key failure, tamper failure, and large-file round trip.
- Post repost media code already demonstrates a repo-local pattern for fresh per-object blob keys and nonces.

Missing for `MD-004`:

- No group media model fields for object encryption key, nonce, derivation version, or context.
- No upload test proving group media calls blob encryption before relay upload.
- No download test proving group media decrypts after encrypted-blob hash verification and before plaintext display checks.
- No live publish or encrypted replay test proving per-object metadata is preserved.
- No test proving two media objects in one message use distinct keys/contexts.
- No test proving cross-object decrypt fails.
- No raw relay/protocol proof that group media bytes stored or streamed by the relay are encrypted bytes rather than the selected plaintext file.

## regression/tests to add first

Add the first proof as a desired-behavior regression, not as a test that blesses current plaintext behavior.

1. Add or extend a Flutter unit proof around `uploadMedia`:
   - For group uploads (`allowedPeers != null`), expect `blob:keygen` and `blob:encrypt` or an equivalent derivation/encrypt command before `media:upload`.
   - Assert `media:upload.filePath` is the encrypted file path or derived encrypted blob path, not the selected plaintext path.
   - Upload two group media files and assert distinct per-object keys or distinct derivation contexts.
   - This should fail before implementation and is the evidence gate.

2. Add model/DB descriptor tests:
   - `MediaAttachment` round-trips the chosen encryption metadata through `copyWith`, `toMap/fromMap`, and `toJson/fromJson`.
   - Any new migration adds encryption fields idempotently.
   - Legacy descriptors remain readable but are not considered coverable as new verified encrypted group media.

3. Add send/replay tests:
   - `send_group_message_use_case_test.dart` proves live `group:publish` media JSON and encrypted offline replay plaintext include per-object encryption metadata.
   - Multi-attachment test proves keys/contexts differ within the same message.
   - Retry tests prove persisted completed media can resend with the same object metadata without reusing another object's key/context.

4. Add receive/download tests:
   - `handle_incoming_group_message_use_case_test.dart` rejects malformed or missing encryption metadata for new group media descriptors once the encrypted contract is active.
   - `download_media_use_case_test.dart` verifies encrypted blob hash before decrypt, decrypts with the object's key/context, then validates plaintext MIME/size before marking `done`.
   - Wrong key/context and cross-object key attempts fail and do not mark media displayable.

5. Add one integration proof:
   - Extend `group_media_fanout_test.dart` or add a focused group-media encryption integration test proving Alice sends two media attachments, Bob receives distinct encryption metadata, Bob downloads/decrypts both, and cross-key decrypt fails.

6. Add Go/raw proof only where it proves a real boundary:
   - Keep or extend `go-mknoon/crypto/file_crypto_test.go` for wrong-key/cross-key failure if the existing blob crypto helpers remain the implementation.
   - If the bridge API changes, extend `go-mknoon/bridge/bridge_test.go`.
   - If a raw relay harness can compare source plaintext to stored bytes in a client-driven test, assert the stored group blob differs from plaintext. Do not add a relay-only encryption test that merely uploads already-encrypted bytes and calls that proof of client behavior.

## step-by-step implementation plan

1. Confirm no one has already added group media encryption fields since this plan was written:
   - Search for `encryptionKeyBase64`, `encryptionNonce`, `derivationContext`, `mediaKey`, `blob:keygen`, and `blob:encrypt` in group media paths.
   - If exact group MD-004 coverage already exists, stop and reclassify with evidence.

2. Add the proof-first failing regression:
   - Prefer `upload_media_use_case_test.dart` plus a focused group send/replay test.
   - The failure should show that group media currently calls `media:upload` with plaintext `localFilePath` and no object key/context.

3. Choose the narrow crypto contract:
   - Preferred low-risk path: reuse existing blob crypto helpers and post media precedent: generate one random AES-256 key per media object, encrypt the selected file with AES-GCM, upload encrypted bytes, and carry key+nonce inside the encrypted group message/replay descriptor.
   - Alternative path: derive per-object keys from the group epoch key with a stable HKDF info/context containing at least `groupId`, `messageId`, `blobId`, media index, and version. Use this only if it avoids storing raw media keys without broad new crypto surface.
   - Do not rely on unique nonces alone under one reusable media key.

4. Extend `MediaAttachment` and persistence:
   - Add only the minimal fields needed for chosen contract, such as `isEncrypted`, `encryptionKeyBase64`, `encryptionNonce`, `encryptionContextVersion`, or `derivationContext`.
   - Add one new migration rather than editing already-landed migration 058.
   - Update DB helpers, repository mapping, in-memory fakes, and tests.

5. Encrypt before group upload:
   - For `allowedPeers != null`, validate MIME and size on plaintext first, then encrypt to a temporary encrypted file.
   - Compute `contentHash` over the encrypted relay blob bytes unless implementation evidence proves a better MD-003-compatible invariant.
   - Call `media:upload` with the encrypted file path.
   - Preserve the sender's local plaintext path for display, but store enough metadata to retry/resend safely.
   - Delete temporary encrypted files after upload attempts where safe.

6. Publish protected metadata:
   - Include object encryption metadata in `MediaAttachment.toJson()` only for group media descriptors that are already inside encrypted group publish/replay envelopes.
   - Ensure flow events and logs never emit raw media keys.
   - Avoid adding relay-visible plaintext key material.

7. Receive and store metadata:
   - Validate required encryption metadata for new group media descriptors.
   - Preserve metadata through live receive, duplicate enrichment, encrypted inbox replay, foreground push drain, and new-member onboarding.

8. Decrypt on download:
   - Download encrypted blob to a temporary encrypted path.
   - Verify encrypted `contentHash` before decrypt.
   - Decrypt with the object's key/context to the display path.
   - Validate plaintext MIME and size after decrypt.
   - Mark `done` only after both encrypted integrity and plaintext policy pass.
   - Wrong key/context, malformed key/nonce/context, decrypt failure, or hash mismatch must leave media unavailable and not display plaintext.

9. Preserve retry paths:
   - Update incomplete-upload retry to reuse the attachment's own object encryption metadata or regenerate a new object key only before descriptor publication, not after other peers may have received descriptors.
   - Update failed-message retry to resend from persisted completed attachments with their own metadata.
   - Ensure `wireEnvelope` and retry payload handling do not accidentally log or relay plaintext keys outside encrypted envelopes.

10. Run focused tests, then broad gates.

11. Update closure docs only after green gates:
   - Source matrix row `MD-004`.
   - `test-inventory.md`.
   - Breakdown ledger if this pipeline run requires status bookkeeping.

Stop conditions:

- If proof-first tests unexpectedly pass with exact current code evidence, stop before production changes and reclassify.
- If the only feasible design requires relay-wide storage redesign, MLS/key-schedule redesign, or a broad secret-storage policy change, stop and mark `MD-004` prerequisite-blocked.
- If encryption metadata cannot be kept out of relay-visible plaintext, stop and do not mark Covered.

## risks and edge cases

- A `.enc` relay filename is not encryption proof.
- Hash semantics can regress MD-003 if the code verifies plaintext hash while uploading encrypted blobs. Decide and test encrypted-blob hash explicitly.
- Sender local display uses plaintext durable copies while receiver downloads encrypted relay bytes. Tests must cover both paths.
- Retrying an already-published media descriptor with a different key/nonce would strand receivers. Retry must preserve descriptor metadata after publication.
- Incomplete upload retry before publication may safely regenerate encrypted bytes only if the descriptor has not escaped.
- Offline inbox replay must preserve the same media metadata as live PubSub.
- Flow events, logs, bridge debug output, and relay push metadata must not expose raw media keys.
- Legacy hash-only group media already in local DB may be displayed unavailable rather than upgraded silently.
- DB secret-storage policy may become a follow-up (`DB-006`) if the chosen implementation stores media keys in SQLCipher tables.

## exact tests and gates to run

Focused Flutter tests:

- `flutter test --no-pub test/features/conversation/application/upload_media_use_case_test.dart`
- `flutter test --no-pub test/features/conversation/application/download_media_use_case_test.dart`
- `flutter test --no-pub test/features/conversation/domain/models/media_attachment_test.dart`
- `flutter test --no-pub test/core/database/helpers/media_attachments_db_helpers_test.dart`
- `flutter test --no-pub test/core/database/integration/full_migration_chain_test.dart`
- `flutter test --no-pub test/core/database/migrations/059_media_attachment_encryption_columns_test.dart` if a new migration 059 is added.
- `flutter test --no-pub test/features/groups/application/send_group_message_use_case_test.dart`
- `flutter test --no-pub test/features/groups/application/handle_incoming_group_message_use_case_test.dart`
- `flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`
- `flutter test --no-pub test/features/groups/application/group_message_listener_test.dart`
- `flutter test --no-pub test/features/groups/application/retry_incomplete_group_uploads_use_case_test.dart`
- `flutter test --no-pub test/features/groups/application/retry_failed_group_messages_use_case_test.dart`
- `flutter test --no-pub test/features/groups/presentation/group_conversation_wired_test.dart`

Focused integration tests:

- `flutter test --no-pub test/features/groups/integration/group_media_fanout_test.dart`
- `flutter test --no-pub test/features/groups/integration/group_new_member_onboarding_test.dart`
- `flutter test --no-pub test/features/groups/integration/announcement_new_reader_onboarding_test.dart`
- `flutter test --no-pub test/features/groups/integration/group_resume_recovery_test.dart`
- `flutter test --no-pub -d macos integration_test/foreground_group_push_drain_test.dart` when foreground drain is affected and local device selection requires `-d`.

Go tests:

- `(cd go-mknoon && go test ./crypto ./bridge ./node)`
- `(cd go-relay-server && go test ./... -run 'GroupMedia|Media')`

Broad gates:

- `flutter test --no-pub test/features/groups`
- `flutter test --no-pub test/features/groups/integration`
- `./scripts/run_test_gates.sh groups`
- `./scripts/run_test_gates.sh completeness-check`
- `git diff --check`

## known-failure interpretation

- The first desired-behavior MD-004 proof should fail before implementation. That is expected and is the evidence gate. It must pass after implementation.
- Existing dirty-tree failures unrelated to touched files must be rerun and classified before being attributed to MD-004.
- The prior MD-003 inventory records an unrelated `feed_wired_test.dart` compile failure in `orbit_wired.dart`; do not treat that as an MD-004 signal unless MD-004 touches that path.
- If unqualified `integration_test/foreground_group_push_drain_test.dart` reports multiple devices, rerun with an explicit device such as `-d macos`.
- `SMOKE-GAP-05` is not a shell command.
- A relay-only test that uploads arbitrary encrypted bytes proves relay opacity only for that fixture; it does not prove Flutter group uploads encrypt before relay unless the client upload path is exercised.

## done criteria

Planning is done when this file exists and records the evidence, scope, closure bar, proof-first rule, exact tests/gates, and stop conditions.

Implementation is done only when:

- A row-specific proof fails before implementation and passes after implementation.
- Group upload encrypts each media object before relay upload.
- Distinct same-message and cross-message media objects have distinct keys or derivation contexts.
- Cross-object decrypt fails.
- Live publish and encrypted replay preserve metadata.
- Download verifies encrypted blob hash, decrypts, validates plaintext MIME/size, and displays only verified plaintext.
- Focused tests and required gates pass or unrelated pre-existing failures are clearly documented.
- Source matrix, `test-inventory.md`, and breakdown ledger record `MD-004` truth without reusing MD-003 evidence.

## scope guard

Do not:

- Close `MD-004` using MD-003 content hash proof.
- Treat group envelope encryption as media blob encryption.
- Treat relay `allowedPeers` as key separation.
- Use one reusable media key for all objects.
- Move into chunking, dedupe, thumbnail privacy, removed-member access, quarantine UI, or relay storage redesign.
- Modify 1:1/post media contracts except for backward-compatible helper reuse.
- Add product UX or broad media type changes.
- Emit media keys in logs, flow events, push metadata, relay metadata, or non-encrypted protocol fields.

## accepted differences / intentionally out of scope

- Posts already have a per-blob media encryption pattern. This session may reuse that helper pattern but does not need to unify post and group media models.
- 1:1 media can remain on its existing contract.
- Relay ACL checks remain useful defense-in-depth but are not the MD-004 closure mechanism.
- Remote thumbnail privacy remains `MD-007`; current MD-004 work should only handle thumbnail encryption if a remote thumbnail blob is already part of the group media descriptor.
- Full device-lab proof is not required before implementation if repo-owned proof shows the current gap and focused integration covers live/replay descriptor behavior.
- DB-wide secret-storage hardening belongs to `DB-006` unless current MD-004 implementation cannot safely persist enough metadata for download/retry.

## dependency impact

- `MD-005` chunk resume must know whether chunks are encrypted blob chunks or plaintext chunks.
- `MD-006` dedupe must use encrypted blob identity/hash carefully after MD-004 changes content-hash semantics.
- `MD-007` thumbnail privacy can reuse the object-key/context pattern if remote thumbnails become first-class.
- `MD-011` removed-member future-media access depends on future descriptors not exposing keys to removed members.
- `MD-012` quarantine UI should consume decrypt/hash failure states from this session.
- `LP-007` relay content encryption can cite MD-004 only after relay-visible media bytes are proven opaque.
- `DB-006` may need follow-up if storing per-object media keys in SQLCipher tables is considered ordinary message-table secret storage.

## reviewer pass

Sufficiency: sufficient as an evidence-gated execution plan with adjustments already included.

Missing files/tests: no structural missing files after adding `retry_failed_group_messages_use_case.dart`, `group_message_listener.dart`, `drain_group_offline_inbox_use_case.dart`, Go bridge/node media, and relay media.

Stale assumptions: the plan accounts for MD-001/MD-002/MD-003 now being closed, but does not conflate those rows with encryption key separation. It also rejects the unrelated older `MD-004` same-user proof.

Overengineering check: the plan avoids relay redesign, chunking, dedupe, thumbnail privacy, removed-member access, quarantine UI, and MLS/key schedule work.

Minimum needed: a proof-first failing test, minimal per-object key/context contract, upload encrypt, descriptor persistence, receive/download decrypt, focused integration, and gate runs.

## arbiter pass

Structural blockers remaining: none for writing or executing this plan. There is a closure blocker for marking `MD-004` `Covered` today: current group media has no first-class per-object encryption key or derivation context and appears to upload plaintext bytes to the relay media path.

Incremental details intentionally deferred:

- Exact field names for encryption metadata.
- Whether to use random per-object keys or HKDF-derived contexts.
- Exact terminal status string for decrypt failure if distinct from `integrity_failed` or `failed`.
- Whether the raw relay proof is client-driven Go integration or covered by Flutter bridge-command proof plus Go crypto tests.

Accepted differences intentionally left unchanged:

- Existing post media encryption remains separate.
- 1:1 media behavior remains separate.
- MD-003 digest verification remains closed but may need hash-semantics updates to follow encrypted blob bytes.
- Device-lab proof is not required before targeted repo implementation unless the repo proof cannot exercise live/replay descriptor behavior.
