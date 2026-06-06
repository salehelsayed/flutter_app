# 1. Title and Type

- Title: Move Account To A New Device
- Issue type: `new-feature`
- Output doc path: `Test-Flight-Improv/Move-Feature/01-move-account-to-new-device-pr.md`

# 2. Problem Statement

Users who replace their phone need a clear way to move their mknoon account from the old device to the new device without losing their identity, private keys, database, message history, media, group state, or local account data.

Today the app supports local identity creation, mnemonic restore, encrypted local storage, QR scanning, local WiFi discovery, and direct local transfer primitives, but it does not have a complete account migration journey. Restoring from a mnemonic is not a full migration because it does not carry the existing encrypted database, media files, DB encryption key, media keys, group keys, or the exact existing ML-KEM secret key.

The product expectation for this feature is an account move, not two active primary phones. After a successful migration, the new phone is the active device for the account and the old phone must no longer send, receive, or sync new messages for that account.

# 3. Impact Analysis

- Affected users: users who buy a new phone, replace a broken-but-still-accessible phone, or move to a fresh iOS install while keeping the same mknoon account. Users whose old phone is lost or unavailable use recovery words instead of this full migration path.
- Trigger moment: first setup on the new phone, or a settings action on the old phone to move the account.
- Severity: high for trust and data continuity because the data involved includes private keys, encrypted message history, media, groups, and account identity.
- User risk if missing: the user may believe mnemonic restore is enough, but later find old media, group keys, local history, social-feed data, introductions, push-preview decryption, or encrypted receive capability missing.
- Product risk if over-scoped: supporting two active primary phones would require true multi-device sync, message fanout, conflict policy, push-token coordination, read-state rules, and group convergence policy. That is a separate feature and should not be part of this migration MVP.
- Privacy risk: account migration transfers the most sensitive local data in the app, so the transfer must be end-to-end encrypted and must not send the migration bundle through relay or cloud infrastructure.

# 4. Current State

- App startup opens the encrypted SQLCipher database before routing the user into onboarding or the main app. The database key is stored in secure storage under `db_encryption_key`. Evidence: `lib/main.dart`, `lib/core/database/encrypted_db_opener.dart`, `test/core/database/encrypted_db_opener_test.dart`
- The app has a database `user_version` wired through startup, but it does not yet have a migration-bundle protocol version, source app version, compatibility manifest, or controlled downgrade/import gate. Evidence: `lib/main.dart`, `lib/core/database/encrypted_db_opener.dart`
- As of this June 6, 2026 review, the app database version is `74`. Recent migration surfaces include group member device identities stored in `group_members.devices_json` and group message `logical_delivery_id`; migration validation must not freeze at an older named subset of tables. Evidence: `lib/main.dart`, `lib/core/database/migrations/062_group_member_device_identities.dart`, `lib/core/database/migrations/074_group_message_logical_delivery_id.dart`
- Identity secrets are split between the database row and secure storage. The critical secure-storage keys include `identity_private_key`, `identity_mnemonic12`, and `identity_ml_kem_secret_key`. Evidence: `lib/features/identity/domain/repositories/identity_repository_impl.dart`, `lib/core/secure_storage/migrate_secrets_to_secure_storage.dart`, `test/features/identity/domain/repositories/identity_repository_impl_test.dart`
- Mnemonic restore regenerates ML-KEM key material during restore, so it is not equivalent to moving the exact existing account state. Evidence: `lib/features/identity/application/restore_identity_use_case.dart`
- Media and group encryption material can be stored through secure-storage references such as `secure:media_attachment_encryption_key:<attachmentId>` and `secure:group_key_material:<encodedGroupId>:<generation>`. Importing the database without those secure-store values would leave encrypted media or groups undecryptable, but these row-referenced keys are only part of the secure-storage namespace. Evidence: `lib/core/secure_storage/secret_storage_references.dart`, `lib/features/conversation/domain/repositories/media_attachment_repository_impl.dart`, `lib/features/groups/domain/repositories/group_repository_impl.dart`
- Encrypted media attachment decryptability depends on the file bytes, the secure-storage key, and the in-database nonce/scheme metadata staying atomic. If the secure key is missing, hydration can produce a present attachment row with no usable decryption key. Evidence: `lib/features/conversation/domain/models/media_attachment.dart`, `lib/features/conversation/domain/repositories/media_attachment_repository_impl.dart`, `test/core/database/migrations/059_media_attachment_encryption_columns_test.dart`
- The app also stores fixed secure-storage keys that are not discoverable from database row references, including `db_encryption_key`, `identity_private_key`, `identity_mnemonic12`, `identity_ml_kem_secret_key`, `secrets_migrated`, `background_preference`, `image_quality_preference`, `video_quality_preference`, `push_fcm_token`, and `push_fcm_platform`. On iOS, the app additionally mirrors `identity_ml_kem_secret_key` and group keys such as `group_key:<rawGroupId>:<generation>` into the shared Apple access group `group.com.mknoon.app.share` for notification preview decryption; this naming differs from the primary secure-storage group key reference, which URI-encodes the group ID. Evidence: `lib/core/secure_storage/migrate_secrets_to_secure_storage.dart`, `lib/features/settings/domain/models/background_preference.dart`, `lib/features/settings/domain/models/image_quality_preference.dart`, `lib/features/push/infrastructure/push_token_store_impl.dart`, `lib/core/secure_storage/flutter_secure_key_store.dart`, `lib/features/identity/domain/repositories/identity_repository_impl.dart`, `lib/features/groups/domain/repositories/group_repository_impl.dart`, `ios/NotificationService/NotificationPreviewResolver.swift`
- The current `SecureKeyStore` abstraction exposes point reads/writes/deletes/contains checks, but not secure-storage namespace enumeration. A migration exporter cannot satisfy full keychain discovery without either a migration-specific enumeration API or a complete explicit key registry augmented by database-discovered `secure:` references. Evidence: `lib/core/secure_storage/secure_key_store.dart`, `lib/core/secure_storage/flutter_secure_key_store.dart`
- Group history can depend on retained non-latest key generations and pending rotation drafts, not only the latest group key. The retention policy keeps up to 8 generations, and group messages/offline replay reference the generation used for encryption. Evidence: `lib/features/groups/domain/models/group_key_retention_policy.dart`, `lib/core/database/helpers/group_keys_db_helpers.dart`, `lib/features/groups/domain/repositories/group_repository_impl.dart`, `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`
- Group membership is now account-plus-device aware. Group members can carry active device entries with `deviceId`, `transportPeerId`, signing public key, ML-KEM public key, key package ID, and key package public material, and send/invite/replay paths validate sender or recipient device binding. Migration must treat these device-bound group fields as first-class account state rather than assuming peer ID alone is sufficient. Evidence: `lib/features/groups/domain/models/group_member.dart`, `lib/features/groups/application/group_sender_device_binding.dart`, `lib/features/groups/domain/models/group_welcome_key_package.dart`, `lib/features/groups/application/send_group_message_use_case.dart`, `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`, `test/features/groups/integration/group_messaging_smoke_test.dart`
- The encrypted database lives under `getDatabasesPath()` while app-owned media lives under the application documents directory. Copying only the documents directory does not capture `identity.db`, and copying only the database root does not capture media. Evidence: `lib/core/database/encrypted_db_opener.dart`, `lib/core/media/media_file_manager.dart`
- The existing database opener already uses `sqlcipher_export` for plaintext-to-encrypted conversion, and the app does not configure a WAL journal mode. A migration export should therefore prefer `sqlcipher_export` or an equivalently verified consistent snapshot instead of a WAL-checkpoint-only plan. Evidence: `lib/core/database/encrypted_db_opener.dart`
- Local app-owned media paths are usually stored as relative paths such as `media/...`, `post_media/...`, and `pending_uploads/...`, but some fallback paths can be raw absolute local paths. Migration cannot assume every `local_path` is portable without validation. Evidence: `lib/core/media/media_file_manager.dart`, `lib/features/conversation/application/upload_media_use_case.dart`
- Posts/social-feed, introductions, inbox staging, group sub-tables, contact avatars, group avatars, post media, and generated video thumbnails are separate local data surfaces that can affect what history renders after migration. Evidence: `lib/core/database/migrations/019_introductions_table.dart`, `lib/core/database/migrations/027_posts_core.dart`, `lib/core/database/migrations/045_inbox_staging_entries.dart`, `lib/core/database/migrations/070_group_key_rotation_drafts.dart`, `lib/features/home/presentation/widgets/user_avatar.dart`, `lib/core/media/video_thumbnail_cache.dart`
- The app already has QR generation/scanning primitives for contact exchange, but the current contact QR payload intentionally keeps a narrow contact-add contract and does not represent account migration. The contact parser requires contact fields such as `pk`, `ns`, `rv`, `ts`, and `sig`, treats malformed timestamps as non-fatal, and the scanner routes a parsed contact QR into contact-add side effects. Migration QR handling therefore needs an explicit type boundary and migration-specific parsing before any contact side effect runs. Evidence: `lib/features/qr_code/application/build_qr_payload_use_case.dart`, `lib/features/qr_code/application/parse_qr_payload_use_case.dart`, `lib/features/qr_code/presentation/screens/qr_scanner_wired.dart`
- The app already has local WiFi discovery and local WebSocket/HTTP transfer surfaces for direct peer communication and local media upload. Those surfaces provide useful local-network building blocks, but the migration bundle itself still needs its own encrypted, authenticated, migration-specific transfer path because it contains account secrets and is not ordinary media. Evidence: `lib/core/local_discovery/local_ws_server.dart`, `lib/core/local_discovery/local_p2p_service.dart`, `lib/core/local_discovery/local_media_server.dart`, `test/core/local_discovery/local_ws_server_test.dart`, `test/core/local_discovery/local_media_integration_test.dart`
- The current local media upload path is a chat-media endpoint: it accepts a MIME allowlist, streams one HTTP `PUT` to `/media/<id>`, and has no range/resume contract. It is not directly reusable for an opaque resumable migration bundle without a migration-specific endpoint or protocol. Evidence: `lib/core/local_discovery/local_media_server.dart`, `lib/core/local_discovery/local_media_sender.dart`
- The bridge already exposes useful cryptographic primitives, including ML-KEM key generation, ML-KEM message encryption/decryption, and AES-GCM blob key/file helpers. The existing file helpers read and write whole files in memory, so they are not by themselves a bundle-scale transfer primitive for a device migration. Evidence: `lib/core/bridge/bridge.dart`, `go-mknoon/crypto/file_crypto.go`
- The app already has a ref-counted wake-lock controller that can keep the screen awake during long operations. Evidence: `lib/core/device/upload_wake_lock.dart`, `test/core/device/upload_wake_lock_test.dart`
- iOS already declares local-network, Bonjour, and camera usage needed for QR plus local discovery. Evidence: `ios/Runner/Info.plist`
- Android backup is disabled, which is consistent with explicit in-app migration rather than OS-level app backup. Evidence: `android/app/src/main/AndroidManifest.xml`
- Current relay, rendezvous, inbox, and push state are keyed by `peerId`. The rendezvous backend stores one registration per namespace and peer ID, the push-token backend stores one token per peer ID, and the inbox is a single peer-ID queue whose retrieve/ack path lets two active devices compete for consumption. That means two active primary phones using the same identity would compete for messages instead of reliably syncing. Evidence: `go-relay-server/backend_memory.go`, `go-relay-server/inbox_store.go`, `go-relay-server/push_token_store.go`
- Server-side rendezvous and push unregister primitives exist, but the current Dart bridge command surface exposes rendezvous register/discover and push-token register without a matching migration cutover command that explicitly unregisters personal rendezvous and push-token leases before `node:stop`. A stop-only cutover can leave server-side leases alive until TTL expiry or re-registration. Evidence: `lib/core/bridge/go_bridge_client.dart`, `go-mknoon/node/rendezvous.go`, `go-relay-server/inbox.go`, `go-mknoon/node/personal_rendezvous_refresh.go`
- Startup currently starts P2P after routing to the main app for returning users. A migrated-out old device will need a user-visible blocked state before normal P2P startup. Evidence: `lib/features/identity/presentation/startup_router.dart`, `test/features/identity/presentation/screens/startup_router_test.dart`

