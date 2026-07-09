# 229 - Cross-Track Media Download And Storage Controls

Status: execution-ready
Type: Feature Improvement
Spec: free-text intent — user-controlled automatic downloads and safe local media storage management for 1:1, discussions, and announcements
Classification: implementation-ready
Closure tier: host

## Planning Progress

| Time | Role | Files inspected | Decision/blocker | Next action |
|---|---|---|---|---|
| 2026-07-09 | Evidence Collector / Planner | direct `ChatMessageListener`, group `GroupConversationWired`, `download_media_use_case.dart`, `MediaAttachment`, `MediaFileManager`, settings preference patterns/UI/tests, connectivity dependency, relay media TTL | HEAD auto-downloads direct media after receipt and group media on load with no preference seam. A local `evicted` state is needed so clearing a copy does not immediately auto-download it again. | Add pure policy, wiring, destructive-file, and settings RED tests. |

## Problem And Evidence

- Behavior to improve: users need per-lane and per-media-type automatic-download controls, a storage inventory, and a safe “remove local copy but keep message” action.
- Impact: HEAD consumes data/storage automatically and conflates an app-private downloaded copy with a user-exported file or a deleted message.
- Confirmed current mechanism: direct receipt calls `_autoDownloadMedia` without a user policy at `lib/features/conversation/application/chat_message_listener.dart:180` and triggers it at `:631`.
- Confirmed current mechanism: group load calls `_downloadPendingMedia` at `lib/features/groups/presentation/screens/group_conversation_wired.dart:1344`; discussions and announcements share this wired screen.
- Confirmed current model gap: `MediaAttachment.downloadStatus` documents pending/downloading/done/failed at `lib/features/conversation/domain/models/media_attachment.dart:42` and has no user-evicted state.
- Confirmed file boundary: app-owned media lives under Documents `media/<scope>/<blob>` and `MediaFileManager.deleteFile` routes through ownership telemetry (`lib/core/media/media_file_manager.dart:273`).
- Confirmed product constraint: relay media expires after seven days (`go-relay-server/media.go:21`), so an evicted old copy may be permanently unavailable; UI must not promise cloud-style re-download.
- Confirmed settings mechanism: image/video preferences already use SecureKeyStore load/save and focused settings sheets (`lib/features/settings/application/image_quality_preference_use_cases.dart:6`, `lib/features/settings/presentation/screens/settings_wired.dart:215`).
- Existing coverage: direct/group download retry and media file manager tests cover transfer integrity and deletion primitives, not user policy or storage management.
- Missing coverage: policy decisions, three-lane wiring, manual-download bypass, eviction durability, arbitrary-path preservation, inventory totals, settings restart, and no-retry-loop behavior.
- Refuted findings: “clear cache can always re-download later” is refuted by the seven-day relay TTL.
- Unresolved findings: precise roaming detection is not exposed by current dependencies. This plan treats roaming as cellular and labels that accepted difference; a future native network-context owner is required before a distinct roaming toggle is claimed.
- Affected production, test, and gate files: new settings domain/application models; `ChatMessageListener`; `GroupConversationWired`; `MediaAttachment`; media repository/file manager; settings screen/wired/l10n; focused tests. No schema migration.

## Scope Contract And Guard

In scope:
- Add `MediaConversationKind {oneToOne, discussion, announcement}`, `MediaDownloadNetwork {wifi, cellular}`, versioned `MediaDownloadPreferences`, and pure `MediaDownloadPolicy.shouldAutoDownload`.
- Preserve HEAD defaults on upgrade: normal supported image/video/audio/file types remain enabled until the user changes a setting.
- Inject policy/network context into direct listener and shared group wired download entry points; derive discussion vs announcement from the existing group type.
- Add `kMediaDownloadStatusEvicted`; auto-download/recovery ignores it, while an explicit user retry may transition it to pending/downloading.
- Add `MediaStorageManager.inventory` and `clearLocalCopy`: delete only the app-owned file, clear `localPath`, persist `evicted`, and retain message, attachment descriptor, encryption metadata, bookmark, and caption.
- Add a Settings “Media & storage” route with lane/type/network controls and scoped storage totals/actions.

Must preserve:
- Direct/group content-hash, encryption, retry budget, terminal failure, and relay-ack behavior -> existing download tests; `GREEN sentinels`.
- Manual unavailable-media Retry remains user-authoritative even when auto-download is disabled -> TC-229-04.
- Message and sibling attachment persistence during local-copy eviction -> TC-229-06.

