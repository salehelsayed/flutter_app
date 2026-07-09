# 228 - Shared Media Library And Local Viewer-State Persistence

Status: execution-ready
Type: New Feature
Spec: free-text intent — shared media galleries, bookmarks, and durable video resume state across 1:1, group, and announcement lanes
Classification: implementation-ready
Closure tier: device

## Planning Progress

| Time | Role | Files inspected | Decision/blocker | Next action |
|---|---|---|---|---|
| 2026-07-09 | Evidence Collector / Planner | media attachment schema/model/repository/helpers, messages/group_messages helpers, DB v69 local deletions, DB version/main migration chain, repository/migration tests | One shared attachment table already spans direct and group message IDs, but HEAD only loads by message IDs and has no bookmark/resume fields. DB v96 can add local-only state and scoped joins without wire changes. | Add migration and repository RED tests first. |

## Problem And Evidence

- Behavior to improve: lane-specific UI plans need one durable, paged source for media across a conversation, plus local bookmark and last-video-position state.
- Impact: HEAD can hydrate attachments only after loading message rows, so it cannot efficiently build Shared Media, stable cross-message swipe, batch selection, or persistent bookmarks/resume.
- Confirmed current mechanism: `media_attachments` has one global attachment row keyed by `id` and `message_id` (`lib/core/database/migrations/010_media_attachments.dart:18`).
- Confirmed current gap: `MediaAttachmentRepository` exposes only per-message and multi-message lookup (`lib/features/conversation/domain/repositories/media_attachment_repository.dart:11`); `dbLoadMediaForMessages` orders attachment-local rows but carries no parent/scope metadata (`lib/core/database/helpers/media_attachments_db_helpers.dart:113`).
- Confirmed persistence gap: current DB version is 95 (`lib/core/database/app_database_version.dart:1`); `media_attachments` has no `is_bookmarked` or `last_playback_position_ms` column.
- Confirmed preservation seam: group local deletions use durable message-id tombstones (`lib/core/database/migrations/069_group_message_local_deletions.dart:7`) and group reinsertion is rejected (`lib/core/database/helpers/group_messages_db_helpers.dart:21`). Library queries must not resurrect absent parents.
- Existing coverage: media helper/repository tests cover per-message hydration; migration 010 and `full_migration_chain_test.dart` cover the old schema. No test can fail for conversation-scoped pagination or local viewer state.
- Missing coverage: structural and production-SQLCipher v95->v96 migration/default/idempotency, direct/group scope isolation, stable cursor pagination, parent deletion, local-only serialization, and restart persistence.
- Refuted findings: a separate media table per lane is not required; the existing global attachment table and globally unique message IDs support scoped parent joins.
- Unresolved findings: N/A — bookmark and playback position are explicitly local-only and do not require product/wire policy.
- Affected production, test, and gate files: new migration 096; DB version and migration chain; `MediaAttachment`; media DB helpers/repository; new `MediaLibraryScope`, `MediaLibraryEntry`, `MediaLibraryCursor/Page`; structural migration/helper/repository/full-chain tests; dedicated SQLCipher device proof and exact discovery rule.

## Scope Contract And Guard

In scope:
- DB v96 adds `is_bookmarked INTEGER NOT NULL DEFAULT 0` and `last_playback_position_ms INTEGER NOT NULL DEFAULT 0` to `media_attachments`, with a justified bookmark lookup index.
- Add a shared `MediaLibraryRepository` capability implemented by `MediaAttachmentRepositoryImpl`.
- Page visual media for `direct(contactPeerId)` and `group(groupId)` scopes, returning attachment plus parent message id, sender, timestamp, caption, direction, and local deletion/download state.
- Stable newest-first cursor pagination using parent timestamp, message id, and attachment id; filters for image/video/both and bookmarked-only.
- Persist bookmark and clamped playback position locally; clear playback position when the attachment is deleted or playback completes.

Must preserve:
- Encryption metadata remains hydrated through the existing secure-store path -> existing repository tests plus TC-228-08.
- `MediaAttachment.toJson` remains wire-only and omits bookmark/playback state -> TC-228-02.
- Per-message attachment ordering and download/retry writes -> existing helper/repository `GREEN sentinels`.
- Local message deletion removes/omits its media without affecting sibling messages -> TC-228-07.

Hard `Do not`:
- Do not add bookmark/resume fields to direct or group encrypted payloads.
- Do not change message delivery, group permissions, relay retention, media encryption, go-libp2p, or download status policy.
- Do not preload an unbounded history; every library read must be paged with a fixed caller-supplied limit ceiling.
- Do not infer announcement/discussion authorization in the shared repository; lane UI plans supply the group scope and enforce their own policy.

