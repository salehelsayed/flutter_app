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
- User risk if missing: the user may believe mnemonic restore is enough, but later find old media, group keys, local history, or encrypted receive capability missing.
- Product risk if over-scoped: supporting two active primary phones would require true multi-device sync, message fanout, conflict policy, push-token coordination, read-state rules, and group convergence policy. That is a separate feature and should not be part of this migration MVP.
- Privacy risk: account migration transfers the most sensitive local data in the app, so the transfer must be end-to-end encrypted and must not send the migration bundle through relay or cloud infrastructure.

# 4. Current State

- App startup opens the encrypted SQLCipher database before routing the user into onboarding or the main app. The database key is stored in secure storage under `db_encryption_key`. Evidence: `lib/main.dart`, `lib/core/database/encrypted_db_opener.dart`, `test/core/database/encrypted_db_opener_test.dart`
- Identity secrets are split between the database row and secure storage. The critical secure-storage keys include `identity_private_key`, `identity_mnemonic12`, and `identity_ml_kem_secret_key`. Evidence: `lib/features/identity/domain/repositories/identity_repository_impl.dart`, `lib/core/secure_storage/migrate_secrets_to_secure_storage.dart`, `test/features/identity/domain/repositories/identity_repository_impl_test.dart`
- Mnemonic restore regenerates ML-KEM key material during restore, so it is not equivalent to moving the exact existing account state. Evidence: `lib/features/identity/application/restore_identity_use_case.dart`
- Media and group encryption material can be stored through secure-storage references such as `secure:media_attachment_encryption_key:<attachmentId>` and `secure:group_key_material:<groupId>:<generation>`. Importing the database without those secure-store values would leave encrypted media or groups undecryptable. Evidence: `lib/core/secure_storage/secret_storage_references.dart`, `lib/features/conversation/domain/repositories/media_attachment_repository_impl.dart`, `lib/features/groups/domain/repositories/group_repository_impl.dart`
- Local media paths are stored as relative app-document paths such as `media/...`, `post_media/...`, and `pending_uploads/...`, which makes them portable if the files are copied into the new device's app document directory. Evidence: `lib/core/media/media_file_manager.dart`
- The app already has QR generation/scanning primitives for contact exchange, but the current contact QR payload intentionally keeps a narrow contact-add contract and does not represent account migration. Evidence: `lib/features/qr_code/application/build_qr_payload_use_case.dart`, `lib/features/qr_code/presentation/screens/qr_scanner_screen.dart`
- The app already has local WiFi discovery and local WebSocket/HTTP transfer surfaces for direct peer communication and local media upload. Those surfaces provide useful local-network building blocks, but the migration bundle itself still needs its own encrypted session because it contains account secrets. Evidence: `lib/core/local_discovery/local_ws_server.dart`, `lib/core/local_discovery/local_p2p_service.dart`, `test/core/local_discovery/local_ws_server_test.dart`, `test/core/local_discovery/local_media_integration_test.dart`
- The bridge already exposes useful cryptographic primitives, including ML-KEM key generation, ML-KEM message encryption/decryption, and AES-GCM blob key/file helpers. Evidence: `lib/core/bridge/bridge.dart`
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
- End-to-end encrypted migration of account data, including identity secrets, database, DB encryption key, message history, contacts, groups, media metadata, media files, group keys, media attachment keys, and app-owned local files needed for history to render.
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