Hard `Do not`:
- Do not change upload quality, relay TTL, relay ack/delete, message delivery, group publish/auth, go-libp2p, or notification behavior.
- Do not interpret “Save to Photos/Files” as app-cache download; native egress is plan 227.
- Do not delete gallery/exported/arbitrary absolute files.
- Do not mark an evicted attachment `done`, auto-recover it on mount, or promise re-download availability.
- Do not add unbounded filesystem scans on startup or conversation build.

Deferred / accepted difference:
- Separate roaming detection/toggle -> future native network-context plan; cellular policy applies while roaming on HEAD-supported platforms.
- Per-chat exceptions -> lane library plans may add them after global/per-lane controls prove stable.
- Batch export -> plans 233/237/241; private-media forced download rules -> plans 234/238/242.

Dependencies:
- Plan 228 `MediaLibraryRepository` supplies bounded scope inventory metadata; plan 229 may land after 228 but adds no DB version.
- Existing SecureKeyStore, `connectivity_plus`, media download use case, and file ownership guards.

## Test Contract

| Case | Behavior | Named test/proof | Tier / fixture | HEAD -> GREEN | Mutation | Gate / registration |
|---|---|---|---|---|---|---|
| TC-229-01 | Versioned preferences decode missing/corrupt values to HEAD-compatible defaults and round-trip every lane/type/network choice. | `test/features/settings/domain/models/media_download_preferences_test.dart::codec preserves compatible defaults and every lane matrix value` | host unit | HEAD compile RED: model absent -> default matrix is enabled and valid custom JSON round-trips; unknown version fails safely to defaults | default normal media to disabled or omit announcement key -> TC-229-01 red | `flutter test test/features/settings/domain/models/media_download_preferences_test.dart`; AUTO (`feature-host-all`) |
| TC-229-02 | Pure policy distinguishes 1:1, discussion, announcement, media type, network, explicit/manual, protected, and evicted state. | `test/features/settings/application/media_download_policy_test.dart::policy decides all lane type and network combinations without transport side effects` | host unit / table fixture | HEAD compile RED -> exact matrix results; manual action bypasses only auto preference, never integrity/protection | ignore lane or allow protected/expired media -> TC-229-02 red | `flutter test test/features/settings/application/media_download_policy_test.dart`; AUTO (`feature-host-all`) |
| TC-229-03 | Direct live receipt consults policy before `downloadMedia`, while allowed default behavior remains one download. | `test/features/conversation/application/chat_message_listener_test.dart::auto download policy gates direct attachments before transfer` | host application / fake repo, gateway, policy | HEAD RED: listener has no policy -> denied call count zero and row remains pending; allowed call count one | call download before policy or drop contact/media context -> TC-229-03 red | `flutter test test/features/conversation/application/chat_message_listener_test.dart --plain-name 'auto download policy gates direct attachments before transfer'`; AUTO + add file remains in `ONE_TO_ONE_TESTS` |
| TC-229-04 | Shared group loader passes discussion/announcement kind; auto denial does not block an explicit retry. | `test/features/groups/presentation/group_conversation_wired_test.dart::download policy separates discussion announcement and manual retry` | widget/application host / fake group types and download function | HEAD RED: no policy seam -> denied auto calls zero in each kind; explicit retry calls once and preserves integrity gate | hardcode discussion or gate manual retry -> TC-229-04 red | `flutter test test/features/groups/presentation/group_conversation_wired_test.dart --plain-name 'download policy separates discussion announcement and manual retry'`; AUTO + existing `GROUP_TESTS` registration |
| TC-229-05 | Preference load/save reconstructs the matrix after a fresh settings mount and reports save failure without lying in UI. | `test/features/settings/presentation/screens/settings_wired_test.dart::media download settings persist and rollback failed saves` | widget host / fake SecureKeyStore | HEAD compile RED -> reopened screen shows saved matrix; thrown write restores prior value and visible error | keep optimistic toggle after failed write -> TC-229-05 red | `flutter test test/features/settings/presentation/screens/settings_wired_test.dart --plain-name 'media download settings persist and rollback failed saves'`; AUTO (`feature-host-all`) |
| TC-229-06 | Clear local copy deletes one owned file, persists evicted/null path, and preserves descriptor/message/key/bookmark/siblings. | `test/core/media/media_storage_manager_test.dart::clear local copy is narrow durable and non-destructive` | repository host integration / real temp files + `sqflite_common_ffi` DB helpers/repository + fresh repository handle | HEAD compile RED -> target file gone; all stated rows/fields/siblings survive; a freshly constructed repository remains evicted with null path | delete parent row/directory, make the update in-memory-only, or clear encryption/bookmark -> TC-229-06 red | `flutter test test/core/media/media_storage_manager_test.dart --plain-name 'clear local copy is narrow durable and non-destructive'`; AUTO (`core-host-all`; `test/core/**`) |
| TC-229-07 | Unknown, exported, gallery, and another attachment's path are never deleted. | `test/core/media/media_storage_manager_test.dart::clear rejects every non-owned or mismatched path` | host unit / real temp paths | HEAD compile RED -> typed rejected result and all files survive | broaden ownership to any absolute path -> TC-229-07 red | `flutter test test/core/media/media_storage_manager_test.dart --plain-name 'clear rejects every non-owned or mismatched path'`; AUTO (`core-host-all`) |
| TC-229-08 | Bounded inventory reports existing app-owned bytes by lane/type and ignores missing/exported/pending paths. | `test/core/media/media_storage_manager_test.dart::bounded inventory totals only existing owned media by scope` | host integration / fake paged library + real temp files | HEAD compile RED -> exact totals, next cursor, no scan beyond requested page | use descriptor size without file existence/ownership or unbounded load -> TC-229-08 red | `flutter test test/core/media/media_storage_manager_test.dart --plain-name 'bounded inventory totals only existing owned media by scope'`; AUTO (`core-host-all`) |
| TC-229-09 | Evicted rows do not auto-loop on reopen; explicit re-download truthfully settles done or terminal unavailable after relay expiry in both direct and group-backed lanes. | `test/features/conversation/integration/media_eviction_redownload_test.dart::direct evicted media waits for explicit retry` and `::group and announcement evicted media settle terminal expiry without an auto loop` | host integration / direct + shared group-wired fixtures, fake relay download outcomes, repository reopen | HEAD compile RED -> each reopened lane makes zero transfer; user action calls once; not-found becomes terminal without loop | classify evicted as pending/retryable failed or omit either lane fixture -> TC-229-09 red | `flutter test test/features/conversation/integration/media_eviction_redownload_test.dart`; add this exact shared file to `ONE_TO_ONE_TESTS`, `ONE_TO_ONE_HOST_TESTS`, and `GROUP_TESTS` |
| TC-229-10 | Existing encrypted download/promotion and group integrity behavior remain unchanged when defaults allow auto-download. | `test/features/conversation/application/download_media_use_case_test.dart` and `test/core/media/group_media_integrity_policy_test.dart` | `GREEN sentinel` / existing host fixtures | GREEN on HEAD -> remain GREEN with default preferences | bypass download/integrity use case from new policy wiring -> sentinels red | `flutter test test/features/conversation/application/download_media_use_case_test.dart test/core/media/group_media_integrity_policy_test.dart`; AUTO/curated existing gates |
| TC-229-11 | The local `evicted` status persists through DB map/copy paths but never enters attachment wire JSON. | `test/features/conversation/domain/models/media_attachment_test.dart::toJson produces camelCase keys without DB-only fields` | `GREEN sentinel` strengthened / existing model map+wire fixture with evicted control | Existing test is GREEN because `downloadStatus` is DB-only -> remains GREEN after adding the evicted constant and local transition | add `downloadStatus`/`evicted` to `toJson` or drop status from `toMap/fromMap` -> TC-229-11 red | `flutter test test/features/conversation/domain/models/media_attachment_test.dart --plain-name 'toJson produces camelCase keys without DB-only fields'`; AUTO (`feature-host-all`; `test/features/**`) |

