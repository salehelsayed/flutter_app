export const meta = {
  name: 'move-media-relay-leak-triage',
  description: 'Triage why group media leaked to relay after Move Account instead of riding in the bundle',
  phases: [
    { title: 'Trace', detail: 'Trace each root-cause dimension against real source + logs' },
    { title: 'Verify', detail: 'Adversarially verify each finding against code/logs' },
    { title: 'Synthesize', detail: 'Reconcile into ranked root causes + fixes' },
  ],
}

// ---------------------------------------------------------------------------
// Established evidence (from current pixel.log / iphone-13.log, Jun 9 2026).
// Agents must VERIFY these against source; do not blindly trust prose.
// ---------------------------------------------------------------------------
const EVIDENCE = `
ESTABLISHED LOG FACTS (current run, Jun 9 2026; cwd = flutter_app):
- Logs: ./pixel.log (old phone, Android, sender of the move) and ./iphone-13.log (new phone, receiver).
- Group id: f91d3f06-9490-4b1c-96e9-27add9df503b. Bundle rows: chatMediaCount:7, contactCount:2, groupCount:1, groupMaterialRowCount:1.
- TWO GROUP images were lost from the bundle and later fetched from relay by the iPhone:
    blob 36a7ef51-5a82-4985-90d9-4b810b91a86f (1012567 B)
    blob 78869014-d101-4e0b-b3b8-02f82afbf9fd (1382568 B)
  Both: messageId 200482dc-d59d-4615-a632-39799e4ee634, enforceGroupMediaPolicy:true,
  encryptionScheme:blob_aes_256_gcm_v1, DB downloadStatus:done,
  storedPath "media/f91d3f06-9490-4b1c-96e9-27add9df503b/<blob>.jpg" (relative).
- PIXEL @14:36:27 (pixel.log ~3319-3344): both group blobs had MEDIA_DOWNLOAD_LOCAL_MISS (reason no_local_path,
  hasLocalPath:false). App relay-downloaded them (MEDIA_DOWNLOAD_TRANSPORT_AUDIT routedViaRelayStore:true,
  sourceRole relay_media_store) just to DISPLAY them. After decrypt:
    * APP_OWNED_MEDIA_DELETE reason="replace_existing_plaintext_before_decrypt_rename" path=<blob>.jpg -> SKIPPED_MISSING (no plaintext existed)
    * APP_OWNED_MEDIA_DELETE reason="group_download_encrypted_companion_cleanup_after_decrypt" path=<blob>.jpg.enc existsBefore:true bytesBefore:1012583 -> SUCCESS existsAfter:false  (the .enc companion was DELETED)
    * MEDIA_DB_UPDATE_LOCAL_PATH -> MEDIA_DOWNLOAD_DURABLE_LOCAL_PATH_COMMITTED relativePath "media/f91d3f06.../<blob>.jpg" fileExists:true fileBytes:1012567 -> MEDIA_DOWNLOAD_SUCCESS
  i.e. at 14:36:27 the decrypted plaintext .jpg existed & was committed durable; the .enc was deleted.
  caller for these deletes = "downloadMedia.groupDownloadDecrypt".
  There is NO later APP_OWNED_MEDIA_DELETE telemetry for these .jpg files anywhere in pixel.log.
- PIXEL @14:38:13-14 (pixel.log ~7718-7737) bundle assembly:
    * ACCOUNT_MIGRATION_BUNDLE_SOURCE_ROWS_LOADED chatMediaCount:7
    * ACCOUNT_MIGRATION_BUNDLE_SOURCE_MISSING_MEDIA_DOWNGRADE_START downgradeCount:2 targetDownloadStatus:"integrity_failed" issueCodes:["missingRequiredFile"]  (the 2 group blobs; selectedReason "source_file_missing", candidateCount:3, blocking:true initially)
    * ACCOUNT_MIGRATION_BUNDLE_SOURCE_MISSING_MEDIA_DOWNGRADE_SUCCESS updatedRowCount:2  (rows flipped to integrity_failed, issue blocking now false)
    * ACCOUNT_MIGRATION_BUNDLE_SOURCE_FILE_MANIFEST_ISSUES issueCount:2 blockingIssueCount:0
    * ACCOUNT_MIGRATION_BUNDLE_SOURCE_RELAY_FREE_MEDIA_AUDIT policy:"sanitize_missing_media_without_relay" relayMediaDownloadCount:0 requiredChatMediaCount:7 migratedChatMediaCount:5 fileEntryCount:5 missingRequiredMediaCount:2 sanitizedMissingMediaCount:2 relayDependencyRisk:false
    * ACCOUNT_MIGRATION_BUNDLE_SOURCE_FILE_PAYLOAD_BUILT fileEntryCount:5 fileEntryCountsByKind:{chatMedia:5}  (all 5 survivors are 1:1, paths media/<contactPeerId>/<blob>.jpg, selected_candidate_reason "normalize_stored_path")
  => Transfer reported SUCCESS with only 5/7 chat media; the 2 GROUP media were dropped, not bundled.
- KEY ASYMMETRY: all five 1:1 media (relative path media/<peerId>/<blob>.jpg, candidateCount:2) resolved fine via
  "normalize_stored_path"; both group media (relative path media/<groupId>/<blob>.jpg, candidateCount:3) were
  "source_file_missing". Same relative-path SHAPE & same base dir => a generic base-dir bug is unlikely; the failure is GROUP-SPECIFIC.
  (The candidate-path array itself is TRUNCATED out of the log line, so logs alone cannot show which 3 paths were checked.)
- IPHONE @14:38:40 (iphone-13.log ~1328-1394) post-import, opening the group chat: MEDIA_DOWNLOAD_LOCAL_MISS for
  36a7ef51 & 78869014 (reason no_local_path, encryptedCompanionExpected:true, plannedDownloadPath <blob>.jpg.enc) ->
  P2P_MEDIA_DOWNLOAD_REQUEST -> GO_BRIDGE_SEND cmd "media:download" -> P2P_MEDIA_DOWNLOAD_RESPONSE ok:true
  routedViaRelayStore:true sourceRole relay_media_store -> MEDIA_DOWNLOAD_SUCCESS. => relay fallback for the exact 2 dropped blobs.

THE PIVOTAL UNRESOLVED FORK (resolve by reading SOURCE):
  H1 (manifest false-negative): the plaintext .jpg DID exist on the Pixel at 14:38:14, but the migration manifest
     builder's group-media candidate-path resolution looked at the wrong name/extension/dir (e.g. expected the .enc
     companion, or a /group/ vs /contact/ path), so it wrongly reported source_file_missing. Bytes were available; bundle wrongly excluded them.
  H2 (genuine non-retention): the plaintext .jpg was actually gone by 14:38:14 because received group media is not
     durably retained on a member device (some retention/cleanup path deletes it, possibly without APP_OWNED_MEDIA_DELETE telemetry),
     so there were no bytes to bundle.
  Decide which (or both) holds, with file:line evidence.

CODE LOCATIONS (all under flutter_app/):
  lib/features/conversation/application/download_media_use_case.dart   (groupDownloadDecrypt, companion cleanup, durable-path commit)
  lib/core/media/media_file_manager.dart                              (path resolution, delete, persist)
  lib/core/media/media_file_path_convention.dart                     (NEW shared path convention)
  lib/core/media/app_owned_media_delete_telemetry.dart               (NEW delete telemetry)
  lib/features/conversation/application/link_incoming_local_media_use_case.dart
  lib/features/conversation/domain/repositories/media_attachment_repository_impl.dart
  lib/core/database/helpers/media_attachments_db_helpers.dart
  lib/features/account_migration/application/migration_file_manifest_builder.dart
  lib/features/account_migration/application/migration_file_manifest_validator.dart
  lib/features/account_migration/domain/models/migration_file_manifest.dart
  lib/features/account_migration/application/account_migration_bundle_transfer.dart
  (search for the bundle SOURCE that emits ACCOUNT_MIGRATION_BUNDLE_SOURCE_* events: grep -rl "RELAY_FREE_MEDIA_AUDIT\\|sanitize_missing_media_without_relay\\|MISSING_MEDIA_DOWNGRADE" lib/)
  Plan that defined the intended behavior: Test-Flight-Improv/Move-Feature/01-move-account-to-new-device-pr-session-MIG-012-relay-independent-media-plan.md
  (its Closure Bar: "A Move Account transfer cannot succeed with blocking file-manifest issues for critical media.")
`