Deferred / accepted difference:
- Gallery UI, batch actions, Go to message, and viewer list wiring -> plans 233, 237, and 241.
- Bookmark sync across a user's other devices is not included; owner is a future multi-device local-state plan because no such wire contract exists.
- Cache eviction/download controls -> plan 229; advanced player UI -> plan 230.

Dependencies:
- DB v95 at HEAD; this plan exclusively reserves DB v96.
- Existing `messages`, `group_messages`, and `media_attachments` schemas and SecureKeyStore hydration.

## Test Contract

| Case | Behavior | Named test/proof | Tier / fixture | HEAD -> GREEN | Mutation | Gate / registration |
|---|---|---|---|---|---|---|
| TC-228-01 | DB v96 is structurally wired, adds both local-state columns with zero defaults, preserves rows, and is run-twice idempotent. | `test/core/database/migrations/096_media_library_state_test.dart::v95 to v96 structurally preserves attachments and adds local state idempotently` | migration host / `sqflite_common_ffi` v95 structural fixture | HEAD RED: migration/file/columns absent -> PRAGMA shows both NOT NULL defaults; before/after row fields survive; second run and both registry arms pass structurally | omit one ALTER/default/registry arm or make second run non-idempotent -> TC-228-01 red | `flutter test test/core/database/migrations/096_media_library_state_test.dart`; AUTO (`test/core/**`); does not claim SQLCipher closure |
| TC-228-01D | The same v95->v96 migration and fresh/full chain preserve rows/state on the production `sqflite_sqlcipher` engine across repeated migration and close/reopen. | `integration_test/media_library_state_sqlcipher_proof_test.dart::v95 to v96 real SQLCipher preserves rows defaults reopen and full chain` | Android+iOS device proof / password-protected `sqflite_sqlcipher`, v95 upgrade DB + fresh-chain DB | HEAD device RED: migration/proof absent -> encrypted DB capability, PRAGMA/defaults, byte-bearing before/after rows, explicit state writes, second invocation, close/reopen mapping, `user_version=96`, and fresh/full-chain open pass | open plaintext, skip an upgrade/fresh registry arm, lose bytes/state, or fail rerun/reopen -> TC-228-01D red | `flutter test integration_test/media_library_state_sqlcipher_proof_test.dart -d "$ANDROID_DEVICE_ID"` and `-d "$IOS_DEVICE_ID"`; exact `ignored`/manual-SQLCipher discovery rule |
| TC-228-02 | Bookmark/resume map to DB but never serialize into media wire JSON. | `test/features/conversation/domain/models/media_attachment_test.dart::library state is local-only across map and wire serialization` | host unit | HEAD RED: fields absent -> `toMap/fromMap/copyWith` round-trip state while `toJson` omits both keys | add either key to `toJson` or drop it from `toMap` -> TC-228-02 red | `flutter test test/features/conversation/domain/models/media_attachment_test.dart`; AUTO (`feature-host-all`) |
| TC-228-03 | Direct library query returns only the named contact's visual parent rows and correct metadata, excluding deleted/hidden parents. | `test/core/database/helpers/media_library_db_helpers_test.dart::direct scope is isolated and excludes non-visible parents` | repository/DB host / `sqflite_common_ffi` structural fixture | HEAD compile RED: helper absent -> mixed-contact fixture returns only expected image/video entries and caption/sender/time | remove contact or deletion predicate -> TC-228-03 red | `flutter test test/core/database/helpers/media_library_db_helpers_test.dart --plain-name 'direct scope is isolated and excludes non-visible parents'`; AUTO (`test/core/**`) |
| TC-228-04 | Group library query returns only the named group and never returns a parent removed under the v69 local-deletion contract. | `test/core/database/helpers/media_library_db_helpers_test.dart::group scope respects group and durable local deletion boundaries` | repository/DB host / `sqflite_common_ffi` structural fixture | HEAD compile RED -> mixed groups plus a tombstoned/deleted message yield only live scoped parents | remove group predicate or use attachment-only rows without parent join -> TC-228-04 red | `flutter test test/core/database/helpers/media_library_db_helpers_test.dart --plain-name 'group scope respects group and durable local deletion boundaries'`; AUTO (`test/core/**`) |
| TC-228-05 | Cursor pagination is deterministic under equal timestamps and filter changes do not duplicate/skip entries. | `test/core/database/helpers/media_library_db_helpers_test.dart::newest-first cursor is stable across tied parent timestamps` | repository/DB host / `sqflite_common_ffi` structural fixture | HEAD compile RED -> concatenated pages equal one unique total order `(timestamp,messageId,attachmentId)` | page by offset or timestamp alone -> TC-228-05 red | `flutter test test/core/database/helpers/media_library_db_helpers_test.dart --plain-name 'newest-first cursor is stable across tied parent timestamps'`; AUTO (`test/core/**`) |
| TC-228-06 | Bookmark and playback position persist across a fresh repository; position clamps to media duration and completion resets to zero. | `test/features/conversation/domain/repositories/media_attachment_repository_impl_test.dart::bookmark and playback state survive reopen and clamp safely` | repository host / `sqflite_common_ffi` + fake SecureKeyStore | HEAD compile RED -> fresh instance returns bookmarked row and bounded position; completion clears only position | store negative/over-duration position or update by message instead of attachment -> TC-228-06 red | `flutter test test/features/conversation/domain/repositories/media_attachment_repository_impl_test.dart --plain-name 'bookmark and playback state survive reopen and clamp safely'`; AUTO (`feature-host-all`) |
| TC-228-07 | Deleting one attachment/message removes its library state while preserving sibling parent/attachment state. | `test/features/conversation/domain/repositories/media_attachment_repository_impl_test.dart::attachment cleanup removes local library state without sibling loss` | repository host / `sqflite_common_ffi` + real temp rows | HEAD RED: no state fields/library query -> deleted entry disappears; sibling bookmark/position remain | broad-update/delete by scope id -> TC-228-07 red | `flutter test test/features/conversation/domain/repositories/media_attachment_repository_impl_test.dart --plain-name 'attachment cleanup removes local library state without sibling loss'`; AUTO (`feature-host-all`) |
| TC-228-08 | Scoped pages hydrate encryption metadata through the existing key store and never log/return keys in preview diagnostics. | `test/features/conversation/domain/repositories/media_attachment_repository_descriptors_test.dart::media library page hydrates keys without exposing them in descriptors` | repository host / `sqflite_common_ffi` + fake SecureKeyStore/event sink | HEAD compile RED -> entry attachment is decryptable; descriptor/flow details contain no key/nonce | build entries directly from raw rows or log full map -> TC-228-08 red | `flutter test test/features/conversation/domain/repositories/media_attachment_repository_descriptors_test.dart`; AUTO (`feature-host-all`) |
| TC-228-09 | Structural fresh install and full upgrade chain include v96 exactly and expose the columns; TC-228-01D closes the same paths on encrypted storage. | `test/core/database/integration/full_migration_chain_test.dart::full chain includes media library state v96` | integration host / `sqflite_common_ffi` structural chain | HEAD RED: current version/chain stop at 95 -> fresh and upgraded structural DBs expose fields and current version 96 | bump constant without onCreate/onUpgrade call -> TC-228-09 red | `flutter test test/core/database/integration/full_migration_chain_test.dart --plain-name 'full chain includes media library state v96'`; AUTO (`test/core/**`) |