- QR pairing must create a single-use, expiring, authenticated migration session.
- The old phone must only export account data after explicit user action from the migration flow.
- The old phone must show a final confirmation before exporting account data.
- Both phones should show a short confirmation code or clear session confirmation before transfer begins.
- If local device authentication is already available for sensitive account actions, migration export should use it before exporting account data.
- A contact QR, expired migration QR, reused migration QR, or stale migration session must never authorize account export.
- Migration import may only run when no active account exists on the new phone.
- Any empty database or key material created during first startup on the new phone is replaceable staging state until migration commits.
- If an active account already exists on the new phone, migration requires an explicit erase/reset before starting.
- Failed migration cleans or quarantines staging data and must not expose it through normal app startup.
- Migration export must be manifest-driven. Manifest items must be classified as critical or non-critical. Critical items include the database, database checksum, DB encryption key, schema/app version, identity secrets, every secure-storage key referenced by database rows, required group keys, media encryption keys referenced by retained media, every app-owned local file required to preserve promised history rendering, file sizes, and file checksums. Non-critical cache files may be omitted only if the UI can safely render without them.
- Database export must use a transactionally consistent SQLCipher/SQLite snapshot. If WAL or journal state exists, export must use a consistent snapshot mechanism or checkpoint and quiesce writes before copying database files.
- A raw database-file copy is not valid unless export proves the copied database includes all committed state. The manifest checksum must cover the exported consistent snapshot, not an arbitrary file on disk.
- The final export must be a consistent snapshot across database, secure storage, account queues, and app-owned files. During manifest generation and final export, account-state mutations that could change the exported state must be paused, including send queue, retry queue, upload queue, inbox drain, media writes, group-key writes, secure-storage mutations, and account-related database writes.
- Export fails if any required referenced secret or file is missing.
- Import fails unless every required manifest item is present and verified.
- Before starting a large transfer, both phones should check migration compatibility and tell the user to update if either app version is unsupported.
- Migration is supported only when the new app version can open or migrate the exported database schema.
- Unsupported future database or schema versions must fail before commit.
- Successful import requires the new phone to open the imported database and load identity from secure storage before normal app entry.
- Before import commit, the new phone must verify that imported secure-storage secrets match the imported account identity. The identity private key must match the expected public identity or peer ID, the ML-KEM secret key must match expected public key material when that relationship is checkable, and required secure-storage references must resolve to the expected account, group, and media records.
- If imported identity material is present but mismatched, import fails before commit.
- Migration logs, analytics, crash reports, and debug events must not include mnemonics, private keys, DB keys, group keys, media keys, migration bundle contents, raw QR payloads, decrypted manifest secrets, or secure-storage values. Coarse non-sensitive states such as pairing failed, version incompatible, checksum failed, storage insufficient, permission denied, or import verification failed may be recorded.
- Temporary migration artifacts must be encrypted at rest or memory-only, scoped to the migration session, deleted after success, cancellation, or failed-import cleanup, and excluded from user-visible partial account state.
- Migration must not rely on iCloud Backup, iCloud Keychain, or OS-level app restore as the migration mechanism. iOS keychain accessibility, persistence, backup, and sync behavior must be verified so identity secrets and staging secrets do not unexpectedly survive, sync, or resurrect account state outside the explicit migration flow.
- Import is first written to a non-active staging area on the new phone.
- Migration staging applies to database files, app-owned media files, manifest data, and secure-storage values. Imported secure-storage values must be written under a migration staging namespace, and active secure-storage keys must not be overwritten until database, file, manifest, version, checksum, identity-load, and cutover verification all pass.
- No imported secret becomes an active secret until commit.
- The new phone becomes active only after database, secure-storage secrets, media files, manifest checks, version compatibility, identity loading, and durable cutover all pass.
- The old phone is marked migrated-out only after the new phone has proven the imported account can open in verified, non-active staging.
- During final cutover, the old phone must durably enter a network-blocked or migrated-out state before the new phone becomes active or enters normal app startup.
- The new phone may only enter normal app startup after receiving proof that the old phone has durably blocked normal account activity.
- Final migration success requires a durable cutover record on both devices: the new phone has durably committed imported-active state, the old phone has durably committed migrated-out state, and normal success UI is shown only after both durable states are known.
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
- On old-phone migration commit, the old phone stops active P2P/account networking immediately, closes active inbound/outbound account streams, cancels message polling and inbox draining, prevents send/retry/upload queues from running for the migrated-out account, and skips push-token and rendezvous registration for migrated-out accounts.
- Send, receive, retry, upload, local discovery, inbox-drain, push-registration, and rendezvous-registration entry points must observe active-account state, not only startup routing.

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
- No broad redesign of the existing contact QR flow.
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
- After successful migration, the new phone opens into the existing account with the same identity, contacts, conversation history, group state, media history, and app-owned local media files.
- After successful migration, the new phone has proven it can open a consistent imported database snapshot, load the migrated identity, and verify imported secrets match the imported account before entering the normal app.
- After successful migration, the new phone receives new messages for the account.
- After successful migration, the old phone immediately stops active account networking and no longer receives, sends, syncs, retries, uploads, drains inboxes, registers push/rendezvous state, or displays new account activity for that account.
- After successful migration, normal success UI appears only after the new phone has durably committed active state and the old phone has durably committed migrated-out state.
- If the migrated account had pending drafts, sends, retries, uploads, pending media work, or app-owned pending upload files, valid pending work resumes only on the new phone after commit; unsafe pending work blocks success or remains paused/failed with clear local state.
- After successful migration, sending a message from the new phone does not create a synced outgoing row on the old phone.
- After successful migration, deleting the app on the old phone does not create duplicate account state or duplicate messages.
- After successful migration, opening the old phone shows a migrated-out screen with an erase action and does not expose normal account UI, old inbox, conversations, or read-only history mode.

