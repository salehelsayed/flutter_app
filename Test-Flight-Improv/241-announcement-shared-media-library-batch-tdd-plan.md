# 241 - Announcement Shared-Media Library And Batch Actions

Status: execution-ready
Type: New Feature
Spec: free-text intent — browse and manage received announcement images/videos as a scoped library without weakening announcement authorization
Classification: implementation-ready
Closure tier: host

## Planning Progress

| Time | Role | Files inspected | Decision/blocker | Next action |
|---|---|---|---|---|
| 2026-07-09 | Evidence Collector | `graphify-arch` query; `group_info_screen.dart`; `group_conversation_wired.dart`; group/media repositories; plan 228 shared library contract | The shared attachment table can support an announcement-scoped library after plan 228, but Group Info has no entry and the current viewer is built from only one message's attachments | define the announcement UI, paging, cross-message viewer, and jump-to-message adapter over shared contracts |
| 2026-07-09 | Planner | plans 227-230 and 239; group local-delete tombstones; group gate/discovery scripts | Save/share/storage/delete primitives already have owners; this plan should compose them and must not create another DB or transport contract | lock batch semantics, old-message navigation proof, and announcement read-only sentinels |

## Problem And Evidence

- Behavior to improve: an announcement member or admin needs a Group Info media library for received images/videos, filters and bookmarks, cross-message browsing, Go to message, and explicit single/batch actions.
- Impact: today media can be rediscovered only by scrolling the conversation; actions cannot be applied consistently to several items and older media cannot be navigated as a durable collection.
- Confirmed current gap: `GroupInfoScreen` at `lib/features/groups/presentation/screens/group_info_screen.dart:22` renders group controls/members but no media-library destination.
- Confirmed current gap: `GroupConversationWired._onMediaTap` at `lib/features/groups/presentation/screens/group_conversation_wired.dart:4486` loads only the tapped message's attachments and passes paths/index to `FullScreenImageViewer`, so swiping cannot cross message boundaries.
- Confirmed current gap: `_loadMessages` at `lib/features/groups/presentation/screens/group_conversation_wired.dart:1310` initially loads the latest page, while `_scrollToHighlightedMessage` at `:3718` can scroll only to an item already in that page. A library jump to an older message therefore needs targeted/anchored loading, not just a route argument.
- Confirmed persistence seam: plan 228 adds a stable cursor-paged `MediaLibraryRepository` over the shared attachment table, scoped by group ID, plus local bookmark and playback state in DB v96. This plan reuses that contract and allocates no schema.
- Confirmed deletion seam: `GroupMessageRepository.deleteMessage` at `lib/features/groups/domain/repositories/group_message_repository.dart:71` writes the v69 local-deletion tombstone through `dbDeleteGroupMessage`; plan 239 owns whole-message Delete for me and its file cleanup.
- Confirmed storage seam: plan 229 owns `MediaStorageManager.clearLocalCopy` and the durable `evicted` state, which retains the message/descriptor/bookmark rather than pretending a cloud copy is guaranteed.
- Existing coverage: plan-228 TC-228-04/05 proves group-scope isolation and cursor stability; `announcement_happy_path_test.dart` proves a reader receives media; current Group Conversation tests prove announcement readers remain read-only while reactions remain available.
- Missing coverage: no Group Info entry, announcement-scoped paged grid, filter/selection state, cross-message typed viewer, old-message anchor load, batch result handling, or announcement authorization sentinel around those flows exists.
- Refuted findings: no new libp2p topic, envelope, recipient, relay, or encryption behavior is needed. The library operates on already-persisted local group messages/media and all outgoing actions delegate to existing destination contracts.
- Unresolved findings: N/A — internal batch Forward is explicitly outside in evidence-gated plan 251, and attachment-only deletion is deliberately not claimed.
- Affected production, test, and gate files: Group Info and Group Conversation routing, a new announcement media-library surface/controller, an anchored group-message repository query, shared typed viewer/action adapters, announcement library tests, and `GROUP_TESTS` registration.

