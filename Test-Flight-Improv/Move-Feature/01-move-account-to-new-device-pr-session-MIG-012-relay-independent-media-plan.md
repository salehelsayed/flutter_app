# MIG-012 Relay-Independent Move Account Media Plan

Status: execution-ready; final acceptance remains evidence-gated on device logs.

## Planning Progress

- 2026-06-08 22:25 CEST - Arbiter completed. Files inspected: `pixel.log`, `iphone-13.log`, `lib/features/account_migration/application/account_migration_bundle_transfer.dart`, `lib/features/account_migration/application/migration_file_manifest_builder.dart`, `lib/features/account_migration/application/account_migration_transfer_flow.dart`, `lib/core/media/media_file_manager.dart`, `lib/features/conversation/application/download_media_use_case.dart`, `test/features/account_migration/application/account_migration_bundle_transfer_test.dart`, `migration_file_manifest_builder_test.dart`, `migration_file_manifest_validator_test.dart`, `Test-Flight-Improv/test-gate-definitions.md`, `scripts/run_test_gates.sh`. Decision: plan is implementation-ready, but physical/simulator acceptance is evidence-gated. Next action: implement TDD regressions.
- 2026-06-08 22:18 CEST - Reviewer completed. Finding: copying bytes is insufficient unless the DB snapshot also points to the copied relative path. Required correction: repair source DB media paths before snapshot export.
- 2026-06-08 22:08 CEST - Planner completed. Decision: keep normal live chat `media:download` unchanged; Move Account must stop relying on it for migrated historical media.
- 2026-06-08 21:58 CEST - Evidence Collector completed. Decision: logs show `chatMediaCount:5`, `fileEntryCount:3`, two blocking `missingRequiredFile` issues, transfer success, then iPhone `media:download` for migrated blobs.

## Real Scope

- Fix Move Account media packaging so migrated chat/group media is carried old-phone-to-new-phone in the encrypted migration bundle whenever the old phone has the bytes locally.
- Repair stale `media_attachments.local_path` values on the old phone before exporting the DB snapshot when the canonical app-owned file exists.
- Fail bundle assembly before transfer when critical migrated media bytes are not locally available.
- Do not change normal 1:1/group live media upload/download behavior, relay deletion policy, QR pairing, group membership migration, cutover, or MIG-006 release evidence.

## Closure Bar

- A Move Account transfer cannot succeed with blocking file-manifest issues for critical media.
- If a media row has a stale/legacy/missing `local_path` but the canonical app-owned file exists, the migrated DB snapshot references that canonical relative path and the file bundle includes the bytes.
- If the old phone truly lacks the media bytes, the old phone fails bundle assembly with `fileManifestBlockingIssues`; it does not create a successful transfer that depends on relay availability.
- After import, opening migrated 1:1/group chats with bundled media resolves local files without `MEDIA_DOWNLOAD_START`, `P2P_MEDIA_DOWNLOAD_REQUEST`, or `GO_BRIDGE_SEND cmd=media:download` for those migrated blob ids.

## Source Of Truth

- Current code and focused tests beat rollout prose.
- Named gate behavior comes from `Test-Flight-Improv/test-gate-definitions.md` and `scripts/run_test_gates.sh`; if they disagree, the script wins.
- User product rule: historical messages/media must not rely on relay retention after Move Account.

## Session Classification

Evidence-gated. The implementation and host tests are ready to write, but final end-to-end acceptance requires a physical or simulator Move Account run proving no post-move media relay downloads for migrated local media.

## Exact Problem Statement

Pixel assembled a migration bundle with 5 chat media rows but only 3 file entries, logged 2 blocking `missingRequiredFile` issues, still reported transfer success, and iPhone later fetched migrated images by blob id through `media:download`. This violates the product rule that messages/media should not live on relay and should not be required after delivery.

## Evidence

- `pixel.log:6476`: migration saw `chatMediaCount:5`.
- `pixel.log:6483`: file manifest had `issueCodes:["missingRequiredFile"]`, `blockingIssueCount:2`.
- `pixel.log:6484` and `pixel.log:6485`: degraded payload still built with `fileEntryCount:3`.
- `pixel.log:6580`: transfer still succeeded.
- `iphone-13.log:1273`, `iphone-13.log:1305`, `iphone-13.log:1333`, `iphone-13.log:1338`: iPhone downloaded migrated images through the P2P/relay media path after opening the chat.
- `migration_file_manifest_builder.dart` currently ignores media rows with empty `local_path` and only validates the stored path.
- `account_migration_bundle_transfer.dart` currently logs degraded file manifests but still returns a payload.
- `account_migration_bundle_transfer_test.dart` currently preserves the wrong behavior in `assembles bundle when legacy local media paths cannot be migrated`.

## Files And Repos To Inspect Next

- `lib/features/account_migration/application/account_migration_bundle_transfer.dart`
- `lib/features/account_migration/application/migration_file_manifest_builder.dart`
- `lib/features/account_migration/domain/models/migration_file_manifest.dart`
- `lib/core/media/media_file_manager.dart`
- Optional shared helper: `lib/core/media/media_file_path_convention.dart`
- `test/features/account_migration/application/account_migration_bundle_transfer_test.dart`
- `test/features/account_migration/application/migration_file_manifest_builder_test.dart`
- `test/features/account_migration/application/migration_file_manifest_validator_test.dart`
- `test/core/media/media_file_manager_test.dart`
- `Test-Flight-Improv/test-gate-definitions.md` only if new test files are added.

## Existing Tests Covering This Area

