export const meta = {
  name: 'move-relay-free-gap-hunt',
  description: 'Find feature gaps/bugs that can prevent a relay-free account move to a new phone',
  phases: [
    { title: 'Hunt', detail: '8 domain finders trace move-feature code for relay-free gaps' },
    { title: 'Verify', detail: 'Adversarial verification of every finding against source' },
    { title: 'Critic', detail: 'Completeness critic + extra finders for missed angles' },
    { title: 'Synthesize', detail: 'Ranked gap report' },
  ],
}

// ---------------------------------------------------------------------------
const CONTEXT = `
MISSION: Find feature gaps and bugs that can prevent moving an account old-phone -> new-phone RELAY-FREE.
cwd = flutter_app. Code is the working tree (lib/features/account_migration/ is NEW/untracked — analyze working tree, not HEAD).

DEFINITION OF RELAY-FREE (the product rule):
- The move bundle travels direct WiFi (sourceTransport move_bundle_direct_wifi). After import + cutover, ALL HISTORICAL
  data (messages, media, posts, groups, contacts, identity, avatars) must open from local data WITHOUT relay:
  no GO_BRIDGE_SEND cmd "media:download", no inbox-retention dependence, no re-fetch of historical blobs.
- Relay use for FUTURE/live delivery (new incoming messages, rendezvous for live group pubsub, FCM push) is ACCEPTABLE.
- A gap = (a) data needed post-move that is NOT packaged/imported; (b) packaged but broken on import (paths, statuses, crypto);
  (c) post-import code that re-fetches HISTORICAL data from relay or silently loses it; (d) policies that silently drop
  data and still report success; (e) cutover/lifecycle steps that leave the move incomplete, lossy, or insecure;
  (f) anything that makes the move FAIL outright. Classify each finding by type.

KNOWN ISSUES — DO NOT RE-REPORT AS NEW (only note interactions / new manifestations):
1. [KNOWN-1] group_feed_media_verification.dart:57/64 validates encrypted-blob contentHash against decrypted plaintext ->
   raw file.delete() of received group .jpg on every group-feed render (no telemetry); PLUS the migration downgrade
   _shouldDowngradeMissingChatMediaIssue (account_migration_bundle_transfer.dart:~498) sanitizes blocking critical chat-media
   issues to non-blocking and reports success. Doc: Test-Flight-Improv/Move-Feature/MIG-012-group-media-relay-leak-triage.md
   INTERACTIONS ARE IN SCOPE: e.g. does the SAME verification bug fire on the NEW phone against imported group media?
2. [KNOWN-2] Segment-transfer TimeoutException: _postJson 10s timeout, no retry/try-catch, zero transport telemetry,
   bundleSourceFailed mislabel. Doc: Test-Flight-Improv/Move-Feature/move-transfer-timeout-before-handoff-triage.md
3. [KNOWN-SPEC] Spec review G1-G7 (Test-Flight-Improv/Move-Feature/01-move-account-to-new-device-spec-review.md):
   G1 erase secret-residue on old phone, G2 SQLCipher cipher-param portability Android->iOS, G3 device-local cutover flag,
   G4 server-side relay/push deregister, G5 disk-space probe, G6 session-auth binding, G7 iOS suspension mid-transfer.
   These were SPEC gaps (2026-06-06). If a Gx is STILL unimplemented in the working-tree code AND it impacts relay-free
   moves or move integrity, REPORT it with label "spec-gap-still-open"; if since implemented, skip it.

GROUNDED INVENTORY OF WHAT THE BUNDLE PACKAGES (verified by scout; re-verify details as needed):
- DB: full SQLCipher snapshot export (migration_database_snapshot_exporter.dart) — covers ALL tables.
- Rows loaded for manifests (account_migration_bundle_transfer.dart:1684-1694): chatMedia (joined media_attachments query
  :1723), post_media_attachments, posts_media_upload_recovery, contacts, identity, groups, group_keys, group_key_drafts.
- File manifest kinds (migration_file_manifest.dart:1-8): chatMedia, postMedia, contactAvatar, identityAvatar, groupAvatar,
  pendingUpload, videoThumbnail. Issue codes include missingRequiredFile, unsupportedAbsolutePath, missingChatMediaMetadata,
  missingSecureStoreKey, missingPostMediaCrypto, fileSizeMismatch, transientFile.
- Secure storage (migration_secure_storage_registry.dart): static keys db_encryption_key, identity_private_key,
  identity_mnemonic12, identity_ml_kem_secret_key, secrets_migrated; PLUS discovered keys via
  migration_secure_storage_reference_collector.dart: group key material refs (group_keys.encrypted_key secure references +
  shared group mirrors per group/generation), media_attachments.encryption_key_base64 secure references.
- Pending work manifest (migration_pending_work_manifest_builder.dart): outgoing 'messages' rows with pending-ish statuses,
  follow-on events, pending introduction responses. (Check what is NOT covered: group outbox? posts outbox? reactions?)
- Key application files: account_migration_bundle_transfer.dart (source+receiver), account_migration_local_transfer_runtime.dart
  (transport+handlers+receiver lifecycle), migration_file_manifest_builder.dart, migration_database_snapshot_exporter.dart,
  migration_database_import_staging.dart / _validator / _active_importer / migration_database_import_cleanup.dart,
  migration_file_import_cleanup.dart, migration_secure_storage_staging.dart / _cleanup.dart, migration_cutover_coordinator.dart /
  _repository_impl / _bridge_cleanup, migration_export_authorization.dart, migration_storage_preflight.dart,
  account_migration_runtime_network_gate.dart, migration_qr_payload_use_case.dart, migration_pairing_session_repository_impl.dart,
  account_migration_authority_repository_impl.dart, migration_group_manifest_builder.dart / _validator,
  migration_pending_work_manifest_builder.dart / _validator, presentation/screens/account_migration_journey_wired.dart, lib/main.dart (wiring).
- Related app code: lib/core/media/media_file_manager.dart, media_file_path_convention.dart, lib/features/conversation/application/
  (download/upload/link media use cases), lib/features/posts/, lib/features/groups/, lib/core/local_discovery/, lib/core/lifecycle/handle_app_resumed.dart.
- DB tables exist for: messages, media_attachments, groups, group_messages, group_keys(+drafts), group_member_device_identities,
  group_pending_key_repairs, group_welcome_key_package_tombstones, group_history_gap_repairs, group_sync_receipts,
  group_invite_delivery_attempts, pending_group_invites, group_reaction_replay_outbox, introductions(+keys/recipient_keys),
  introduction_outbox, pending_intro_responses, inbox_staging_entries, posts_* (core/engagement/nearby/pins/pass_along/
  follow_on_outbox/media_upload_recovery/repost_*), contact_requests, identity, contacts. Full DB snapshot carries all rows;
  gaps come from FILES, SECURE VALUES, REMOTE/RELAY STATE, and POST-IMPORT BEHAVIOR — not usually from missing rows.

METHOD REQUIREMENTS for every finding:
- Ground in working-tree source with file:line cites; quote the load-bearing line(s).
- Give a concrete user-visible failure scenario ("user moves account, then opens X -> Y happens").
- Classify type: relay-dependency-historical | data-loss | move-failure | silent-degradation | security | correctness.
- Severity: critical/high/medium/low. Confidence: high/medium/low (be honest).
- If you check a suspect area and it is actually HANDLED CORRECTLY, list it in 'verifiedOk' (do not pad findings).
`