# 5. Scope Clarification

In scope:

- iOS-to-iOS account migration as the first supported user journey.
- New-phone first-launch onboarding entry point: `Move from old phone`.
- Old-phone settings entry point: `Move account to new phone`.
- QR-based pairing between the new phone and old phone.
- Direct same-WiFi transfer for the migration data.
- End-to-end encrypted migration of account data, including identity secrets, database, DB encryption key, message history, contacts, groups, group member device rosters, sender device/transport metadata, group key-package material, posts/social-feed state, introductions, inbox staging, media metadata, media files, retained group-key generations, pending group-key rotation drafts, media attachment keys, and app-owned local files needed for history to render.
- Clear progress UI on both phones, with stages such as preparing, connecting, encrypting, transferring database, transferring media, checking, and finishing.
- Keeping both devices awake while the transfer is actively running in the foreground.
- A strict completion rule: the new phone is not allowed into the normal app until the import is fully verified.
- A strict old-phone rule: after successful migration, the old phone becomes migrated out and must not send, receive, sync, or display new account activity.
- Clear recovery behavior: if migration fails or is cancelled before final completion, the old phone remains the active account holder and the new phone must not expose partial account data as a usable account.

First-launch choice model:

- `I'm new here`: creates a brand-new account and new keys.
- `Move from old phone`: full device migration when the user still has the old phone.
- `Restore with recovery words`: disaster recovery when the old phone is unavailable; this must not be presented as full history, media, or group-key migration.

Expected user decision rule:

- If the user still has the old phone, they should choose `Move from old phone`.
- If the user lost the old phone or no longer has access to it, they should choose `Restore with recovery words`.
- If the user wants a new account, they should choose `I'm new here`.

Canonical migration states:

- New phone states: `no_account`, `migration_pairing`, `migration_import_staging`, `migration_verified_waiting_for_cutover`, `active`, `migration_failed_cleanup_required`.
- Old phone states: `active`, `migration_exporting_network_paused`, `migration_cutover_pending_blocked`, `migrated_out`, `migration_failed_active_restored`.

Security and handoff invariants:

- QR pairing must use an explicit migration payload type and must create a single-use, expiring, authenticated migration session.
- Migration QR parsing must use a migration-specific parser or discriminated scanner dispatch. It must not reuse the contact QR parser's contact-only field contract or its fail-open behavior for malformed timestamps.
- The migration QR payload contract must be versioned separately from contact QR payloads and must carry the session data needed for authenticated local transfer without depending on contact-only fields such as `pk`, `ns`, `rv`, `ts`, and `sig`.
- The old phone must only export account data after explicit user action from the migration flow.
- The old phone must show a final confirmation before exporting account data.
- Both phones should show a short confirmation code or clear session confirmation before transfer begins.
- If local device authentication is already available for sensitive account actions, migration export should use it before exporting account data.
- Current app code has no local device-auth package or `LAContext` path. If migration adds or later detects local device authentication for sensitive account actions, export must require it and include release-blocking coverage; otherwise this gate is explicitly not applicable for the current codebase.
- A contact QR, expired migration QR, reused migration QR, malformed-timestamp migration QR, or stale migration session must never authorize account export.
- Single-use is durable: the migration session ID is recorded consumed before export authorization and remains rejected across app restart. Expiry must be measured against an authenticated session challenge/response or an explicit skew window, not only an embedded QR timestamp from one device clock.
- Migration QR handling must be separated from contact QR handling before any contact-add, contact-request, or profile-picture-download side effects can run.
- Migration QR parsing must reject incompatible payloads before invoking the contact QR parser, scanned-QR use case, QR scanner contact branch, contact-request flow, or profile/avatar download side effects.
- Because the new phone starts without an account identity, the pairing flow must define how the identity-less new phone authenticates the session and how the old phone binds export authorization to that authenticated session.
- Existing contact-request ephemeral encryption is not sufficient unless it is refactored into a migration-session API. The new phone must generate a fresh migration ephemeral keypair, session ID, and expiry before QR display. The old phone must bind export authorization and migration bundle-key encryption to that exact consumed session ID and ephemeral public key, and the confirmation code must be derived from the established authenticated channel rather than from QR contents alone.
- Migration import may only run when no active account exists on the new phone.
- Any empty database or key material created during first startup on the new phone is replaceable staging state until migration commits.
- If an active account already exists on the new phone, migration requires an explicit erase/reset before starting.
- Failed migration cleans or quarantines staging data and must not expose it through normal app startup.
- Migration export must be manifest-driven. Manifest items must be classified as critical or non-critical. Critical items include the database, database checksum, DB encryption key, schema/app version, identity secrets, the secure-storage migration sentinel needed for correct identity loading, every required secure-storage value in the primary app keychain, every required mirrored value in the iOS shared access group, every retained group-key generation and pending group-key rotation draft, media encryption keys referenced by retained media, every app-owned local file required to preserve promised history rendering, file sizes, and file checksums. Non-critical cache files may be omitted only if the UI can safely render without them.
- Chat-media encryption keys are secure-storage manifest items when stored as `secure:` references. Post-media encryption keys are DB-column crypto metadata carried by the database snapshot, so post-media must not be expected in the secure-storage manifest unless a future migration changes its storage model.
- Secure-storage discovery must enumerate the full app-owned secure-storage namespace across both iOS keychain access groups and classify each key. It must not rely only on database rows that contain `secure:` references.
- Because the current secure-storage abstraction does not expose enumeration, implementation must add a migration-specific enumeration/read-all capability or maintain an explicit migration key registry for every app-owned fixed key, then merge that registry with DB-discovered `secure:` references. The same registry must drive export, import, erase/reset, success cleanup, cancellation cleanup, and failed-import cleanup. Tests must fail when a new app-owned secure-storage key is introduced without a migration policy.
- Fixed secure-storage keys that are not row-referenced must be classified explicitly, including `db_encryption_key`, identity secret keys, `secrets_migrated`, app preference keys, and device-bound push-token keys.
- Every fixed secure-storage key must have an explicit migrate, clear, regenerate, or intentionally-device-local policy; app preference keys must not disappear only because no database row references them.
- Account erase/reset must delete every app-owned key classified by the migration registry across the primary keychain and `group.com.mknoon.app.share`, including shared `identity_ml_kem_secret_key` and every `group_key:<rawGroupId>:<generation>`. Failed-import cleanup must delete staged secure values and any already-promoted values if commit began. Tests must fail if any app-owned secret survives cleanup in either access group.
- Device-bound push-token values are not valid migrated account state by themselves. MVP policy: do not carry the old device's push token as active account state; clear or ignore stale token material during import and force fresh push registration on the new phone after cutover.
- Migration must preserve notification-preview decryption on the new iPhone by migrating or re-establishing the shared-access-group values needed by the iOS notification service extension before claiming success.
- Committed retained group-key generations must be verified by resolved key bytes in both the primary and shared keychain stores, not only by database reference strings or latest-key lookup. Pending group-key rotation drafts are verified in the primary store only and must not be required in the shared push/NSE store unless a future implementation starts mirroring drafts there.
- Database export must use a transactionally consistent SQLCipher/SQLite snapshot. The export contract must be correct for the database's actual journal mode and must not rely on a WAL-only checkpoint assumption; `sqlcipher_export` is the preferred current primitive unless implementation proves an equivalent consistent snapshot.
- Existing `sqlcipher_export` use is proof that the primitive is available, not an existing account-migration exporter. Migration must implement its own quiesced export path, pause account writes first, export from a clean source connection, close and detach the exported database, and checksum the exported SQLCipher file.
- A raw database-file copy is not valid unless export proves the copied database includes all committed state. The manifest checksum must cover the exported consistent snapshot, not an arbitrary file on disk.
- The export contract must not depend on WAL checkpointing. `identity.db-journal`, `identity.db-wal`, and `identity.db-shm` are transient sidecars, not manifest data. A raw-copy fallback is invalid if a hot rollback journal or WAL sidecar is required to recover committed state; export must use `sqlcipher_export`, SQLite backup, or fail.
- The export scope must cover both storage roots: the encrypted database root and the application documents root that contains app-owned media and pending media files.
- Database scope means the full current schema, not only the named user-facing categories. Any selective validation or future selective export must enumerate every table in the migration chain and prove no local account table is silently omitted. For the current schema version `74`, this includes recent group-device and delivery-state fields such as `group_members.devices_json`, group welcome key-package/tombstone state, pending membership/repair state, group sync receipts, and `group_messages.logical_delivery_id`.
- For schema version `74`, baseline migration coverage is the full durable table/column inventory generated by migrations `001` through `074`, not a hand-picked category list. Tests must compare export/import coverage against that generated inventory and exclude only transient rebuild tables.
- The final export must be a consistent snapshot across database, secure storage, account queues, and app-owned files. During manifest generation and final export, account-state mutations that could change the exported state must be paused, including send queue, retry queue, upload queue, inbox drain, media writes, group-key writes, secure-storage mutations, and account-related database writes.
- Export fails if any required referenced secret or file is missing.
- Import fails unless every required manifest item is present and verified.
- Encrypted chat-media entries are verified atomically. For fully downloaded local media, exported-file size/checksum, database metadata, `encryption_nonce`, `encryption_scheme`, and the resolved secure-store media key must match. For pending or failed encrypted media, the key, nonce, scheme, and remote ciphertext hash needed for future re-download must match. Any mismatch fails import before success.
- Encrypted post-media entries are verified through their file bytes and DB-resident crypto metadata such as `encryption_key_base64`, `encryption_nonce`, and `is_encrypted`, not through secure-store resolved media keys unless a future storage migration changes that model.
- Before starting a large transfer, both phones should check migration compatibility and tell the user to update if either app version is unsupported.
- Migration is supported only when the new app version can open or migrate the exported database schema.
- Unsupported future database or schema versions must fail before commit.
- The migration manifest must carry a migration protocol version, exported database `user_version`, source app version/build, minimum compatible importer version, and an explicit unsupported-version failure reason before any large bundle transfer or commit.
- The migration manifest must include SQLCipher opener metadata: `cipher_version`, `cipher_compatibility`, `cipher_page_size`, `kdf_iter`, HMAC/KDF algorithms, plaintext-header configuration, and DB-key encoding semantics. Import must apply those PRAGMAs before first read or run `cipher_migrate` before treating wrong-key/corruption as final. A release-blocking test must open an exported database across differing SQLCipher defaults.
- Successful import requires the new phone to have the imported DB encryption key available before opening the imported database, then open the imported database and load identity from secure storage before normal app entry.
- Import must not generate or persist a replacement `db_encryption_key` for an imported database, and it must not set the secure-storage migration sentinel against an imported identity row with missing active secrets.
- Imported `identity` rows must preserve `private_key`, `mnemonic12`, and `ml_kem_secret_key` as `NULL`; those secrets must exist only in staged/promoted secure storage before identity load is considered valid. Import must commit the corresponding secure-storage secrets before setting `secrets_migrated` or permitting normal startup.
- Before import commit, the new phone must verify that imported secure-storage secrets match the imported account identity. The identity private key must match the expected public identity or peer ID, the ML-KEM secret key must match expected public key material by encrypting a fresh nonce to the imported ML-KEM public key and decrypting it with the imported `identity_ml_kem_secret_key`, and required secure-storage references must resolve to the expected account, group, and media records.
- If imported identity material is present but mismatched, import fails before commit.
- Migration logs, analytics, crash reports, and debug events must not include mnemonics, private keys, DB keys, group keys, media keys, migration bundle contents, raw QR payloads, decrypted manifest secrets, or secure-storage values. Coarse non-sensitive states such as pairing failed, version incompatible, checksum failed, storage insufficient, permission denied, or import verification failed may be recorded.
- Temporary migration artifacts must be encrypted at rest or memory-only, scoped to the migration session, deleted after success, cancellation, or failed-import cleanup, and excluded from user-visible partial account state. Temporary files and transient media artifacts such as `.enc`, `.download.jpg`, and `.raw.*.jpg` must not be carried as durable account data unless the manifest explicitly classifies them as required.
- Migration must not rely on iCloud Backup, iCloud Keychain, or OS-level app restore as the migration mechanism. iOS keychain accessibility, locked-device and reboot readability, persistence, backup, and sync behavior must be verified so identity secrets and staging secrets do not unexpectedly survive, sync, or resurrect account state outside the explicit migration flow.
- Import is first written to a non-active staging area on the new phone.
- Migration staging applies to database files, app-owned media files, manifest data, and secure-storage values. Imported secure-storage values must be written under a migration staging namespace, and active secure-storage keys must not be overwritten until database, file, manifest, version, checksum, identity-load, and cutover verification all pass.
- No imported secret becomes an active secret until commit.
- The new phone becomes active only after database, secure-storage secrets, media files, manifest checks, version compatibility, identity loading, and durable cutover all pass.
- A large migration bundle must be transferred and encrypted with bounded memory use, chunk or segment verification, and resume from verified progress after interruption. It must never require whole-file plaintext/ciphertext residency in memory or claim success from an incomplete segment set.
- Migration must not reuse the normal local media `PUT /media/<id>` protocol as-is. It needs a migration-specific segmented transfer with per-segment AEAD, unique nonces, authenticated session ID/key binding, durable verified-progress checkpoints, range/resume semantics, and rejection of whole-file AES-GCM helpers for large bundles.
- The old phone is marked migrated-out only after the new phone has proven the imported account can open in verified, non-active staging.
- During final cutover, the old phone must durably enter a network-blocked or migrated-out state before the new phone becomes active or enters normal app startup.
- The new phone may only enter normal app startup after receiving proof that the old phone has durably blocked normal account activity.
- Final migration success requires a durable cutover record on both devices: the new phone has durably committed imported-active state, the old phone has durably committed migrated-out state, and normal success UI is shown only after both durable states are known.
- Active, migrating, and migrated-out account-authority state must be persisted per account as device-local state outside the migrated database bundle. It is intentionally device-local, not exported in the migration manifest: the old phone writes `migrated_out`, the new phone writes its own `active` state only after commit, and imported database rows must never carry source-device active/migrated-out authority.
- Cutover recovery must reason over named durable records such as `old_network_blocked`, `old_block_proof_received`, and `new_active_committed`.
- If cutover is interrupted before `old_network_blocked` is durable, the old phone remains active and the new phone remains retryable or staged.
- If `old_network_blocked` is durable but `old_block_proof_received` or `new_active_committed` is not durable, startup resolves to retry/cleanup or temporarily zero-active-device state, never old-active and never two-active.
- If `old_network_blocked` and `new_active_committed` are durable, the new phone is active and the old phone is blocked as migrated out.
- There must be no state where both devices can start normal P2P for the account.
- In rare crash or interruption cases, the migration flow must prefer a retry, cleanup, or temporarily zero-active-device state over allowing two active primary devices.
- During active final export and transfer, the old phone pauses account network activity for this account.
- During active migration, the old phone disables user sends for this account and stops consuming relay inbox messages before the final export snapshot.
- Any messages not included in the export must remain available for the new phone to receive after cutover.
- If migration fails before commit, the old phone resumes normal networking.
- MVP device-identity policy: this is an account move, not creation of a sibling linked device. The new phone must either preserve the existing account transport/device identity exactly and block the old phone before normal startup, or, if a future implementation chooses a replacement device identity, it must explicitly rebind/revoke the old device entries in group member rosters, key-package state, sender-device metadata, push/rendezvous ownership, and pending work before claiming success. It must never silently add a second active device roster entry for the migrated account.
- Drafts and local unsent user data may migrate as local account data.
- Pending outbound work is migrated and becomes owned by the new phone after commit. This includes committed sends, retry jobs, upload jobs, pending media work, and app-owned pending upload files that are valid local account state.
- Pending outbound work resumes only on the new phone after commit, using existing idempotency and deduplication rules. If an item cannot be safely migrated, migration must either fail before success or leave that item paused/failed with a clear local state; it must not be silently dropped or resumed on both devices.
- After commit, the old phone must never resume copied pending jobs.
- On old-phone migration commit, the old phone stops active P2P/account networking immediately, closes active inbound/outbound account streams, cancels message polling and inbox draining, leaves live group topics, cancels group discovery loops, prevents send/retry/upload queues from running for the migrated-out account, and skips push-token and rendezvous registration for migrated-out accounts.
- Cutover must explicitly issue personal `RendezvousUnregister` and `inbox:unregister_token` for the migrated-out peer ID before treating local `node:stop` as sufficient. The old phone must clear or ignore its local persisted push-token material and must prevent startup, resume, watchdog, or personal-rendezvous recovery from re-registering after `migrated_out`.
- Send, receive, retry, upload, local discovery, inbox-drain, group-topic rejoin, group discovery, profile-update listener, contact profile-picture download, group-avatar download, push-handler recovery, push-registration, and rendezvous-registration entry points must observe active-account state, not only startup routing. Imported avatar files and avatar-version state should suppress re-download unless verification proves the file is missing or invalid.

