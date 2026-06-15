# MIG-012 — Group Media Leaked To Relay After Move Account: Root-Cause Triage

**Date:** 2026-06-09
**Scenario:** Move Account from Pixel (Android, old phone) → iPhone 13 (new phone)
**Symptom (as reported):** After the move completed, the new phone retrieved group media from the relay; those images were not included in the move bundle.
**Logs analysed:** `./pixel.log` (old phone / sender), `./iphone-13.log` (new phone / receiver) — both from the Jun 9 2026 run.
**Method:** 13-agent triage workflow — 6 dimensions traced against working-tree source, each adversarially verified, then synthesized. All load-bearing code and log lines were re-checked verbatim.

> **Verdict in one line:** Two group images were *genuinely deleted from disk on the Pixel* (by a comparison-domain bug in the group-feed display verification) before the bundle was built, and a second defect (`sanitize_missing_media_without_relay`) then silently downgraded the resulting blocking errors and reported the transfer as a success — leaving the relay as the only place the images still existed.

---

## Executive Summary

When the user moved their account from a Pixel (Android) to an iPhone 13, two group images were silently dropped from the move bundle and the new phone re-fetched them from the relay store. The single most important root cause is **H2 (genuine non-retention)**: the decrypted plaintext group `.jpg` files were *genuinely gone from disk on the Pixel by bundle-assembly time* — they were committed durable at 14:36:27 but vanished within seconds via an un-instrumented deletion, so the migration manifest builder correctly reported `source_file_missing`. The competing hypothesis H1 (manifest false-negative / wrong path lookup) is conclusively **falsified**: the builder probed the exact correct plaintext path and the bytes were truly absent. An amplifying second defect then converts this loss into a *silent success*: the bundle source's `sanitize_missing_media_without_relay` policy downgrades the blocking critical-media issues to non-blocking, nulls the rows, and reports the transfer succeeded with 5/7 media — directly violating the MIG-012 Closure Bar. User-facing impact: historical group media is silently excluded from the move and survives only because the relay still happens to hold it, defeating the entire premise of a relay-independent move.

## What The Logs Prove

All references are to the current-run `./pixel.log` (old phone, sender) and `./iphone-13.log` (new phone, receiver).

**Pixel — display-time relay download, decrypt, durable commit (~14:36:27–28):**
- `pixel.log:3319` — `MEDIA_DOWNLOAD_LOCAL_MISS` for blob 36a7ef51 (`no_local_path`, `hasLocalPath:false`); the blob is not on disk, so the app fetches it just to display it.
- `pixel.log:3329` — `P2P_MEDIA_DOWNLOAD_RESPONSE` ok, `routedViaRelayStore:true`, `sourceRole relay_media_store`.
- `pixel.log:3337-3338` — `APP_OWNED_MEDIA_DELETE replace_existing_plaintext_before_decrypt_rename` on the `.jpg` → `SKIPPED_MISSING` (`existsBefore:false`); no plaintext existed before the rename — rules this delete out as the loss cause and confirms the plaintext is created by the post-decrypt rename.
- `pixel.log:3339-3340` — `APP_OWNED_MEDIA_DELETE group_download_encrypted_companion_cleanup_after_decrypt` on the `.enc` → `SUCCESS existsAfter:false`; the encrypted companion is deliberately deleted post-decrypt.
- `pixel.log:3343` — `MEDIA_DOWNLOAD_DURABLE_LOCAL_PATH_COMMITTED` for 36a7ef51 at `media/f91d3f06.../<blob>.jpg`, `fileExists:true fileBytes:1012567`. The plaintext `.jpg` is the durable at-rest artifact and is genuinely on disk.
- `pixel.log:3355` / `pixel.log:3384` — delayed probes for 36a7ef51 at +250ms and +1000ms, both `fileExists:true` (last live observation of this blob).
- `pixel.log:3387` — `DURABLE_LOCAL_PATH_COMMITTED` for 78869014, `fileExists:true fileBytes:1382568` (14:36:28.582).
- `pixel.log:3402` — delayed probe 78869014 @250ms `fileExists:true`.
- `pixel.log:3405-3406` — **the smoking gun**: delayed probe 78869014 @1000ms `fileExists:false fileBytes:0`, then `MEDIA_GROUP_DURABLE_LOCAL_PATH_DELAYED_PROBE_MISSING`. The durable plaintext `.jpg` vanished ~1.04s after commit. The only events in the gap (`pixel.log:3390-3404`) are DB reads and `GROUP_MESSAGES_DB_MARK_READ` — **no `APP_OWNED_MEDIA_DELETE` telemetry of any kind.**

