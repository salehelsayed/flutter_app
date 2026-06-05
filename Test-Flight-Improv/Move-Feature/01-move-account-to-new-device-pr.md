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
- Identity secrets are split between the database row and secure storage. The critical secure-storage keys include `identity_private_key`, `identity_mnemonic12`, and `identity_ml_kem_secret_key`. Evidence: `lib/features/identity/domain/repositories/identity_repository_impl.dart`, `lib/core/secure_storage/migrate_secrets_to_secure_storage.dart`, `test/features/identity/domain/repositories/identity_repository_impl_test.dart`
- Mnemonic restore regenerates ML-KEM key material during restore, so it is not equivalent to moving the exact existing account state. Evidence: `lib/features/identity/application/restore_identity_use_case.dart`
- Media and group encryption material can be stored through secure-storage references such as `secure:media_attachment_encryption_key:<attachmentId>` and `secure:group_key_material:<encodedGroupId>:<generation>`. Importing the database without those secure-store values would leave encrypted media or groups undecryptable, but these row-referenced keys are only part of the secure-storage namespace. Evidence: `lib/core/secure_storage/secret_storage_references.dart`, `lib/features/conversation/domain/repositories/media_attachment_repository_impl.dart`, `lib/features/groups/domain/repositories/group_repository_impl.dart`
- Encrypted media attachment decryptability depends on the file bytes, the secure-storage key, and the in-database nonce/scheme metadata staying atomic. If the secure key is missing, hydration can produce a present attachment row with no usable decryption key. Evidence: `lib/features/conversation/domain/models/media_attachment.dart`, `lib/features/conversation/domain/repositories/media_attachment_repository_impl.dart`, `test/core/database/migrations/059_media_attachment_encryption_columns_test.dart`
- The app also stores fixed secure-storage keys that are not discoverable from database row references, including `db_encryption_key`, `identity_private_key`, `identity_mnemonic12`, `identity_ml_kem_secret_key`, `secrets_migrated`, `background_preference`, `image_quality_preference`, `video_quality_preference`, `push_fcm_token`, and `push_fcm_platform`. On iOS, the app additionally mirrors `identity_ml_kem_secret_key` and group keys such as `group_key:<rawGroupId>:<generation>` into the shared Apple access group `group.com.mknoon.app.share` for notification preview decryption; this naming differs from the primary secure-storage group key reference, which URI-encodes the group ID. Evidence: `lib/core/secure_storage/migrate_secrets_to_secure_storage.dart`, `lib/features/settings/domain/models/background_preference.dart`, `lib/features/settings/domain/models/image_quality_preference.dart`, `lib/features/push/infrastructure/push_token_store_impl.dart`, `lib/core/secure_storage/flutter_secure_key_store.dart`, `lib/features/identity/domain/repositories/identity_repository_impl.dart`, `lib/features/groups/domain/repositories/group_repository_impl.dart`, `ios/NotificationService/NotificationPreviewResolver.swift`
- Group history can depend on retained non-latest key generations and pending rotation drafts, not only the latest group key. The retention policy keeps up to 8 generations, and group messages/offline replay reference the generation used for encryption. Evidence: `lib/features/groups/domain/models/group_key_retention_policy.dart`, `lib/core/database/helpers/group_keys_db_helpers.dart`, `lib/features/groups/domain/repositories/group_repository_impl.dart`, `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`
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
- Current relay and push state are keyed by `peerId`. The rendezvous backend stores one registration per namespace and peer ID, the push-token backend stores one token per peer ID, and inbox retrieval consumes messages for a peer. That means two active primary phones using the same identity would compete for messages instead of reliably syncing. Evidence: `go-relay-server/backend_memory.go`, `go-relay-server/push_token_store.go`
- Startup currently starts P2P after routing to the main app for returning users. A migrated-out old device will need a user-visible blocked state before normal P2P startup. Evidence: `lib/features/identity/presentation/startup_router.dart`, `test/features/identity/presentation/screens/startup_router_test.dart`

# 5. Scope Clarification

In scope:

