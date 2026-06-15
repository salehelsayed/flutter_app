Status: executed-accepted

# MIG-005 Plan: Media, app-owned files, and storage preflight manifest

Source doc: `Test-Flight-Improv/Move-Feature/01-move-account-to-new-device-pr.md`
Breakdown artifact: `Test-Flight-Improv/Move-Feature/01-move-account-to-new-device-pr-session-breakdown.md`
Session id: `MIG-005`
Session title: Media, app-owned files, and storage preflight manifest

## Planning Progress

- 2026-06-07 01:01:30 CEST - Arbiter completed. Files inspected since last update: reviewer outcome, mandatory section coverage, simulator-gate decision, source checklist ledger, and scope guard. Decision/blocker: no structural blocker remains; MIG-005 is execution-ready as a host-testable manifest/storage-preflight slice with simulator/device media rendering left to later sessions. Next action: execute only this MIG-005 plan and stop before transfer, cutover, pending-work ownership, UI, or final device acceptance.
- 2026-06-07 01:01:30 CEST - Reviewer completed; Arbiter started. Files inspected since last update: full MIG-005 draft plan, source proposal checklist rows, media/avatar/post/group code evidence, existing tests/gates, and storage-preflight gap. Decision/blocker: plan is sufficient; no missing direct tests or closure bar. Reviewer accepts no `$run-flutter-reliability-sims` gate for this session because it does not implement real transfer/rendering journeys. Next action: arbitrate review findings and mark reusable if no structural blocker remains.
- 2026-06-07 01:01:30 CEST - Planner completed; Reviewer started. Files inspected since last update: drafted plan sections from collected evidence. Decision/blocker: draft covers file manifest item classification, app-owned path resolution/healing, chat/post media atomic metadata, avatar/group-avatar roots, generated thumbnails, transient exclusion, storage preflight, tests/gates, docs, and later-session residuals. Next action: review for missing simulator gate, stale source assumptions, and hidden transfer/cutover/pending-work scope.
- 2026-06-07 01:01:30 CEST - Evidence Collector completed; Planner started. Files inspected since last update: `MediaFileManager`, `VideoThumbnailCache`, chat media model/repository/upload/download use cases, post media model/helpers/upload/download/recovery, group avatar storage/model/helpers, profile avatar upload/download/resolver tests, media integrity policy/tests, source proposal rows, gate definitions, and storage-preflight searches. Decision/blocker: no existing account-migration file manifest or storage preflight service exists; current media roots and tests provide enough host evidence to plan a narrow implementation. Next action: draft the execution-safe plan.
- 2026-06-07 00:58:48 CEST - Evidence Collector started. Files inspected since last update: reusable breakdown row for MIG-005, MIG-004 closure state, source proposal/media rows via `rg`, gate/test inventory media rows, two graphify queries for media/file/storage migration context, and existing file/test inventory from `rg --files`. Decision/blocker: no plan artifact existed; graphify returned weak/broad matches, so targeted docs and source files are authoritative for this session. Next action: inspect media file manager, media attachment/post media/group avatar/thumbnail/storage tests, then draft the narrow MIG-005 plan.

## real scope

MIG-005 builds the file/media manifest and storage-preflight layer that later transfer and import sessions consume.

In scope:

- Add account-migration file manifest models for app-owned document files, criticality, kind/category, relative path, byte size, SHA-256 checksum, source row identity, and validation issues.
- Add a manifest builder that resolves app-owned document paths from database/media rows without recording raw absolute iOS container paths in the manifest.
- Cover durable roots already used by the app: `media/`, `media/avatars/`, `media/group_avatars/`, `post_media/`, and `pending_uploads/`.
- Verify present local chat media files against DB metadata, including size/checksum, `download_status`, `content_hash`, `encryption_nonce`, `encryption_scheme`, and secure-store media-key reference/presence when a chat media row is encrypted.
- Verify present post-media files against DB metadata, including size/checksum and DB-resident `encryption_key_base64`, `encryption_nonce`, and `is_encrypted` fields.
- Classify profile/contact avatars and group avatars from their canonical app-owned paths.
- Classify generated video thumbnails as non-critical/regeneratable cache unless implementation proves a specific thumbnail is required for safe rendering.
- Exclude or fail-fast transient artifacts such as `.enc`, `.download.jpg`, and `.raw.*.jpg` so they cannot silently become durable migrated account state.
- Add storage preflight accounting for required bytes, optional/cache bytes, staging overhead/headroom, and available bytes through an injectable storage-capacity provider.
- Preserve existing normal media upload/download, avatar, group-avatar, post-media, and local-WiFi media behavior.