**Pixel — bundle assembly (~14:38:13–14, sessionId 412f475e):**
- `pixel.log:7718` — `BUNDLE_SOURCE_ROWS_LOADED` `chatMediaCount:7 contactCount:2 groupCount:1 groupMaterialRowCount:1`.
- `pixel.log:7721` — `MISSING_MEDIA_DOWNGRADE_START` `downgradeCount:2 targetDownloadStatus:integrity_failed issueCodes:[missingRequiredFile]`; the 2 group blobs, `selectedReason source_file_missing`, `candidateCount:3`, `blocking:true` initially. At this moment both DB rows are still `downloadStatus:done` with `storedPath` intact — proving the row was intact until the migration downgrade flipped it.
- `pixel.log:7722` — `MISSING_MEDIA_DOWNGRADE_SUCCESS` `updatedRowCount:2`; rows now `integrity_failed`, issues now `blocking:false`.
- `pixel.log:7726-7728` / `7731-7733` — per-candidate `MISSING_MEDIA_CANDIDATE_DIAGNOSTIC` events (NOT truncated; emitted individually) enumerate all 3 candidates each blob was probed against: cand0 `media/<groupId>/<blob>.jpg` (`normalize_stored_path`, `allowTransient:false`, absolute path `/data/user/0/com.mknoon.app/app_flutter/media/f91d3f06.../<blob>.jpg`) → `source_file_missing`; cand1 `pending_uploads/<msgId>/<blob>.jpg` (`recover_completed_media_from_pending_upload`); cand2 `media/<groupId>/<blob>.jpg.enc` (`migrate_encrypted_group_media_companion`, `allowTransient:true`). **All three missing.** The correct plaintext path was probed first and was genuinely absent.
- `pixel.log:7734` — `RELAY_FREE_MEDIA_AUDIT` `policy:sanitize_missing_media_without_relay requiredChatMediaCount:7 migratedChatMediaCount:5 missingRequiredMediaCount:2 sanitizedMissingMediaCount:2 blockingIssueCount:0 relayDependencyRisk:false`.
- `pixel.log:7737` — `FILE_PAYLOAD_BUILT` `fileEntryCount:5 fileEntryCountsByKind:{chatMedia:5}`, all 5 survivors are 1:1 (`media/<peerId>/<blob>.jpg`, `criticality:critical`).
- `pixel.log:7851` — `ACCOUNT_MIGRATION_TRANSFER_SUCCEEDED` (14:38:25.546). **Transfer reported SUCCESS with only 5/7 chat media.**

The Pixel runs as a single process throughout (pid 20067, no restart/reinstall between commit at 14:36 and build at 14:38), so the file existed, then was deleted within the same process, with no instrumented delete.

**iPhone — import then relay fallback (~14:38:20–43):**
- `iphone-13.log:717` — `BUNDLE_IMPORT_FILES_WRITTEN` `writtenCount:5 manifestItemCount:5 fileEntryCountsByKind:{chatMedia:5}`. The 2 group blobs are absent — the iPhone never received their bytes.
- `iphone-13.log:718` — `IMPORT_RELAY_FREE_MEDIA_AUDIT relayDependencyRisk:false`; the import side is blind to the 2 sanitized rows.
- `iphone-13.log:1340,1342` — opening the group chat: `MEDIA_DOWNLOAD_LOCAL_MISS` for 36a7ef51 & 78869014 (`no_local_path`, `encryptedCompanionExpected:true`, `encryptedCompanionFoundBeforeRestore:false`).
- `iphone-13.log:1362,1368` — `P2P_MEDIA_DOWNLOAD_RESPONSE` ok, `routedViaRelayStore:true`, `sourceRole relay_media_store`, `servedByPhone:false`. The exact 2 dropped blobs are fetched from the relay store.
- `iphone-13.log:1398-1401` — on the iPhone BOTH blobs survive @250ms AND @1000ms probes (unlike the Pixel), confirming the same code retains durably here and the Pixel loss is environment/timing-dependent, not a deterministic delete.