- `migration_file_manifest_builder_test.dart` covers app-owned file manifest inclusion, transient skips, checksums, and legacy app-document path healing.
- `migration_file_manifest_validator_test.dart` covers missing required files and metadata validation.
- `account_migration_bundle_transfer_test.dart` covers bundle assembly, secure values, receiver staging, and active cutover.
- The current `account_migration_bundle_transfer_test.dart` legacy-path test is stale and must be reversed because it permits degraded success.

## Regression/Tests To Add First

1. Flip `assembles bundle when legacy local media paths cannot be migrated` to expect `AccountMigrationBundleAssemblyException` with reason `fileManifestBlockingIssues` when no local app-owned media file can be found.
2. Add builder coverage for stale/unsupported `local_path` plus canonical 1:1 file present: manifest includes `media/<contactPeerId>/<blobId>.<ext>`, no blocking issue, and a DB path repair is planned.
3. Add builder coverage for group media: `group_messages.group_id` derives `media/<groupId>/<blobId>.<ext>`.
4. Add builder coverage for `local_path` null/empty with no canonical file: blocking `missingRequiredFile`, not silent skip.
5. Add bundle-source coverage that path repairs happen before snapshot export, so the exported DB snapshot has the canonical relative `local_path`.
6. Add runtime-read coverage that files disappearing or changing between manifest and payload read fail assembly instead of producing a degraded bundle.

## Step-By-Step Implementation Plan

1. Extract the media path convention into a shared deterministic helper, or expose equivalent path/extension helpers without `path_provider`, so migration and `MediaFileManager` cannot drift.
2. Replace `_queryTableIfExists(db, 'media_attachments')` for media with an enriched query that joins optional `messages` and `group_messages` tables and adds nullable owner fields such as `one_to_one_contact_peer_id` and `group_id`.
3. Extend `MigrationFileManifestBuilder` to evaluate candidate paths in order: stored app-owned path, canonical 1:1 path, canonical group path, and pending-upload path for `upload_pending` rows.
4. Make media rows with no resolvable local bytes produce blocking `missingRequiredFile`; do not silently skip empty `local_path`.
5. Return explicit path-repair decisions from the manifest build step: media row id, canonical relative path, old stored path, and reason.
6. Reorder `AccountMigrationProductionBundleSource.call`: build/validate the media file manifest and apply safe `media_attachments.local_path` repairs before database snapshot export.
7. If any blocking manifest issue remains after repair, throw `AccountMigrationBundleAssemblyException('file manifest has blocking issues ...')` before segment encryption or transfer.
8. Treat runtime read failures/checksum changes as hard assembly failures, preferably with `fileChangedWhileAssembling` for changed bytes and `fileManifestBlockingIssues` for missing required bytes.
9. Keep receiver `_writeImportedFiles` defensive: reject payloads whose manifest is invalid or whose file entries do not match the manifest.
10. Do not modify `downloadMedia`; it remains a live-chat fallback, not a Move Account correctness path.
11. Run `graphify update .` after code changes.

## Risks And Edge Cases

- A file can disappear between manifest creation and payload read; this must fail, not degrade.
- Path repair mutates old-phone DB before cutover. Limit repairs to app-owned/canonical paths whose bytes exist and pass size/hash checks.
- `upload_pending` rows should keep their retry status; only repair their local path.
- Group encrypted media needs both local bytes and crypto metadata; existing metadata validation remains required.
- Unsupported gallery/cache paths are not migrated unless the same bytes are already present under the app-owned canonical path.
- If old phone never downloaded an incoming image, Move Account should report that it cannot assemble a complete account bundle instead of relying on relay.

## Exact Tests And Gates To Run

- `flutter test test/features/account_migration/application/migration_file_manifest_builder_test.dart`
- `flutter test test/features/account_migration/application/migration_file_manifest_validator_test.dart`
- `flutter test test/features/account_migration/application/account_migration_bundle_transfer_test.dart`
- `flutter test test/core/media/media_file_manager_test.dart` if the shared path convention touches `MediaFileManager`
- `flutter test test/features/account_migration/application/migration_pending_work_manifest_builder_test.dart` if pending-upload path handling changes
- `./scripts/run_test_gates.sh feature-host-all` when time allows for the broader feature regression sweep.
- `./scripts/run_test_gates.sh completeness-check` only if new test files are added or gate classifications change.
- Physical/simulator evidence gate: Pixel old phone to iPhone new phone with known local 1:1 and group images. Pass only if post-import chat open shows no `MEDIA_DOWNLOAD_START`, no `P2P_MEDIA_DOWNLOAD_REQUEST`, and no `GO_BRIDGE_SEND` with `cmd:"media:download"` for migrated blob ids.

## Known-Failure Interpretation

- Existing TestFlight notes list unrelated baseline/posts/transport red gates. They must not be attributed to this work unless the changed files overlap.
- Direct account-migration application tests listed above should be green.
- If `completeness-check` is run, interpret any pre-existing unmatched-file failures against `Test-Flight-Improv/test-gates-reference.md`.

## Done Criteria

- The stale degraded-success test is reversed.
- New tests prove canonical path healing for 1:1 and group media.
- New tests prove missing local media blocks bundle assembly.
- Source DB path repairs occur before snapshot export, and exported DB rows reference bundled local files.
- Runtime file loss/change fails assembly.
- No implementation path calls relay/media download as part of Move Account packaging or import.
- `graphify update .` has been run after code changes.
- Physical/simulator logs prove migrated media opens from local files without post-move relay download.

## Scope Guard

- Do not change live chat media upload/download semantics.
- Do not implement relay retention/deletion policy in this session.
- Do not close the overall Move Account doc while MIG-006 remains deferred.
- Do not mark final acceptance complete from host tests alone.
- Stop and re-plan if media files are intentionally deleted immediately after delivery and no local owned copy exists, because that becomes a product-level retention decision rather than a migration packaging bug.