Out of scope:

- No segmented transfer, AEAD chunking, resume protocol, same-WiFi discovery, or local media server changes.
- No durable cutover, old-phone quiescing, runtime migrated-out gates, pending-work ownership/resume policy, or UI.
- No final proof that migrated files render in every conversation/group/post screen on devices; that belongs to transfer/import/final acceptance sessions.
- No change to SQLCipher DB snapshot/import logic except consuming MIG-004 manifest/database evidence if needed.

## closure bar

MIG-005 is good enough when host-side tests prove the migration file manifest can be generated and validated from representative current DB rows plus a documents directory, and storage preflight can fail before transfer if the new phone cannot hold the staged account bundle.

| Checklist item | Required proof in this session |
| --- | --- |
| App-owned roots | Tests prove only `media/`, `media/avatars/`, `media/group_avatars/`, `post_media/`, and `pending_uploads/` are considered app-owned durable document roots. |
| File size/checksum manifest | Tests prove each included durable file records relative path, byte size, SHA-256 checksum, criticality, and source row identity. |
| Raw absolute paths | Tests prove legacy absolute paths under the app documents `media/` or `post_media/` roots are healed to relative manifest paths, while arbitrary absolute/gallery paths are flagged and not silently claimed as migrated. |
| Chat-media atomicity | Tests prove downloaded encrypted chat/group media requires the local file plus content hash, nonce, scheme, and resolved/available secure-store media key reference; missing/mismatched metadata fails manifest validation. |
| Pending/failed chat media | Tests prove app-owned `pending_uploads/` files are classified and hashed when present, while remote-only pending/failed media is represented as metadata-only or a later pending-work residual without requiring a nonexistent local file. |
| Post-media atomicity | Tests prove local post-media files are verified with DB-resident crypto fields (`encryption_key_base64`, `encryption_nonce`, `is_encrypted`) and are not expected in secure storage. |
| Avatars | Tests prove profile/contact avatars under `media/avatars/` and group avatars under `media/group_avatars/` are classified and verified when DB rows reference them. |
| Generated thumbnails | Tests prove `.thumb.jpg` video thumbnails are either classified non-critical/regeneratable cache or explicitly omitted with a safe reason; missing thumbnails cannot fail a critical migration. |
| Transient artifacts | Tests prove `.enc`, `.download.jpg`, and `.raw.*.jpg` files are excluded or reported as transient artifacts instead of durable account files. |
| Storage preflight | Tests prove required-file bytes plus staging overhead/headroom are compared to available bytes; insufficient storage returns a non-sensitive failure reason before transfer/import commit. |
| Cleanup boundary | Tests prove MIG-005 cleanup removes staged file-manifest artifacts for a session without deleting active app-owned media files; DB import cleanup remains MIG-004 and secure-storage cleanup remains MIG-003. |

No simulator closure gate is required for MIG-005 unless execution changes real media rendering, media transfer, local discovery, notification-preview, or multi-device flows. This session is a manifest/preflight slice. Existing media journey simulator/device evidence remains supporting context, while final migrated rendering and transport acceptance stay assigned to MIG-007, MIG-011, and MIG-012.

## source of truth

- Primary product/security contract: `Test-Flight-Improv/Move-Feature/01-move-account-to-new-device-pr.md`, especially rows requiring manifest-driven critical/non-critical items, storage roots, app-owned files, file sizes/checksums, chat-media atomicity, post-media DB crypto metadata, raw absolute path handling, transient artifact exclusion, storage preflight, and no partial account exposure.
- Session boundary: MIG-005 row in `Test-Flight-Improv/Move-Feature/01-move-account-to-new-device-pr-session-breakdown.md`. It wins over broader feature requirements for this session.
- Dependency contracts: MIG-003 secure-storage registry/staging and MIG-004 DB manifest/import staging closure. MIG-005 consumes those contracts; it does not reopen them.
- Current code/tests win over stale prose. Evidence inspected includes `lib/core/media/media_file_manager.dart`, `lib/core/media/video_thumbnail_cache.dart`, `lib/core/media/group_media_integrity_policy.dart`, chat media model/repository/upload/download use cases, post media model/helpers/upload/download/recovery, profile/avatar upload/download/resolver, group avatar storage/model/helpers, media/avatar/post/group tests, gate definitions, and test inventory.
- `Test-Flight-Improv/test-gate-definitions.md` is the named gate source. If it disagrees with `scripts/run_test_gates.sh`, the script wins.
- Graphify was queried first as required, but returned weak/broad matches for this topic. Targeted docs and source files are authoritative where graph context was incomplete.