## Root Causes (Ranked)

### 1. Received group plaintext `.jpg` is not durably retained on a member device — Severity: Critical — Classification: **H2 (group media not retained)** — THIS IS THE TRIGGER

**Mechanism.** The intended at-rest representation of received group media is the decrypted plaintext `.jpg`: `download_media_use_case.dart:1285` renames `<blob>.jpg.enc.dec → media/<groupId>/<blob>.jpg` in the durable app-documents dir, deletes the `.enc` companion (`download_media_use_case.dart:1287-1293`, reason `group_download_encrypted_companion_cleanup_after_decrypt`), and commits the plaintext as durable. The decrypt output is written next to the source (`file_crypto.go:103`, `<path>.dec`), not a cache/temp dir, so the commit is durable by design. The post-commit probe (`download_media_use_case.dart:85-148`) is read-only and never deletes — it only *witnesses* the loss.

Yet the committed plaintext is deleted within ~1s with **no `APP_OWNED_MEDIA_DELETE` telemetry** (`pixel.log:3405-3406` for blob 78869014). Because only `deleteAppOwnedMediaFileIfExists` (`app_owned_media_delete_telemetry.dart:104-127`) emits delete telemetry, the deletion must come from a raw `dart:io` `File.delete()` that bypasses the instrumented helper. There is a concrete deterministic culprit in the group-feed display path (see Root Cause 2), plus a second candidate raw-delete route (`group_conversation_wired.dart:2223 _deleteUnsafeLocalMediaFile`). By bundle-build time (14:38:14) the bytes are genuinely gone, so the manifest correctly reports `source_file_missing` — there are no bytes to bundle.

This is the root cause confirmed across four dimensions (`group-media-lifecycle`, `manifest-builder-group-paths`, `group-vs-1to1-retention-asymmetry`, `log-timeline-authoritative`), all verdicts `holdsUp:true` / `confidence:high`.

### 2. Comparison-domain bug in group-feed display verification deletes valid plaintext (the deterministic deleter) — Severity: Critical — Classification: **H2 (the specific deleter)**

**Mechanism.** `contentHash` is computed over the **encrypted** `.enc` blob, not the plaintext, and *only for group uploads*: `upload_media_use_case.dart:276` does `contentHash = computeFileSha256Hex(encryptedUploadPath)` inside an `if (isGroupUpload)` guard. The download path correctly validates that hash against the `.enc` companion *before* decrypt (`download_media_use_case.dart:1174-1177`, and again at `685-688`). But the group-feed display verification re-runs the *same encrypted-blob hash against the decrypted plaintext `.jpg`*: `group_feed_media_verification.dart:57` calls `validateFileContentHash(path: resolvedPath /* plaintext .jpg */, expectedHash: attachment.contentHash /* .enc hash */)`. Since `sha256(plaintext) != sha256(.enc)`, this always returns `content_hash_mismatch`, and `group_feed_media_verification.dart:62-66` then executes a raw `await file.delete()` inside try/catch — **bypassing `deleteAppOwnedMediaFileIfExists`, so no `APP_OWNED_MEDIA_DELETE` event is emitted** — and flips the row to `integrity_failed` *in memory only* (a returned `copyWith`, never persisted to DB).

This path runs on *every* group-feed/conversation render of a `done` content-hash-bearing attachment (callers: `load_feed_use_case.dart:109`, `load_group_feed_snapshot_use_case.dart:34`, `feed_wired.dart:896`). The file already passed an `exists()` check at `group_feed_media_verification.dart:49-55`, and there is no size/MIME escape hatch, so for valid group media the delete fires deterministically on the (guaranteed) mismatch.