## Scope Contract And Guard

In scope:
- Add a Media entry to announcement Group Info for both readers and admins. Route with a typed `MediaLibraryScope.group(groupId)` and re-load current group state on open.
- Render a lazy, cursor-paged newest-first grid with All, Images, Videos, and Bookmarked filters; each entry uses plan 228's parent metadata and never queries by attachment rows without a live matching group-message parent.
- Open plan 230's typed viewer with `MediaViewerItem` entries across messages, preserving the library cursor/filter and loading the next page near either edge. Viewer and grid use the same capability model.
- Implement Go to message using a repository query/window anchored by `(groupId, messageId)`. Merge/deduplicate that window into conversation state, render neighboring context, highlight exactly the target, and truthfully report locally deleted/unavailable targets.
- Add single and multi-select Save and external Share through plan 227, Bookmark through plan 228, Clear local copy through plan 229, and Delete for me through plan 239. Every operation re-loads current entries and returns item-level results.
- Batch Delete for me deduplicates selected parent message IDs and explicitly warns that every attachment on each selected message will be removed. Execute plan 239's whole-message tombstoning use case per parent; do not implement attachment-only delete.

Must preserve:
- Announcement readers remain unable to publish or quote-reply -> `test/features/groups/presentation/group_conversation_wired_test.dart::non-admin in announcement group cannot write` and `::stale writer callbacks cannot bypass read-only announcement mode`.
- Group-scope isolation, stable paging, local-only bookmark/resume serialization, and deleted-parent exclusion -> plan-228 TC-228-02/04/05.
- Viewer action eligibility and video controls remain type/capability driven -> plan 230 shared typed-viewer tests.
- Go authorization still rejects non-admin announcement publishing -> TC-241-11.

Hard `Do not`:
- Do not add a new DB migration, duplicate bookmark/playback fields, or query attachments without a live parent constrained to the exact group ID.
- Do not eagerly load the full media history, use offset-only paging, or replace the conversation list with a full reload that loses current scroll/focus state.
- Do not publish into the source announcement, change member/admin roles, or change Go group framing, topics, validators, recipient selection, retry, relay, or encryption behavior.
- Do not delete user-exported Photos/Files copies, sibling messages, or one attachment while leaving a replayable attachment-level deletion claim.
- Do not treat `evicted` as deleted or promise that an old evicted relay object can always be downloaded again.

Deferred / accepted difference:
- Album/document/audio/link tabs are outside this image/video plan and remain separate product work.
- Single-item internal Forward remains plan 240. Multi-source/batch Forward is evidence-gated plan 251 and is not invented by this execution-ready library plan.
- Attachment-only deletion remains deferred until a durable per-attachment anti-replay contract exists; this plan visibly performs whole-message Delete for me.
- A media item with a locally deleted/missing parent is omitted or shown unavailable; the library does not reconstruct history from relay state.

Dependencies:
- `Test-Flight-Improv/228-shared-media-library-bookmark-persistence-tdd-plan.md` supplies DB v96 and `MediaLibraryRepository/Scope/Entry/Page` plus bookmark/playback updates.
- `Test-Flight-Improv/227-received-media-native-egress-foundation-tdd-plan.md` supplies typed native Save/Share; `Test-Flight-Improv/229-cross-track-media-download-storage-controls-tdd-plan.md` supplies clear-local-copy/`evicted` semantics.
- `Test-Flight-Improv/230-shared-typed-media-viewer-tdd-plan.md` supplies the typed cross-item viewer; plan 239 supplies Delete for me. Plans 240/251 separately own single-item and batch internal Forward.
- No new migration and no Go/libp2p production change are permitted by this plan.

## Test Contract