## Edge Cases

- If the QR code is expired, malformed, or scanned by the wrong flow, both phones show a clear failure and no account data is transferred.
- If a contact QR, stale migration QR, or already-used migration QR is scanned, it does not authorize account export.
- If the phones are not on the same usable local network, the app explains the requirement and does not use relay or cloud transfer as a hidden fallback.
- If local-network permission, camera permission, or WiFi availability prevents pairing, the user sees a clear next step and the old phone remains active.
- If the transfer is interrupted before final verification, the new phone does not enter the normal app and the old phone remains the active device.
- If cutover is interrupted before commit, startup resolves to the old phone as active and the new phone as retryable or cleaned staging.
- If cutover is interrupted after commit, startup resolves to the new phone as active and the old phone as migrated out.
- If a crash or interruption prevents proving either stable cutover state, startup shows retry or cleanup rather than allowing both phones to become active.
- If the new phone lacks enough storage for the database and media, migration fails clearly before claiming success.
- If the database export cannot prove a consistent SQLCipher/SQLite snapshot that includes all committed state, migration fails before claiming success.
- If final export cannot prove a consistent snapshot across database, secure storage, account queues, and app-owned files, migration fails before claiming success.
- If any required secure-storage value is missing from the migration export, migration does not claim success.
- If any critical manifest item, required media file, required secret, or database checksum fails, migration does not claim success.
- If a non-critical cache item is omitted, the imported app still renders safely without pretending that required history or media is present.
- If the exported database schema is unsupported by the new app version, migration fails before commit and does not expose partial account data.
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

## Regressions To Preserve

- Existing new-account onboarding remains available for users who are not migrating.
- Existing mnemonic restore remains available, but it is not presented as equivalent to full device migration.
- Existing contact QR scanning and contact QR payload behavior remain unchanged.
- Existing local WiFi messaging and local media transfer behavior remain unchanged for normal conversations.
- Existing SQLCipher database open, migration-chain, and secure-storage migration behavior remain unchanged for normal app startup.
- Existing identity loading remains strict about missing private key or mnemonic secrets.
- Existing P2P startup for normal returning users remains unchanged when the account is not marked as migrated out.
- Existing push notification registration remains tied to the active device after normal startup.
- Existing send, retry, upload, local discovery, inbox-drain, and P2P behavior remains unchanged for accounts that are not in active migration or migrated-out state.
- Existing platform behavior outside iOS-to-iOS migration remains unchanged; Android and cross-platform migration are not part of this MVP.