**This is the single best-evidenced deleter.** The verdict on `group-media-lifecycle` confirms `group_feed_media_verification.dart:64` is the *only* raw `File.delete()` in the group display/conversation paths that bypasses telemetry, uniquely explaining the silent loss. Note the timing differential: blob 78869014 was deleted within the +1000ms probe window (`pixel.log:3405-3406`); blob 36a7ef51 was still present at +1000ms (`pixel.log:3384`) and deleted later at a subsequent feed render before bundle time — consistent with a per-render deterministic delete firing at different render moments.

### 3. H1 (manifest false-negative) — FALSIFIED — Classification: H1, ruled out

The fork is resolved decisively in favor of H2. The manifest builder's first group candidate is the *correct* plaintext path: `migration_file_manifest_builder.dart:420-435` classifies `media/<groupId>/<blob>.jpg`, which does not start with `local_media/` (`:901-903`), so `canonicalLocalMediaPath==null`, `repairReason=normalize_stored_path`, and `exportRelativePath ==` the plaintext path. `_addChatMedia` (`:130-147`) probes candidates *in order* and returns on the first whose `File.exists()` is true; `_isTransientPath` (`:905-908`) flags only `.enc`/`.download.jpg`/`.raw.*.jpg`, so the plaintext `.jpg` is non-transient and is checked first. `_absoluteForRelativePath` (`:890-892`) joins `documentsRootPath` (`getApplicationDocumentsDirectory()`, identical to the base `media_file_manager.dart:221` wrote to at commit). The `.enc` companion is appended **last** (`:496-508`, gated on `groupId != null`) and cannot mask a present plaintext probed first.

Runtime confirms: `pixel.log:7726` shows cand0 (`normalize_stored_path`) probing the exact absolute path the app committed durable at 14:36:27 (`pixel.log:3343`, same pid, no restart) and finding it absent. A present plaintext *cannot* yield `source_file_missing` here. The manifest builder is correct; the bytes were genuinely gone. (Minor citation correction from a verifier: the `normalize_stored_path` diagnostic is `pixel.log:7726`, not 7727; line 7727 is cand1 `recover_completed_media_from_pending_upload`.)

### 4. The amplifier: `sanitize_missing_media_without_relay` downgrades blocking critical media and reports SUCCESS — Severity: Critical — Classification: the amplifier (downgrade/sanitize-instead-of-block)

**Mechanism.** `account_migration_bundle_transfer.dart:498-502 _shouldDowngradeMissingChatMediaIssue` matches *any* issue that is `issue.blocking && issue.sourceTable=='media_attachments' && issue.code==missingRequiredFile` — **with no criticality guard**, so critical group media qualifies. The downgrade (`_downgradeMissingChatMediaIssues`, `:447-475`) then: (1) runs `UPDATE media_attachments SET local_path=NULL, download_status='integrity_failed'` on the live source DB (`:447-459`); (2) rebuilds each downgraded issue with `blocking: false` (`:462-470`); (3) thereby empties the blocking gate at `:388` (`if (manifest.issues.any((issue) => issue.blocking))`), so assembly proceeds; (4) reports `relayDependencyRisk` as `blockingIssueCount > 0` (`:713`) computed *after* the downgrade zeroed blockers, so it always reports `false`. Confirmed at `pixel.log:7734`. The downgrade runs (phase `buildFilePayload`, `:152`) *before* `exportDatabaseSnapshot` (`:178`), so the `integrity_failed`/null state propagates into the exported snapshot (`migration_database_snapshot_exporter.dart:252-256`) and thence verbatim into the imported DB (`migration_database_active_importer.dart:69-83`, no status remap). Ordering proven: `DOWNGRADE_SUCCESS @14:38:14.296` precedes `SNAPSHOT_EXPORTED @14:38:16.047`.

This converts genuinely-missing critical bytes into a silent, relay-dependent "success." Criticality metadata *exists* (`migration_file_manifest.dart:11,25 MigrationFileCriticality`, surviving entries tagged `criticality:critical` at `pixel.log:7737`), but `MigrationFileManifestIssue` (`migration_file_manifest.dart:58-85`) does not carry it, which is why the downgrade cannot branch on criticality today.