### Test Notes

- TC-229-09 contains separate named 1:1 and group/announcement cases in one shared integration file and is registered in both owning arrays. If implementation must split the file, both replacement paths remain mandatory and keep the same lane registrations.
- Storage inventory is user-invoked and paged. No timer/startup scan is permitted.

## Implementation Steps

1. Snapshot `git status --short`; add preference/policy tests and lane wiring REDs.
2. Add SecureKeyStore codec/use cases and inject pure policy with default-compatible behavior. Stop-if any implementation needs a Bridge/relay API change.
3. Add `evicted` model/repository transition and narrow storage manager with ownership checks.
4. Add the Media & storage settings route and lane-specific download wiring; register shared integration tests in owning family arrays where required.
5. Run focused GREEN, direct/group download sentinels, named gates, representative mutations, and hygiene.

## Risks And Blind Spots

- Default changes could strand expected media -> TC-229-01/03 preserve HEAD defaults.
- Group/announcement discriminator could collapse -> TC-229-04.
- Eviction can become data loss after relay expiry -> UI/result copy and TC-229-09 are truthful; no cloud guarantee.
- Lifecycle / derived-state durability: TC-229-05/06/09 reopen fresh settings/repositories.
- Sibling-surface consistency: TC-229-03/04 cover all three lane kinds with deliberate shared policy.
- Destructive-action side effects: TC-229-06/07 assert files, rows, keys, bookmarks, messages, and siblings.
- Invariant re-verification under new transitions: evicted->manual downloading re-enters integrity/size/auth checks in TC-229-02/09.
- Local state must not become transport policy -> TC-229-11 pins DB-only serialization.