Dirty-worktree note: planning observed existing modified/untracked files from MIG-001 through MIG-004 plus this MIG-005 plan. Treat them as current user/controller work and do not revert them.

## session classification

implementation-ready

The session has a narrow host-testable implementation path. It should become evidence-gated only if execution cannot safely identify app-owned document roots or cannot test storage preflight without a broad platform rewrite.

## exact problem statement

After MIG-004, the account-migration DB artifact can be exported/import-staged, but the migration bundle still has no durable account-owned file manifest. A migrated database can point at media, avatars, post media, pending uploads, or generated thumbnail/cache files that either are not copied, are copied from stale absolute paths, or lack size/checksum proof.

The user-visible failure would be a migration that claims success while conversation media, group media, profile avatars, group avatars, post media, or pending media artifacts are missing, mismatched, or undecryptable. The safety failure would be carrying transient ciphertext/temp files as durable account data or starting a transfer without enough storage to stage the bundle.

Existing normal media upload/download, avatar update/download, group avatar storage, post media, and local media transport behavior must stay unchanged for non-migration users.

## files and repos to inspect next

Production files likely to add:

- `lib/features/account_migration/domain/models/migration_file_manifest.dart`
- `lib/features/account_migration/application/migration_file_manifest_builder.dart`
- `lib/features/account_migration/application/migration_file_manifest_validator.dart`
- `lib/features/account_migration/application/migration_storage_preflight.dart`
- `lib/features/account_migration/application/migration_file_import_cleanup.dart`

Production files to inspect/update narrowly:

- `lib/core/media/media_file_manager.dart`
- `lib/core/media/video_thumbnail_cache.dart`
- `lib/core/media/group_media_integrity_policy.dart`
- `lib/features/conversation/domain/models/media_attachment.dart`
- `lib/features/conversation/domain/repositories/media_attachment_repository_impl.dart`
- `lib/features/conversation/application/upload_media_use_case.dart`
- `lib/features/conversation/application/download_media_use_case.dart`
- `lib/features/posts/domain/models/post_media_attachment_model.dart`
- `lib/core/database/helpers/post_media_db_helpers.dart`
- `lib/features/posts/application/attach_post_media_use_case.dart`
- `lib/features/posts/application/download_post_media_use_case.dart`
- `lib/features/posts/domain/models/post_media_upload_recovery_item.dart`
- `lib/features/groups/application/group_avatar_storage.dart`
- `lib/features/settings/application/download_profile_picture_use_case.dart`
- `lib/features/settings/application/upload_profile_picture_use_case.dart`
- `lib/features/home/application/identity_avatar_resolver.dart`

Tests and docs:

- New `test/features/account_migration/application/migration_file_manifest_builder_test.dart`
- New `test/features/account_migration/application/migration_file_manifest_validator_test.dart`
- New `test/features/account_migration/application/migration_storage_preflight_test.dart`
- New `test/features/account_migration/application/migration_file_import_cleanup_test.dart`
- Existing `test/core/media/media_file_manager_test.dart`
- Existing `test/core/media/group_media_integrity_policy_test.dart`
- Existing `test/features/conversation/domain/repositories/media_attachment_repository_impl_test.dart`
- Existing `test/features/conversation/application/download_media_use_case_test.dart`
- Existing `test/features/posts/phase2/attach_post_media_use_case_test.dart`
- Existing `test/features/posts/phase2/download_post_media_use_case_test.dart` if present, otherwise the nearest post-media use-case tests.
- Existing `test/features/posts/improvement/post_media_upload_recovery_repository_test.dart`
- Existing `test/features/groups/application/group_avatar_storage_test.dart`
- Existing `test/features/settings/application/download_profile_picture_use_case_test.dart`
- Existing `test/features/settings/application/upload_profile_picture_use_case_test.dart`
- `Test-Flight-Improv/Move-Feature/01-move-account-to-new-device-pr.md`
- `Test-Flight-Improv/codebase-test-inventory.md`
- `Test-Flight-Improv/test-gate-definitions.md` and `scripts/run_test_gates.sh` only if new tests require executable classification.

