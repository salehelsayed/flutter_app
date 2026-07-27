# Relay-Free Move Account — Feature Gap & Bug Audit

> **Historical static-audit snapshot from 2026-06-10.** Plan 285 later closed
> bounded in-session cutover retry/replay, runtime re-arm, retained-route
> ownership/reset, authority-aware blocked UI, and destination shared-store
> compatibility at host tier. It did not implement user abort/`recover()`,
> durable process-restart recovery, erase-residue cleanup, device acceptance,
> or release acceptance. Supersession notes below update only those findings;
> the original audit remains the historical baseline.

**Date:** 2026-06-10
**Scope:** Everything in the move pipeline that can prevent a relay-free account move (old phone → new phone), EXCLUDING the two already-triaged bugs: the MIG-012 group-media relay leak (`MIG-012-group-media-relay-leak-triage.md`) and the segment-transfer timeout (`move-transfer-timeout-before-handoff-triage.md`) — those appear only where they interact or have new manifestations.
**Method:** 74-agent workflow — 8 domain finders + 3 critic-spawned extra finders over the working tree (`lib/features/account_migration/` is untracked/new), every finding adversarially verified against source, refuted claims retained for the record. Static analysis only; no code changed, no device runs.
**Result:** 61 findings audited → 55 survived verification → ~40 distinct defects: **8 critical, ~13 high, ~14 medium, ~8 low.** 6 refuted.

---

## Executive Summary

This audit swept eleven dimensions of the new (untracked) `lib/features/account_migration/` move pipeline against the relay-free product rule. **Of 61 audited findings, 55 hold up under verification and 6 were refuted.** After merging the duplicate lanes that independently rediscovered the same defect, the 55 confirmed findings reduce to roughly 40 distinct defects: **8 critical, ~13 high, ~14 medium, ~8 low.**

The encouraging half: the *data model* of the move is largely sound. The full SQLCipher snapshot carries every table, sent/received 1:1 media canonicalizes to relative paths, group keys and post crypto travel correctly, LAN-received media is materialized to canonical paths before export, and the import side checksum-verifies every file three times and fails closed on schema drift. Most "does historical X re-fetch from relay" questions came back clean (see Verified OK).

The discouraging half: the *transport, scalability, cutover, and lifecycle* layers contain multiple deterministic failures, several of which directly explain the existing Pixel→iPhone test failures.

The five that matter most before the next Pixel→iPhone test:

1. **Whole-account in-memory assembly (source) + whole-bundle re-buffer (receiver).** The bundle is built and re-decoded as one ~4-6× base64 blob in RAM on the main isolate. The receiver re-buffer (`account_migration_bundle_transfer.dart:1273-1285`) jetsams an iPhone 13 (4 GB) when the source is a Pixel 6 (8 GB) — the exact test hardware — for accounts as small as ~0.4-1.5 GB. *Critical, deterministic, retry-proof.*
2. **Fixed 10s `_postJson` timeout against size-scaling synchronous import handlers** (`account_migration_local_transfer_runtime.dart:118`; `migration_database_active_importer.dart:52-99`). For any non-trivial account the `complete`/`old-block-proof` handlers exceed 10s; the source times out (KNOWN-2) while the receiver keeps importing → split/failed cutover. This is the most likely root cause of the 2026-06-10 timeout.
3. **No quiesce of the old phone during transfer** (`migrationExportingNetworkPaused` is dead). The still-`active` old phone keeps draining and *ACK-deleting* the relay inbox every 30s mid-transfer (`p2p_service_impl.dart:2645-2647`, `inbox.go:386`); messages that arrive after the snapshot are lost permanently while the move reports success. *Critical, silent data-loss.*
4. **Cutover failure bricks both phones with an erase-only screen.** Blocking authority state is persisted *before* the proof round-trip, the recovery machinery (`recover()`, `migrationFailedActiveRestored`) is dead code, and the only UI action erases the account — destroying the sole complete copy. *Critical.*
5. **Export hard-blocks on benign, recoverable conditions.** A single historical voice note/share sent over LAN (temp path), one pending post-media upload, one legacy KNOWN-1-deleted group image, or one missing avatar file each abort the *entire* move at assembly with a generic "try again" message that can never succeed. *Critical/High, deterministic, no remediation hint.*

**Verdict on relay-free readiness:** The relay-free *data design* is essentially correct — if a move completes, historical data opens locally without relay. But the move pipeline is **not production-ready**: it fails deterministically on memory and timeout for real accounts, hard-aborts on common pre-existing data states, silently loses live-window messages, and can brick both devices on any handoff hiccup. Do not run another Pixel→iPhone test with a real-sized account until at least the five above are addressed.

---

## Confirmed Gaps & Bugs (Ranked)

### CRITICAL

**Source assembles the entire account as one in-memory base64 JSON blob (~4-6× account size resident)**
Type: move-failure · Severity: critical · Confidence: high
Export is fully monolithic on the main isolate: every media file and the full DB snapshot are `readAsBytes` whole (`account_migration_bundle_transfer.dart:329`, `:196`), base64'd into one JSON object (`:1556`, `:1629`), serialized to one string then one `Uint8List` (`:205-207`), sliced into segments (`:1428`), and *all* segments ML-KEM-encrypted up front and held (`:1379-1406`). No `Isolate`/`compute` anywhere in the feature. Peak resident ≈ raw + multiple 1.33× copies + 1.78× ciphertext ≈ 4-6× account size, against a ~2 GB iOS foreground jetsam budget. A 4-8 GB media account cannot move; practical ceiling ≈ 300-500 MB.
Scenario: user with group videos taps Move; the old phone OOM-kills (or ANRs) at the "encrypting" stage, identically on every retry.
Fix: stream per-file/per-chunk entries from disk, encrypt+send lazily, move hashing/encode to an isolate.

**Receiver re-buffers the entire decoded bundle in memory at `complete()`**
Type: move-failure · Severity: critical · Confidence: high
Per-segment receive correctly streams plaintext to disk (`:1015-1017`), but `_readBundlePayload` (`:1273-1285`) concatenates every segment into one `BytesBuilder`, `utf8.decode`s + `jsonDecode`s it, and `fromJson` base64-decodes the full DB (`:1526-1528`) and every file entry (`:1621`) into coexisting `Uint8List`s ≈ 2.7-3.7× account size, on the main isolate inside the HTTP handler. Verifier note: the asymmetric band (Pixel 6 8 GB → iPhone 13 4 GB) makes this bite the *receiver* for ~0.4-1.5 GB accounts — the documented test hardware. Receiver session state is in-memory and the session dir is wiped on re-begin, so retries re-fail at the same point.
Scenario: all segments transfer over WiFi (minutes), then the iPhone jetsams at "complete"; verification can never pass.
Fix: parse the payload incrementally; decode each file straight to its destination and verify hashes streaming. Must fix both ends.

**Fixed 10s `_postJson` timeout vs size-scaling synchronous import handlers (new KNOWN-2 manifestation)**
Type: known-bug-interaction · Severity: critical · Confidence: high
The receiver's `complete` handler synchronously runs full reassembly + staging + `_writeImportedFiles` (write + read-back + 2 SHA-256 passes per file) before responding (`account_migration_bundle_transfer.dart:1037-1050`); `old-block-proof` synchronously runs `migration_database_active_importer.dart:52-99` (full-table heap loads, row-by-row insert via one platform-channel call each, `quick_check`, two full logical checksums). The source caps each await at `httpTimeout = 10s` (`account_migration_local_transfer_runtime.dart:118`, `:821`) with no retry/try-catch. Import for even ~100-300 MB exceeds 10s → source throws `TimeoutException` while the receiver keeps importing. At the `old-block-proof` step the source has already called `markOldNetworkBlocked` (`:438`) before the POST, so a timeout strands the old phone blocked-but-not-migrated-out while the new phone may commit active. Verifier note: no code ever writes `migrationFailedActiveRestored`, so the stranded old phone has no recovery path.
Scenario: 400 MB account; every segment transfers, the receiver genuinely imports, but the old phone's `complete`/proof POST times out at 10s → "stopped unexpectedly before final handoff" while the new phone flips to active → split state.
Fix: respond `202` and poll/push status, or scale the timeout with `manifest.totalBytes` and ack before heavy work; never run O(account) work inside a 10s-bounded request.