const FINDINGS_SCHEMA = {
  type: 'object',
  additionalProperties: false,
  required: ['dimension', 'rootCauseConfirmed', 'summary', 'mechanism', 'evidence', 'severity', 'fixDirection'],
  properties: {
    dimension: { type: 'string' },
    rootCauseConfirmed: { type: 'boolean', description: 'true if this dimension is an actual contributing root cause' },
    summary: { type: 'string', description: '1-2 sentence verdict' },
    mechanism: { type: 'string', description: 'Precise causal chain grounded in code, with file:line refs inline' },
    h1OrH2: { type: 'string', description: 'If relevant to the H1/H2 fork: "H1", "H2", "both", or "n/a"' },
    evidence: {
      type: 'array',
      items: {
        type: 'object',
        additionalProperties: false,
        required: ['kind', 'ref', 'detail'],
        properties: {
          kind: { type: 'string', enum: ['code', 'log', 'doc'] },
          ref: { type: 'string', description: 'file:line or log:line' },
          detail: { type: 'string' },
        },
      },
    },
    severity: { type: 'string', enum: ['critical', 'high', 'medium', 'low'] },
    fixDirection: { type: 'string', description: 'Concrete remediation direction (not full code)' },
    openQuestions: { type: 'array', items: { type: 'string' } },
  },
}