| Case | Behavior | Named test/proof | Tier / fixture | HEAD -> GREEN | Mutation | Gate / registration |
|---|---|---|---|---|---|---|
| TC-241-01 | Announcement Group Info exposes Media to reader/admin and routes the exact group scope without exposing write controls | `test/features/groups/presentation/announcement_media_library_test.dart::group info opens the exact announcement media scope for reader and admin` | widget / `WidgetTester`, reader/admin group fixtures, route spy | HEAD has no Media entry -> both roles route with exact group ID while reader compose state stays absent | gate Media on `canWrite` or pass another group ID -> TC-241-01 red | `flutter test test/features/groups/presentation/announcement_media_library_test.dart --plain-name 'group info opens the exact announcement media scope for reader and admin'`; AUTO plus add file to `GROUP_TESTS` |
| TC-241-02 | Paged All/Image/Video/Bookmarked grids contain only live visual media from the source announcement and retain stable order across tied timestamps | `test/features/groups/presentation/announcement_media_library_test.dart::filters and cursor pages render one isolated stable media sequence` | widget/application host / fake paged `MediaLibraryRepository` with mixed-group/deleted/nonvisual rows | HEAD surface absent -> filter requests and rendered IDs match the exact scoped stable sequence without duplicates | use global scope, offset state, or append a duplicate cursor boundary -> TC-241-02 red | `flutter test test/features/groups/presentation/announcement_media_library_test.dart --plain-name 'filters and cursor pages render one isolated stable media sequence'`; AUTO plus `GROUP_TESTS` |
| TC-241-03 | Scrolling loads bounded pages and filter changes cancel/ignore stale page results | `test/features/groups/presentation/announcement_media_library_paging_test.dart::lazy paging ignores an old filter response and never loads the full history` | widget / controlled async repository, request-count spy | HEAD has no pager -> only initial/threshold page sizes are requested; late All response cannot pollute Videos | remove request generation token or fetch all rows -> TC-241-03 red | `flutter test test/features/groups/presentation/announcement_media_library_paging_test.dart`; AUTO plus `GROUP_TESTS` |
| TC-241-04 | Opening a grid item creates typed cross-message viewer items and swiping across a page boundary preserves identity/capabilities | `test/features/groups/presentation/announcement_media_library_viewer_test.dart::viewer navigates across source messages and loads the adjacent cursor page once` | widget / plan-230 viewer harness, paged entries from distinct messages | HEAD viewer receives one message's paths -> viewer order spans messages, selected attachment identity is stable, edge loads once | key viewer by local path/index only or reload the same edge twice -> TC-241-04 red | `flutter test test/features/groups/presentation/announcement_media_library_viewer_test.dart`; AUTO plus `GROUP_TESTS` |
| TC-241-05 | Go to message loads an old target outside the latest conversation page, merges a bounded context window, and highlights it exactly once | `test/features/groups/presentation/announcement_media_go_to_message_test.dart::old library target is anchor-loaded merged and highlighted without losing current rows` | widget/application host / repository with latest 50 plus older anchored window | HEAD `_scrollToHighlightedMessage` cannot find old target -> target and neighbors render, duplicates are absent, target highlight/scroll occurs after layout | call only `_loadMessages` latest page or replace rows without dedupe -> TC-241-05 red | `flutter test test/features/groups/presentation/announcement_media_go_to_message_test.dart --plain-name 'old library target is anchor-loaded merged and highlighted without losing current rows'`; AUTO plus `GROUP_TESTS` |
| TC-241-06 | Go to message for a tombstoned/missing parent reports unavailable and leaves conversation/list state intact | `test/features/groups/presentation/announcement_media_go_to_message_test.dart::deleted library target fails truthfully without recreating or scrolling another message` | widget/application host / absent target plus tombstone repository spy | HEAD has no library route -> typed unavailable result, no insert/save/replay request and no wrong highlight | synthesize a message from media metadata or fall back to nearest row as success -> TC-241-06 red | `flutter test test/features/groups/presentation/announcement_media_go_to_message_test.dart --plain-name 'deleted library target fails truthfully without recreating or scrolling another message'`; AUTO plus `GROUP_TESTS` |
| TC-241-07 | Bookmark toggles update only selected attachment and survive a library remount through plan-228 DB v96 | `test/features/groups/presentation/announcement_media_library_actions_test.dart::bookmark persists across remount and preserves sibling entries` plus plan-228 TC-228-01/06 | widget + repository sentinel / real SQLCipher proof inherited from 228 | HEAD has no bookmark/library state -> selected star survives remount and sibling remains unchanged | store selection only in widget state or update by message ID -> TC-241-07 red | `flutter test test/features/groups/presentation/announcement_media_library_actions_test.dart --plain-name 'bookmark persists across remount and preserves sibling entries' && flutter test test/core/database/migrations/096_media_library_state_test.dart`; AUTO plus `GROUP_TESTS`; DB v96 proof inherited from 228 |
| TC-241-08 | Batch Save/external Share revalidate the bounded selection, submit one ordered plan-227 native request for eligible items, and preserve per-item truth without deleting source rows | `test/features/groups/application/announcement_media_library_batch_actions_test.dart::batch egress returns item results and skips ineligible media without source mutation` | application host / real temp files, fake plan-227 gateway, mixed statuses | HEAD batch coordinator absent -> one gateway call receives the bounded ordered eligible subset; rejected items keep typed results; aggregate Share is `presented`/cancelled rather than recipient-delivered; source rows remain | loop one native call per item, exceed/reorder the bound, pass missing media, or label chooser presentation delivered -> TC-241-08 red | `flutter test test/features/groups/application/announcement_media_library_batch_actions_test.dart --plain-name 'batch egress returns item results and skips ineligible media without source mutation'`; AUTO plus `GROUP_TESTS` |
| TC-241-09 | Clear local copy marks only selected attachment evicted, removes its app-owned bytes, and preserves message, bookmark, library entry and siblings | `test/features/groups/application/announcement_media_library_batch_actions_test.dart::clear local copy preserves descriptor bookmark and siblings while marking evicted` | application host / plan-229 storage manager, real temp paths, repository reopen | HEAD clear-copy flow absent -> exact owned file gone; selected row remains evicted/bookmarked and siblings remain | delete the attachment/message or drop bookmark/encryption metadata -> TC-241-09 red | `flutter test test/features/groups/application/announcement_media_library_batch_actions_test.dart --plain-name 'clear local copy preserves descriptor bookmark and siblings while marking evicted'`; AUTO plus `GROUP_TESTS` |
| TC-241-10 | Batch Delete deduplicates parent IDs, confirms whole-message scope, tombstones each selected parent, removes all owned attachments, and preserves unselected/exported artifacts | `test/features/groups/application/announcement_media_library_batch_delete_test.dart::batch delete removes selected parent messages once and preserves siblings and exports` | application integration host / temp app-owned/exported files, real repository tombstone fixture | HEAD batch delete absent -> selected parents/files gone with one tombstone/use-case call per parent; sibling/export survive | delete by selected attachment ID only, double-delete same parent, or unlink exported path -> TC-241-10 red | `flutter test test/features/groups/application/announcement_media_library_batch_delete_test.dart`; AUTO plus `GROUP_TESTS` |
| TC-241-11 | Library/viewer/actions never grant source-announcement publish capability and Go still rejects a reader publisher | `test/features/groups/presentation/group_conversation_wired_test.dart::non-admin in announcement group cannot write` plus `go-mknoon/node/pubsub_test.go::TestIsAllowedWriter_AnnouncementMemberBlocked` | GREEN sentinel / Flutter widget and Go envelope authorization | GREEN on HEAD -> remains GREEN; library actions emit no source publish/inbox command | reuse `canWrite` as the media-action capability or weaken `isAllowedWriter` -> sentinel red | `flutter test test/features/groups/presentation/group_conversation_wired_test.dart --plain-name 'non-admin in announcement group cannot write' && (cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test ./node -run TestIsAllowedWriter_AnnouncementMemberBlocked -count=1)`; existing `GROUP_TESTS` / Go preservation |