**No quiesce of old-phone inbox drain/pubsub during transfer — late messages drained + ACKed off relay and lost**
Type: data-loss · Severity: critical · Confidence: high
The DB snapshot is frozen once at assembly start (`account_migration_bundle_transfer.dart:196`), but the old phone stays `active` (gate allows all side effects, `account_migration_runtime_network_gate.dart:38-40`) until cutover; `markOldNetworkBlocked` only fires at the very end (`account_migration_local_transfer_runtime.dart:438`). The health check fires `_drainOfflineInbox` every 30s (`p2p_service_impl.dart:181`, `:2645-2647`), staging relay entries then destructively ACKing them (`:1136-1142`; `go-mknoon/node/inbox.go:386` "InboxAck deletes ... entries whose stable entry IDs match"). The designed pause state `migrationExportingNetworkPaused` (`account_migration_authority_state.dart:10`) is declared but never written anywhere. Late messages land only in the old phone's DB (not the frozen snapshot) and are deleted from relay.
Scenario: mid-transfer a contact sends a message; the old phone drains+ACKs it; after cutover the new phone never has it and it is gone from relay — silent permanent loss under a SUCCESS result.
Fix: set `migrationExportingNetworkPaused` before reading the snapshot so the (already-wired) gate blocks drain/ACK/pubsub, and/or do a final incremental drain into the bundle immediately before cutover; suppress ACK once export begins.

**Interrupted/failed cutover bricks both phones into an erase-only screen; recovery machinery is dead code — PARTIALLY SUPERSEDED BY PLAN 285**
Type: move-failure · Severity: critical · Confidence: high
(Plan-285 update: bounded in-session proof loss now retries against a
replay-safe retained receiver route, duplicate completes share one settled
result, and blocked-authority confirmation is state-aware. Durable
process-restart recovery, user abort/`recover()`, and erase-residue cleanup
remain open.)
(Consolidated: independently confirmed by the pending-work-resume, import-pipeline-integrity, and retry-after-failed-attempt lanes.) The old phone persists `migrationCutoverPendingBlocked` *before* the old-block-proof POST (`migration_cutover_coordinator.dart:62-67` ← `account_migration_local_transfer_runtime.dart:438`→`:443`); the new phone persists `migrationVerifiedWaitingForCutover` at verify (`account_migration_bundle_transfer.dart:1058-1064`). Both states `blocksNormalStartup` (`account_migration_authority_state.dart:28-37`) and route to `AccountMigrationBlockedScreen` whose only action is `_eraseMigratedOutAccount` (`startup_router.dart:315-318`, `:672-684`), wiping `db_encryption_key`/`identity_private_key`/`mnemonic12`/ML-KEM. `MigrationCutoverCoordinator.recover()` (`:381-411`) and `migrationFailedActiveRestored` have **zero production callers/writers** (grep-verified). No crash is even required — any proof-POST timeout/WiFi-drop reaches this state. The receiver's verified import lives only in `_sessions` (in-memory), so a restarted new phone can never replay the handoff.
Scenario: handoff hits a WiFi blip; both phones relaunch to "Account moved to another phone — Erase"; tapping erase on the old phone (the only complete copy) loses the account.
Fix: wire `recover()` at startup; write `migrationFailedActiveRestored` (or `active`) on every cutover-failure path before commit; make the blocked screen state-aware with a "resume handoff" action instead of erase-only; persist/rehydrate the receiver's verified import.

**Local-WiFi sender flows persist done-status attachments with raw temp/cache absolute paths → permanent export hard-fail**
Type: move-failure · Severity: critical · Confidence: high
Voice notes sent over LAN persist `localPath: recording.filePath, downloadStatus: 'done'` from `getTemporaryDirectory()` (`conversation_wired.dart:2680-2693`; `record_audio_recorder_service.dart:168-171`) and share-sheet local sends persist `media.file.path` (`share_batch_delivery_coordinator.dart:284-311`), with no durable copy (contrast the relay/image paths which copy to `media/<peer>/<blobId>`). At export, `_classifyStoredPath` returns null for these temp paths, `_addBestPathFailureIssue` emits a blocking critical `missingRequiredFile`, and `_buildFilePayload` throws (`account_migration_bundle_transfer.dart:302-320`); the downgrade is gated to `nonCriticalCache` so it never applies. The rows never change status → permanent blocker.
Scenario: user once sent a voice note to a contact on the same WiFi; months later every Move attempt aborts at `buildFilePayload`, with no way to identify the offending row.
Fix: durable-copy on local-send success (mirror `_buildLocalSuccessAttachmentFromPlan`); add a manifest salvage candidate that materializes an existing absolute path into the canonical relative path instead of emitting a blocking issue.

**iPhone→Android move fails deterministically: iOS shared-access-group secure entries cannot be staged on Android (failure swallowed) — SUPERSEDED AT HOST TIER BY PLAN 285**
Type: move-failure · Severity: critical · Confidence: high
(Plan-285 update: receiver staging/promotion/cleanup now filters to scopes
supported by the destination, with host proof for the primary projection.
Physical cross-platform device acceptance remains open.)
(Reverse direction — does NOT block the tested Pixel→iPhone, but blocks every iOS→Android move.) An iOS source exports `iosSharedAccessGroup`-scoped entries (fixed `identity_ml_kem_secret_key` + one `group_key:<id>:<gen>` mirror per generation). The Android receiver's `sharedStore` is null (`main.dart:336-338`), so the first shared-scope entry throws `StateError('iOS shared access-group secure store is required')` (`migration_secure_storage_staging.dart:189-193`); `complete()`'s `on Object { return false; }` (`account_migration_bundle_transfer.dart:1066-1068`) swallows it with zero telemetry. No platform gate exists, so all segments stream and then the move deterministically dies at completion with "could not verify the transferred account bundle." Any established identity triggers it (the fixed ML-KEM mirror alone suffices).
Scenario: user moves iPhone→Pixel; transfer completes, "checking" always fails; retry never works.
Fix: at receive time, drop/redirect `iosSharedAccessGroup` entries when `sharedStore` is null (they are derivable mirrors); add telemetry to the `complete()` catch.

### HIGH

**`post_media_upload_recovery` rows store absolute compose/temp paths → any pending/failed post-media upload hard-blocks the move**
Type: move-failure · Severity: high · Confidence: high
(Confirmed by both the file-manifest and posts lanes.) `sendPost` persists recovery rows with the raw composer draft path (`send_post_use_case.dart:239-261`), which is a picker/recorder temp path; the durable `post_media/<postId>/` copy only happens at upload time. The builder evaluates all rows unfiltered (`account_migration_bundle_transfer.dart:1686-1689`) and emits a blocking `unsupportedAbsolutePath` *before any file-existence check* (`migration_file_manifest_builder.dart:663-675`); no post-table downgrade exists, so `_buildFilePayload` throws. Rows clear only on upload success, and the retrier is migration-gated off, so in a relay-unreachable state nothing heals them.
Scenario: user composes a post with a photo while offline, then starts the move; assembly aborts every retry; deleting the failed post is the only (undiscoverable) remedy.
Fix: durable-copy post-media drafts to app-owned storage at compose time and store relative paths; treat missing recovery files as non-blocking (mark post failed); surface the affected post in the journey UI.

**Single missing `done` chat/group-media file aborts the entire move; KNOWN-1-damaged devices hard-block (new manifestation)**
Type: move-failure / known-bug-interaction · Severity: high · Confidence: high
(Consolidated three lanes.) Any `''`/`done`/`upload_pending` row whose file is absent yields a blocking critical `missingRequiredFile` that the `nonCriticalCache`-only downgrade (`account_migration_bundle_transfer.dart:501-506`) can never sanitize → hard abort (`:302-320`). The fail-closed behavior itself is intended (MIG-012 Fix C). The gap is the *missing pre-export reconciliation* and the misleading "try again / restart" message (`account_migration_transfer_flow.dart:75-76`) that can never succeed. **Verifier correction:** KNOWN-1's deletion is FIXED in the working tree (`group_feed_media_verification.dart` no longer deletes, `deleteAttempted:false`), so this is *not* universal — it affects only devices already damaged by pre-fix builds (e.g. the test Pixel) or files lost otherwise. An accidental, undiscoverable workaround exists: opening the affected conversation flips the row to `pending` (`group_conversation_wired.dart:2680-2727`), unbricking the move at the cost of dropping that media.
Scenario: a device that ran a pre-fix build (group images deleted on render) hard-fails every Move attempt with a retry-forever message.
Fix: pre-export reconciliation pass — for `done` rows with missing files, heal to `pending`/`failed` and record a non-blocking degraded-to-relay issue with a user-visible count; keep abort only for identity/secure-value criticals.