## Release-Blocking Safety Tests

Before this feature is exposed to users, acceptance evidence must prove these dangerous paths are covered:

- Migration export includes the encrypted database, DB encryption key, identity private key, mnemonic, ML-KEM secret, group keys, media encryption keys, app-owned media files, and app-owned local files required for promised history rendering.
- Imported secure-storage values are staged first and do not overwrite active secure-storage keys before commit.
- The new phone cannot enter normal app UI or start normal account services until import is fully verified and cutover is durable.
- The old phone shuts down account networking at cutover, including P2P, inbound/outbound streams, inbox draining, push/rendezvous registration, send queues, retry queues, upload queues, and local discovery for the migrated-out account.
- Exactly one device becomes active after migration recovery settles; interruption paths must never leave both phones able to start normal P2P for the same account.
- Interrupted migration recovers safely into old-active/new-not-active, new-active/old-migrated-out, or retry/cleanup state.
- Pending sends, retries, uploads, pending media work, and app-owned pending upload files do not duplicate or disappear silently.
- Same-WiFi migration does not fall back to relay, cloud, iCloud Backup, iCloud Keychain, or OS-level app restore as the migration path.
- Sensitive keys and migration data never appear in logs, analytics, crash reports, debug events, readable temporary artifacts, raw QR/session logs, or partial account state.
- After successful migration, the old phone shows only migrated-out UI with an erase action and does not expose normal account UI, old conversations, inbox, or read-only history mode.

## Simulator Acceptance Scenarios

Before release, simulator or device-context acceptance must cover these iOS journeys:

- New phone first launch shows `I'm new here`, `Move from old phone`, and `Restore with recovery words`, and choosing `Move from old phone` enters migration pairing instead of normal onboarding.
- Old phone can open `Move account to new phone`, scan the new phone QR, see final confirmation, and start export only after confirming the migration session.
- Pairing rejects expired, reused, stale, malformed, and contact QR payloads without exporting account data.
- Camera permission denial shows a clear recovery path and leaves the old phone active.
- Local-network permission denial or unavailable same-WiFi path shows a clear recovery path and does not use relay, cloud, iCloud Backup, iCloud Keychain, or OS-level restore as a fallback.
- During transfer, both phones show progress stages and stay awake while the migration screen is foregrounded.
- Killing, locking, backgrounding, or restarting either app before commit recovers to old-active/new-not-active or retry/cleanup state without exposing partial account data.
- Interrupting transfer after import staging but before durable cutover does not let the new phone enter normal app UI or start account services.
- Interrupting final cutover after the old phone has durably blocked account activity recovers to new-active/old-migrated-out.
- A completed migration opens the new phone into the migrated account only after import verification, staged secret promotion, identity loading, and durable cutover are complete.
- Opening the old phone after successful migration shows only the migrated-out screen with an erase action and never shows old inbox, conversations, read-only history, or normal account UI.
- After successful migration, the old phone does not start P2P, local discovery, inbox drain, push registration, rendezvous registration, send retries, or upload queues for the migrated-out account.
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
- Missing acceptance evidence: no current test proves a full account migration export contains every required secure-storage secret referenced by the database.
- Missing acceptance evidence: no current test proves migration export is manifest-driven across database checksum, schema/app version, required secure-storage keys, app-owned files, file sizes, and file checksums.
- Missing acceptance evidence: no current test proves manifest items are classified as critical or non-critical and that omitted cache data does not break safe rendering.
- Missing acceptance evidence: no current test proves database export uses a consistent SQLCipher/SQLite snapshot and rejects raw copies that do not include all committed state.
- Missing acceptance evidence: no current test proves final export is consistent across database, secure storage, account queues, and app-owned files while account-state mutations are paused.
- Missing acceptance evidence: no current test proves a migrated database plus secure-store import can open and render the same history on a fresh install.
- Missing acceptance evidence: no current test proves secure-storage staging uses non-active staged keys and does not overwrite active secure-storage keys before commit.
- Missing acceptance evidence: no current test proves imported secure-storage secrets match the imported account identity and database references before commit.
- Missing acceptance evidence: no current test proves app-owned media files are copied, verified, and displayed after migration.
- Missing acceptance evidence: no current test proves a partially imported migration cannot become the active account.
- Missing acceptance evidence: no current test proves the canonical new-phone and old-phone migration states drive startup, networking, queues, and UI consistently.
- Missing acceptance evidence: no current test proves final cutover ordering requires durable old-phone network-blocked or migrated-out state before new-phone normal startup.
- Missing acceptance evidence: no current test proves durable cutover records on both devices gate normal success UI and resolve to exactly one active device if interrupted before or after commit.
- Missing acceptance evidence: no current test proves ambiguous crash recovery prefers retry/cleanup or zero-active-device state over two active primary devices.
- Missing acceptance evidence: no current test proves the old phone blocks normal P2P startup after migration succeeds.
- Missing acceptance evidence: no current test proves the old phone stops active runtime networking, send/retry/upload queues, inbox draining, push registration, and rendezvous registration at migration commit.
- Missing acceptance evidence: no current test proves the old phone pauses sends and inbox consumption during final export so in-flight messages are not lost from the migration snapshot.
- Missing acceptance evidence: no current test proves valid pending drafts, sends, retries, uploads, media jobs, and app-owned pending upload files migrate and resume only on the new phone after commit, while unsafe items block success or remain paused/failed with clear local state.
- Missing acceptance evidence: no current test proves sensitive migration material is excluded from logs, analytics, crash reports, debug events, and readable temporary artifacts.
- Missing acceptance evidence: no current test proves same-WiFi migration avoids relay/cloud transport.
- Missing acceptance evidence: no current test proves QR pairing is single-use, expiring, authenticated, includes old-phone confirmation and session confirmation, and rejects contact/stale/reused QR payloads for migration export.
- Missing acceptance evidence: no current test proves unsupported exported database versions fail before import commit.
- Missing acceptance evidence: no current test proves version compatibility is checked before large transfer starts.
- Missing acceptance evidence: no current test proves migration import is rejected or gated when an active account already exists on the new phone.
- Missing acceptance evidence: no current test proves iCloud Backup, iCloud Keychain, or OS-level app restore cannot act as migration or resurrect active/staging account state.
- Missing acceptance evidence: no current test proves the old phone shows only migrated-out UI with erase action and does not expose old account UI, read-only conversations, or inbox history.
- Missing acceptance evidence: no current test proves Android and cross-platform migration remain out of MVP scope.
- Missing acceptance evidence: no current test proves the transfer stays awake during the active migration journey.
- Missing acceptance evidence: no current test proves two active phones with the same peer ID are prevented after migration.

Required acceptance evidence layers:

- Unit: deterministic rules for authenticated migration session validity, canonical migration states, manifest completeness, critical/non-critical item handling, consistent database snapshot validation, checksum verification, secret-to-identity matching, version compatibility, durable cutover ordering, staging/commit state, migrated-out state, active-account gating, pending-work ownership, temporary-artifact cleanup, and progress-state transitions.
- Integration: full export/import of database, staged secure-storage values, and app-owned media into a fresh app state without exposing partial account data, overwriting active keys before commit, mismatching secrets, leaking sensitive migration material, losing messages outside the export snapshot, duplicating pending jobs, or leaving two active account holders.
- Smoke: user-visible new-phone and old-phone journeys remain understandable from QR pairing and confirmation through final success, retryable failure, migrated-out old-phone state, and explicit erase.
- Simulator: iOS lifecycle, camera permission, local-network permission, iOS keychain/restore behavior, foreground wake-lock behavior, interruption recovery, runtime old-device shutdown, and post-migration startup behavior.