### Test Notes

- TC-241-02's repository fake must reject a missing/incorrect `MediaLibraryScope`; returning a prefiltered list regardless of input would make the isolation assertion vacuous. Plan-228 real-SQLCipher scope tests remain the persistence boundary proof.
- TC-241-05 discriminates target-present, one anchor query, no duplicate message IDs, and exactly one highlight. A successful route push alone does not prove old-message navigation.
- TC-241-08 returns one item result per selection in deterministic input order while making at most one native call for the eligible subset. For external Share, `presented` proves only that the OS share surface opened; neither host nor device proof may claim recipient delivery.
- TC-241-10 groups selected attachment IDs by parent before confirmation. A message containing two selected attachments is deleted once, and all of that parent's attachments are named in the warning.

## Implementation Steps

1. Snapshot `git status --short`; verify plans 227-230 and 239 contracts are accepted; add TC-241-01 through TC-241-11 before production edits.
2. Add an announcement media-library route/controller over plan 228's scoped cursor API, with filter generations, bounded page loading, selection by durable attachment ID, and typed loading/error/empty states. Stop-if: implementation needs a second schema/library repository or an unbounded query.
3. Add the Group Info entry and typed viewer adapter; preserve exact group scope and selected identity across route/viewer/filter/page transitions.
4. Add a bounded group-message window query and merge/highlight navigation path in `GroupConversationWired`. Stop-if: target loading would bypass the v69 local-deletion tombstone or synthesize a row from attachment metadata.
5. Add one batch coordinator that re-loads selected entries, groups destructive actions by parent, and delegates to plans 227-229/239 without duplicating their policy or native behavior. Stop-if internal Forward semantics enter this plan.
6. Register all new headline announcement library suites in `GROUP_TESTS`; verify AUTO feature/core discovery still selects dependency suites.
7. Run causal RED, focused GREEN, DB v96 sentinel, group/read-only/Go preservation, named gates, analyzer, and diff hygiene.