**Decrypted bundle plaintext (DB snapshot + identity secrets + media) written to disk on the new phone and never cleaned**
Type: security · Severity: high · Confidence: high
(`#9`/`#34` consolidated.) Each accepted segment is decrypted and persisted (`account_migration_bundle_transfer.dart:1015-1017`); concatenated they form the full bundle JSON whose `secure_storage[].value_base64` holds `identity_private_key`, `mnemonic12`, ML-KEM secret, `db_encryption_key`, and all group/media keys (base64 = plaintext-equivalent). Success path only deletes staged keychain *values* (`:1117-1125`); `MigrationFileImportCleanup`/`MigrationDatabaseImportCleanup` have **zero production callers** (dead code), and no startup sweep exists. **Verifier corrections:** Android sets `allowBackup="false"`, so the backup-exfiltration vector is iOS-only (Documents dir backed up by default, no `NSURLIsExcludedFromBackupKey`); the never-cleared promotion journal holds key *names* only.
Scenario: months after a successful move, `documents/account_migration/import/<session>/segments/*.bin` still contains the account's private key/mnemonic/DB key in plaintext-equivalent form.
Fix: wire the dead cleanup classes into success/failure/abandon paths plus a startup sweep; keep segments encrypted-at-rest until import completes; exclude the staging dir from iOS backup.

**Failed-attempt secret + plaintext residue accumulates per session and survives even the explicit "Erase local data" path**
Type: security · Severity: high · Confidence: high
Per failed attempt: staged secure values `account_migration:staging:v1:<sessionId>:...` (full identity/DB/group/media secrets) persist — deleted only on *successful* cutover (`account_migration_bundle_transfer.dart:1121-1124`); `eraseAccount` deletes only registry `activeKey`s and `SecureKeyStore` exposes no enumeration, so staging-prefixed keys are **structurally unreachable** by erase (`migration_secure_storage_cleanup.dart:18-24`). Each new-QR retry uses a new `sessionId`, so prior attempts' decrypted segment dirs orphan forever; `_sessions` entries and an open staged SQLCipher DB leak; the active importer's delete-all+insert leaves attempt-1-only media files as unreferenced orphans (deleted content silently resurrects on disk).
Scenario: two failed attempts then a success leaves two abandoned plaintext dirs + two keychain copies of all secrets that even the migration "erase" can never remove.
Fix: sweep `account_migration/import/*` and enumerate+delete `account_migration:staging:v1:*` for non-active sessions on session-start/failure; extend `eraseAccount` to staging-prefixed keys.

**Disk amplification ~2.4× with zero cleanup; per-retry residue makes each retry more likely to fail**
Type: silent-degradation · Severity: high · Confidence: high
Receiver footprint per attempt ≈ 1.33× (decrypted segments) + staged DB + 1.0× imported files; `acceptManifest` deletes only the *same* sessionId's dir (`:964-969`), so each new-QR retry orphans +1.33× dead disk; the source never deletes `export/<sessionId>.identity.snapshot.db`. **Verifier note:** even the SUCCESS path never deletes the session dir (only staged secure values + DB handle), so residue persists regardless of outcome. The preflight that would catch this (`migration_storage_preflight.dart`) is dead code.
Scenario: 6 GB account on a phone with 20 GB free — attempt 1 fills ~14 GB then fails on the timeout; attempt 2 fails disk-full mid-import; orphaned plaintext bundles linger.
Fix: cleanup on success/failure/startup; delete the source snapshot after read; wire the preflight with staging-overhead included.

**G1 still open: old-phone erase misses all discovered secrets and erases iOS shared-scope keys from the wrong store**
Type: spec-gap-still-open · Severity: high · Confidence: high
`_eraseMigratedOutAccount` calls `eraseAccount(registryKeys: MigrationSecureStorageRegistry.resolve())` with no args, so `discoveredKeys` defaults to `const []` (`migration_secure_storage_registry.dart:185-189`): every `media_attachment_encryption_key:*`, `group_key_material:*`, and shared `group_key:*` mirror survives in the old phone's keychain. Worse, `StartupRouter` has no shared-store field, so it passes `sharedStore: widget.secureKeyStore` (primary) — the registered shared `identity_ml_kem_secret_key` is deleted from the *primary* store while the real shared-keychain copy survives (and iOS keychain survives uninstall). **Verifier note:** identity private key, mnemonic, DB key, and primary ML-KEM ARE erased (DB crypto-erased), so this is residual decryption capability, not impersonation.
Scenario: user taps Erase after a move; the old device still holds the account's group keys, media keys, and shared ML-KEM secret — decryptable from the device or a backup.
Fix: re-run `MigrationSecureStorageReferenceCollector` against the local DB at erase, pass the real shared store on iOS, add the cutover record key to the registry, consider auto-scrub after old-block proof.

**G6 still open: no cryptographic channel/transcript authentication — a LAN peer who sees the QR can push a forged account**
Type: security (spec-gap-still-open) · Severity: high · Confidence: high
The receiver authenticates the channel by string equality only (`account_migration_local_transfer_runtime.dart:574-576`; `account_migration_bundle_transfer.dart:948-950`) on `sessionId` + `newPhoneEphemeralPublicKey`, both printed in the QR. `authenticatedChannelBinding` is a non-secret string; the 6-digit code is a checksum of public QR data and is never verified on the wire; segment crypto is plain ML-KEM-to-public-key with no sender signature; the final `_isValidOldBlockProof` (`:1315-1324`) is field-equality with no signature. Confidentiality of the legitimate bundle holds, so harm is integrity/availability (account substitution / DoS).
Scenario: a same-WiFi attacker who glimpses the QR uploads an attacker-controlled bundle; the new phone imports and activates it.
Fix: derive a shared secret from the new phone's ML-KEM keypair + a QR nonce, require a MAC over the transcript, and verify the displayed code on the new phone before accepting any manifest.

**G7 still open on the receiver: the new phone holds no wake lock during segment transfer**
Type: spec-gap-still-open · Severity: high · Confidence: high
`AccountMigrationProgressWakeLock` is mounted only when a progress stage exists (`account_migration_journey_screen.dart:95-107`), but the new phone's `_progressStage` is first set on `importVerified` — i.e. only *after* all segments and import succeed; there are no per-segment receiver events (`account_migration_local_transfer_runtime.dart:723-727`). So during the whole receive window the new phone shows the bare QR with no wake lock, no `beginBackgroundTask` (iOS) or foreground service (Android). Default ~1 min iOS auto-lock suspends the app, its HttpServer stops answering, the next segment POST hits the 10s timeout. This is a credible H2 root cause of the 2026-06-10 timeout.
Scenario: user sets the new iPhone down; after 60s it auto-locks, the move aborts; every retry fails identically.
Fix: hold the wake lock on the receiver from `startNewPhoneReceiver` to terminal; emit per-segment progress; add background-task/foreground-service around the transfer on both phones.

**No resumability: the checkpoint store is dead code — every interruption restarts from segment 0 with a new QR**
Type: move-failure · Severity: high (↓ from critical) · Confidence: high
The production source always returns pre-encrypted segments, so the runtime takes `_sendPreparedBundleSegments` (`account_migration_local_transfer_runtime.dart:359-371`, `:525-563`) with zero checkpoint consultation; `importSegments`/`markVerified` (the only checkpoint writers) have **zero call sites**, so `transfer_checkpoints.json` is never written. Receiver `_sessions`/`verifiedIndexes` are in-memory and the session dir is wiped on re-accept; retries mint a new `sessionId`→new `bundleId`→fresh dir, and the source re-runs the full export. **Verifier downgrade:** an uninterrupted run still succeeds and no data is lost, so this is an amplifier of the memory/timeout findings, not a standalone failure.
Scenario: at 70% the new phone takes a call; on retry the user re-mints a QR and re-sends all segments from index 0.
Fix: wire the checkpoint store into the production receive path keyed by content hash; persist receiver sessions; let a new pairing adopt a prior bundle's verified segments when `manifestSha256` matches.