Explicit non-goals:

- No cloud backup.
- No relay-based migration fallback.
- No two-active-primary-device sync.
- No new account-level linked-device or multi-primary sync feature. Migration must still remain compatible with existing group member device identities and must not leave the old and new phones both active for the migrated account.
- No message fanout to two phones.
- No automatic sync from the new phone back to the old phone after migration.
- No requirement that sent messages from the new phone appear on the old phone.
- No reliance on mnemonic restore as a full migration path.
- No migration success state if any required keys, database files, or app-owned media files fail verification.
- No change to existing contact QR payload semantics or contact-add behavior for normal contact sharing.
- Android and cross-platform migration are out of scope for this MVP unless explicitly added by a separate scope decision.

Product contract for common questions:

- After migration, messages should arrive on the new phone only.
- After migration, a message sent from the new phone should not appear on the old phone as a synced message.
- Deleting the app from the old phone after migration should not create duplicates.
- A failed or interrupted migration may leave temporary staging files on the new phone, but those files must not become a usable account until verification and commit complete.
- After successful migration, usable account data should be on the new phone. The old phone may retain local data only in a blocked migrated-out state until the user chooses to erase it.
- After migration, the old phone must not enter the normal account UI or expose old history as a read-only device mode. It should show a migrated-out screen with an erase action and may offer setup for a new account.