## Risks And Blind Spots

- Cross-scope leakage from the shared attachment table -> TC-241-01/02 plus plan-228 TC-228-04 constrain exact group/live parent.
- Paging/filter races and list growth -> TC-241-02/03/04 require stable cursors, stale-response rejection, and bounded edge loading.
- Old-message jump may highlight the wrong row or resurrect a deletion -> TC-241-05/06 use target-discriminated anchor results and tombstone absence.
- Mixed egress outcomes can hide partial failure -> TC-241-08 returns item-level results rather than one optimistic boolean.
- Lifecycle / derived-state durability: TC-241-07/10 reopen the library/repository; plan 228 owns bookmark DB persistence and plan 229 owns durable evicted state.
- Sibling-surface consistency: TC-241-04 uses the shared typed viewer/action capabilities; plans 239/240 preserve bubble/viewer parity.
- Destructive-action side effects: TC-241-09/10 prove message/bookmark/sibling/export preservation and whole-message warning semantics.
- Invariant re-verification under new transitions: every action re-loads rows and current policy immediately before execution; TC-241-06/08 cover stale deletion and file eligibility.

## Acceptance Gates

```bash
# Snapshot before execution; record unrelated changes
git status --short

# Causal RED before production edits; expect non-zero because the announcement media-library route is absent
flutter test test/features/groups/presentation/announcement_media_library_test.dart --plain-name 'group info opens the exact announcement media scope for reader and admin'

# Focused GREEN; expect exit 0 and zero failed tests
flutter test test/features/groups/presentation/announcement_media_library_test.dart test/features/groups/presentation/announcement_media_library_paging_test.dart test/features/groups/presentation/announcement_media_library_viewer_test.dart test/features/groups/presentation/announcement_media_go_to_message_test.dart test/features/groups/presentation/announcement_media_library_actions_test.dart test/features/groups/application/announcement_media_library_batch_actions_test.dart test/features/groups/application/announcement_media_library_batch_delete_test.dart

# Shared DB v96 persistence/scope and deletion anti-resurrection; expect exit 0
flutter test test/core/database/migrations/096_media_library_state_test.dart test/core/database/helpers/media_library_db_helpers_test.dart
flutter test test/features/groups/domain/repositories/group_message_repository_impl_test.dart --plain-name 'IR-020 tombstone prevents replay save and unread resurrection'

# Named gates; expect every new announcement suite selected and zero failures
./scripts/run_test_gates.sh groups
./scripts/run_host_test_gates.sh feature-host-all

# Publisher authorization remains unchanged; expect package ok
(cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test ./node -run 'TestIsAllowedWriter_AnnouncementMemberBlocked|TestGroupTopicValidator_AnnouncementNonAdminRejected' -count=1)

# Hygiene; expect no new analyzer issues and no whitespace errors
flutter analyze
git diff --check
```