const FINDINGS_SCHEMA = {
  type: 'object',
  additionalProperties: false,
  required: ['dimension', 'findings', 'verifiedOk'],
  properties: {
    dimension: { type: 'string' },
    findings: {
      type: 'array',
      items: {
        type: 'object',
        additionalProperties: false,
        required: ['title', 'type', 'severity', 'confidence', 'mechanism', 'scenario', 'evidence', 'fixDirection'],
        properties: {
          title: { type: 'string' },
          type: { type: 'string', enum: ['relay-dependency-historical', 'data-loss', 'move-failure', 'silent-degradation', 'security', 'correctness', 'spec-gap-still-open', 'known-bug-interaction'] },
          severity: { type: 'string', enum: ['critical', 'high', 'medium', 'low'] },
          confidence: { type: 'string', enum: ['high', 'medium', 'low'] },
          mechanism: { type: 'string', description: 'Causal chain grounded in code with file:line cites and quoted lines' },
          scenario: { type: 'string', description: 'Concrete user-visible failure scenario post-move' },
          evidence: {
            type: 'array',
            items: {
              type: 'object', additionalProperties: false,
              required: ['ref', 'detail'],
              properties: { ref: { type: 'string' }, detail: { type: 'string' } },
            },
          },
          fixDirection: { type: 'string' },
        },
      },
    },
    verifiedOk: { type: 'array', items: { type: 'string' }, description: 'Suspect areas checked and found correctly handled (1 line each, with file:line)' },
  },
}