Accepted ambiguities for the later implementation pass:

- Exact post-success erase behavior can be finalized later, but the MVP expectation is a blocked migrated-out screen with an explicit erase action rather than immediate automatic deletion.
- Exact placement and wording of the migration entry points, as long as the user journey stays simple and clear.
- Exact handling for personal hotspot, VPN, captive portals, and local-network permission denial, as long as the app does not silently fall back to relay or cloud transfer for the migration bundle.

# 6. Test Cases

## Happy Path

- A user setting up a new iPhone can choose `Move from old phone`, see a QR code, scan it from the old phone, and complete migration without typing recovery words.
- Before a large transfer begins, both phones confirm migration compatibility or tell the user to update.
- Before account export begins, the old phone asks for final confirmation and both phones show a short confirmation code or clear session confirmation.
- During transfer, both phones show clear progress and the user can tell whether the app is preparing, connecting, encrypting, transferring, checking, or finishing.
- During transfer, both phones stay awake while the migration screen is in the foreground.
- When both devices are on the same WiFi, migration data travels directly over the local network and is not sent through relay or cloud infrastructure.
- The migration transfer is end-to-end encrypted so account secrets, database contents, history, and media keys are not readable by the local network or relay infrastructure.
- After successful migration, the new phone opens into the existing account with the same identity, contacts, conversation history, group state, posts/social-feed state, introductions, inbox staging, media history, and app-owned local media files.
- After successful migration, the new phone has proven it can open a consistent imported database snapshot, load the migrated identity, and verify imported secrets match the imported account before entering the normal app.
- After successful migration, the new phone receives new messages for the account.
- After successful migration, foreground message decryption and iOS notification preview decryption both work on the new phone for 1:1 and group messages without waiting for key rotation.
- After successful migration, the old phone immediately stops active account networking and no longer receives, sends, syncs, retries, uploads, drains inboxes, registers push/rendezvous state, or displays new account activity for that account.
- After successful migration, normal success UI appears only after the new phone has durably committed active state and the old phone has durably committed migrated-out state.
- If the migrated account had pending drafts, sends, retries, uploads, pending media work, or app-owned pending upload files, valid pending work resumes only on the new phone after commit; unsafe pending work blocks success or remains paused/failed with clear local state.
- After successful migration, sending a message from the new phone does not create a synced outgoing row on the old phone.
- After successful migration, deleting the app on the old phone does not create duplicate account state or duplicate messages.
- After successful migration, opening the old phone shows a migrated-out screen with an erase action and does not expose normal account UI, old inbox, conversations, or read-only history mode.

## Edge Cases

- If the QR code is expired, malformed, has a malformed timestamp, lacks a migration type, or is scanned by the wrong flow, both phones show a clear failure and no account data is transferred.
- If a contact QR, stale migration QR, already-used migration QR, future-dated QR, or QR created on a clock-skewed device is scanned, it does not authorize account export and does not create a bogus contact or send a contact request.
- If the phones are not on the same usable local network, the app explains the requirement and does not use relay or cloud transfer as a hidden fallback.
- If local-network permission, camera permission, or WiFi availability prevents pairing, the user sees a clear next step and the old phone remains active.
- If the transfer is interrupted before final verification, the new phone does not enter the normal app and the old phone remains the active device.
- If cutover is interrupted before commit, startup resolves to the old phone as active and the new phone as retryable or cleaned staging.
- If cutover is interrupted after commit, startup resolves to the new phone as active and the old phone as migrated out.
- If a crash or interruption prevents proving either stable cutover state, startup shows retry or cleanup rather than allowing both phones to become active.
- If the new phone lacks enough writable storage for the encrypted incoming bundle or verified chunk store, staged SQLCipher database, staged app-owned media/files, manifest and secure-storage staging metadata, transient SQLite sidecars/temp files, and fixed safety headroom, migration fails clearly before transfer or before claiming success. Plaintext decrypted database files must not be written; if an implementation creates any additional decrypted/staged copy, that footprint must be counted and must satisfy the temporary-artifact encryption rule.
- If the database export cannot prove a consistent SQLCipher/SQLite snapshot that includes all committed state, migration fails before claiming success.
- If final export cannot prove a consistent snapshot across database, secure storage, account queues, and app-owned files, migration fails before claiming success.
- If any required primary or shared-access-group secure-storage value is missing from the migration export, migration does not claim success.
- If the imported database is opened before the imported DB encryption key is active, import fails cleanly without generating a new key, encrypting an empty replacement database, or exposing partial account state.
- If identity rows have null secret columns but imported secure-storage secrets are not yet committed, startup and import do not set a migrated-secrets sentinel that would make the identity permanently unloadable.
- If any critical manifest item, required media file, required secret, or database checksum fails, migration does not claim success.
- If a non-critical cache item is omitted, the imported app still renders safely without pretending that required history or media is present.
- If committed retained group-key generations or their shared-access-group mirrors are missing, migration fails before claiming group history or notification-preview decryption was preserved. If pending group-key rotation drafts are missing from the primary store, migration fails before claiming pending group-key state was preserved; drafts are not required in the shared push/NSE store under the current storage model.
- If group history spans the full retained group-key window, including generation-boundary history and pending rotation drafts, every retained epoch still decrypts after migration rather than only the latest group key.
- If app-owned files include `media/`, `post_media/`, `pending_uploads/`, contact avatars, group avatars, generated video thumbnails classified as required, or other required renderable files, those files are present and verified on the new phone before success.
- If a database row contains a raw absolute local media path that is not portable, migration either heals it or fails/flags it clearly before claiming that attachment was preserved.
- If chat-media metadata is present but its local file checksum/size, nonce, scheme, secure-store key, or future re-download ciphertext hash is missing or mismatched, migration fails before claiming that attachment was preserved.
- If post-media metadata is present but its file or DB-resident crypto fields such as `encryption_key_base64`, `encryption_nonce`, or `is_encrypted` are missing or mismatched, migration fails before claiming that post attachment was preserved.
- If the exported database schema is unsupported by the new app version, migration fails before commit and does not expose partial account data.
- If the migration protocol version, source app version, exported database version, or minimum importer version is missing or incompatible, migration fails before large transfer or commit with a clear update path.
- If imported secure-storage identity material does not match the imported account identity or required account/group/media references, migration fails before commit.
- If imported secure-storage values are written during staging, they do not overwrite active secure-storage keys before commit.
- If the final cutover acknowledgement is interrupted before `old_network_blocked` is durable, the old phone remains active and the new phone does not enter normal app state.
- If `old_network_blocked` is durable but `new_active_committed` is not durable, recovery shows retry/cleanup or temporarily zero-active-device state rather than reactivating the old phone.
- If `old_network_blocked` and `new_active_committed` are durable, the new phone remains active and the old phone stays blocked as migrated out.
- If migration is cancelled, fails, or succeeds, temporary migration artifacts do not remain as readable bundles, logs, crash-report content, analytics payloads, or user-visible partial account state.
- If iCloud Backup, iCloud Keychain, or OS-level restore behavior is present on the device, it does not become the migration mechanism or resurrect active/staging account state outside the explicit migration flow.
- If an active account already exists on the new phone, migration does not start until the user explicitly erases or resets that local account state, and that erase/reset deletes app-owned primary and shared-access-group keychain values through the migration registry.
- If the app is backgrounded, locked, interrupted by a call, or killed during migration, the next launch shows a clear retry or cleanup state rather than partial account access. A foreground wake lock is not a suspension guarantee; if migration is foreground-only, manual lock or OS suspension tears down transport and resume must use verified staged progress.
- During final export and transfer, the old phone does not consume new relay inbox messages or allow new user sends for the migrating account.
- If a message is not included in the export snapshot, it remains available for the new phone to receive after cutover, or the old phone resumes normally if migration fails before commit.
- If migration completes and the old phone is later opened, it shows a migrated-out state instead of starting P2P, draining inboxes, registering rendezvous, or registering push tokens.
- If migration completes and resume, push handling, retry recovery, personal-rendezvous recovery, profile-update handling, or avatar download handling later tries to restart account activity, the migrated-out old phone remains blocked and does not resubscribe, restart group discovery, re-register relay/push state, or fetch profile/group avatars.
- If the transfer is interrupted during a large media-heavy bundle, resume uses only verified chunks or segments with authenticated session binding and per-segment AEAD metadata, and never treats a truncated bundle as successful.