**iOS Local Network permission denial on the new phone → "ready" QR while the receiver is invisible; old phone gets misleading "same Wi-Fi" error**
Type: silent-degradation · Severity: high · Confidence: high
`startNewPhoneReceiver` treats `startAdvertising` returning as success (`account_migration_local_transfer_runtime.dart:148-178`); on iOS, Local-Network denial fails the dnssd registration *asynchronously* (verified in bonsoir_darwin 5.1.3 source) and is never thrown, so the QR shows ready. This is the first-use case (no node ran pre-identity), so the migration receiver is exactly when iOS prompts; the `_startLanPermProbe` heuristic exists only in the normal runtime. The old phone then fails `resolvePeer` after 12s with the misleading "Keep both phones on the same Wi-Fi" (`:279-285`), with no pointer to Settings → Privacy → Local Network.
Scenario: user taps "Don't Allow"; QR shows ready; old phone loops on "new phone not found" forever.
Fix: after `startAdvertising`, self-probe within a few seconds; if absent, flip the QR panel to a "check Local Network permission" state; mirror a hint on the old phone after repeated resolve timeouts.

**Old phone silently loses ALL account network after a failed handoff while still the active device**
Type: silent-degradation · Severity: high · Confidence: high
Once `markOldNetworkBlocked` persists `migrationCutoverPendingBlocked`, the gate denies all P2P ops (`account_migration_runtime_network_gate.dart:36-43`; ~22 sites in `p2p_service_impl.dart` plus the background push handler). Failure after the proof POST returns `cutoverRejected` text without reverting authority, and `migrationFailedActiveRestored` is never written. If the user dismisses the transient-looking error and keeps using the old phone, it stops sending/receiving/draining/registering push — only a FLOW log records it. **Verifier note:** across a restart this becomes a hard erase-only lockout (see C5), so the worst case is account loss.
Scenario: first attempt dies at handoff; user keeps the old phone; from then on it receives no messages or pushes and contacts see them offline.
Fix: treat cutover failure as an abort — revert authority to `migrationFailedActiveRestored`/`active`; surface a persistent banner while network-gated.

### MEDIUM

**`upload_failed` outgoing attachments: durable file dropped from the bundle, no post-import retry, path unresolvable on iOS**
Type: data-loss · Severity: medium · Confidence: high
(`#3`/`#15` consolidated.) `_requiresLocalChatMediaFile` excludes `upload_failed`/`upload_cancelled` (`migration_file_manifest_builder.dart:378-380`), so the durable `pending_uploads/` file is never packaged and no path repair is recorded — yet the row migrates. Post-import nothing recovers it (`dbLoadUploadPendingAttachments` queries only `upload_pending`; `_shouldRecoverVisibleAttachment` excludes `upload_failed`), and `resolveStoredPath` lacks a `/pending_uploads/` legacy-absolute branch. **Verifier corrections:** drop the `upload_cancelled` half (cancel deletes the file and retry skips it); the pre-move image does *not* render on the old phone (shows "Media unavailable") — the real loss is *recoverability*: the old phone's retry can re-upload from the durable file, the new phone cannot. Also applies to group `upload_failed`.
Scenario: a photo hit max upload retries; after the move it is permanently unrecoverable and the move reported success.
Fix: package `upload_failed` files as `pendingUpload` (non-blocking if missing), repair paths, add the `/pending_uploads/` resolver branch; optionally remap to `upload_pending` so the user can retry.

**`migrationExportingNetworkPaused` never set → TOCTOU done-without-file, pending-work re-execution, and a pending-upload-deletion race**
Type: relay-dependency-historical / correctness / move-failure · Severity: medium · Confidence: high
(`#16`/`#29`/`#30` consolidated — same dead-state root cause as C4.) Because the old phone is never paused: (a) the chat listener auto-downloads incoming media between snapshot freeze (T1) and snapshot export (T2), producing `done` rows whose files are absent from the file payload → new phone relay-refetches; the relay-free audit hardcodes `relayMediaDownloadCount: 0` so it is invisible (`account_migration_bundle_transfer.dart:1249-1267`). (b) `PendingMessageRetrier` keeps firing, so a queued send the old phone completes mid-transfer is re-executed by the new phone after cutover (stale statuses, double inbox stores). (c) A retried upload finishing mid-export deletes `pending_uploads/<id>/` (`media_file_manager.dart:97`) while the manifest still lists it `upload_pending` → blocking `missingRequiredFile` → transient hard abort.
Scenario: a contact's photo lands during assembly; post-move the new phone silently refetches it from relay; or a finishing upload aborts the move with a misleading error.
Fix: set `migrationExportingNetworkPaused` before `_loadBundleRows` (single root fix for all three); or re-diff manifest-vs-snapshot before export.

**No post-media analog of the chat-media sanitize policy: one orphaned `post_media_attachments` row hard-fails the move**
Type: move-failure · Severity: medium · Confidence: high
Missing post-media files emit blocking critical `missingRequiredFile`/`fileSizeMismatch`/`missingPostMediaCrypto` (`migration_file_manifest_builder.dart:691-714`, `:787-811`) that the `media_attachments`-only downgrade can never reach. Orphans are reachable via the sweep crash window (`sweep_expired_posts_use_case.dart:13-16`) and — stronger — via `download_post_media_use_case.dart:54-71`, which silently skips the rename of a missing decrypted file yet sets `local_path` unconditionally; pinned posts are excluded from the self-healing sweep, making the block permanent. Post media is also invisible in the relay-free audit (`:677-723` counts only `media_attachments`).
Scenario: a kept/pinned post with a lost media file blocks every Move attempt with a generic error.
Fix: extend the sanitize policy + relay-free audit to post media; make `sweepExpiredPosts` delete rows transactionally with files; don't set `local_path` when the file is absent.

**`PendingPostMediaUploadRetrier` destructively wipes a pending post's media post-import (latent landmine)**
Type: data-loss · Severity: medium · Confidence: high
On the new phone the retrier checks the *raw* old-device path (`pending_post_media_upload_retrier.dart:309`, no `MediaFileManager` rebasing) and on miss wipes recovery rows + `replacePostMediaAttachments([])` + sets `deliveryStatus 'failed', media []` (`:326-333`). Post-table paths are never repaired (`_applyFilePathRepairs` filters `media_attachments`). **Verifier note:** masked today by the recovery-row hard-block (H1), so it goes live exactly when H1 is fixed by downgrade/skip; the "deletes transferred attachments" scenario is a crash-window edge — mainline harm is permanently failing an attachment-less pending post the old phone could have retried.
Scenario: after H1 is relaxed, opening the new phone permanently fails a pending media post and loses media the old phone would have re-uploaded.
Fix: resolve recovery paths via `MediaFileManager`, materialize pending post media to app-owned storage at send time, and degrade only un-uploaded items. Fix together with H1.

**Active DB irreversibly overwritten before secure-storage promotion; rollback APIs never wired**
Type: correctness · Severity: medium (↓ from high) · Confidence: high
`importVerifiedStagedDatabase` (delete-all-then-insert, `migration_database_active_importer.dart:69-72`) runs *before* `promote()` (`account_migration_bundle_transfer.dart:1098-1103`); a promote throw is swallowed (`:1126-1128`) with no compensation, and `failedImportCleanup`/`rollbackPromoted` have zero call sites. **Verifier downgrade:** the authority gate keeps the half-state behind the blocked screen (never live), `_retryTransfer` + the import precondition allow an idempotent in-session retry that repairs it, and the trigger (keychain write failure within seconds) is rare — so high→medium. The catastrophic variant requires the rare trigger plus restart-before-retry plus erasing the old phone first (overlaps C5).
Scenario: a keychain write rejects mid-promotion; the half-state is gated, repairable by retry, but a restart converts it into the C5 dead-end.
Fix: promote secure storage before mutating the active DB (staged values are pre-validated), or wrap with compensations and surface a retryable state.