const VERDICT_SCHEMA = {
  type: 'object', additionalProperties: false,
  required: ['holdsUp', 'confidence', 'assessment', 'adjustedSeverity'],
  properties: {
    holdsUp: { type: 'boolean' },
    confidence: { type: 'string', enum: ['high', 'medium', 'low'] },
    assessment: { type: 'string' },
    adjustedSeverity: { type: 'string', enum: ['critical', 'high', 'medium', 'low', 'not-a-bug'] },
    corrections: { type: 'array', items: { type: 'string' } },
  },
}

const CRITIC_SCHEMA = {
  type: 'object', additionalProperties: false,
  required: ['missedAngles'],
  properties: {
    missedAngles: {
      type: 'array', maxItems: 3,
      items: {
        type: 'object', additionalProperties: false,
        required: ['key', 'prompt', 'why'],
        properties: { key: { type: 'string' }, prompt: { type: 'string', description: 'Full self-contained finder prompt for this angle' }, why: { type: 'string' } },
      },
    },
  },
}

const DIMENSIONS = [
  {
    key: 'file-manifest-completeness',
    prompt: `DIMENSION: File-manifest completeness. Enumerate EVERY kind of file the app persists on disk that a user would expect to survive a move (chat media incl. voice notes/audio, video files AND their thumbnails, group media .enc companions, post media, repost media snapshots, avatars: contact/identity/group, pending_uploads dir, local_media dir from local-WiFi transfers, drafts, anything under getApplicationDocumentsDirectory or app support). Sources: lib/core/media/media_file_manager.dart, media_file_path_convention.dart, lib/core/local_discovery/local_media_server.dart + local_media_sender.dart (where do local-WiFi received files land and what local_path do they get?), lib/features/posts/ media storage, avatar storage code. Compare against what migration_file_manifest_builder.dart actually packages (kinds: chatMedia, postMedia, contactAvatar, identityAvatar, groupAvatar, pendingUpload, videoThumbnail). Find: file classes NOT packaged; path shapes the builder cannot resolve (e.g. local_media/... paths, absolute gallery/cache paths, voice-note dirs); files packaged without their crypto metadata. For each gap: would the new phone relay-refetch it, lose it, or break?`,
  },
  {
    key: 'secure-storage-completeness',
    prompt: `DIMENSION: Secure-storage migration completeness + secret lifecycle. Enumerate ALL SecureKeyStore reads/writes app-wide (grep secureKeyStore/keyStore/SecureKeyStore usages in lib/) and all secure-store reference conventions (secret_storage_references.dart). Compare against migration_secure_storage_registry.dart static keys (db_encryption_key, identity_private_key, identity_mnemonic12, identity_ml_kem_secret_key, secrets_migrated) + migration_secure_storage_reference_collector.dart discovered keys (group key refs incl. shared mirrors, media_attachments.encryption_key_base64 refs). Find: (a) secure values used by features but NOT collected (e.g. image_quality_preference, post/repost media keys, introduction keys if secure-stored, anything new); (b) values whose ABSENCE on the new phone breaks decrypt of historical data (worst class: makes imported ciphertext permanently unreadable -> user data loss that relay cannot even fix); (c) the receiver staging/import path (migration_secure_storage_staging.dart) — are all collected keys actually written, atomically, before cutover?; (d) old-phone secret residue after move (G1 spec gap — implemented or not? migration_secure_storage_cleanup.dart). Also: db_encryption_key — is the SNAPSHOT re-encrypted for transport and re-keyed on import, or does the new phone keep the old DB key?`,
  },
  {
    key: 'post-import-1to1-relay',
    prompt: `DIMENSION: Post-import 1:1 chat relay dependencies. Trace what happens on the NEW phone after import when the user opens 1:1 conversations: lib/features/conversation/application/download_media_use_case.dart trigger conditions (which downloadStatus values + missing-file conditions fire media:download), media_attachment_repository_impl, chat message listener, retry_incomplete_uploads_use_case.dart. Questions: (a) which imported downloadStatus values (pending, downloading, failed, upload_pending, integrity_failed) survive import VERBATIM (migration_database_active_importer.dart — any status remap?) and which of those trigger relay fetches on chat open; (b) local_path portability: are imported local_path values relative (good) or can absolute Android paths (/data/user/0/...) reach the iOS DB ( _writeImportedFiles + any import-time path repair — find it or its absence); (c) does _writeImportedFiles place files exactly where the path convention resolves on iOS (Documents dir base); (d) video thumbnails + voice notes resolution post-import; (e) does ANY 'healing'/reconciliation pass run post-import that re-marks rows or re-fetches from relay. Distinguish acceptable (re-fetching a download the OLD phone also didn't have) from gaps (relay-refetching data that WAS in the bundle).`,
  },
  {
    key: 'group-relay-dependencies',
    prompt: `DIMENSION: Group feature relay-free integrity post-move. Trace: (a) group_keys — are ALL key generations packaged (bundle loads group_keys + drafts + secure refs incl. shared mirrors)? If any generation is missing, which historical group messages become undecryptable (find the decrypt path that selects key by generation)? (b) Imported group media: the .enc companions are deleted after decrypt on the old phone — for imported plaintext group media on the NEW phone, does group_feed_media_verification.dart run on first group-feed render and (per KNOWN-1) DELETE the imported plaintext (encrypted-hash-vs-plaintext mismatch) -> relay refetch? That interaction on the NEW phone is IN SCOPE — confirm from code whether imported rows carry contentHash and downloadStatus done, hence enter that path. (c) rejoinGroupTopics / groupPeerDiscoveryLoop on the new phone — live relay use is fine, but does any HISTORY repair (group_history_gap_repairs, group_sync_receipts, drain offline inbox) re-pull historical messages from relay inbox and potentially duplicate or depend on retention? (d) member device identities: same peer id migrates (identity private key) — do OTHER members' devices accept the moved device without a key rotation (group_member_device_identities)? Would messages sent BY others DURING the move window be lost for the new phone (sent to old phone's inbox / pubsub while old phone is network-blocked)? (e) pending_group_invites / welcome key packages — does an in-flight invite survive the move?`,
  },
  {
    key: 'posts-relay-dependencies',
    prompt: `DIMENSION: Posts feature relay-free integrity post-move. The bundle loads post_media_attachments + posts_media_upload_recovery rows and packages postMedia files (+ missingPostMediaCrypto issue code exists). Trace lib/features/posts/: (a) post media storage paths + crypto (repost encrypted snapshots, repost media crypto migration tables) — fully packaged with keys? (b) pending_post_media_upload_retrier.dart on the NEW phone post-import: does it resume uploads correctly or duplicate/fail? (c) any post display path that re-fetches historical post media from relay when local file present/absent; (d) posts engagement/pass-along/outbox tables — anything needing remote state that breaks after peer moves; (e) the sanitize/downgrade policy for MISSING POST media in the bundle source (is there a post-media analog of the chat-media downgrade — does it block, sanitize, or silently skip?). Cite the actual code.`,
  },
  {
    key: 'cutover-relay-lifecycle',
    prompt: `DIMENSION: Cutover + relay-side lifecycle. Trace migration_cutover_coordinator.dart, _repository_impl, migration_cutover_bridge_cleanup.dart, account_migration_runtime_network_gate.dart, migration_export_authorization.dart, the old-block-proof exchange in account_migration_local_transfer_runtime.dart (_runOldPhoneCutoverIfConfigured, _handleOldBlockProof), lease cleanup, and lib/main.dart wiring. Questions: (a) MESSAGE-LOSS WINDOW: between DB snapshot export (old phone) and cutover, messages can arrive at the old phone (it drained group inbox during transfer per pixel.log) — are messages received AFTER snapshot but BEFORE cutover transferred to the new phone, lost, or left only on the old phone? Does the old phone keep ACKing/draining relay inbox during transfer (removing messages from relay so the new phone can never get them)? Look for any quiesce/pause of inbox drain + pubsub during transfer — found or absent? (b) relay/push server-side dereg (G4): does the old phone deregister from relay inbox + FCM, and does the new phone register fresh (push token re-register on iOS)? If both devices stay registered, who receives? (c) cutover flag device-local (G3) and old phone permanently blocked (network gate) — re-verify current implementation status; what happens if old phone app reinstalled/cleared? (d) authority/lease model (account_migration_authority_repository_impl.dart) — single-writer guarantee real or advisory? (e) what happens to the RELAY MEDIA STORE blobs the old account uploaded — left forever (retention concern) or cleaned?`,
  },
  {
    key: 'pending-work-resume',
    prompt: `DIMENSION: Pending-work migration + resume on the new phone. migration_pending_work_manifest_builder.dart covers: outgoing 1:1 'messages' with pending statuses, follow-on events, pending introduction responses. Find what is NOT covered and whether it matters: group message outbox / unsent group messages (group_messages statuses), group_reaction_replay_outbox, introduction_outbox, posts_follow_on_outbox, pending media uploads (upload_pending attachments — pendingUpload file kind exists; is the RESUME wired on the new phone via retry_incomplete_uploads_use_case?), contact_requests in-flight, key_exchange_retrier state. For each: (a) is the DATA migrated (DB snapshot says yes for rows — so focus on whether associated FILES/secure values/timers survive); (b) does the NEW phone actually RESUME the work post-import (find the startup/resume wiring in main.dart / handle_app_resumed.dart / listeners) or does it sit dead forever (silent-degradation); (c) does the OLD phone's copy of the same pending work double-send after cutover (or is it network-gated)? Also the pending-work manifest VALIDATOR on import — does failed validation block or sanitize?`,
  },
  {
    key: 'import-pipeline-integrity',
    prompt: `DIMENSION: Import pipeline integrity on the new phone. Trace migration_database_import_staging.dart, migration_database_import_validator.dart, migration_database_schema_inventory.dart, migration_database_active_importer.dart, migration_database_import_cleanup.dart, migration_file_import_cleanup.dart, account_migration_import_precondition.dart, and the receiver side of account_migration_bundle_transfer.dart (_writeImportedFiles, complete()). Find: (a) schema drift: the schema inventory vs CURRENT migrations list — if the old phone runs a NEWER or OLDER app version (different schema version), does import fail-closed, silently drop tables, or corrupt? Is there a version handshake in the QR/transcript? (b) atomicity: if the app crashes mid-import (after files written, before DB swap, or after DB swap before secure values), what state results — is there a staged/atomic swap + journal, and a recovery path on next launch? (c) SQLCipher portability (G2): how is the snapshot decrypted/re-created on iOS (cipher params pinned? migration_database_sqlcipher_capability_test.dart exists in integration_test/ — what does it prove)? (d) import cleanup: does migration_file_import_cleanup or database_import_cleanup ever DELETE files that imported rows still reference? (e) preconditions: importing onto a phone that ALREADY has an identity/data — blocked, merged, or clobbered? (f) replay/double-import protection (same bundle re-sent; session reuse — G6 session-auth binding status).`,
  },
]