**Layering.** H2 (Root Causes 1+2) is the *trigger* — the bytes were genuinely gone. The amplifier (Root Cause 4) is what turns a recoverable situation into a *silent* failure: even given missing bytes, a correct implementation would fail-closed per the Closure Bar; instead it sanitizes and succeeds. Both layers are independently critical; fixing only one leaves the other defect live (fix retention alone → the sanitize path still mis-handles any future genuine loss; fix sanitize alone → group media still gets lost and the transfer now correctly *fails*, which is better but still loses the media).

## Why Group Media But Not 1:1 Media

The asymmetry (5/5 one-to-one media survived; 2/2 group media deleted) is fully explained at the code level by two compounding, group-specific facts:

1. **`contentHash` is computed only for group uploads.** `upload_media_use_case.dart:276` runs inside `if (isGroupUpload)` (block `245-278`); 1:1 uploads skip it entirely and `contentHash` stays null. So only group attachments carry the encrypted-blob hash that later gets mis-applied to plaintext.

2. **Only group/feed display runs the mismatched re-validation.** `resolveGroupFeedMediaForDisplay` / `group_feed_media_verification.dart` is invoked only from group-feed/conversation display paths (`load_feed_use_case.dart:109`, `load_group_feed_snapshot_use_case.dart:34`, `feed_wired.dart:896`). The 1:1 display path does not run this encrypted-hash re-validation and does not raw-delete on mismatch.

Together: a 1:1 attachment has no `contentHash` to mismatch and never enters the deleting code path, so its plaintext survives and the manifest resolves it via `normalize_stored_path` (candidateCount:2). A group attachment carries an encrypted-blob `contentHash`, hits the mismatch on every display render, and gets raw-deleted; by bundle time its plaintext is gone (candidateCount:3, `source_file_missing`). This is a *retention* asymmetry, not a path-resolution asymmetry — the only manifest path difference (the `.enc` candidate appended last) cannot mask a present plaintext.

## Contradiction With The MIG-012 Plan

The MIG-012 plan's Closure Bar states (verbatim, `Test-Flight-Improv/Move-Feature/01-move-account-to-new-device-pr-session-MIG-012-relay-independent-media-plan.md:19-23`): *"A Move Account transfer cannot succeed with blocking file-manifest issues for critical media,"* and *"If the old phone truly lacks the media bytes, the old phone fails bundle assembly with `fileManifestBlockingIssues`; it does not create a successful transfer that depends on relay availability."*

The shipped code does the **exact opposite**. When the old phone truly lacked the bytes (the H2 condition the Closure Bar explicitly anticipates), instead of failing bundle assembly:
- `_shouldDowngradeMissingChatMediaIssue` (`:498`) demotes the *critical* group-media `missingRequiredFile` issues from `blocking:true` to `blocking:false` (`:470`) with no criticality guard;
- the DB rows are nulled and flipped to `integrity_failed` (`:447-459`);
- the blocking gate (`:388`) sees zero blockers and proceeds;
- `relayDependencyRisk` is reported `false` (`:713`) precisely *because* the downgrade zeroed the blockers first;
- the transfer reports `SUCCEEDED` (`pixel.log:7851`) carrying 5/7 media.

The result is the precise scenario the Closure Bar was written to prevent: a "successful" transfer whose group images can only be recovered from relay availability (proven by the iPhone relay fallback at `iphone-13.log:1362,1368`). The plan said *fail*; the code *downgrades + sanitizes + succeeds*.

## Recommended Fixes (Ordered)

**Fix A — Stop the deterministic plaintext deletion (minimal correct fix for the trigger; maps to Root Cause 2).** In `group_feed_media_verification.dart:57`, do **not** validate the encrypted-blob `contentHash` against the decrypted plaintext file. For an already-`done` group attachment, the bytes were already integrity-verified against the `.enc` *before* decrypt (`download_media_use_case.dart:1174-1177`), so the per-display re-validation is redundant — the cleanest fix is to drop the content-hash re-check for already-decrypted `done` group media. If a per-display check is still wanted, store a separate plaintext hash (requires schema/migration + send-side recompute) and verify that. This is the smallest change that makes the plaintext `.jpg` the true durable artifact so the bundle builder finds the bytes.