## Execution Interpretation And Done Criteria

- Expected RED: TC-241-01 fails because Group Info has no announcement Media route; TC-241-04/05 fail because the viewer and conversation loader have no cross-message/anchor contracts.
- Green sentinel: plan-228 DB/scoped-query tests, IR-020 tombstone tests, announcement reader compose tests, and Go publisher authorization stay green.
- Pre-existing dirty tree / known failure: record unrelated changes; do not edit the already-dirty `Test-Flight-Improv/00-INDEX.md` in this plan.
- Environment blocker: native Save/Share OS proof is inherited from plan 227; no simulator/device or real relay is required for this local library composition plan.
- Scope drift: a new schema/version, full-history eager load, attachment-only deletion, source-announcement publish, or Go wire/auth change blocks completion.

- [ ] Every behavior has a named test or justified inherited proof.
- [ ] Causal RED, focused GREEN, and representative mutation re-red are recorded.
- [ ] Plan 228 DB v96 migration/scope/persistence gates and plans 227/229/230 shared gates are green.
- [ ] Old-message navigation proves target-present/source-correct behavior beyond the latest page.
- [ ] Batch action summaries are item/target discriminated and destructive actions preserve siblings/exports.
- [ ] New headline files are registered in `GROUP_TESTS` and selected by the named groups gate.
- [ ] Go publisher sentinels, `feature-host-all`, and preservation tests pass.
- [ ] `flutter analyze` has no new issues; `git diff --check` is clean.
- [ ] Scope Contract And Guard is respected.

## Handoff

- First causal RED command: `flutter test test/features/groups/presentation/announcement_media_library_test.dart --plain-name 'group info opens the exact announcement media scope for reader and admin'`.
- Preservation command: `(cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test ./node -run 'TestIsAllowedWriter_AnnouncementMemberBlocked|TestGroupTopicValidator_AnnouncementNonAdminRejected' -count=1)`.
- Manual registration: add the seven new announcement library/action test files to `GROUP_TESTS`; AUTO feature discovery also selects them.
- Migration: none; reuse plan 228 DB v96 and require its real-SQLCipher migration/full-chain proofs before acceptance.
- Boundary closure: host-only announcement library composition; plan 227 separately owns Android/iOS Save/external-Share proof. This plan has no messaging destination or group live/replay boundary.
- Unresolved evidence: none for this scope. Execute after shared plans 227-230 and announcement plan 239; internal Forward remains outside in plans 240/251.

## Execution Progress

| Time | Phase | Files | Last command/result | Current evidence | Decision/blocker | Next |
|---|---|---|---|---|---|---|
| - | not started | - | - | - | awaiting accepted dependency contracts | contract extraction |