// ---------------------------------------------------------------------------
phase('Hunt')

const traceOne = (d) =>
  agent(`${d.prompt}\n\n---\n${CONTEXT}`, { label: `hunt:${d.key}`, phase: 'Hunt', schema: FINDINGS_SCHEMA })
    .then((r) => (r ? { ...r, _key: d.key } : null))

const verifyFinding = (f, dimKey) =>
  agent(
    `You are an adversarial verifier for a relay-free-move gap hunt. Try to REFUTE this finding against the ACTUAL working-tree source (cwd flutter_app). Check: do the cited file:line exist and say what is claimed? Is the mechanism what the code really does (read the surrounding code, not just the cited line)? Is the failure scenario actually reachable (trace the caller chain)? Is it secretly one of the KNOWN issues re-reported (then mark not-a-bug unless it is a genuinely distinct manifestation/interaction)? Is the severity honest? Default holdsUp:false when evidence is thin.\n\nFINDING (dimension ${dimKey}):\n${JSON.stringify(f, null, 2)}\n\n---\n${CONTEXT}`,
    { label: `verify:${(f.title || 'untitled').slice(0, 40)}`, phase: 'Verify', schema: VERDICT_SCHEMA },
  ).then((v) => ({ finding: f, verdict: v, dimension: dimKey }))