## existing tests covering this area

- `test/core/media/media_file_manager_test.dart` proves relative media/post-media/pending-upload path generation, legacy absolute media/post-media path healing, and safe deletion of app-owned pending uploads without deleting arbitrary source/gallery files.
- `test/core/media/group_media_integrity_policy_test.dart` proves SHA-256 hashing, content-hash validation, and verified group-media display eligibility.
- `test/features/conversation/domain/repositories/media_attachment_repository_impl_test.dart` proves encrypted chat media keys are written to secure storage as `secure:` references and hydrated on read.
- `test/features/conversation/application/download_media_use_case_test.dart` proves normal download/status/integrity behavior, including group media encryption/hash checks where covered.
- `test/features/posts/phase2/attach_post_media_use_case_test.dart` and related post-media tests prove post media attachment creation and DB persistence behavior.
- `test/features/posts/improvement/post_media_upload_recovery_repository_test.dart` and `test/core/services/pending_post_media_upload_retrier_test.dart` prove pending post media recovery rows and retry behavior, not migration ownership.
- `test/features/groups/application/group_avatar_storage_test.dart` proves group avatars use `media/group_avatars/<groupId>.jpg`, reject bad images, and delete `.download.jpg` temps.
- `test/features/settings/application/download_profile_picture_use_case_test.dart`, `upload_profile_picture_use_case_test.dart`, and `identity_avatar_resolver_test.dart` prove profile/contact avatars use `media/avatars/<peerId>.jpg` and raw profile downloads use transient `.raw.*.jpg` files.
- Existing local media transport tests prove ordinary local media behavior, not migration bundle file manifesting or storage preflight.

Missing today:

- No account-migration file manifest model or builder exists.
- No test proves every app-owned file referenced by DB rows is represented by relative path, size, checksum, criticality, and source-row metadata.
- No migration-specific validator rejects missing local required files, unsupported absolute paths, transient artifacts, missing encrypted-media metadata, or post-media crypto mismatch.
- No migration storage-preflight service computes required/staged footprint versus available bytes.
- No cleanup helper for staged file-manifest/import artifacts exists.

## regression/tests to add first

Add red tests before production implementation:

- `test/features/account_migration/application/migration_file_manifest_builder_test.dart`
  - Builds a documents-root fixture with chat media, post media, contact/profile avatars, group avatar, generated thumbnail, and pending-upload files.
  - Proves manifest items use relative app-owned paths, SHA-256 checksums, byte sizes, criticality, source table/source id, and category.
  - Proves legacy absolute app-document paths are healed to relative paths and arbitrary absolute paths are flagged rather than included.
  - Proves transient `.enc`, `.download.jpg`, and `.raw.*.jpg` files are excluded or reported as transient.
- `test/features/account_migration/application/migration_file_manifest_validator_test.dart`
  - Proves missing required local files fail manifest validation.
  - Proves encrypted chat media requires content hash, nonce, scheme, and secure-store media key presence/reference before export is accepted.
  - Proves encrypted post media requires DB-resident key/nonce/is-encrypted consistency and does not look for post-media keys in secure storage.
  - Proves generated thumbnails are non-critical/regeneratable and missing thumbnails do not fail a critical manifest.
- `test/features/account_migration/application/migration_storage_preflight_test.dart`
  - Proves required bytes, optional bytes, staging overhead, and headroom are summed deterministically.
  - Proves insufficient available bytes returns `storage_insufficient` or equivalent non-sensitive reason before transfer.
  - Proves storage-provider failures produce a fail-closed preflight result.
- `test/features/account_migration/application/migration_file_import_cleanup_test.dart`
  - Proves session-scoped staged file artifacts and sidecars are deleted.
  - Proves active documents-root media/post_media/avatar files are not deleted by failed/cancelled file-import cleanup.