- iOS-to-iOS account migration as the first supported user journey.
- New-phone first-launch onboarding entry point: `Move from old phone`.
- Old-phone settings entry point: `Move account to new phone`.
- QR-based pairing between the new phone and old phone.
- Direct same-WiFi transfer for the migration data.
- End-to-end encrypted migration of account data, including identity secrets, database, DB encryption key, message history, contacts, groups, posts/social-feed state, introductions, inbox staging, media metadata, media files, retained group-key generations, pending group-key rotation drafts, media attachment keys, and app-owned local files needed for history to render.
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
- A contact QR, expired migration QR, reused migration QR, malformed-timestamp migration QR, or stale migration session must never authorize account export.
- Migration QR handling must be separated from contact QR handling before any contact-add, contact-request, or profile-picture-download side effects can run.
- Because the new phone starts without an account identity, the pairing flow must define how the identity-less new phone authenticates the session and how the old phone binds export authorization to that authenticated session.
- Migration import may only run when no active account exists on the new phone.
- Any empty database or key material created during first startup on the new phone is replaceable staging state until migration commits.
- If an active account already exists on the new phone, migration requires an explicit erase/reset before starting.
- Failed migration cleans or quarantines staging data and must not expose it through normal app startup.
- Migration export must be manifest-driven. Manifest items must be classified as critical or non-critical. Critical items include the database, database checksum, DB encryption key, schema/app version, identity secrets, the secure-storage migration sentinel needed for correct identity loading, every required secure-storage value in the primary app keychain, every required mirrored value in the iOS shared access group, every retained group-key generation and pending group-key rotation draft, media encryption keys referenced by retained media, every app-owned local file required to preserve promised history rendering, file sizes, and file checksums. Non-critical cache files may be omitted only if the UI can safely render without them.
- Secure-storage discovery must enumerate the full app-owned secure-storage namespace across both iOS keychain access groups and classify each key. It must not rely only on database rows that contain `secure:` references.
- Fixed secure-storage keys that are not row-referenced must be classified explicitly, including `db_encryption_key`, identity secret keys, `secrets_migrated`, app preference keys, and device-bound push-token keys.
- Every fixed secure-storage key must have an explicit migrate, clear, regenerate, or intentionally-device-local policy; app preference keys must not disappear only because no database row references them.
- Device-bound push-token values are not valid migrated account state by themselves. MVP policy: do not carry the old device's push token as active account state; clear or ignore stale token material during import and force fresh push registration on the new phone after cutover.
- Migration must preserve notification-preview decryption on the new iPhone by migrating or re-establishing the shared-access-group values needed by the iOS notification service extension before claiming success.
- Retained group-key generations and pending group-key rotation drafts must be verified by resolved key bytes in both the primary and shared keychain stores, not only by database reference strings or latest-key lookup.
- Database export must use a transactionally consistent SQLCipher/SQLite snapshot. The export contract must be correct for the database's actual journal mode and must not rely on a WAL-only checkpoint assumption; `sqlcipher_export` is the preferred current primitive unless implementation proves an equivalent consistent snapshot.
- A raw database-file copy is not valid unless export proves the copied database includes all committed state. The manifest checksum must cover the exported consistent snapshot, not an arbitrary file on disk.
- The export scope must cover both storage roots: the encrypted database root and the application documents root that contains app-owned media and pending media files.
- Database scope means the full current schema, not only the named user-facing categories. Any selective validation or future selective export must enumerate every table in the migration chain and prove no local account table is silently omitted.
- The final export must be a consistent snapshot across database, secure storage, account queues, and app-owned files. During manifest generation and final export, account-state mutations that could change the exported state must be paused, including send queue, retry queue, upload queue, inbox drain, media writes, group-key writes, secure-storage mutations, and account-related database writes.
- Export fails if any required referenced secret or file is missing.
- Import fails unless every required manifest item is present and verified.
- Encrypted media and post-media entries are verified atomically: file bytes, database metadata, `encryption_nonce`, `encryption_scheme`, and the resolved media key must either all match the manifest or the import fails before success.
- Before starting a large transfer, both phones should check migration compatibility and tell the user to update if either app version is unsupported.
- Migration is supported only when the new app version can open or migrate the exported database schema.
- Unsupported future database or schema versions must fail before commit.
- The migration manifest must carry a migration protocol version, exported database `user_version`, source app version/build, minimum compatible importer version, and an explicit unsupported-version failure reason before any large bundle transfer or commit.
- Successful import requires the new phone to have the imported DB encryption key available before opening the imported database, then open the imported database and load identity from secure storage before normal app entry.
- Import must not generate or persist a replacement `db_encryption_key` for an imported database, and it must not set the secure-storage migration sentinel against an imported identity row with missing active secrets.
- Before import commit, the new phone must verify that imported secure-storage secrets match the imported account identity. The identity private key must match the expected public identity or peer ID, the ML-KEM secret key must match expected public key material when that relationship is checkable, and required secure-storage references must resolve to the expected account, group, and media records.
- If imported identity material is present but mismatched, import fails before commit.
- Migration logs, analytics, crash reports, and debug events must not include mnemonics, private keys, DB keys, group keys, media keys, migration bundle contents, raw QR payloads, decrypted manifest secrets, or secure-storage values. Coarse non-sensitive states such as pairing failed, version incompatible, checksum failed, storage insufficient, permission denied, or import verification failed may be recorded.
- Temporary migration artifacts must be encrypted at rest or memory-only, scoped to the migration session, deleted after success, cancellation, or failed-import cleanup, and excluded from user-visible partial account state. Temporary files and transient media artifacts such as `.enc`, `.download.jpg`, and `.raw.*.jpg` must not be carried as durable account data unless the manifest explicitly classifies them as required.
- Migration must not rely on iCloud Backup, iCloud Keychain, or OS-level app restore as the migration mechanism. iOS keychain accessibility, locked-device and reboot readability, persistence, backup, and sync behavior must be verified so identity secrets and staging secrets do not unexpectedly survive, sync, or resurrect account state outside the explicit migration flow.
- Import is first written to a non-active staging area on the new phone.
- Migration staging applies to database files, app-owned media files, manifest data, and secure-storage values. Imported secure-storage values must be written under a migration staging namespace, and active secure-storage keys must not be overwritten until database, file, manifest, version, checksum, identity-load, and cutover verification all pass.
- No imported secret becomes an active secret until commit.
- The new phone becomes active only after database, secure-storage secrets, media files, manifest checks, version compatibility, identity loading, and durable cutover all pass.
- A large migration bundle must be transferred and encrypted with bounded memory use, chunk or segment verification, and resume from verified progress after interruption. It must never require whole-file plaintext/ciphertext residency in memory or claim success from an incomplete segment set.
- The old phone is marked migrated-out only after the new phone has proven the imported account can open in verified, non-active staging.
- During final cutover, the old phone must durably enter a network-blocked or migrated-out state before the new phone becomes active or enters normal app startup.
- The new phone may only enter normal app startup after receiving proof that the old phone has durably blocked normal account activity.
- Final migration success requires a durable cutover record on both devices: the new phone has durably committed imported-active state, the old phone has durably committed migrated-out state, and normal success UI is shown only after both durable states are known.
- Active, migrating, and migrated-out account state must be persisted per account and must be observable by startup, resume, push, retrier, queue, and networking entry points.
- If the final cutover acknowledgement is interrupted before old migrated-out state is durable, the old phone remains active and the new phone remains retryable or staged.
- If the final cutover acknowledgement is interrupted after old migrated-out state is durable, the new phone is active and the old phone is blocked as migrated out.
- If cutover is interrupted before commit, the old phone remains active and the new phone cleans or retries staging.
- If cutover is interrupted after commit, the new phone is active and the old phone is blocked as migrated out.
- There must be no state where both devices can start normal P2P for the account.
- In rare crash or interruption cases, the migration flow must prefer a retry, cleanup, or temporarily zero-active-device state over allowing two active primary devices.
- During active final export and transfer, the old phone pauses account network activity for this account.
- During active migration, the old phone disables user sends for this account and stops consuming relay inbox messages before the final export snapshot.
- Any messages not included in the export must remain available for the new phone to receive after cutover.
- If migration fails before commit, the old phone resumes normal networking.
- Drafts and local unsent user data may migrate as local account data.
- Pending outbound work is migrated and becomes owned by the new phone after commit. This includes committed sends, retry jobs, upload jobs, pending media work, and app-owned pending upload files that are valid local account state.
- Pending outbound work resumes only on the new phone after commit, using existing idempotency and deduplication rules. If an item cannot be safely migrated, migration must either fail before success or leave that item paused/failed with a clear local state; it must not be silently dropped or resumed on both devices.
- After commit, the old phone must never resume copied pending jobs.
- On old-phone migration commit, the old phone stops active P2P/account networking immediately, closes active inbound/outbound account streams, cancels message polling and inbox draining, leaves live group topics, cancels group discovery loops, prevents send/retry/upload queues from running for the migrated-out account, and skips push-token and rendezvous registration for migrated-out accounts.
- Send, receive, retry, upload, local discovery, inbox-drain, group-topic rejoin, group discovery, push-handler recovery, push-registration, and rendezvous-registration entry points must observe active-account state, not only startup routing.