// Pipeline: each dimension's findings go to verification as soon as that dimension finishes.
const dimResults = await pipeline(
  DIMENSIONS,
  traceOne,
  (res) => {
    if (!res || !res.findings || res.findings.length === 0) return { dim: res, verified: [] }
    return parallel(res.findings.map((f) => () => verifyFinding(f, res._key)))
      .then((vs) => ({ dim: res, verified: vs.filter(Boolean) }))
  },
)

const okResults = dimResults.filter(Boolean)
let allVerified = okResults.flatMap((r) => r.verified)
const verifiedOkNotes = okResults.flatMap((r) => (r.dim && r.dim.verifiedOk) ? r.dim.verifiedOk.map((n) => `[${r.dim._key}] ${n}`) : [])

log(`Initial hunt: ${allVerified.length} findings verified across ${okResults.length} dimensions`)

// ---------------------------------------------------------------------------
phase('Critic')

const surviving = allVerified.filter((v) => v.verdict && v.verdict.holdsUp)
const criticInput = {
  dimensionsRun: DIMENSIONS.map((d) => d.key),
  survivingFindingTitles: surviving.map((v) => `[${v.dimension}] ${v.finding.title} (${v.verdict.adjustedSeverity})`),
  refutedTitles: allVerified.filter((v) => !v.verdict || !v.verdict.holdsUp).map((v) => `[${v.dimension}] ${v.finding.title}`),
  verifiedOkNotes,
}