Then run affected existing media/avatar/post tests to prove normal behavior remains unchanged.

## step-by-step implementation plan

1. Add the red tests above with fixture rows and temp directories. Keep them independent from platform plugins by injecting documents-root and storage-capacity providers.
2. Add file manifest data models with deterministic JSON serialization and stable checksum ordering. Avoid absolute paths in manifest JSON.
3. Add path classification helpers for app-owned roots: `media/`, `media/avatars/`, `media/group_avatars/`, `post_media/`, and `pending_uploads/`. Reuse `MediaFileManager` behavior where practical.
4. Add file hashing and metadata capture using streaming SHA-256, not whole-bundle reads.
5. Add builder inputs as row loaders or plain row collections for chat media, post media, post media recovery, contacts/identity avatars, and groups. Do not introduce broad repository rewrites.
6. Implement chat-media manifest rules: durable local file present -> critical file item; app-owned pending upload -> critical pending-upload file item; encrypted rows require content hash, nonce, scheme, and secure-store key availability; remote-only pending/failed rows become metadata/residual entries instead of missing-file failures.
7. Implement post-media manifest rules: local post-media files become critical file items; encrypted post media validates DB-resident crypto fields; pending post recovery paths are included only when app-owned/present or flagged as unsafe/unportable for later MIG-010 ownership decisions.
8. Implement avatar rules for `media/avatars/<peerId>.jpg` and `media/group_avatars/<groupId>.jpg`, driven by DB paths or canonical path derivation where current code already uses canonical files.
9. Implement thumbnail/transient policy: `.thumb.jpg` is non-critical/regeneratable cache; `.enc`, `.download.jpg`, and `.raw.*.jpg` are not durable manifest items.
10. Implement storage preflight with injectable available-bytes provider and a conservative staging multiplier/headroom constant. Keep platform/native free-space APIs behind the provider; do not add iOS/Android native code unless execution proves no Dart/testable abstraction can satisfy the plan.
11. Implement staged file-import cleanup for migration-session temp directories/artifacts only. Do not delete active media roots.
12. Update source proposal and test inventory docs for MIG-005 evidence/residuals. Update gate definitions/script only if completeness-check requires explicit classification.
13. Run exact direct tests, affected existing tests, format, diff check, completeness-check, baseline, and `graphify update .`.
14. Stop and replan if file manifesting requires mutating normal media repositories broadly, if storage preflight cannot be represented without native code, or if execution discovers that media rendering/transfer behavior must change to make manifest tests meaningful.

## risks and edge cases

- A raw absolute path can point to a user gallery or old iOS container and must not be claimed as migrated unless it resolves under the app documents root.
- Transient `.enc`, `.download.jpg`, and `.raw.*.jpg` files may be present during active downloads/uploads; carrying them as durable account data can expose incomplete or duplicate media state.
- Chat media and post media use different encryption-key storage models; mixing them can create false missing-key failures or undecryptable files.
- Pending upload source paths may refer to app-owned `pending_uploads/` files or arbitrary source/gallery files. MIG-005 should classify preflight/missing-file risk; MIG-010 owns resume/pause/fail semantics.
- Video thumbnails can be regenerated. Treating them as critical would block valid migrations unnecessarily.
- Storage preflight can be stale by the time transfer starts. This session should include headroom and fail-closed provider errors, while transfer/session rechecks remain later.
- Hashing large files must be streaming and deterministic.
- Logs and manifest issues must not include secret values or media contents; paths should be relative and non-sensitive where possible.

## exact tests and gates to run

Direct new MIG-005 tests:

```bash
flutter test test/features/account_migration/application/migration_file_manifest_builder_test.dart
flutter test test/features/account_migration/application/migration_file_manifest_validator_test.dart
flutter test test/features/account_migration/application/migration_storage_preflight_test.dart
flutter test test/features/account_migration/application/migration_file_import_cleanup_test.dart
```

Affected existing direct tests:

```bash
flutter test test/core/media/media_file_manager_test.dart
flutter test test/core/media/group_media_integrity_policy_test.dart
flutter test test/features/conversation/domain/repositories/media_attachment_repository_impl_test.dart
flutter test test/features/conversation/application/download_media_use_case_test.dart
flutter test test/features/posts/phase2/attach_post_media_use_case_test.dart
flutter test test/features/posts/improvement/post_media_upload_recovery_repository_test.dart
flutter test test/features/groups/application/group_avatar_storage_test.dart
flutter test test/features/settings/application/download_profile_picture_use_case_test.dart
flutter test test/features/settings/application/upload_profile_picture_use_case_test.dart
flutter test test/features/home/application/identity_avatar_resolver_test.dart
```

If execution adds or changes post media download behavior, also run:

```bash
flutter test test/features/posts/phase2/download_post_media_use_case_test.dart
```

Named/host gates:

```bash
dart format lib/features/account_migration test/features/account_migration
git diff --check
./scripts/run_test_gates.sh completeness-check
FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh baseline
```

Optional breadth only if execution touches existing local media transport or render paths:

```bash
./scripts/run_test_gates.sh 1to1
./scripts/run_test_gates.sh posts
./scripts/run_test_gates.sh groups
```

Do not add `$run-flutter-reliability-sims` closure for MIG-005 unless execution changes real multi-device media transfer/rendering behavior. Final media journey/device acceptance remains later-session scope.

## known-failure interpretation

- Treat failures in new MIG-005 tests as session-caused unless the red-before-green run already recorded the expected missing-API failure.
- Treat failures in media file manager, media repository, post media, avatar, group avatar, and storage preflight direct tests as session-caused unless a focused pre-change rerun proves the same failure already existed.
- A plain `./scripts/run_test_gates.sh baseline` failure caused only by multiple attached devices/no selected target is an environment/device-selection failure; retry with `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh baseline`.
- Existing macOS build warnings, deployment-target warnings, or `Failed to foreground app; open returned 1` are not blockers if the gate exits green, matching MIG-003 and MIG-004 gate interpretation.
- Do not remove or reclassify existing media/post/group tests to make MIG-005 green. Red named gates require exact failing file/test names and a pre-existing, unrelated, flaky, environment, or session-caused classification.

## done criteria

- File manifest models and deterministic JSON serialization exist.
- Manifest builder covers chat media, post media, avatars, group avatars, pending-upload app-owned files, generated thumbnails, and transient exclusion rules.
- Included files have relative path, size, checksum, criticality, source table/source id, and category.
- Unsupported arbitrary absolute paths are flagged and not included as durable migrated files.
- Encrypted chat-media rows prove metadata and secure-store key availability; encrypted post-media rows prove DB-resident crypto fields.
- Missing required files fail validation before transfer/import success.
- Storage preflight computes required bytes plus headroom/staging overhead and fails closed when unavailable.
- Staged file cleanup deletes only session-scoped file-import artifacts.
- Existing normal media/avatar/post/group behavior direct tests pass.
- Source proposal and test inventory are updated for MIG-005 evidence/residuals.
- Required direct tests, `./scripts/run_test_gates.sh completeness-check`, `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh baseline`, and `graphify update .` pass after implementation edits.

Coverage ledger:

| User-listed MIG-005 requirement | Closure state required |
| --- | --- |
| file/media manifest | Covered by manifest builder/model tests |
| app documents and media roots | Covered by app-owned root classifier tests |
| chat media | Covered by chat media file/checksum/encryption metadata tests |
| post media | Covered by post-media file/checksum/DB crypto tests |
| pending uploads | Covered by app-owned pending-upload classification and storage preflight tests; ownership/resume stays MIG-010 |
| contact avatars | Covered by `media/avatars/` manifest tests |
| group avatars | Covered by `media/group_avatars/` manifest tests |
| generated thumbnails | Covered as non-critical/regeneratable cache tests |
| required vs non-critical cache | Covered by criticality and missing-file behavior tests |
| transient artifact exclusion | Covered by `.enc`, `.download.jpg`, `.raw.*.jpg` tests |
| file size/checksum verification | Covered by manifest checksum tests |
| raw absolute local path healing/flagging | Covered by app-doc absolute healing and arbitrary absolute rejection tests |
| chat-media key/nonce/scheme atomicity | Covered by encrypted chat media validator tests |
| DB-resident post-media crypto fields | Covered by post-media validator tests |
| native writable-space preflight | Covered by injectable storage provider and preflight tests; true OS free-space device proof remains later acceptance if platform code is added |

## scope guard