Explicit non-goals:

- No cloud backup.
- No relay-based migration fallback.
- No two-active-primary-device sync.
- No linked-device feature.
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
- If a contact QR, stale migration QR, or already-used migration QR is scanned, it does not authorize account export and does not create a bogus contact or send a contact request.
- If the phones are not on the same usable local network, the app explains the requirement and does not use relay or cloud transfer as a hidden fallback.
- If local-network permission, camera permission, or WiFi availability prevents pairing, the user sees a clear next step and the old phone remains active.
- If the transfer is interrupted before final verification, the new phone does not enter the normal app and the old phone remains the active device.
- If cutover is interrupted before commit, startup resolves to the old phone as active and the new phone as retryable or cleaned staging.
- If cutover is interrupted after commit, startup resolves to the new phone as active and the old phone as migrated out.
- If a crash or interruption prevents proving either stable cutover state, startup shows retry or cleanup rather than allowing both phones to become active.
- If the new phone lacks enough storage for the database and media, migration fails clearly before claiming success.
- If the database export cannot prove a consistent SQLCipher/SQLite snapshot that includes all committed state, migration fails before claiming success.
- If final export cannot prove a consistent snapshot across database, secure storage, account queues, and app-owned files, migration fails before claiming success.
- If any required primary or shared-access-group secure-storage value is missing from the migration export, migration does not claim success.
- If the imported database is opened before the imported DB encryption key is active, import fails cleanly without generating a new key, encrypting an empty replacement database, or exposing partial account state.
- If identity rows have null secret columns but imported secure-storage secrets are not yet committed, startup and import do not set a migrated-secrets sentinel that would make the identity permanently unloadable.
- If any critical manifest item, required media file, required secret, or database checksum fails, migration does not claim success.
- If a non-critical cache item is omitted, the imported app still renders safely without pretending that required history or media is present.
- If retained group-key generations, pending group-key rotation drafts, or their shared-access-group mirrors are missing, migration fails before claiming group history was preserved.
- If group history spans the full retained group-key window, including generation-boundary history and pending rotation drafts, every retained epoch still decrypts after migration rather than only the latest group key.
- If app-owned files include `media/`, `post_media/`, `pending_uploads/`, contact avatars, group avatars, generated video thumbnails classified as required, or other required renderable files, those files are present and verified on the new phone before success.
- If a database row contains a raw absolute local media path that is not portable, migration either heals it or fails/flags it clearly before claiming that attachment was preserved.
- If media or post-media metadata is present but its file, nonce, scheme, or resolved encryption key is missing or mismatched, migration fails before claiming that attachment was preserved.
- If the exported database schema is unsupported by the new app version, migration fails before commit and does not expose partial account data.
- If the migration protocol version, source app version, exported database version, or minimum importer version is missing or incompatible, migration fails before large transfer or commit with a clear update path.
- If imported secure-storage identity material does not match the imported account identity or required account/group/media references, migration fails before commit.
- If imported secure-storage values are written during staging, they do not overwrite active secure-storage keys before commit.
- If the final cutover acknowledgement is interrupted before old migrated-out state is durable, the old phone remains active and the new phone does not enter normal app state.
- If the final cutover acknowledgement is interrupted after old migrated-out state is durable, the new phone remains active and the old phone stays blocked as migrated out.
- If migration is cancelled, fails, or succeeds, temporary migration artifacts do not remain as readable bundles, logs, crash-report content, analytics payloads, or user-visible partial account state.
- If iCloud Backup, iCloud Keychain, or OS-level restore behavior is present on the device, it does not become the migration mechanism or resurrect active/staging account state outside the explicit migration flow.
- If an active account already exists on the new phone, migration does not start until the user explicitly erases or resets that local account state.
- If the app is backgrounded, locked, or killed during migration, the next launch shows a clear retry or cleanup state rather than partial account access.
- During final export and transfer, the old phone does not consume new relay inbox messages or allow new user sends for the migrating account.
- If a message is not included in the export snapshot, it remains available for the new phone to receive after cutover, or the old phone resumes normally if migration fails before commit.
- If migration completes and the old phone is later opened, it shows a migrated-out state instead of starting P2P or draining inboxes.
- If migration completes and resume, push handling, or retry recovery later tries to rejoin group topics, the migrated-out old phone remains blocked and does not resubscribe or restart group discovery.
- If the transfer is interrupted during a large media-heavy bundle, resume uses only verified chunks or segments and never treats a truncated bundle as successful.