**Export hard-aborts the whole move on any single missing critical secure value, including derivable best-effort shared mirrors**
Type: move-failure · Severity: medium · Confidence: high
`_collectSecureEntries` throws on any absent critical key (`account_migration_bundle_transfer.dart:257-265`), and *all* discovered keys are critical (`migration_secure_storage_registry.dart:156-183`) — including iOS `sharedGroupMirror` keys that are redundant duplicates of primary `group_key_material` and whose writes are best-effort/swallowed (`group_repository_impl.dart:472-489`). This phase runs *before* the per-row `missingSecureStoreKey` downgrade machinery, preempting it. iOS-source-specific (`sharedStore` is iOS-only).
Scenario: a group whose shared push-mirror write once failed (logged+swallowed) makes the iOS user's move fail outright with an opaque error.
Fix: demote shared mirrors to optional/derived (re-derivable from primary at import); for genuinely dangling primary refs, emit a per-row issue with explicit accounting instead of a whole-move abort.

**Group manifest and pending-work manifest builders/validators are dead code — no group/pending integrity gate runs in the real flow**
Type: silent-degradation · Severity: medium · Confidence: high
(`#18`/`#28` consolidated.) `MigrationGroupManifestBuilder/Validator` and `MigrationPendingWorkManifestBuilder/Validator` implement retained-key completeness, key-material presence, mirror consistency, moved-device policy, inbox-cursor presence, pending-key-repair coverage, terminal-status/sensitive-material scans, and resume policies — but are referenced **only by their own validators and tests**; the production bundle builds only the file manifest (`account_migration_bundle_transfer.dart:408-421`) and the receiver never re-validates. The only live group protection (`_collectSecureEntries` critical-throw) covers existence of referenced values but no structural checks. **Verifier note:** the live file-manifest layer already covers most file-presence cases, so the residual lost protections are defense-in-depth (sensitive-material scan, structural integrity, unenforced pause/fail resume policies) — no demonstrated data loss flows from the dead code itself.
Scenario: an account with degraded group state (undecryptable message lacking a repair row, missing retained generation) exports+imports with success reported and no issue surfaced.
Fix: wire the group validator into the source and include the group/pending-work manifests in the payload for receiver re-validation.

**Receiver-side exception blackout: `complete()` and `acceptOldBlockProof()` swallow all errors with no telemetry**
Type: known-bug-interaction · Severity: medium · Confidence: high
`complete()` ends `on Object { return false; }` (`account_migration_bundle_transfer.dart:1066-1068`) and `acceptOldBlockProof()` `on Object { return null; }` (`:1126-1128`); the entire `acceptOldBlockProof` phase chain emits zero flow events, so promotion `StateError`s and import failures surface to the sender only as generic `bundle_verification_failed`/`cutover_rejected`. **Verifier corrections:** `_writeImportedFiles` *does* emit file-failure events, so file-import inside `complete()` is diagnosable; the blackout fully applies to payload-decode, secure-staging, staged-DB open, and all of `acceptOldBlockProof`. Fail-closed safety holds, so this is a diagnosability gap.
Scenario: a move fails at cutover; new-phone FLOW logs identify nothing, making field triage impossible without a debugger.
Fix: emit `…_IMPORT_FAILED`/`…_CUTOVER_FAILED` with error type + phase in both catch blocks before returning, and propagate a machine-readable reason to the sender.

**Lease cleanup (server-side rendezvous + push deregister, G4) retry path never invoked**
Type: silent-degradation · Severity: medium (↓ from high) · Confidence: high
The deregisters are real (`migration_cutover_bridge_cleanup.dart:15-33`) but each failure only sets `leaseCleanupPending`; `recover()`/`retryLeaseCleanup` have zero callers and no startup hook resumes it. **Verifier downgrade:** harm is bounded and self-healing — rendezvous TTL ≤ 2h, push tokens are single-per-peerId, and the migrated identity means the new phone re-registers under the *same* peerId and overwrites both within minutes; misdirected pushes lose nothing (store-and-forward). So G4 is substantially closed; the residual is the unwired resume path.
Scenario: a relay-unreachable cutover leaves a stale rendezvous/push registration that nothing retries until TTL/overwrite.
Fix: wire `recover()` into startup to complete a deferred deregister when connectivity returns.

**Cutover/block is device-local only with no server-side revocation; the migrated-out old phone retains DB + key + secrets**
Type: security (spec-gap-still-open, G1/G3) · Severity: medium · Confidence: high
Authority/cutover state live only in this device's secure store (`migration_cutover_repository_impl.dart:8`); nothing on the relay enforces single-writer per account peerId, and cutover does not erase the old phone's DB/secrets (erase is user-tap-only). A pre-move iOS backup restore (Keychain backed up by default) re-seeds DB+key while omitting the authority record → the old phone boots normal, re-registers, and drains/ACKs the account inbox — a destructive second writer.
Scenario: user restores the old phone from a pre-move iCloud snapshot; two devices then fight over the account and ACK messages away from the new phone.
Fix: add a relay-side single-writer/revocation signal bound to a migration epoch, and/or proactively erase old-phone DB-key residue at cutover.

**G5 still open: disk-space preflight and active-account import precondition are dead code**
Type: spec-gap-still-open · Severity: medium · Confidence: high
(`#37`/`#60` consolidated.) `MigrationStoragePreflight.evaluate` and `evaluateAccountMigrationImportPrecondition` have zero production callers; the receiver writes hundreds of MB with no free-space check, and the active importer unconditionally `txn.delete(tableName)` for every table (`migration_database_active_importer.dart:71`) with no `activeAccountExists` guard. **Verifier note:** the clobber path is UI-gated (the receive journey is unreachable when an identity exists), so live impact is a late, generic, fail-closed move failure on low-storage devices.
Scenario: a storage-tight new phone writes segments until the FS fills, then fails late with "could not verify the bundle" and no disk hint; retries make it worse.
Fix: invoke the preflight at `acceptManifest` (reject with a storage-specific message including stale staging sizes); gate import on the precondition.

**G2 partially open: SQLCipher cross-platform cipher profile not fully pinned and not proven by the capability test**
Type: spec-gap-still-open · Severity: medium · Confidence: high
`kdf_iter` and `cipher_page_size` are now captured and pinned (`migration_database_snapshot_exporter.dart:226-240`; `migration_database_import_staging.dart:188-197`) — progress since the spec review — but HMAC algorithm, KDF algorithm, and plaintext-header-size are not, and the only capability test is same-device round-trip, not Android→iOS. **Verifier note:** with the current pinned plugin both platforms ship SQLCipher 4 with identical defaults, so matched app versions are unaffected today; the trigger is version skew or a future upgrade. Fails closed (no corruption) but the move can never succeed and surfaces a generic "could not verify" message.
Scenario: a future plugin/SQLCipher default change makes Pixel→iPhone snapshots un-openable; every move fails with no cipher hint.
Fix: pin the full cipher profile in the manifest and apply it in the opener; add a real Android-export→iOS-open capability gate.

**Clock skew on either phone makes pairing permanently fail with misleading errors**
Type: move-failure · Severity: medium · Confidence: high
All TTL enforcement is on the old phone's clock: `createdAt` >2 min future → `futureTimestamp` (generic "not a valid QR"), `expiresAt` in the past → `expired` ("show a new code"); the receiver never re-checks expiry (`migration_qr_payload_use_case.dart:94`, `:146-151`). The success window is roughly `newClock − oldClock ∈ (−5 min, +2 min]`; outside it every regenerated QR fails and no message mentions date/time. A factory-fresh offline new phone (the prime relay-free target) is a plausible trigger.
Scenario: a new phone whose clock is 40 min behind makes every QR "expired"; the user regenerates endlessly.
Fix: detect large `|now − createdAt|` and show "Check the date & time on both phones"; consider anchoring freshness to a scan-time delta.