## Acceptance Gates

```bash
git status --short

# Causal RED; expect non-zero because preference/policy types are absent
flutter test test/features/settings/domain/models/media_download_preferences_test.dart --plain-name 'codec preserves compatible defaults and every lane matrix value'

# Focused GREEN
flutter test test/features/settings/domain/models/media_download_preferences_test.dart
flutter test test/features/settings/application/media_download_policy_test.dart
flutter test test/core/media/media_storage_manager_test.dart
flutter test test/features/conversation/integration/media_eviction_redownload_test.dart
flutter test test/features/conversation/application/chat_message_listener_test.dart
flutter test test/features/groups/presentation/group_conversation_wired_test.dart
flutter test test/features/settings/presentation/screens/settings_wired_test.dart
flutter test test/features/conversation/domain/models/media_attachment_test.dart --plain-name 'toJson produces camelCase keys without DB-only fields'

# Preservation and named gates; expect exit 0 and new target selection where registered
flutter test test/features/conversation/application/download_media_use_case_test.dart test/core/media/group_media_integrity_policy_test.dart
./scripts/run_test_gates.sh 1to1
./scripts/run_test_gates.sh groups
./scripts/run_host_test_gates.sh core-host-all
./scripts/run_host_test_gates.sh feature-host-all

flutter analyze
git diff --check
```

## Execution Interpretation And Done Criteria

- Expected RED: TC-229-01 compile-fails because `MediaDownloadPreferences` is absent.
- Green sentinel: existing direct encrypted download and group integrity policy tests.
- Pre-existing dirty tree / known failure: record at execution start.
- Environment blocker: none; roaming remains an explicit accepted difference, not an unreported missing proof.
- Scope drift: any relay/ack/transport, upload, native egress, or private-media wire change blocks this plan.

- [ ] Every behavior has a named test and honest HEAD state.
- [ ] Policy, lane wiring, settings durability, eviction cleanup, local-only serialization, and expiry truth pass.
- [ ] New headline integration tests are registered in the owning family arrays and selected.
- [ ] Representative policy/ownership/retry mutations re-red.
- [ ] Analyzer and diff hygiene pass without new issues.
- [ ] Scope guard and accepted roaming difference remain explicit.

## Handoff

- First causal RED command: `flutter test test/features/settings/domain/models/media_download_preferences_test.dart --plain-name 'codec preserves compatible defaults and every lane matrix value'`.
- Preservation command: `flutter test test/features/conversation/application/download_media_use_case_test.dart test/core/media/group_media_integrity_policy_test.dart`.
- Manual registration: add `test/features/conversation/integration/media_eviction_redownload_test.dart` to `ONE_TO_ONE_TESTS`, `ONE_TO_ONE_HOST_TESTS`, and `GROUP_TESTS`; unit/widget tests remain AUTO-globbed.
- Migration: none.
- Boundary closure: host only; no relay availability claim is made because expiry is a deterministic fake outcome here.
- Unresolved evidence: distinct roaming detection is deferred and must not be advertised.

## Execution Progress

| Time | Phase | Files | Last command/result | Current evidence | Decision/blocker | Next |
|---|---|---|---|---|---|---|
| - | not started | - | - | - | awaiting accepted plan | contract extraction |