const VERDICT_SCHEMA = {
  type: 'object',
  additionalProperties: false,
  required: ['holdsUp', 'confidence', 'assessment'],
  properties: {
    holdsUp: { type: 'boolean', description: 'Does the finding survive adversarial scrutiny against code+logs?' },
    confidence: { type: 'string', enum: ['high', 'medium', 'low'] },
    assessment: { type: 'string' },
    corrections: { type: 'array', items: { type: 'string' } },
    missedEvidence: { type: 'array', items: { type: 'string' } },
  },
}

const DIMENSIONS = [
  {
    key: 'group-media-lifecycle',
    prompt: `Trace the LOCAL FILE LIFECYCLE of RECEIVED, ENCRYPTED GROUP media on a member device: relay download -> decrypt -> persist -> any cleanup/retention. Read download_media_use_case.dart (focus groupDownloadDecrypt path), media_file_manager.dart, app_owned_media_delete_telemetry.dart, link_incoming_local_media_use_case.dart, media_attachment_repository_impl.dart, media_attachments_db_helpers.dart.
ANSWER PRECISELY: After MEDIA_DOWNLOAD_DURABLE_LOCAL_PATH_COMMITTED (plaintext .jpg committed, .enc companion deleted), is that plaintext .jpg the durable at-rest artifact, or is it transient/cleaned later? Is there ANY code path (retention policy, app-lifecycle/resume cleanup, group-media privacy enforcement, cache trim, "delayed probe") that deletes the decrypted plaintext group .jpg WITHOUT emitting APP_OWNED_MEDIA_DELETE telemetry? Is the intended at-rest representation for group media the .enc or the .jpg? Decide H1 vs H2.`,
  },
  {
    key: 'manifest-builder-group-paths',
    prompt: `Trace migration_file_manifest_builder.dart + media_file_path_convention.dart + migration_file_manifest_validator.dart + migration_file_manifest.dart.
ANSWER PRECISELY: For a media_attachments row belonging to a GROUP (group_messages.group_id, encryptionScheme blob_aes_256_gcm_v1), what candidate paths does the builder generate, in what order (the log says candidateCount:3 for group vs 2 for 1:1)? Does it look for the plaintext "<blob>.jpg" or the encrypted "<blob>.jpg.enc" companion, or both? How does it derive the group dir (media/<groupId>/ vs media/<contactPeerId>/)? How does it resolve relative->absolute (which base directory; getApplicationDocumentsDirectory vs app_flutter/app support)? Could it report source_file_missing for a plaintext .jpg that actually exists on disk because it only probes .enc or a wrong dir? Why would 1:1 (candidateCount:2, "normalize_stored_path") resolve but group (candidateCount:3) fail? This is the crux of H1.`,
  },
  {
    key: 'downgrade-sanitize-vs-block',
    prompt: `Find and trace the migration BUNDLE SOURCE that emits ACCOUNT_MIGRATION_BUNDLE_SOURCE_* events (grep lib/ for "sanitize_missing_media_without_relay", "MISSING_MEDIA_DOWNGRADE", "RELAY_FREE_MEDIA_AUDIT", "relayDependencyRisk"). Also read account_migration_bundle_transfer.dart.
ANSWER PRECISELY: Where is the decision to DOWNGRADE a critical-media manifest issue from blocking:true to blocking:false, flip the DB row to downloadStatus "integrity_failed", "sanitize" it out, and STILL return a successful bundle with relayDependencyRisk:false? Is this an intentional policy ("sanitize_missing_media_without_relay") that CONTRADICTS the MIG-012 Closure Bar ("a Move Account transfer cannot succeed with blocking file-manifest issues for critical media")? Quote the exact code that demotes blocking->non-blocking. Is critical group media being silently treated as droppable? This is the amplifying root cause that converts "missing bytes" into "silent relay fallback".`,
  },
  {
    key: 'group-vs-1to1-retention-asymmetry',
    prompt: `Explain the ASYMMETRY: in this run all five 1:1 media survived into the bundle but BOTH group media were dropped. Trace why group encrypted media is treated differently from 1:1 media in local retention and in migration packaging. Look at enforceGroupMediaPolicy usage (grep lib/), the .enc companion model for group media, and whether RECEIVED group media is ever persisted durably on a member device or always re-fetched from relay on view (the Pixel itself had to relay-download both group images at 14:36 just to display them — hasLocalPath:false). Read download_media_use_case.dart, media_file_manager.dart, and any group-media-policy code.
ANSWER PRECISELY: Is the real upstream problem that group media is fundamentally not retained locally on receivers (so even a "complete" bundle could never include it), independent of the manifest/sanitize bugs? Decide H1 vs H2 from this angle.`,
  },
  {
    key: 'iphone-import-readback',
    prompt: `Confirm the RECEIVER (import) side. In iphone-13.log around lines 1300-1400 the iPhone, after import, opens the group chat and re-downloads 36a7ef51 & 78869014 from the relay (P2P_MEDIA_DOWNLOAD_REQUEST -> media:download -> routedViaRelayStore:true). Trace the import code (migration_database_active_importer.dart, migration_database_import_staging.dart, migration_file_import_cleanup.dart, _writeImportedFiles in the bundle transfer) and the conversation media-load path on iOS.
ANSWER PRECISELY: After import, what downloadStatus / local_path do the 2 group rows have on the iPhone, and what makes opening the chat trigger a relay download (no local file present, status not 'done', or 'integrity_failed' from the Pixel downgrade)? Confirm the iPhone NEVER received bytes for these 2 blobs in the bundle. Note whether the downgrade-to-integrity_failed on the Pixel propagates into the imported DB and shapes the iPhone behavior.`,
  },
  {
    key: 'log-timeline-authoritative',
    prompt: `Produce an AUTHORITATIVE, line-cited timeline from the CURRENT ./pixel.log and ./iphone-13.log (do NOT trust the summary — re-derive with grep). Include exact line numbers for: (a) the two group-blob relay downloads + decrypt + .enc cleanup + durable-path commit on the Pixel; (b) bundle rows loaded, missing-media downgrade start/success, file-manifest issues (blockingIssueCount), relay-free media audit, file payload built; (c) the transfer success / completion event(s) — grep for ACCOUNT_MIGRATION transfer/cutover/complete/success; (d) on the iPhone: import/cutover events, and the post-import group-chat relay downloads of the 2 blobs. Also confirm whether ANY APP_OWNED_MEDIA_DELETE or other delete touches the plaintext .jpg of the 2 group blobs AFTER 14:36:27 (it appears there is none — verify). Return the timeline as the mechanism field with each step carrying a log:line ref in evidence. Flag any evidence that CONTRADICTS the H2 (non-retention) story, e.g. a delete event you find.`,
  },
]