## Regressions To Preserve

- Existing new-account onboarding remains available for users who are not migrating.
- Existing mnemonic restore remains available, but it is not presented as equivalent to full device migration.
- Existing contact QR scanning and contact QR payload behavior remain unchanged for normal contact sharing.
- Adding a migration QR branch does not let migration payloads fall through to contact-add, contact-request, or profile-picture-download side effects.
- Existing local WiFi messaging and local media transfer behavior remain unchanged for normal conversations.
- Existing SQLCipher database open, migration-chain, and secure-storage migration behavior remain unchanged for normal app startup.
- Existing identity loading remains strict about missing private key or mnemonic secrets.
- Existing P2P startup for normal returning users remains unchanged when the account is not marked as migrated out.
- Existing push notification registration remains tied to the active device after normal startup.
- Existing send, retry, upload, local discovery, inbox-drain, and P2P behavior remains unchanged for accounts that are not in active migration or migrated-out state.
- Existing platform behavior outside iOS-to-iOS migration remains unchanged; Android and cross-platform migration are not part of this MVP.

## Release-Blocking Safety Tests

Before this feature is exposed to users, acceptance evidence must prove these dangerous paths are covered:

- Migration export includes the encrypted database, DB encryption key, identity private key, mnemonic, ML-KEM secret, secure-storage migration sentinel behavior, every critical primary keychain value, every critical shared-access-group keychain value, retained group-key generations, pending group-key rotation drafts, media encryption keys, app-owned media files, and app-owned local files required for promised history rendering.
- Full export/import restores database rows across the full current database schema, including conversations, contacts, groups, posts/social-feed, introductions, inbox staging, pending work, secure-storage values, app-owned media files, and app-owned local files into a fresh app state that can open and render the migrated account.
- Migrated images, voice messages, videos, post media, avatars, group avatars, and other app-owned attachments remain decryptable and renderable because their media files, metadata, nonce/scheme data, and media encryption keys match after import.
- Generated video thumbnails are either copied and verified when classified as required, or omitted only when the new phone safely regenerates them without claiming user-visible media loss.
- Historical group messages and offline-replay envelopes encrypted under retained non-latest group-key generations remain decryptable after import, including the full eight-generation retained window and pending rotation drafts, and every retained generation is verified by resolved key bytes in the primary and shared keychain stores.
- iOS notification service extension preview decryption works on the new phone after import for migrated 1:1 and group secrets, including shared-access-group mirrors.
- Imported secure-storage values are staged first and do not overwrite active secure-storage keys before commit.
- Database export uses `sqlcipher_export` or an equivalently proven consistent SQLCipher/SQLite snapshot, and import rejects torn, stale, or incomplete snapshots.
- Database export/import covers both the SQLCipher database root and the app documents/media root; a documents-only or database-only copy is not sufficient.
- Import ordering proves the DB encryption key, imported database, identity secure-storage values, and secure-storage migration sentinel cannot be committed in an order that creates a new empty database or unloadable identity.
- Durable cutover records prove final migration success only after the new phone is active-ready and the old phone is durably migrated out or network-blocked.
- The new phone cannot enter normal app UI or start normal account services until import is fully verified and cutover is durable.
- The old phone shuts down account networking at cutover, including P2P, inbound/outbound streams, inbox draining, live group topic subscriptions, group discovery loops, push/rendezvous registration, send queues, retry queues, upload queues, and local discovery for the migrated-out account.
- Resume, push-handler, and retrier paths cannot rejoin group topics or restart group discovery for a migrated-out account.
- Exactly one device becomes active after migration recovery settles; interruption paths must never leave both phones able to start normal P2P for the same account.
- Interrupted migration recovers safely into old-active/new-not-active, new-active/old-migrated-out, or retry/cleanup state.
- Pending sends, retries, uploads, pending media work, and app-owned pending upload files do not duplicate or disappear silently.
- Same-WiFi migration does not fall back to relay, cloud, iCloud Backup, iCloud Keychain, or OS-level app restore as the migration path.
- Same-WiFi migration uses an authenticated encrypted migration transfer path that can carry an opaque account bundle rather than relying on the normal media upload MIME contract.
- Large bundle transfer and encryption are streaming/chunked, memory-bounded, resumable from verified progress, and recover predictably after interruption, backgrounding, or app restart without accepting partial data as success.
- Push-token behavior after cutover clears or ignores the stale old-device token, forces fresh new-phone registration, leaves the new phone as the active push target for the peer ID, and prevents stale old-device token state from winning.
- QR pairing has a type discriminator, uses migration-specific parsing or scanner dispatch, fails closed on malformed timestamp/session data, records consumption for single-use semantics, and keeps contact QR and migration QR side effects separated.
- Migration QR compatibility proves contact-only field sets are rejected by the migration flow and migration-only field sets do not fall through to contact parsing or contact side effects.
- Sensitive keys and migration data never appear in logs, analytics, crash reports, debug events, readable temporary artifacts, transient media artifacts, raw QR/session logs, or partial account state.
- iOS primary and shared keychain staging behavior is verified across lock, unlock, reboot, success cleanup, cancellation cleanup, and failed-import cleanup.
- After successful migration, the old phone shows only migrated-out UI with an erase action and does not expose normal account UI, old conversations, inbox, or read-only history mode.