## Regressions To Preserve

- Existing new-account onboarding remains available for users who are not migrating.
- Existing mnemonic restore remains available, but it is not presented as equivalent to full device migration.
- Existing contact QR scanning and contact QR payload behavior remain unchanged for normal contact sharing.
- Adding a migration QR branch does not let migration payloads fall through to contact parsing, contact-add, contact-request, or profile-picture-download side effects.
- Existing local WiFi messaging and local media transfer behavior remain unchanged for normal conversations; migration-specific segmented transfer must not weaken or replace the normal media `PUT /media/<id>` contract.
- Existing SQLCipher database open, migration-chain, and secure-storage migration behavior remain unchanged for normal app startup.
- Existing identity loading remains strict about missing private key or mnemonic secrets.
- Existing P2P startup for normal returning users remains unchanged when the account is not marked as migrated out.
- Existing push notification registration remains tied to the active device after normal startup.
- Existing send, retry, upload, local discovery, inbox-drain, P2P, profile-update, and avatar-download behavior remains unchanged for accounts that are not in active migration or migrated-out state.
- Existing platform behavior outside iOS-to-iOS migration remains unchanged; Android and cross-platform migration are not part of this MVP.

## Release-Blocking Safety Tests

Before this feature is exposed to users, acceptance evidence must prove these dangerous paths are covered:

- Migration export includes the encrypted database, DB encryption key, identity private key, mnemonic, ML-KEM secret, secure-storage migration sentinel behavior, every critical primary keychain value, every critical shared-access-group keychain value, committed retained group-key generations, pending group-key rotation drafts from the primary store, chat-media secure-storage encryption keys, DB-resident post-media crypto metadata, app-owned media files, and app-owned local files required for promised history rendering.
- Full export/import restores database rows across the full current database schema, including conversations, contacts, groups, posts/social-feed, introductions, inbox staging, pending work, secure-storage values, app-owned media files, and app-owned local files into a fresh app state that can open and render the migrated account.
- Full export/import covers current schema version `74` fields, including group member `devices_json`, sender `transportPeerId` and `senderDeviceId` metadata, group welcome key-package state, pending group membership/repair state, group sync receipts, and group message `logical_delivery_id`.
- Full export/import coverage is compared against the generated schema-version-`74` durable table/column inventory from migrations `001` through `074`, not only against named feature categories.
- Group device-identity migration proves the new phone can send, receive, decrypt, and validate group messages/invites/replays using the migrated device binding, and that migration does not leave both the old and new phones as active device roster entries for the same moved account.
- Migrated images, voice messages, videos, avatars, group avatars, and other chat-media attachments remain decryptable and renderable because their media files, metadata, nonce/scheme data, and secure-store media encryption keys match after import.
- Migrated post media remains decryptable and renderable because its media files and DB-resident crypto metadata, including `encryption_key_base64`, `encryption_nonce`, and `is_encrypted`, match after import.
- Generated video thumbnails are either copied and verified when classified as required, or omitted only when the new phone safely regenerates them without claiming user-visible media loss.
- Historical group messages and offline-replay envelopes encrypted under retained non-latest group-key generations remain decryptable after import, including the full eight-generation retained window, and every committed retained generation is verified by resolved key bytes in the primary and shared keychain stores. Pending rotation drafts are verified by resolved key bytes in the primary store.
- iOS notification service extension preview decryption works on the new phone after import for migrated 1:1 and group secrets, including shared-access-group mirrors.
- Imported secure-storage values are staged first and do not overwrite active secure-storage keys before commit.
- Secure-storage migration has either an enumerating primary/shared keychain export path or an explicit migration key registry merged with DB-discovered `secure:` references, and coverage proves every app-owned fixed key has a migrate, clear, regenerate, or intentionally-device-local policy.
- Account erase/reset, success cleanup, cancellation cleanup, and failed-import cleanup use the same primary/shared keychain registry and prove no app-owned secret survives in either access group, including shared `identity_ml_kem_secret_key` and `group_key:<rawGroupId>:<generation>` mirrors.
- Database export uses `sqlcipher_export` or an equivalently proven consistent SQLCipher/SQLite snapshot, and import rejects torn, stale, or incomplete snapshots.
- Database export/import captures SQLCipher opener metadata and proves import can open an exported database when exporter and importer SQLCipher defaults differ, either by applying pinned PRAGMAs before first read or by running `cipher_migrate`.
- Database export/import covers both the SQLCipher database root and the app documents/media root; a documents-only or database-only copy is not sufficient.
- The new phone has a native writable-space preflight that accounts for the encrypted incoming bundle or verified chunk store, staged SQLCipher database, staged files, secure-storage staging metadata, transient SQLite/temp files, and safety headroom before claiming migration can proceed.
- Import ordering proves the DB encryption key, imported database, identity secure-storage values, and secure-storage migration sentinel cannot be committed in an order that creates a new empty database or unloadable identity.
- Import verification proves `identity.private_key`, `identity.mnemonic12`, and `identity.ml_kem_secret_key` remain `NULL`, secure-storage identity secrets are present before `secrets_migrated` is set, and the imported ML-KEM secret decrypts a fresh challenge encrypted to the imported ML-KEM public key.
- Durable cutover records prove final migration success only after the new phone is active-ready and the old phone is durably migrated out or network-blocked.
- The new phone cannot enter normal app UI or start normal account services until import is fully verified and cutover is durable.
- The old phone shuts down account networking at cutover, including P2P, inbound/outbound streams, inbox draining, live group topic subscriptions, group discovery loops, server-side personal `RendezvousUnregister`, `inbox:unregister_token`, push/rendezvous registration, send queues, retry queues, upload queues, and local discovery for the migrated-out account.
- Resume, push-handler, retrier, watchdog/personal-rendezvous recovery, profile-update, contact-avatar download, and group-avatar download paths cannot rejoin topics, restart discovery, re-register relay/push state, or fetch avatar/profile media for a migrated-out account.
- Exactly one device becomes active after migration recovery settles; interruption paths must never leave both phones able to start normal P2P for the same account.
- Interrupted migration recovers safely into old-active/new-not-active, new-active/old-migrated-out, or retry/cleanup state.
- Pending sends, retries, uploads, pending media work, and app-owned pending upload files do not duplicate or disappear silently.
- Same-WiFi migration does not fall back to relay, cloud, iCloud Backup, iCloud Keychain, or OS-level app restore as the migration path.
- Same-WiFi migration uses an authenticated encrypted migration transfer path that can carry an opaque account bundle rather than relying on the normal media upload MIME contract.
- Large bundle transfer and encryption are streaming/chunked, memory-bounded, migration-specific, per-segment AEAD protected with unique nonces, resumable from verified progress, and recover predictably after interruption, backgrounding, app restart, manual lock, or iOS suspension without accepting partial data as success.
- Push-token behavior after cutover clears or ignores the stale old-device token, forces fresh new-phone registration, leaves the new phone as the active push target for the peer ID, and prevents stale old-device token state from winning.
- QR pairing has a type discriminator, uses migration-specific parsing or scanner dispatch, fails closed on malformed timestamp/session data, records durable consumption for single-use semantics, binds export authorization and bundle-key encryption to the consumed session ID and new-phone ephemeral public key, handles old/new phone clock offset, and keeps contact QR and migration QR side effects separated.
- Migration QR compatibility proves contact-only field sets are rejected by the migration flow and migration-only field sets do not fall through to contact parsing or contact side effects.
- Sensitive keys and migration data never appear in logs, analytics, crash reports, debug events, readable temporary artifacts, transient media artifacts, raw QR/session logs, or partial account state.
- iOS primary and shared keychain staging behavior is verified across lock, unlock, reboot, success cleanup, cancellation cleanup, and failed-import cleanup.
- After successful migration, the old phone shows only migrated-out UI with an erase action and does not expose normal account UI, old conversations, inbox, or read-only history mode.