const critic = await agent(
  `You are the completeness critic for a relay-free-move gap hunt. Below are the 8 dimensions already swept, the surviving findings, refuted findings, and verified-OK notes. Identify up to 3 MISSED ANGLES that could hide additional gaps preventing a relay-free account move — angles NOT covered by the existing dimensions and not duplicating known issues. Think about: QR/pairing payload contents & versioning, identity/peer-id continuity on the Go/libp2p side (does the Go node state migrate or regenerate?), contact-request in-flight state, notification/FCM token handoff, multi-platform path conventions, iOS Keychain peculiarities (kSecAttrAccessible after restore), bundle size limits / very large accounts, the receiver's _writeImportedFiles overwrite semantics, anything in lib/main.dart startup that assumes fresh-install state. For each missed angle return a SELF-CONTAINED finder prompt (the finder will see the same CONTEXT block). If coverage is genuinely complete, return an empty list.\n\nCOVERAGE SO FAR:\n${JSON.stringify(criticInput, null, 2)}\n\n---\n${CONTEXT}`,
  { label: 'critic:coverage', phase: 'Critic', schema: CRITIC_SCHEMA },
)

if (critic && critic.missedAngles && critic.missedAngles.length > 0) {
  log(`Critic found ${critic.missedAngles.length} missed angles: ${critic.missedAngles.map((a) => a.key).join(', ')}`)
  const extraResults = await pipeline(
    critic.missedAngles.map((a) => ({ key: `extra-${a.key}`, prompt: a.prompt })),
    traceOne,
    (res) => {
      if (!res || !res.findings || res.findings.length === 0) return { dim: res, verified: [] }
      return parallel(res.findings.map((f) => () => verifyFinding(f, res._key)))
        .then((vs) => ({ dim: res, verified: vs.filter(Boolean) }))
    },
  )
  const okExtra = extraResults.filter(Boolean)
  allVerified = allVerified.concat(okExtra.flatMap((r) => r.verified))
  verifiedOkNotes.push(...okExtra.flatMap((r) => (r.dim && r.dim.verifiedOk) ? r.dim.verifiedOk.map((n) => `[${r.dim._key}] ${n}`) : []))
} else {
  log('Critic: coverage judged complete, no extra angles')
}