## Simulator Acceptance Scenarios

Before release, simulator or device-context acceptance must cover these iOS journeys:

- New phone first launch shows `I'm new here`, `Move from old phone`, and `Restore with recovery words`, and choosing `Move from old phone` enters migration pairing instead of normal onboarding.
- Old phone can open `Move account to new phone`, scan the new phone QR, see final confirmation, and start export only after confirming the migration session.
- Pairing rejects expired, reused, stale, malformed, and contact QR payloads without exporting account data.
- Pairing rejects migration payloads that are missing the migration type or have malformed timestamps, and contact QR scanning still behaves normally.
- Camera permission denial shows a clear recovery path and leaves the old phone active.
- Local-network permission denial or unavailable same-WiFi path shows a clear recovery path and does not use relay, cloud, iCloud Backup, iCloud Keychain, or OS-level restore as a fallback.
- During transfer, both phones show progress stages and stay awake while the migration screen is foregrounded.
- Killing, locking, backgrounding, or restarting either app before commit recovers to old-active/new-not-active or retry/cleanup state without exposing partial account data.
- Interrupting transfer after import staging but before durable cutover does not let the new phone enter normal app UI or start account services.
- Interrupting final cutover after the old phone has durably blocked account activity recovers to new-active/old-migrated-out.
- A completed migration opens the new phone into the migrated account only after import verification, staged secret promotion, identity loading, and durable cutover are complete.
- Opening the old phone after successful migration shows only the migrated-out screen with an erase action and never shows old inbox, conversations, read-only history, or normal account UI.
- After successful migration, the old phone does not start P2P, local discovery, inbox drain, live group topics, group discovery, push registration, rendezvous registration, send retries, or upload queues for the migrated-out account.
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
- Missing acceptance evidence: no current test proves every fixed secure-storage key has an explicit migrate, clear, regenerate, or intentionally-device-local policy, including app preference keys that are not row-referenced.
- Missing acceptance evidence: no current test proves manifest items are classified as critical or non-critical and that omitted cache data does not break safe rendering.
- Missing acceptance evidence: no current test proves database export uses `sqlcipher_export` or an equivalently consistent SQLCipher/SQLite snapshot and rejects raw copies that do not include all committed state.
- Missing acceptance evidence: no current test proves migration validation covers the full current database schema rather than only the named high-level categories.
- Missing acceptance evidence: no current test proves final export is consistent across database, secure storage, account queues, and app-owned files while account-state mutations are paused.
- Missing acceptance evidence: no current test proves a migrated database plus secure-store import can open and render the same conversation, group, post/social-feed, introduction, inbox staging, pending-work, and media history on a fresh install.
- Missing acceptance evidence: no current test proves secure-storage staging uses non-active staged keys and does not overwrite active secure-storage keys before commit.
- Missing acceptance evidence: no current test proves imported secure-storage secrets match the imported account identity and database references before commit.
- Missing acceptance evidence: no current test proves all retained group-key generations, pending group-key rotation drafts, and shared-access-group mirrors survive export/import and decrypt multi-epoch group history.
- Missing acceptance evidence: no current test proves retained group-key generations and pending group-key rotation drafts are verified by resolved key bytes rather than latest-key lookup or reference-string presence.
- Missing acceptance evidence: no current test proves the full eight-generation retained group-key window survives migration at the retention boundary.
- Missing acceptance evidence: no current test proves app-owned media files from both storage roots are copied, verified, and displayed after migration.
- Missing acceptance evidence: no current test proves migrated image, voice-message, video, post-media, avatar, group-avatar, and attachment rows still match their migrated files, nonce/scheme metadata, and media encryption keys after import.
- Missing acceptance evidence: no current test proves generated video thumbnails are copied when required or safely regenerated when treated as non-critical cache.
- Missing acceptance evidence: no current test proves raw absolute media paths are healed or flagged rather than silently claimed as migrated.
- Missing acceptance evidence: no current test proves the DB encryption key import, database open, identity secret promotion, and secure-storage migration sentinel ordering cannot create an empty replacement database or unloadable identity.
- Missing acceptance evidence: no current test proves a partially imported migration cannot become the active account.
- Missing acceptance evidence: no current test proves the canonical new-phone and old-phone migration states drive startup, networking, queues, and UI consistently.
- Missing acceptance evidence: no current test proves final cutover ordering requires durable old-phone network-blocked or migrated-out state before new-phone normal startup.
- Missing acceptance evidence: no current test proves durable cutover records on both devices gate normal success UI and resolve to exactly one active device if interrupted before or after commit.
- Missing acceptance evidence: no current test proves ambiguous crash recovery prefers retry/cleanup or zero-active-device state over two active primary devices.
- Missing acceptance evidence: no current test proves the old phone blocks normal P2P startup after migration succeeds.
- Missing acceptance evidence: no current test proves the old phone stops active runtime networking, send/retry/upload queues, inbox draining, live group topic subscriptions, group discovery loops, push registration, and rendezvous registration at migration commit.
- Missing acceptance evidence: no current test proves resume, push-handler, and retrier paths cannot rejoin group topics for a migrated-out account.
- Missing acceptance evidence: no current test proves the old phone pauses sends and inbox consumption during final export so in-flight messages are not lost from the migration snapshot.
- Missing acceptance evidence: no current test proves valid pending drafts, sends, retries, uploads, media jobs, and app-owned pending upload files migrate and resume only on the new phone after commit, while unsafe items block success or remain paused/failed with clear local state.
- Missing acceptance evidence: no current test proves sensitive migration material is excluded from logs, analytics, crash reports, debug events, and readable temporary artifacts.
- Missing acceptance evidence: no current test proves transient media artifacts such as `.enc`, `.download.jpg`, and `.raw.*.jpg` are excluded, cleaned, or explicitly classified before they can enter durable migrated account state.
- Missing acceptance evidence: no current test proves same-WiFi migration avoids relay/cloud transport while using an authenticated encrypted migration-specific transfer path for an opaque account bundle.
- Missing acceptance evidence: no current test proves large bundle encryption and transfer are streaming/chunked, memory-bounded, resumable from verified progress, chunk/checksum verified, and interruption-safe.
- Missing acceptance evidence: no current test proves QR pairing is type-discriminated, single-use, expiring, authenticated, includes old-phone confirmation and session confirmation, fails closed on malformed timestamps, and rejects contact/stale/reused QR payloads for migration export.
- Missing acceptance evidence: no current test proves migration QR handling avoids the contact QR parser's contact-only field contract and fail-open malformed-timestamp behavior.
- Missing acceptance evidence: no current test proves migration QR payload compatibility is versioned separately from contact QR payload compatibility.
- Missing acceptance evidence: no current test proves stale old-device push tokens cannot remain the winning push target after migration.
- Missing acceptance evidence: no current test proves unsupported exported database versions fail before import commit.
- Missing acceptance evidence: no current test proves version compatibility is checked before large transfer starts.
- Missing acceptance evidence: no current test proves migration import is rejected or gated when an active account already exists on the new phone.
- Missing acceptance evidence: no current test proves iCloud Backup, iCloud Keychain, or OS-level app restore cannot act as migration or resurrect active/staging account state.
- Missing acceptance evidence: no current test proves primary and shared keychain staging secrets are cleaned correctly across lock, unlock, reboot, success, cancellation, and failed import.
- Missing acceptance evidence: no current test proves the old phone shows only migrated-out UI with erase action and does not expose old account UI, read-only conversations, or inbox history.
- Missing acceptance evidence: no current test proves Android and cross-platform migration remain out of MVP scope.
- Missing acceptance evidence: no current test proves the transfer stays awake during the active migration journey.
- Missing acceptance evidence: no current test proves two active phones with the same peer ID are prevented after migration.

## Acceptance Evidence

Required acceptance evidence layers:

- Unit: deterministic rules for typed authenticated migration session validity, single-use QR consumption, canonical migration states, manifest completeness, secure-storage namespace classification, critical/non-critical item handling, consistent database snapshot validation, checksum verification, secret-to-identity matching, version compatibility, DB-key/identity-secret import ordering, durable cutover ordering, staging/commit state, migrated-out state, active-account gating, pending-work ownership, temporary-artifact cleanup, and progress-state transitions.
- Integration: full export/import of database, staged primary and shared secure-storage values, retained group-key generations, pending group-key rotation drafts, and app-owned media into a fresh app state without exposing partial account data, overwriting active keys before commit, mismatching secrets, leaking sensitive migration material, losing messages outside the export snapshot, duplicating pending jobs, breaking notification-preview decryption, or leaving two active account holders.
- Smoke: user-visible new-phone and old-phone journeys remain understandable from QR pairing and confirmation through final success, retryable failure, migrated-out old-phone state, and explicit erase.
- Simulator: iOS lifecycle, camera permission, local-network permission, iOS keychain/restore behavior, foreground wake-lock behavior, interruption recovery, runtime old-device shutdown, and post-migration startup behavior.