Non-goals:

- No migration transfer protocol, local discovery/session endpoint, encrypted segment format, range/resume, relay/cloud/iCloud behavior, or local media server changes.
- No old-phone quiescing, final export mutation pause, durable cutover, old-phone migrated-out runtime gates, server cleanup, or new-active commit.
- No pending-work ownership/resume/fail semantics beyond classifying app-owned files and unportable paths.
- No UI progress/failure copy, wake lock, permission prompts, or user journey screens.
- No group device identity, retained group-key window proof, or NSE notification-preview proof beyond file/avatar manifesting.
- No broad media repository rewrite, generic backup framework, or change to normal `MediaFileManager` path semantics unless a direct MIG-005 regression requires it.
- No final device/simulator account-move acceptance.

Overengineering signals:

- Replacing existing media upload/download flows instead of adding a migration manifest layer.
- Scanning arbitrary filesystem paths outside app documents as migrated data.
- Treating cache thumbnails as critical without a rendering proof.
- Adding native platform free-space code before the injectable Dart storage provider is proven insufficient.

## accepted differences / intentionally out of scope

- MIG-005 does not close full migrated rendering. It proves the bundle can know which files are required and verified; MIG-007/MIG-012 must prove transferred/imported files render on devices.
- MIG-005 does not decide pending-work ownership. It only classifies app-owned pending-upload files and unsafe/unportable paths; MIG-010 owns resume-only-new-phone semantics.
- Generated thumbnails are allowed to be non-critical/regeneratable cache unless execution discovers a required thumbnail invariant.
- Native/OS free-space API proof is not required if execution uses an injectable provider and no native platform code is added. Device storage permission/failure UX remains later acceptance.
- Secure-storage enumeration remains MIG-003. MIG-005 may verify referenced media-key availability through MIG-003 contracts, but it must not reopen keychain registry scope.

## dependency impact

- MIG-007 depends on the file manifest item shape, checksums, sizes, criticality, and total byte counts before transporting the migration bundle.
- MIG-008 depends on verified DB, secure-storage, and file staging before safe activation/cutover.
- MIG-010 depends on pending-upload classifications and unsafe path flags before assigning queue ownership.
- MIG-011 depends on storage-preflight failure reasons and manifest progress totals for user-facing progress/failure UI.
- MIG-012 final acceptance depends on MIG-005 evidence but must add device/simulator proof that migrated files display and missing optional caches safely regenerate.

If MIG-005 becomes evidence-gated because app-owned roots or storage preflight cannot be represented without broad platform work, MIG-007 through MIG-012 should not proceed beyond planning against a provisional file-manifest contract.

## docs-to-update contract

After implementation evidence, update only current docs needed for durable project state:

- `Test-Flight-Improv/Move-Feature/01-move-account-to-new-device-pr.md`: rows for app-owned files, media roots, file size/checksum manifest, critical/non-critical cache, chat/post media atomicity, avatar/group-avatar coverage, raw absolute path handling, transient artifact exclusion, storage preflight, and later transfer/rendering residuals.
- `Test-Flight-Improv/codebase-test-inventory.md`: new MIG-005 account-migration file/storage tests and any affected media tests.
- `Test-Flight-Improv/test-gate-definitions.md` and `scripts/run_test_gates.sh`: only if completeness-check shows a new file needs explicit classification.
- Do not update the session breakdown to `closed` during implementation planning or coding. Closure status belongs to the later closure audit step after accepted execution/QA evidence.

## reviewer outcome

Reviewer verdict: sufficient as-is for MIG-005 planning; no structural blocker.

- Mandatory sections: present. The plan includes real scope, closure bar, source of truth, classification, problem statement, files to inspect, existing coverage, regressions to add first, implementation steps, risks, tests/gates, known-failure interpretation, done criteria, scope guard, accepted differences, dependency impact, and docs contract.
- Checklist coverage: sufficient. Every MIG-005 row item maps to a planned proof or explicit later-session accepted difference.
- Simulator gate need: no `$run-flutter-reliability-sims` gate is required for this session as written. The plan does not change real media transfer, multi-device rendering, notification delivery, lifecycle, or transport. If execution changes those surfaces, the plan already elevates optional breadth and requires reclassification.
- Stale assumptions: none found. Current code establishes durable relative roots and transient suffixes; storage-preflight absence is acknowledged as missing implementation rather than assumed present.
- Scope guard: sufficient. Transfer, cutover, pending-work ownership, UI, group/NSE continuity, and final acceptance are excluded.
- Minimum adjustment needed: none before execution.