**Fix B — Route all deletes through telemetry and stop deleting on a bare hash mismatch (maps to Root Causes 1+2).** Replace the raw `await file.delete()` at `group_feed_media_verification.dart:64` (and `group_conversation_wired.dart:2223`) with `deleteAppOwnedMediaFileIfExists` so any future loss emits `APP_OWNED_MEDIA_DELETE` and is attributable. Never delete a file that passed `exists()` + valid size/MIME on a mere hash mismatch — re-download/repair instead of destroy.

**Fix C — Make the sanitize downgrade criticality-aware and fail-closed (the deeper correctness fix; maps to Root Cause 4 / the Closure Bar).** Add criticality to `MigrationFileManifestIssue` (`migration_file_manifest.dart:58-85`) or join by `sourceId` to the existing `MigrationFileCriticality`. Make `_shouldDowngradeMissingChatMediaIssue` (`:498`) refuse to demote **critical** media; a critical `missingRequiredFile` must remain `blocking:true` and force `AccountMigrationBundleAssemblyException` (fail-closed), satisfying the Closure Bar. Restrict sanitize-to-non-blocking to genuinely non-critical/cache items (videoThumbnail, transient). Also fix `relayDependencyRisk` (`:713`) to derive from `sanitizedMissingMediaCount > 0`, not post-downgrade `blockingIssueCount`, so the audit cannot report a false negative.

**Fix D — Optionally, relay-aware re-materialization before bundling (alternative to fail-closed for recoverable media).** Since the rows are `done` with complete encryption metadata and the bytes are relay-recoverable (proven by the iPhone fallback), the source could re-fetch+decrypt from relay to repopulate the plaintext before bundling, rather than failing or shipping incomplete. This preserves UX but must not be used to *justify* shipping a relay-dependent bundle — it is a repair step, after which the bytes are bundled.

**Fix E — Regression tests.** (1) Assert received group media remains on disk N seconds after `DURABLE_LOCAL_PATH_COMMITTED` (guards Fixes A/B). (2) Assert a missing *critical* group-media file produces a blocking issue and bundle-assembly failure — not a sanitized success — replacing the existing test that asserts "assembles bundle when legacy local media paths cannot be migrated."

**Ordering rationale.** Fix A is the minimal fix that stops the bug from triggering at all and is the highest-leverage change. Fixes A+B together close the retention defect (H2). Fix C is the deeper correctness fix that brings the migration back into compliance with the Closure Bar and protects against *any* future genuine loss. C should not be skipped even after A/B, because A/B address the *known* deleter while C makes the system fail-safe against unknown ones.

## Open Questions / Evidence Gaps

- **Exact deleter confirmation for blob 36a7ef51.** The probe witnessed blob 78869014 vanish in the +1000ms window (`pixel.log:3405-3406`), but 36a7ef51 was still present at +1000ms (`pixel.log:3384`) and was deleted at some later feed render before 14:38:14 — the exact deletion moment for it is unobserved (no probe between 14:36:28.538 and bundle time). `group_feed_media_verification.dart:64` is the strongest and only telemetry-bypassing candidate in the group display path, but the log does not directly stamp which render fired the delete for 36a7ef51. (Note: the per-candidate bundle diagnostics at `pixel.log:7726-7733` are *not* truncated — earlier notes that the candidate array was truncated apply only to the inline `candidateDiagnostics` field on the `MEDIA_DOWNLOAD_LOCAL_MISS` / `DOWNGRADE_START` aggregate lines, not the resolving bundle-source diagnostics.)
- **iPhone import readback contradiction (verifier downgraded).** The `iphone-import-readback` finding's *core* claim — that the Pixel's `integrity_failed` status drove the relay fetch — did **not** hold up (verdict `holdsUp:false`, `confidence:high`). `_shouldRecoverVisibleAttachment` (`group_conversation_wired.dart:2963-2968`) explicitly *excludes* `integrity_failed`, yet the relay download fired on chat-open, and no resolve-time `MEDIA_REPO_SAVE` exists for these blobs (only the 2 `downloading` flips at `iphone-13.log:1318,1320`). This is only consistent with the loaded status being `pending`/`failed`, not `integrity_failed`. So the *receiver-side* mechanism for what status the iPhone actually hydrated is **unresolved** — either the `integrity_failed` value did not reach the hydrated row, or the binary that produced the log differs from HEAD on the recovery gate. This does not affect the H2 conclusion or the fact that the iPhone received no bytes and relay-fetched them (`iphone-13.log:717,1340,1362`); only the precise receiver gating status is open. The defensible reduced statement is: *no-local-file + recoverable status (pending/failed) triggers the relay fetch.*
- **Why Android-specific.** The same code retains both blobs durably on the iPhone (`iphone-13.log:1398-1401`). If Fix A removes the deterministic feed-path delete, this asymmetry should disappear; if loss persists, an Android-specific timing/race or sandbox factor would need investigation. Not settled by the current logs.
- **Uncommitted working-tree code.** `lib/features/account_migration/` is untracked and `group_conversation_wired.dart` / `download_media_use_case.dart` are heavily modified in the working tree; the analysis reflects working-tree source, which matches the run that produced the logs on all load-bearing lines (the recovery gate `2963-2968` is unchanged at both HEAD and working-tree).