## Simulator Acceptance Scenarios

Before release, simulator or device-context acceptance must cover these iOS journeys:

- New phone first launch shows `I'm new here`, `Move from old phone`, and `Restore with recovery words`, and choosing `Move from old phone` enters migration pairing instead of normal onboarding.
- Old phone can open `Move account to new phone`, scan the new phone QR, see final confirmation, and start export only after confirming the migration session.
- Pairing rejects expired, reused, stale, malformed, future-dated, clock-skewed, and contact QR payloads without exporting account data.
- Pairing rejects migration payloads that are missing the migration type or have malformed timestamps, and contact QR scanning still behaves normally.
- Camera permission denial shows a clear recovery path and leaves the old phone active.
- Local-network permission denial or unavailable same-WiFi path shows a clear recovery path and does not use relay, cloud, iCloud Backup, iCloud Keychain, or OS-level restore as a fallback.
- New-phone insufficient writable storage is detected before transfer or before success, with clear recovery UI and without leaving usable partial account state.
- During transfer, both phones show progress stages and stay awake while the migration screen is foregrounded.
- Killing, locking, backgrounding, call-interrupting, or restarting either app before commit recovers to old-active/new-not-active, retry/cleanup, or temporarily zero-active-device state without exposing partial account data.
- Interrupting transfer after import staging but before durable cutover does not let the new phone enter normal app UI or start account services.
- Interrupting final cutover after the old phone has durably blocked account activity recovers to new-active/old-migrated-out.
- A completed migration opens the new phone into the migrated account only after import verification, staged secret promotion, identity loading, and durable cutover are complete.
- Opening the old phone after successful migration shows only the migrated-out screen with an erase action and never shows old inbox, conversations, read-only history, or normal account UI.
- After successful migration, the old phone does not start P2P, local discovery, inbox drain, live group topics, group discovery, push registration, rendezvous registration, personal-rendezvous recovery, server-side push/rendezvous leases, send retries, upload queues, profile-update downloads, or avatar downloads for the migrated-out account.
- Pending sends, retries, uploads, pending media work, and app-owned pending upload files resume only on the new phone after commit or remain paused/failed with clear local state.
- Sensitive migration material is not visible in simulator logs, app debug events, crash payloads, temporary readable files, or UI-visible partial state.
- Existing non-migration startup, new-account onboarding, mnemonic restore, contact QR, local WiFi messaging, media, and P2P flows still behave normally after the migration feature is present.

## Existing Coverage And Gaps