**App-resume/relay-recovery `restartAdvertising` nukes in-flight migration peer resolution**
Type: correctness · Severity: medium · Confidence: high
`performImmediateHealthCheck` → `restartAdvertising` (`p2p_service_impl.dart:3298-3301`) calls `stopAdvertising`, which completes every pending `resolvePeer` with null and clears `_peers` (`bonsoir_discovery_service.dart:177-184`) on the *shared* discovery instance. `runOldPhoneTransfer` does a single-shot `resolvePeer` (12s, no retry, `account_migration_local_transfer_runtime.dart:272-285`), so a health check landing in that window instantly yields `localPeerUnavailable`. Triggered by app resume *and* by relay push recovery (so it can fire with the app foregrounded).
Scenario: user glances at the new phone and returns; resume restarts advertising right as "connecting" resolves → "new phone not found" on a healthy LAN; manual retry usually works.
Fix: retry `resolvePeer` once on null-before-timeout, or suspend the health-check `restartAdvertising` while a migration run is active.

**Receiver WS server binds IPv4-only while mDNS can hand the old phone an IPv6/link-local address**
Type: move-failure · Severity: medium · Confidence: high
`HttpServer.bind(InternetAddress.anyIPv4, 0)` (`local_ws_server.dart:96`); `LocalPeer` carries one `service.host` (`bonsoir_discovery_service.dart:107-115`) which, via bonsoir_android's single `hostAddress` literal, can be an IPv6/scoped address on IPv6-preferring WLANs; `_postJson` connects to that literal with no family fallback → uncaught `SocketException` → "stopped unexpectedly before final handoff." Direction-dependent: Android-sender is the weak path (iPhone-sender returns `.local` and resolves all families).
Scenario: old Pixel on an IPv6 mesh discovers the new iPhone, gets an IPv6 host, and every transfer fails immediately at connecting.
Fix: bind dual-stack (`anyIPv6`, `v6Only:false`) or store all resolved addresses and try them in order.

**Throughput profile makes large transfers multi-hour even if memory allowed**
Type: move-failure · Severity: medium · Confidence: medium
~41k sequential 256 KiB segments (`account_migration_bundle_transfer.dart:71`), a fresh `HttpClient` per POST with no keep-alive (`account_migration_local_transfer_runtime.dart:813`/`:838`), all-upfront encryption, single-isolate, 10s per-POST death, no resume, and only coarse step-level progress (nothing on the new phone). **Verifier note:** capped by the memory finding to ~200-500 MB accounts, where this 5-15 min opaque window invites the user to kill the app (→ full restart).
Scenario: a 400 MB account shows a frozen "Transferring database…" for 10+ minutes; the user swipes it away and the next attempt starts from zero.
Fix: reuse one keep-alive `HttpClient`, pipeline encrypt-and-send, emit per-segment progress to both UIs, and use 1-4 MiB segments.

### LOW

**Any DB-referenced avatar file missing on disk hard-blocks the export (recoverable from the DB blob)**
Type: move-failure · Severity: low (↓ from medium) · Confidence: high
Identity/contact/group avatar items emit blocking critical `missingRequiredFile` that the `nonCriticalCache`-only downgrade can't reach, even though the app renders identity avatars from `identity.avatarBlob` and contact avatars self-heal (`migration_file_manifest_builder.dart:690-702`; `identity_avatar_resolver.dart:73-90`). **Verifier correction:** the flagship mnemonic-restore scenario is unreachable (restore sets `avatar_version` null); the only realistic trigger is the non-atomic delete-then-rename window in `AvatarNormalizationHelper.commitAvatar` or external file loss.
Fix: downgrade avatar issues to non-blocking or regenerate from `identity.avatar_blob` at export.

**`videoThumbnail` packaging is dead code in production export**
Type: silent-degradation · Severity: low · Confidence: high
`scanDocumentsForCacheAndTransients: false` (`account_migration_bundle_transfer.dart:419`) means no `.thumb.jpg` is ever shipped, which also makes the `nonCriticalCache` downgrade unreachable; thumbnails regenerate locally from the migrated video (`video_thumbnail_cache.dart:29-88`). Impact is first-render CPU/battery only; the residual harm is the misleading telemetry/review impression that thumbnails migrate.
Fix: delete the dead `videoThumbnail`/scan path or enable scanning for `.thumb.jpg` companions.

**Extension-map divergence renames local-WiFi voice notes (`.bin` → `.m4a`) across the move**
Type: correctness · Severity: low · Confidence: high
`LocalMediaServer._extensionFromMime` maps `audio/mp4` → `.bin` while `MediaFilePathConvention` maps it → `.m4a` (`local_media_server.dart:506-520`; `media_file_path_convention.dart:33-49`); the canonicalizer rewrites the extension at export. No data loss (post-move name is strictly better); the sharper risk is pre-move `.bin` playback, a pre-existing LAN-receive issue independent of the move.
Fix: unify both maps on `MediaFilePathConvention` with an `audio/mp4` entry and a defined fallback.

**Incoming post media stuck `pending`/`downloading`/`failed` silently excluded; no post-media download retrier exists**
Type: silent-degradation · Severity: low · Confidence: high
`_addPathBackedItem` silently returns (no item, no issue) for null `local_path` (`migration_file_manifest_builder.dart:659-662`); `downloadPostMedia` is wired only into receive-time listeners, so there is no post-import or display-path recovery. **Verifier note:** the `failed` portion is a pre-existing app gap (no retrier even on the old phone); the move-specific loss is the in-flight `pending`/`downloading` window. UI shows a perpetual placeholder with no retry button.
Fix: record a non-blocking manifest issue for non-`done` post media, or add a one-shot post-import reconciliation while the relay blob may still exist.

**Strict QR-version equality maps cross-version pairing to "not a valid Move Account QR code"**
Type: correctness · Severity: low (↓ from medium) · Confidence: high
`version != currentAccountMigrationPairingQrVersion` (`migration_qr_payload_use_case.dart:116`) collapses into the generic invalid-QR message, never reaching the manifest layer's proper "Update both phones" copy. **Verifier note:** unreachable today (only v1 exists) but a fix-before-first-ship copy gap, since the old phone's message is frozen at release; the same collapse mis-reports the today-reachable `futureTimestamp` case.
Fix: give `unsupportedVersion`/`futureTimestamp` dedicated "update both phones / check date & time" copy; consider a min/max version range.

**Transcript/pairing-stage `_postJson` exceptions are uncaught → misleading "before final handoff" (KNOWN-2 pattern at an earlier step)**
Type: known-bug-interaction · Severity: low (↓ from medium) · Confidence: high
All six `_postJson` call sites are unprotected; a connect-refused at the transcript stage propagates to the generic journey catch and is even tagged `bundleSourceFailed` though no bundle source ran. **Verifier note:** pure mislabel at a retryable pre-mutation stage; KNOWN-2's documented fix (wrap `_postJson` itself) resolves it.
Fix: wrap each `_postJson` stage in try/catch mapping to stage-specific reason codes (`pairingConnectFailed` vs transfer vs handoff).

**Migration pairing-session store grows unbounded and retains ML-KEM ephemeral SECRET keys; receiver TTL is never enforced**
Type: security · Severity: low · Confidence: high
(`#47`/`#55` consolidated.) `savePendingNewPhoneSession` only ever adds (`migration_pairing_session_repository_impl.dart:18-24`); each QR mint persists `newPhoneEphemeralSecretKey`, and no prune/TTL sweep exists, so every QR's decryption-capable secret persists. Separately, the receiver never re-checks `expiresAt` (`account_migration_bundle_transfer.dart:944-950`), so the QR TTL is advisory after start. **Verifier note:** the secrets accumulate on the *new* phone, which never runs the `eraseAccount` path that could remove them; exploitation needs secure-storage extraction + a recorded WiFi capture.
Fix: delete the pending session+secret on consume/expiry/terminal state; sweep expired sessions at receiver start; enforce `expiresAt` in `_handleTranscript`/`acceptTranscript`.

---

## Known-Issue Interactions

The audit confirmed several findings classified `known-bug-interaction` and explicitly distinguished them from the documented KNOWN issues.