### Test Notes

- Direct visibility follows the existing messages visible-row predicate; group visibility requires a live parent row and therefore cannot surface an orphan attachment.
- Cursor fields are opaque to UI callers. Tests compare stable identity, not SQL implementation text.

## Implementation Steps

1. Snapshot `git status --short`; add migration, model-serialization, scoped-query, and persistence RED tests.
2. Add idempotent migration 096; wire onCreate/onUpgrade, DB constant, and full-chain assertions. Stop-if another accepted plan has claimed v96. Add the dedicated encrypted-engine TC-228-01D and exact manual discovery rule.
3. Add local-state fields to `MediaAttachment` map/copy paths but explicitly omit them from wire JSON.
4. Add shared scope/entry/page types, SQL helpers, repository capability, key hydration, and bounded writes.
5. Run focused GREEN, existing media repository sentinels, Android+iOS SQLCipher proof, core/feature gates, mutation re-red, and hygiene.

## Risks And Blind Spots

- Cross-table ID ambiguity -> TC-228-03/04 require a matching parent in exactly one scoped lane.
- Pagination churn -> TC-228-05 uses a three-part stable cursor.
- Local state leaking onto encrypted wire -> TC-228-02.
- Host SQLite can mask production cipher/plugin migration failures -> TC-228-01D is required and host rows make no SQLCipher claim.
- Lifecycle / derived-state durability: TC-228-06 reconstructs from a fresh repository/DB handle.
- Sibling-surface consistency: TC-228-03/04 prove direct and group scopes through the same capability; announcements intentionally reuse group scope in plan 241.
- Destructive-action side effects: TC-228-07 asserts removal and preservation.
- Invariant re-verification under new transitions: completion reset and fresh reopen re-clamp position in TC-228-06.

## Acceptance Gates