- Existing coverage partially proves encrypted DB key creation and persistence through `test/core/database/encrypted_db_opener_test.dart`.
- Existing coverage partially proves identity secret migration into secure storage through `test/core/secure_storage/migrate_secrets_to_secure_storage_test.dart`.
- Existing coverage partially proves identity loading and secure-store expectations through `test/features/identity/domain/repositories/identity_repository_impl_test.dart`.
- Existing coverage partially proves QR rendering and scanning surfaces through QR and first-time-experience widget tests.
- Existing coverage partially proves local WiFi WebSocket/media transfer behavior through local discovery tests.
- Existing coverage partially proves wake-lock ref-count behavior through `test/core/device/upload_wake_lock_test.dart`.
- Existing coverage partially proves returning-user startup and P2P startup routing through startup-router tests.
- Missing acceptance evidence: no current test proves a full account migration export contains every required secure-storage value across the primary app keychain and iOS shared access group.
- Missing acceptance evidence: no current test proves migration export is manifest-driven across database checksum, schema/app version, required secure-storage keys, shared-access-group mirror keys, app-owned files, file sizes, and file checksums.
- Missing acceptance evidence: no current test proves the secure-storage migration path can enumerate both keychain access groups or otherwise derives a complete registry of fixed secure-storage keys plus DB-discovered `secure:` references.
- Missing acceptance evidence: no current test proves account erase/reset, success cleanup, cancellation cleanup, and failed-import cleanup use that same registry and leave no app-owned secret in either the primary keychain or `group.com.mknoon.app.share`.
- Missing acceptance evidence: no current test proves every fixed secure-storage key has an explicit migrate, clear, regenerate, or intentionally-device-local policy, including app preference keys that are not row-referenced.
- Missing acceptance evidence: no current test proves manifest items are classified as critical or non-critical and that omitted cache data does not break safe rendering.
- Missing acceptance evidence: no current test proves database export uses `sqlcipher_export` or an equivalently consistent SQLCipher/SQLite snapshot and rejects raw copies that do not include all committed state.
- Missing acceptance evidence: no current test proves SQLCipher cipher parameters are captured, pinned, or migrated so an exported database opens across differing exporter/importer SQLCipher defaults.
- Missing acceptance evidence: no current test proves migration validation covers the full current database schema rather than only the named high-level categories.
- Missing acceptance evidence: no current test proves migration validation is generated from the full durable table/column inventory for migrations `001` through `074` instead of a stale hand-maintained table list.
- Missing acceptance evidence: no current test proves schema version `74` group-device and delivery-state fields, including `devices_json`, sender device/transport metadata, key-package state, pending group repair/membership state, sync receipts, and `logical_delivery_id`, survive export/import.
- Missing acceptance evidence: no current test proves final export is consistent across database, secure storage, account queues, and app-owned files while account-state mutations are paused.
- Missing acceptance evidence: no current test proves a migrated database plus secure-store import can open and render the same conversation, group, post/social-feed, introduction, inbox staging, pending-work, and media history on a fresh install.
- Missing acceptance evidence: no current test proves secure-storage staging uses non-active staged keys and does not overwrite active secure-storage keys before commit.
- Missing acceptance evidence: no current test proves imported secure-storage secrets match the imported account identity and database references before commit, including an ML-KEM public/secret challenge round-trip.
- Missing acceptance evidence: no current test proves imported identity rows keep `private_key`, `mnemonic12`, and `ml_kem_secret_key` NULL while the corresponding staged secure-storage secrets are present before `secrets_migrated` is set.
- Missing acceptance evidence: no current test proves all committed retained group-key generations and their shared-access-group mirrors, plus primary-store pending group-key rotation drafts, survive export/import and decrypt multi-epoch group history.
- Missing acceptance evidence: no current test proves migrated group member device identities either preserve the moved account's existing device identity or explicitly rebind/revoke old device entries before success.
- Missing acceptance evidence: no current test proves committed retained group-key generations and primary-store pending group-key rotation drafts are verified by resolved key bytes rather than latest-key lookup or reference-string presence.
- Missing acceptance evidence: no current test proves the full eight-generation retained group-key window survives migration at the retention boundary.
- Missing acceptance evidence: no current test proves app-owned media files from both storage roots are copied, verified, and displayed after migration.
- Missing acceptance evidence: no current test proves migrated chat-media rows still match their migrated files, nonce/scheme metadata, secure-store media encryption keys, and future re-download ciphertext hashes after import.
- Missing acceptance evidence: no current test proves migrated post-media rows still match their files and DB-resident crypto fields such as `encryption_key_base64`, `encryption_nonce`, and `is_encrypted` after import.
- Missing acceptance evidence: no current test proves generated video thumbnails are copied when required or safely regenerated when treated as non-critical cache.
- Missing acceptance evidence: no current test proves raw absolute media paths are healed or flagged rather than silently claimed as migrated.
- Missing acceptance evidence: no current test proves the DB encryption key import, database open, identity secret promotion, and secure-storage migration sentinel ordering cannot create an empty replacement database or unloadable identity.
- Missing acceptance evidence: no current test proves a partially imported migration cannot become the active account.
- Missing acceptance evidence: no current test proves the canonical new-phone and old-phone migration states drive startup, networking, queues, and UI consistently.
- Missing acceptance evidence: no current test proves final cutover ordering requires durable old-phone network-blocked or migrated-out state before new-phone normal startup.
- Missing acceptance evidence: no current test proves durable cutover records on both devices gate normal success UI and resolve to exactly one active device if interrupted before or after commit.
- Missing acceptance evidence: no current test proves ambiguous crash recovery prefers retry/cleanup or zero-active-device state over two active primary devices.
- Missing acceptance evidence: no current test proves the old phone blocks normal P2P startup after migration succeeds.
- Missing acceptance evidence: no current test proves the old phone stops active runtime networking, send/retry/upload queues, inbox draining, live group topic subscriptions, group discovery loops, push registration, rendezvous registration, server-side personal rendezvous leases, and push-token leases at migration commit.
- Missing acceptance evidence: no current test proves resume, push-handler, retrier, watchdog/personal-rendezvous recovery, profile-update, contact-avatar download, and group-avatar download paths cannot restart account activity for a migrated-out account.
- Missing acceptance evidence: no current test proves the old phone pauses sends and inbox consumption during final export so in-flight messages are not lost from the migration snapshot.
- Missing acceptance evidence: no current test proves valid pending drafts, sends, retries, uploads, media jobs, and app-owned pending upload files migrate and resume only on the new phone after commit, while unsafe items block success or remain paused/failed with clear local state.
- Missing acceptance evidence: no current test proves sensitive migration material is excluded from logs, analytics, crash reports, debug events, and readable temporary artifacts.
- Missing acceptance evidence: no current test proves transient media artifacts such as `.enc`, `.download.jpg`, and `.raw.*.jpg` are excluded, cleaned, or explicitly classified before they can enter durable migrated account state.
- Missing acceptance evidence: no current test proves same-WiFi migration avoids relay/cloud transport while using an authenticated encrypted migration-specific transfer path for an opaque account bundle.
- Missing acceptance evidence: no current test proves large bundle encryption and transfer are streaming/chunked, memory-bounded, migration-specific, per-segment AEAD protected with unique nonces, resumable from verified progress, chunk/checksum verified, and interruption-safe across app restart, backgrounding, manual lock, and OS suspension.
- Missing acceptance evidence: no current test proves QR pairing is type-discriminated, single-use, expiring, authenticated, includes old-phone confirmation and session confirmation, binds export to the new phone's ephemeral public key and consumed session ID, fails closed on malformed timestamps, and rejects contact/stale/reused/future-dated/clock-skewed QR payloads for migration export.
- Missing acceptance evidence: no current test proves migration QR handling avoids the contact QR parser's contact-only field contract and fail-open malformed-timestamp behavior.
- Missing acceptance evidence: no current test proves migration QR payload compatibility is versioned separately from contact QR payload compatibility.
- Missing acceptance evidence: no current test proves stale old-device push tokens cannot remain the winning push target after migration.
- Missing acceptance evidence: no current test proves unsupported exported database versions fail before import commit.
- Missing acceptance evidence: no current test proves version compatibility is checked before large transfer starts.
- Missing acceptance evidence: no current test proves migration import is rejected or gated when an active account already exists on the new phone.
- Missing acceptance evidence: no current test proves explicit erase/reset before migration deletes app-owned secrets from both keychain access groups and cannot leave shared-access-group mirrors behind.
- Missing acceptance evidence: no current test proves iCloud Backup, iCloud Keychain, or OS-level app restore cannot act as migration or resurrect active/staging account state.
- Missing acceptance evidence: no current test proves primary and shared keychain staging secrets are cleaned correctly across lock, unlock, reboot, success, cancellation, and failed import.
- Missing acceptance evidence: no current test proves the old phone shows only migrated-out UI with erase action and does not expose old account UI, read-only conversations, or inbox history.
- Missing acceptance evidence: no current test proves Android and cross-platform migration remain out of MVP scope.
- Missing acceptance evidence: no current test proves the transfer stays awake during the active migration journey.
- Missing acceptance evidence: no current test proves foreground wake-lock behavior is not treated as an iOS suspension guarantee, or that manual lock/call interruption resumes only from verified staged progress.
- Missing acceptance evidence: no current test proves two active phones with the same peer ID are prevented after migration.

## Acceptance Evidence

Required acceptance evidence layers:

- Unit: deterministic rules for typed authenticated migration session validity, ephemeral session-key binding, durable single-use QR consumption, clock-skew handling, canonical migration states (`no_account`, `migration_pairing`, `migration_import_staging`, `migration_verified_waiting_for_cutover`, `active`, `migration_failed_cleanup_required`, `migration_exporting_network_paused`, `migration_cutover_pending_blocked`, `migrated_out`, and `migration_failed_active_restored`), manifest completeness, secure-storage namespace classification or registry completeness, registry-driven cleanup, critical/non-critical item handling, SQLCipher parameter compatibility, native storage preflight accounting, consistent database snapshot validation, checksum verification, secret-to-identity matching, ML-KEM challenge verification, group device-identity preservation or rebind policy, version compatibility, DB-key/identity-secret import ordering, durable cutover record ordering, staging/commit state, migrated-out state, active-account gating, server-side deregistration policy, pending-work ownership, temporary-artifact cleanup, and progress-state transitions.
- Integration: full export/import of database, staged primary and shared secure-storage values, committed retained group-key generations, primary-store pending group-key rotation drafts, group member device rosters, sender device/transport metadata, key-package state, chat-media secure keys, post-media DB crypto metadata, and app-owned media into a fresh app state without exposing partial account data, overwriting active keys before commit, mismatching secrets, leaking sensitive migration material, losing messages outside the export snapshot, duplicating pending jobs, breaking notification-preview decryption, creating a second active group device entry for the moved account, leaving server-side old-device rendezvous/push leases active, or leaving two active account holders.
- Smoke: user-visible new-phone and old-phone journeys remain understandable from QR pairing and confirmation through final success, retryable failure, migrated-out old-phone state, and explicit erase.
- Simulator: iOS lifecycle, camera permission, local-network permission, clock-skewed pairing, insufficient storage, iOS keychain/restore behavior, foreground wake-lock behavior, manual lock/call/background suspension recovery, runtime old-device shutdown, server-side lease cleanup, and post-migration startup behavior.