- **KNOWN-1 fires as a hard *move-blocker*, not a relay-leak, on legacy-damaged devices.** The working tree has *fixed* KNOWN-1's deletion (`group_feed_media_verification.dart` no longer deletes; `deleteAttempted:false`, `PLAINTEXT_HASH_VALIDATION_SKIPPED`) and tightened the downgrade to `nonCriticalCache` (video thumbnails only). The net effect is an *inversion* of the MIG-012 silent "downgrade-to-success + relay leak": any device whose rows are still `done` + missing-file (because a pre-fix build already deleted the plaintext and the `.enc` companion is gone) now hard-aborts the entire move (`account_migration_bundle_transfer.dart:501-506`, `:302-320`). This affects the MIG-012 TestFlight cohort (e.g. the test Pixel) but NOT clean installs. The only (accidental, undiscoverable) escape is opening the affected conversation. See H2 above and `MIG-012-group-media-relay-leak-triage.md`.
- **KNOWN-2's `_postJson` blackout has three distinct new manifestations** beyond the documented segment-stall: the **size-scaling import-handler timeout** (Critical, C3 — the likely 2026-06-10 root cause); the **transcript/pairing-stage uncaught exception** (Low, mislabel at an earlier step); and the **receiver-side exception blackout** in `complete()`/`acceptOldBlockProof()` (Medium — same zero-telemetry pattern on the import/cutover side). A segment-loop-only KNOWN-2 fix would miss all three. See `move-transfer-timeout-before-handoff-triage.md`.
- **KNOWN-1's snapshot-baking amplifier was already documented and is no longer reachable** — the `relay-dependency-historical` finding alleging the source downgrade still mutates the snapshot into relay-refetch state was refuted (see below); it is a re-report of MIG-012 Root Cause 4, now gated to thumbnails.

---

## Spec-Review Gaps Status (G1-G7)

- **G1 (erase secret-residue on old phone) — STILL OPEN (High).** `eraseAccount` deletes only fixed registry keys and uses the wrong (primary) store for shared-scope keys; all discovered media/group keys + the iOS shared ML-KEM mirror survive (`migration_secure_storage_registry.dart:185-189`; `startup_router.dart:672-684`). *Partially mitigated:* identity private key, mnemonic, DB key, and primary ML-KEM ARE erased. Also see the device-local cutover/no-revocation gap (Medium).
- **G2 (SQLCipher cipher-param portability) — PARTIALLY IMPLEMENTED.** `kdf_iter` + `cipher_page_size` are now captured and re-applied (progress since the review); HMAC algorithm, KDF algorithm, plaintext-header-size, and a real Android→iOS capability test remain open (`migration_database_import_staging.dart:188-197`). Per verifiedOk: "substantially implemented," fails closed.
- **G3 (device-local cutover flag) — IMPLEMENTED (flag itself).** The cutover/authority flag is stored, survives the import swap (`db_encryption_key` deliberately not promoted), and gates startup. The residual concern is that it is *only* device-local with no server-side revocation (folded into the G1/G3 Medium security finding), not the flag's existence.
- **G4 (server-side relay/push deregister) — SUBSTANTIALLY IMPLEMENTED.** Rendezvous + inbox push-token deregister are issued at cutover (`migration_cutover_bridge_cleanup.dart:15-33`). The only residue is the unwired retry/resume (`recover()`/`retryLeaseCleanup` dead code, Medium) — and it self-heals via same-peerId re-registration.
- **G5 (disk-space probe) — STILL OPEN (Medium).** `MigrationStoragePreflight.evaluate` is fully implemented but has zero production callers; no platform `availableBytes` provider exists. The active-account import precondition is likewise unwired.
- **G6 (session-auth binding) — STILL OPEN (High).** No MAC/signature anywhere in the transcript→manifest→segment→old-block-proof→cutover chain; authentication is string equality on public QR data.
- **G7 (iOS suspension mid-transfer) — STILL OPEN on the receiver (High).** The new phone holds no wake lock during segment receive (and there is no background-task/foreground-service), the very phase where it bites hardest; the old phone's wake lock is only a partial mitigation.

---

## Refuted / Not-A-Bug

- **Android→iOS never populates the iOS shared ML-KEM mirror (push broken):** refuted — `_mirrorMlKemSecretForPush` runs on *every* `loadIdentity()` (`identity_repository_impl.dart:111`), and the migration receiver-activation explicitly invalidates the cache, so the shared mirror is written immediately after cutover.
- **Files for `pending`/`downloading`/`failed` rows relay-refetched where the old phone could heal offline:** refuted — the cited crash windows leave `localPath` NULL (atomic `updateLocalPath` writes path+`done` together), so the old phone is equally relay-dependent; no old-vs-new asymmetry exists, and the exclusion is explicit audited design.
- **`startLiveServices` one-shot strands migrated pending work after an in-process gated boot:** historical audit verdict was refuted; Plan 285 later proved the latent one-shot cache could strand post-cutover startup and replaced it with a coalesced, retryable, per-side-effect checkpoint ledger. This item is superseded at host tier.
- **Source-side missing-media downgrade bakes integrity-failed rows into the snapshot → relay refetch:** refuted — re-report of KNOWN-1/MIG-012 Root Cause 4; the downgrade is now `nonCriticalCache`-gated (video thumbnails only, never real chat media), and `integrity_failed` is excluded from auto-recovery.
- **Each export attempt permanently mutates the source DB and ratchets media loss across retries:** refuted — the downgrade is critical-gated (thumbnails), KNOWN-1's deletion is fixed, and path-repair writes are benign relative-path normalization; no media-loss ratchet.
- **New-phone retry races attempt-1 receiver teardown against attempt-2 advertising (dead QR):** refuted — `stop()`'s dispatch is synchronous-until-first-await and always targets attempt-1's broadcast; worst case is a *visible* failure or a benign broadcast leak (phone stays resolvable), never a silently dead fresh QR.

---

## Verified OK

Areas checked and found sound (coverage visibility; from verifiedOk notes):

File/media packaging
- Relay-uploaded outgoing chat media (direct + group, incl. voice) durable-copied to relative `media/<peer>/<blobId>` at upload (`upload_media_use_case.dart:328-348`); received relay media stored relative `done`.
- LAN-received 1:1/group media is materialized to canonical `media/<peer>/` and the source DB repaired *before* snapshot export — no relay refetch.
- Group `.enc` companion exported as fallback when plaintext is missing; the new phone restores it relay-free via `restoreEncryptedCompanionIfAvailable`.
- Sent 1:1 media (incl. voice) durable-copied with relative paths; voice-note extensions deterministic on both platforms; video thumbnails regenerate locally.
- Contact avatars / group avatars stored relative, reference set only after successful commit; `.download.jpg` temps excluded as transient.
- Post media (sent + received), repost media, and pass-avatar snapshots travel via relative paths + inline crypto / DB BLOBs; post expiry deletes media + rows atomically; drafts are in-memory only.
- `upload_pending` chat-media files packaged as `pendingUpload` with path repair and post-import resume; import writes every file relative to documents root with triple SHA-256 verification and rejects blocking manifests.
- KNOWN-1 deletion + plaintext-hash validation appear fixed in the working tree (no new manifestation on the import side).

Secure storage / crypto
- `db_encryption_key` lifecycle correct (re-encrypted under old key for transport, new phone keeps its own key, old key not promoted); G2 cipher params partially pinned and fail-closed.
- Media-attachment secure keys fully collected via LEFT JOINs (chat/group/orphaned); post crypto travels in the DB; group-key-draft refs collected; settings prefs migrated, push token clear-and-regenerate; promotion ordering validated before cutover; `secrets_migrated` derived not copied.
- Introductions hold no secure-store material; group key-draft cleanup ordering avoids dangling refs; Android→iOS shared group-key mirrors self-heal at startup.

Post-import behavior
- Import does no status remap (rows copied verbatim, atomic, checksum-verified); packaged rows carry relative paths; file placement matches `resolveStoredPath`; lazy per-chat recovery prefers local files before any relay call and emits `MEDIA_DOWNLOAD_RELAY_DEPENDENCY_RISK` telemetry; KNOWN-1 hash-verify does not fire on imported 1:1 media.
- Group historical text never becomes undecryptable (plaintext stored); offline-inbox drain resumes from the migrated cursor without re-pull/dup; moved device accepted without rotation; in-flight invites/welcome packages survive; group outbox/pending work resumes from migrated rows; posts never re-fetch historical media; retriers migration-gated on the source.