## arbiter outcome

Final planning verdict: execution-ready.

Structural blockers remaining: none.

Incremental details intentionally deferred:

- Exact manifest field names and storage-headroom constants are implementation details as long as tests prove deterministic bytes/checksums/criticality/source identity and fail-closed insufficient storage.
- Exact storage provider implementation may stay Dart-injectable unless execution proves native free-space APIs are required.

Accepted differences intentionally left unchanged:

- No simulator/device media-rendering closure in MIG-005.
- No pending-work ownership/resume semantics in MIG-005.
- No migration transport/cutover/UI work in MIG-005.
- Generated thumbnails may be non-critical/regeneratable cache.

## Execution Progress

- 2026-06-07 01:18:35 CEST - MIG-005 implementation completed. Added account-migration file manifest models, builder, validator, storage preflight, and staged file-import cleanup helpers; added four focused account-migration application tests; updated the Move Account proposal, test inventory, and gate definitions with MIG-005 evidence and residual scope.
- 2026-06-07 01:18:35 CEST - Direct test evidence completed. The combined MIG-005 and affected media/avatar/post suite passed with `+126`.
- 2026-06-07 01:18:35 CEST - Gate evidence completed. `dart format`, `git diff --check`, `./scripts/run_test_gates.sh completeness-check`, `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh baseline`, and `graphify update .` passed.

## Execution Verdict

Verdict: accepted for MIG-005.

Evidence:

- New account-migration file tests passed:
  - `test/features/account_migration/application/migration_file_manifest_builder_test.dart`
  - `test/features/account_migration/application/migration_file_manifest_validator_test.dart`
  - `test/features/account_migration/application/migration_storage_preflight_test.dart`
  - `test/features/account_migration/application/migration_file_import_cleanup_test.dart`
- Affected existing direct tests passed in the same `flutter test` run:
  - `test/core/media/media_file_manager_test.dart`
  - `test/core/media/group_media_integrity_policy_test.dart`
  - `test/features/conversation/domain/repositories/media_attachment_repository_impl_test.dart`
  - `test/features/conversation/application/download_media_use_case_test.dart`
  - `test/features/posts/phase2/attach_post_media_use_case_test.dart`
  - `test/features/posts/improvement/post_media_upload_recovery_repository_test.dart`
  - `test/features/groups/application/group_avatar_storage_test.dart`
  - `test/features/settings/application/download_profile_picture_use_case_test.dart`
  - `test/features/settings/application/upload_profile_picture_use_case_test.dart`
  - `test/features/home/application/identity_avatar_resolver_test.dart`
- `dart format` completed on the new account-migration production and test files.
- `git diff --check` passed.
- `./scripts/run_test_gates.sh completeness-check` passed with `793/793` test files classified.
- `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh baseline` passed. Host baseline passed with `+105`; macOS `integration_test/loading_states_smoke_test.dart` passed with `+7`; macOS `integration_test/posts_phase1_fake_test.dart` passed with `+1`. Existing macOS deployment/linker warnings and `Failed to foreground app; open returned 1` appeared but the gate exited green.
- `graphify update .` passed after code/doc changes, rebuilding `graphify-out` with `91981` nodes, `162367` edges, and `4049` communities. Existing graphify skill/package version skew warning remained non-blocking.

Accepted differences:

- MIG-005 proves host-side app-owned file manifesting, media metadata validation, storage preflight, and staged file cleanup only.
- No network transfer, import rendering, cutover, pending-work ownership/resume semantics, UI, or simulator/device final account-move acceptance was implemented or claimed.
- Storage preflight remains provider-injected host logic; native OS free-space API proof remains later acceptance if native platform code is added.

## Closure Progress

- 2026-06-07 01:18:35 CEST - Completion auditor classification: `closed` for MIG-005 only. The session closure bar is met by focused host tests, affected direct regression tests, docs updates, baseline gate, completeness check, whitespace check, and graph update. The overall Move Account program remains open because MIG-006 through MIG-012 are still pending.