// ---------------------------------------------------------------------------
phase('Synthesize')

const synthInput = allVerified.map((v) =>
  `### [${v.dimension}] ${v.finding.title}\nFINDING:\n${JSON.stringify(v.finding, null, 2)}\nVERDICT:\n${JSON.stringify(v.verdict, null, 2)}`
).join('\n\n')

const report = await agent(
  `You are the lead analyst. Synthesize this verified gap-hunt into a single Markdown report body (no surrounding code fence) titled-ready content for: "Relay-Free Move Account — Feature Gap & Bug Audit". The audience: the developer deciding what to fix before the next Pixel->iPhone move test.

Sections:
1. ## Executive Summary — how many confirmed gaps, the 3-5 that matter most, overall verdict on relay-free readiness.
2. ## Confirmed Gaps & Bugs (Ranked) — ONLY findings whose verdict holdsUp:true. For each: bolded title, type, severity (use adjustedSeverity), confidence, precise mechanism with file:line cites, concrete post-move user scenario, fix direction. Group by severity. Incorporate verifier corrections.
3. ## Known-Issue Interactions — findings classified known-bug-interaction (e.g. KNOWN-1 firing on the new phone against imported media).
4. ## Spec-Review Gaps Status (G1-G7) — which are still open in code (per findings), which implemented (per verifiedOk notes), which unassessed.
5. ## Refuted / Not-A-Bug — one line each: claim + why refuted (so the next auditor doesn't re-chase them).
6. ## Verified OK — areas checked and found sound (one line each, from verifiedOk notes), so coverage is visible.
7. ## Coverage Map & Residual Risk — dimensions swept, what was NOT swept (be honest), and the top residual risks.
8. ## Recommended Fix Order — pragmatic ordering considering the two KNOWN triaged bugs already queued; note dependencies between fixes.

Rules: only assert what verified findings support; reflect verifier downgrades; keep every claim cited; do not re-litigate KNOWN-1/KNOWN-2 as new findings (reference their triage docs); be exhaustive but not padded.

VERIFIED-OK NOTES:\n${JSON.stringify(verifiedOkNotes, null, 2)}\n\n---\nALL VERIFIED FINDINGS:\n${synthInput}\n\n---\n${CONTEXT}`,
  { label: 'synthesize:report', phase: 'Synthesize' },
)

return { report, totalFindings: allVerified.length, surviving: allVerified.filter((v) => v.verdict && v.verdict.holdsUp).length }