```bash
# Snapshot before execution
git status --short

# First causal RED; expect non-zero because migration 096 is absent
flutter test test/core/database/migrations/096_media_library_state_test.dart --plain-name 'v95 to v96 structurally preserves attachments and adds local state idempotently'

# Focused GREEN; expect exit 0 and zero failed tests
flutter test test/core/database/migrations/096_media_library_state_test.dart
flutter test test/core/database/helpers/media_library_db_helpers_test.dart
flutter test test/features/conversation/domain/repositories/media_attachment_repository_impl_test.dart
flutter test test/features/conversation/domain/models/media_attachment_test.dart
flutter test test/core/database/integration/full_migration_chain_test.dart

# Preservation sweeps; expect exit 0 and target discovery
flutter test test/core/database/helpers/media_attachments_db_helpers_test.dart
flutter test test/features/conversation/domain/repositories/media_attachment_repository_descriptors_test.dart
./scripts/run_host_test_gates.sh core-host-all
./scripts/run_host_test_gates.sh feature-host-all

# Production encrypted-engine closure; repeat on one physical Android and iOS target
flutter devices --machine
test -n "$ANDROID_DEVICE_ID"
test -n "$IOS_DEVICE_ID"
flutter test integration_test/media_library_state_sqlcipher_proof_test.dart -d "$ANDROID_DEVICE_ID"
flutter test integration_test/media_library_state_sqlcipher_proof_test.dart -d "$IOS_DEVICE_ID"
./scripts/check_reliability_simulation_discovery.sh --records-tsv | rg '^ignored[[:space:]]+ignored[[:space:]]+integration_test/media_library_state_sqlcipher_proof_test\.dart[[:space:]]+'

# Hygiene
flutter analyze
git diff --check
```

## Device/Relay Proof Profile

- Profile: single-device database proof repeated on one physical Android and one physical iOS device; no peer, network, or relay is involved.
- Boundary being proven: migration 096, defaults, row preservation, explicit bookmark/resume writes, idempotent repeat, close/reopen mapping, `user_version`, and fresh/full-chain creation on the production password-protected `sqflite_sqlcipher` engine.
- Live availability check: `flutter devices --machine`; export distinct `$ANDROID_DEVICE_ID` and `$IOS_DEVICE_ID`. A missing platform leaves its required row environment-blocked, not GREEN.
- Required setup: self-contained v95 and fresh encrypted database fixtures created/deleted by the proof; no production data, account, or relay credentials.
- Closure role: required migration/storage closure. Host `sqflite_common_ffi` tests prove SQL/query behavior but cannot substitute for cipher/plugin behavior.
- Registration: add an exact `integration_test/media_library_state_sqlcipher_proof_test.dart` case in `scripts/check_reliability_simulation_discovery.sh`, category/kind `ignored`, note `manual Android/iOS media-library-state SQLCipher migration proof outside reliability-sim`; no messaging family-array edit.
- Discovery command: the literal `--records-tsv | rg ...` command above must select exactly one record and no unclassified record for the path.
- Closure commands: the two platform-specific commands above; each exits 0 only after encrypted capability, v95 upgrade, repeated migration, reopen, and fresh/full chain pass.
- Relay profile: N/A; any messaging/relay dependency is scope drift.

## Execution Interpretation And Done Criteria

- Expected RED: TC-228-01 fails because migration 096 and both columns do not exist.
- Green sentinel: existing per-message media helper/repository and full migration-chain behavior stays green.
- Pre-existing dirty tree / known failure: record from execution snapshot.
- Environment blocker: missing physical Android or iOS target blocks that required TC-228-01D row; host structural tests do not replace it.
- Scope drift: any message payload, group permission, relay, or Go edit blocks completion and moves to the owning lane plan.

- [ ] Every behavior has a named causal test.
- [ ] DB v96 has structural host plus Android/iOS real-SQLCipher PRAGMA, before/after, run-twice, close/reopen, fresh-install, and full-chain proof.
- [ ] Representative cursor/wire/cleanup mutations re-red.
- [ ] Core and feature gates pass with semantic outcomes.
- [ ] `flutter analyze` has no new issues; `git diff --check` is clean.
- [ ] Scope Contract And Guard is respected.

## Handoff

- First causal RED command: `flutter test test/core/database/migrations/096_media_library_state_test.dart --plain-name 'v95 to v96 structurally preserves attachments and adds local state idempotently'`.
- Preservation command: `flutter test test/core/database/helpers/media_attachments_db_helpers_test.dart test/features/conversation/domain/repositories/media_attachment_repository_descriptors_test.dart`.
- Manual registration: exact `ignored`/manual-SQLCipher discovery rule for `integration_test/media_library_state_sqlcipher_proof_test.dart`; host tests remain auto-globbed.
- Migration: DB v96, structural host coverage plus required Android/iOS production-SQLCipher upgrade/reopen/full-chain proof.
- Boundary closure: two single-device encrypted-DB runs; no peer/network/relay claim.
- Unresolved evidence: none.

## Execution Progress

| Time | Phase | Files | Last command/result | Current evidence | Decision/blocker | Next |
|---|---|---|---|---|---|---|
| - | not started | - | - | - | awaiting accepted plan | contract extraction |