Transport / pairing / lifecycle
- `migrationPeerId` is QR-derived (not guessable), self-match filtered, route-isolated on the shared WS server, port-0 bound (no fixed-port conflict), no scan-before-listen race, confirmation code shown on both phones, QR one-shot replay-protected, different-subnet failure bounded to a 12s timeout with accurate guidance, iOS Bonjour entitlements present.
- Receiver streams segments to disk (no RAM accumulation during transfer); old phone holds a wake lock through every non-terminal stage; segment AAD binding sound; pending pairing session survives a receiver restart; path traversal guarded; no artificial framing limit.

Retry / import integrity
- Secure-storage staging is sessionId-namespaced (no cross-attempt mixing); staged DB/segments are per-session and recreated on re-send; overwrite semantics clean; `checkpointConflict` unreachable; export authorization one-shot; server-side deregistration ordering correct (never early on failure); same-session retry clean w.r.t. authority; import cleanup never deletes documents-dir files referenced by imported rows; schema-version/shape drift fails closed; pairing-session store fails closed on parse error.

---

## Coverage Map & Residual Risk

**Dimensions swept:** file-manifest completeness (chat, group, post, avatar, voice, pending-upload, thumbnails); secure-storage completeness (fixed + discovered keys, mirrors, cipher params, promotion); 1:1 post-import relay behavior; group relay dependencies (keys, history, inbox cursor, device binding, invites); posts relay dependencies; cutover/relay lifecycle (drain, deregister, revocation, push token); pending-work resume (all outboxes/retriers); import-pipeline integrity (atomicity, traversal, schema drift, channel auth, preflight, cipher portability); pairing/transport establishment (QR, mDNS, permissions, IP family, clock, TTL); transfer scalability/resume (memory, throughput, checkpoints, wake lock, disk); retry-after-failure stale state (authority, residue, races). G1-G7 re-verified against the working tree.

**Not swept (honest gaps):**
- **No on-device runtime verification** — entirely static analysis. The memory-ceiling multipliers (4-6× source, 2.7-3.7× receiver), the "~100-300 MB exceeds 10s" timeout threshold, and the multi-hour throughput estimate are *unbenchmarked* and should be measured on the actual Pixel 6 → iPhone 13 pair.
- **Real Android→iOS SQLCipher byte-compatibility not tested** on hardware (only argued from defaults).
- **Go relay server mostly out of scope** — only `inbox.go` ACK destructiveness, `push_token_store.go`, `media.go` TTL, and `rendezvous.go` TTL were touched; no end-to-end relay-side audit.
- **Concurrency/timing races characterized by code reading, not stress-tested** (the resolve-race, export-delete race, TOCTOU window are reasoned, not reproduced).
- **Go bridge segment crypto (`migration_segment_crypto`) correctness not independently audited** beyond AAD binding.
- **iOS background-suspension exact timing, battery/thermal behavior of long transfers, and error-message localization/accessibility** not assessed.

**Top residual risks:**
1. Media-heavy real accounts — memory ceiling + 10s timeout + no-resume + disk amplification *compound*; a multi-GB account almost certainly cannot complete today, and a small test account may mask all four.
2. The MIG-012 cohort (test Pixel) — legacy KNOWN-1-damaged `done` rows hard-block the move with a retry-forever message.
3. Cutover interruption — Plan 285 host-hardens in-session proof loss and
   blocked-route recovery, but durable process-restart recovery, user abort,
   and erase-residue safety remain open.
4. Live-window data loss — inbox drain during transfer silently destroys messages while reporting success, undermining trust in a "successful" test.
5. Plaintext secret residue on the new phone (iOS backup vector) and old-phone key residue (G1).

---

## Recommended Fix Order

Context: KNOWN-1's deletion is already fixed in the working tree (good — but the legacy-row hard-block it leaves behind still needs handling). KNOWN-2 is triaged but its fix must cover the size-scaling import-handler timeout (C3) and the uncaught transcript-stage/receiver-side exceptions, not just the segment loop. Dependencies are noted so related work is batched.

1. **Diagnosability first (cheap, unblocks everything else):** wire telemetry into `complete()`/`acceptOldBlockProof()` catch blocks and all six `_postJson` stages with phase + reason codes (Medium #20, Low #45). Without this, the next test failure is again a black box. No dependencies.

2. **Make the move *startable* — fix the export hard-blockers (one manifest-builder workstream):** durable-copy LAN-sent media and post-media drafts at send time (C6, H1); add a pre-export reconciliation pass that heals `done`+missing rows to `pending`/`failed` and emits non-blocking degraded-to-relay accounting (H2, including the legacy KNOWN-1 cohort); downgrade avatar issues and add a post-media sanitize analog (L1, M2); include `upload_failed` files in packaging (M-`#3/#15`). These all touch `migration_file_manifest_builder.dart` + the downgrade policy and share a fix shape; do them together. Without them the bundle never assembles for realistic devices.

3. **Finish the remaining handoff recovery work (partially superseded by Plan
   285):** Plan 285 closed bounded in-session proof retry/replay,
   authority-aware blocked UI, and retained-route reset ownership. Remaining
   work must make commit state durably observable across process restart,
   implement an owner-approved safe abort/recovery path, and close erase
   residue. Do not describe `recover()` as currently wired or rehydrate the
   receiver session without a separate authorized design.

4. **Quiesce the old phone — single root fix, high leverage:** set `migrationExportingNetworkPaused` before `_loadBundleRows` and gate drain/ACK/pubsub/retriers on it. This resolves the critical silent message loss (C4 #25) *and* the TOCTOU/double-send/pending-delete cluster (M4 = #16/#29/#30) in one change.

5. **Make the transport survive a real account (the big workstream, partly batchable with KNOWN-2):** (a) hold a wake lock on the receiver from `startNewPhoneReceiver` + add background-task/foreground-service (G7 #52) — cheap, directly attacks the suspected timeout; (b) make `complete`/`old-block-proof` async (respond 202, poll/push) or scale the timeout and ack-before-heavy-work (C3 #50, KNOWN-2); (c) refactor to streaming per-file/per-chunk on both source and receiver to kill the memory ceiling (C1 #48, C2 #49). The streaming refactor *enables* resumability (H9 #51) and lowers disk amplification (H5 #53), and the async-handler change is a prerequisite for the timeout fix to mean anything — design (b) and (c) together. For the *next* test specifically, (a) + (b) + a small-account run can validate the pipeline before the larger (c) effort lands; production needs (c).

6. **Security/cleanup hygiene (one cleanup workstream):** wire the dead `MigrationFileImportCleanup`/`MigrationDatabaseImportCleanup` into success/failure/abandon + a startup sweep, extend `eraseAccount` to staging-prefixed keys, exclude the staging dir from iOS backup, and fix G1's discovered-secret enumeration + wrong-store wiring (H3 #9/#34, H4 #59, H5 #53, M10 #27, H6/G1 #8). Mostly wiring of existing code; do after the move reliably completes so cleanup paths are actually exercised.

7. **Graceful failure + portability:** wire `MigrationStoragePreflight` at `acceptManifest` and gate import on the precondition (M11/G5 #37/#60); pin the full SQLCipher cipher profile and add an Android→iOS capability gate (M12/G2 #38).

8. **Pairing/transport robustness (medium/low hardening):** dual-stack WS bind (M15 #46), Local-Network-permission self-probe + hint (H10 #41), resolve-race retry / pause health-check during transfer (M14 #44), clock-skew and QR-version messaging (M13 #43, L5 #42), session/TTL pruning (L #47/#55), reverse-direction iPhone→Android shared-key remap (C7 #7/#17), and throughput/keep-alive/progress UX (M16 #54).

9. **Defense-in-depth last:** wire the dead group/pending-work validators into the source + payload for receiver re-validation (M7 #18/#28); add the G6 cryptographic channel binding (H7 #36) — important for the security posture but not a precondition to a successful honest-actor test on a trusted LAN.

Dependency summary: (2) gates the move starting; (3) and (4) gate *trusting* a test result; (5) gates the move *completing* for real accounts and subsumes resumability/disk; (6) reuses (5)'s plumbing; (1) should land first because it makes (3)/(4)/(5) debuggable.

---

*Generated by the `move-relay-free-gap-hunt` workflow (74 agents: 11 finder dimensions, per-finding adversarial verification, completeness critic, synthesis). Workflow script: `.move-relay-free-gap-hunt-workflow.js` (re-runnable). Report only — no code changes made.*