## Confidence

- **Root Cause 1 (group plaintext not durably retained / H2):** **High.** Confirmed across four dimensions, all verdicts `holdsUp:true`/`confidence:high`. Decisive evidence: `DURABLE_LOCAL_PATH_COMMITTED` (`pixel.log:3343,3387`) → `DELAYED_PROBE_MISSING` (`pixel.log:3406`) with no delete telemetry, plus the manifest builder probing the correct path and finding it absent (`pixel.log:7726`).
- **Root Cause 2 (comparison-domain bug at `group_feed_media_verification.dart:57`/`:64`):** **High** that this is *a* deterministic telemetry-bypassing deleter (code verified verbatim; it is the only such raw delete in the group display path, and `contentHash` is provably the encrypted-blob hash). **Medium** that it is the *specific* delete that fired for blob 36a7ef51 in this run, since the exact intervening render is not log-stamped.
- **Root Cause 3 (H1 falsified):** **High.** Source semantics and runtime candidate diagnostics agree exactly; a present plaintext cannot yield `source_file_missing` through this builder.
- **Root Cause 4 (sanitize-instead-of-block amplifier):** **High.** Every load-bearing code line and log line (`:498`, `:462-475`, `:447-459`, `:713`, `:388`, `pixel.log:7721,7722,7734,7851`) verified verbatim; Closure Bar text matches verbatim; criticality plumbing gap confirmed.
- **Group-vs-1:1 asymmetry explanation:** **High.** Structurally grounded in the `if (isGroupUpload)` hash guard plus group-only display verification.
- **Receiver-side hydration status (which gate fired on the iPhone):** **Low/Unresolved.** The one finding asserting `integrity_failed` propagation as the relay-fetch driver was downgraded (`holdsUp:false`); the import outcome (no bytes → relay fetch) is High, but the precise gating status is an open question.

---

### Appendix — Key identifiers for reproduction

- **Group id:** `f91d3f06-9490-4b1c-96e9-27add9df503b`
- **Lost group blobs:** `36a7ef51-5a82-4985-90d9-4b810b91a86f` (1,012,567 B), `78869014-d101-4e0b-b3b8-02f82afbf9fd` (1,382,568 B); both `messageId 200482dc-d59d-4615-a632-39799e4ee634`, `enforceGroupMediaPolicy:true`, `encryptionScheme blob_aes_256_gcm_v1`.
- **Bundle session:** `412f475e-ff5f-4d35-b644-97d0fa3edfde`
- **Outcome:** 7 chat media required → 5 bundled (all 1:1) → transfer `SUCCEEDED` → iPhone relay-fetched the 2 group blobs on chat open.

*Generated by the `move-media-relay-leak-triage` workflow (13 agents: 6 trace dimensions, 6 adversarial verifiers, 1 synthesis).*