phase('Trace')
const results = await pipeline(
  DIMENSIONS,
  (d) => agent(`${d.prompt}\n\n---\n${EVIDENCE}`, {
    label: `trace:${d.key}`,
    phase: 'Trace',
    schema: FINDINGS_SCHEMA,
  }).then((f) => ({ ...f, _key: d.key })),
  (finding, d) => agent(
    `You are an adversarial verifier. A triage agent produced this finding for the Move-Account group-media-relay-leak bug. Try to REFUTE it against the ACTUAL source code and logs (cwd = flutter_app; logs ./pixel.log ./iphone-13.log). Check: are the file:line refs real and do they say what's claimed? Is the causal mechanism actually what the code does? Is there contradicting evidence? Be skeptical; default to holdsUp:false if the evidence is thin. If it holds, say so with confidence.\n\nFINDING UNDER REVIEW (dimension ${d.key}):\n${JSON.stringify(finding, null, 2)}\n\n---\n${EVIDENCE}`,
    { label: `verify:${d.key}`, phase: 'Verify', schema: VERDICT_SCHEMA },
  ).then((v) => ({ finding, verdict: v, key: d.key })),
)

const verified = results.filter(Boolean)

phase('Synthesize')
const synthesisInput = verified.map((r) =>
  `### Dimension: ${r.key}\nFINDING:\n${JSON.stringify(r.finding, null, 2)}\nVERDICT:\n${JSON.stringify(r.verdict, null, 2)}`
).join('\n\n')

const report = await agent(
  `You are the lead debugger. Synthesize the verified findings below into a single coherent root-cause analysis for this bug:
"After moving an account Pixel -> iPhone13, group media was NOT included in the move bundle and the new phone retrieved it from the relay instead."

Write a thorough Markdown report body (no surrounding code fence) with these sections:
1. ## Executive Summary  (3-5 sentences: what happened, the single most important root cause, and the user-facing impact)
2. ## What The Logs Prove  (the line-cited timeline, Pixel then iPhone; use the log-timeline-authoritative dimension)
3. ## Root Causes (Ranked)  — for each: a bolded title, severity, the precise mechanism with file:line and log:line citations, and whether it is H1 (manifest false-negative), H2 (group media not retained), or the amplifier (downgrade/sanitize-instead-of-block). RESOLVE the H1-vs-H2 fork explicitly and state which holds, with evidence. If both contribute, explain the layering.
4. ## Why Group Media But Not 1:1 Media  (the asymmetry)
5. ## Contradiction With The MIG-012 Plan  (the Closure Bar said a transfer must FAIL on blocking critical-media issues; explain how the shipped code downgrades+sanitizes+succeeds instead)
6. ## Recommended Fixes (Ordered)  — concrete, mapped to each root cause, noting which is the minimal correct fix vs the deeper retention fix
7. ## Open Questions / Evidence Gaps  — anything logs/code could not settle (e.g. truncated candidate-path array)
8. ## Confidence  — per root cause, reflecting the adversarial verdicts

Only assert what the verified findings support. Where a verifier downgraded a finding, reflect that. Prefer precise file:line / log:line citations. Be exhaustive but do not pad.\n\n---\nVERIFIED FINDINGS:\n${synthesisInput}\n\n---\n${EVIDENCE}`,
  { label: 'synthesize:report', phase: 'Synthesize' },
)

return { report, verified }
