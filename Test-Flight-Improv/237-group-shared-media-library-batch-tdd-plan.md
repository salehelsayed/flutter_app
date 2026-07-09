# 237 - Group Shared Media Library And Batch Actions

Status: execution-ready
Type: New Feature
Spec: free-text intent — add a paged discussion-group media library with cross-message viewing, batch actions, bookmarks, and Go to message
Classification: implementation-ready
Closure tier: host

## Planning Progress

| Time | Role | Files inspected | Decision/blocker | Next action |
|---|---|---|---|---|
| 2026-07-09 | Evidence Collector / Planner | plan-228 library contract, group conversation/info screens and wiring, group message repository, viewer, media attachment repository, delete/egress/forward/storage plans, group tests and gate scripts | HEAD loads media only for the currently loaded timeline page and has no group gallery. Existing highlight navigation cannot reach a message outside the first page. Shared repository/viewer/action primitives are deliberately owned by plans 228-230/235-236. | Land those primitives, then add a discussion-only route/controller and first widget RED. |

## Problem And Evidence

- Behavior to improve: a user needs one shared-media surface for a `GroupType.chat` group, with paged Images/Videos/Bookmarked views, cross-message viewer navigation, multi-select batch actions, and Go to message.
- Impact: media is currently discoverable only by scrolling message history; older media, saved/bookmarked items, and bulk retention/sharing operations are effectively inaccessible.
- Confirmed current timeline limit: `_loadMessages` in `lib/features/groups/presentation/screens/group_conversation_wired.dart:1310` requests a first page of 50 and builds `mediaMap` only for loaded messages. That is not a media-library query.
- Confirmed shared persistence prerequisite: plan 228 adds `MediaLibraryScope.group(groupId)`, stable cursor pages, parent metadata, bookmark/playback state, and group-local-deletion filtering. It explicitly defers gallery UI, batch actions, and Go to message to this plan.
- Confirmed navigation gap: `initialHighlightedMessageId` and `_scrollToHighlightedMessage` in `group_conversation_wired.dart:3714` scroll only when a widget key exists in the loaded `_messages`; an older library entry outside the first timeline page remains unresolved.
- Confirmed repository opportunity: `GroupMessageRepository.getMessage(id)` exists, and `getMessagesPage(groupId, limit, offset)` is bounded, but there is no indexed/bounded window-around-anchor method. Repeatedly loading all preceding pages would violate the bounded-library goal.
- Confirmed entry-point gap: `GroupInfoScreen`/wired exposes group information/actions but no shared-media route.
- Confirmed viewer gap: HEAD's `FullScreenImageViewer` only accepts path lists. Plan 230 owns typed `MediaViewerItem`, selection-aware actions, metadata, playback/resume, and backward compatibility; this plan must page those items across parent messages rather than create another viewer.
- Confirmed destructive semantic: plan 235's Delete for me is whole-message and tombstone-backed. Selecting two attachments from one message must therefore produce one explicit whole-message deletion, not two competing deletes.
- Confirmed storage semantic: plan 229 owns `MediaStorageManager.clearLocalCopy` and the durable `evicted` state. Remove local copy must retain the message/library entry and must not masquerade as Delete for me.
- Missing coverage: no discussion-only route, bounded group-scoped gallery, cross-message viewer paging, selection-capability intersection, batch egress/bookmark/delete/evict, fresh-mount bookmark proof, off-page Go-to-message anchor, or announcement isolation test exists.
- Refuted finding: loading all group messages and filtering their attachments is not an acceptable shortcut. Plan 228 defines cursor pagination specifically to avoid unbounded history loading and equal-timestamp duplication/skips.
- Unresolved finding: N/A. Exact production symbols from plans 228-230/235-236 are known execution dependencies; implementation stops and refreshes references if an accepted contract changes, but there is no product/source evidence gap.
- Affected production, test, and gate files: new group shared-media screen/wiring/controller, `GroupInfoScreen` entry point, a bounded group-message window query for Go to message, typed viewer/action adapters, group repository/presentation/integration tests, and `GROUP_TESTS` registration.

## Scope Contract And Guard

In scope:
- `GroupType.chat` only. Add a Shared media entry from group info and reject an attempted stale/deep route before any media query if the group is announcement, QA, dissolved, or unavailable.
- Page `MediaLibraryRepository` with `MediaLibraryScope.group(groupId)`, a fixed maximum page size, newest-first stable cursor, and Images/Videos/Bookmarked filters.
- Render a lazy grid with transfer/availability state; never decode full-resolution assets for thumbnails and never eagerly load all pages.
- Open plan 230's typed viewer at the selected entry, preserve cursor-backed cross-message order, and fetch the next/previous page without duplicate/skip when approaching a boundary.
- Single-select actions reuse plans 235/236. Multi-select exposes the safe intersection of selected-item capabilities.
- Batch Save/OS Share uses one bounded ordered plan-227 native request for the unique selection; batch Bookmark uses plan 228; batch Delete for me uses plan 235 with parent-message deduplication/confirmation; batch Remove local copy uses plan 229.
- Show truthful results at each dependency's actual boundary: Save may return per-item outcomes; external Share returns one aggregate `presented`/cancel/failure chooser outcome and never recipient-delivery success.
- Single-item Forward from the selected gallery/viewer item remains plan 236. Multi-item internal Forward is absent from this plan and evidence-gated in plan 250.
- Bookmark changes made in gallery or viewer update the same attachment-local state and survive a fresh screen/repository instance.
- Add a bounded `getMessagesAround(groupId, anchorMessageId, before, after)` repository capability (or equivalently indexed bounded window contract) so Go to message can load/merge an old anchor, preserve order, highlight once, and scroll after layout.
- After local delete, eviction, bookmark, download completion, or new eligible attachment, update only affected library identities or refresh the bounded current page; never leave phantom selected entries.

Must preserve:
- Plan 228 group scope, stable cursor, key hydration, deletion filtering, bookmark local-only serialization, and bounded limit.
- Plan 230 selected-item viewer behavior and legacy callers.
- Plan 235 durable local tombstone and whole-message Delete-for-me semantics.
- Plan 236 destination authorization/per-target re-encryption and forwarded marker semantics.
- Announcement reader/admin behavior and absence of a discussion shared-media query/route.
- Timeline focus/scroll position for ordinary conversation entry and live updates.

Hard `Do not`:
- Do not query or display this discussion library for `GroupType.announcement` or `GroupType.qa`; announcement shared media belongs to plan 241.
- Do not alter group message wire payloads, delivery, relay, encryption, group membership, Go bridge, or go-libp2p.
- Do not load all messages/attachments, use offset-only media pagination, or use timestamp alone as a cursor.
- Do not export/forward/decode missing, pending, failed, quarantined, expired, consumed, or protected items.
- Do not treat Remove local copy as message deletion, remove bookmarks on eviction, or treat Delete for me as attachment-only.
- Do not delete the same parent message twice when multiple selected entries share it.
- Do not claim bookmarks sync to other devices; plan 228 state is local.

Deferred / accepted difference:
- A global all-conversations media library, search/OCR, albums, duplicate detection, and cloud backup are out of scope.
- Multi-item internal Forward is deferred to evidence-gated plan 250; this plan neither chooses album-versus-individual semantics nor shows an active multi-select Forward action.
- Native Photos/Files/chooser behavior remains plan 227's device closure; this plan proves one bounded ordered request, item selection/eligibility, Save result mapping, and aggregate external-Share presentation without claiming recipient delivery.
- Explicit redownload/cache policy comes from plan 229; an evicted entry may remain visible but egress/forward stays disabled until a verified local copy exists.
- Announcement media library parity is intentionally not accepted here; plan 241 owns its read-only/admin action differences.

Dependencies:
- Plan 228 shared media-library/bookmark persistence (DB v96) and plan 229 cross-track download/storage controls.
- Plan 230 canonical typed viewer at `Test-Flight-Improv/230-shared-typed-media-viewer-tdd-plan.md`.
- Plan 235 group core actions and plan 236 group forwarding.
- Plan 227 native egress for Save/OS Share.
- Existing group info/conversation routes and group repository.

## Test Contract

| Case | Behavior | Named test/proof | Tier / fixture | HEAD -> GREEN | Mutation | Gate / registration |
|---|---|---|---|---|---|---|
| TC-237-01 | Group info exposes Shared media only for an active `GroupType.chat`; stale/deep access to other types rejects before querying. | `test/features/groups/presentation/group_shared_media_entry_test.dart::GML-01 shared media entry and route are discussion only` | host widget / chat, announcement, qa, dissolved fixtures + query spy | HEAD compile/widget RED: route/screen absent -> chat navigates; other rows have no entry and direct route makes zero library calls | remove type/status guard or check it after query -> GML-01 red | `flutter test test/features/groups/presentation/group_shared_media_entry_test.dart --plain-name 'GML-01 shared media entry and route are discussion only'`; add file to `GROUP_TESTS` |
| TC-237-02 | Images/Videos/Bookmarked tabs query only the named group with stable cursor pages and no cross-group/tombstoned parents. | `test/features/groups/presentation/group_shared_media_wired_test.dart::GML-02 filters page one scoped group and preserve cursor identity` | host widget/repository integration / mixed production-repository host SQLite fixture from plan 228 | HEAD compile RED: UI absent -> exact scope/filter/limit/cursor calls and identities render | omit scope/filter or replace cursor with offset -> GML-02 red | focused wired test; add file to `GROUP_TESTS`; plan-228 repository tests remain AUTO |
| TC-237-03 | Grid creation and scrolling are lazy/bounded and fetch one next page near the threshold without duplicate in-flight requests. | `test/features/groups/presentation/group_shared_media_screen_test.dart::GML-03 grid virtualizes and coalesces cursor page requests` | host widget / 3-page fake repository, build-count probes | HEAD compile RED -> initial child builds stay bounded; threshold creates one request; equal-timestamp identities appear exactly once | build all entries or remove in-flight coalescing -> GML-03 red | add file to `GROUP_TESTS` |
| TC-237-04 | Tapping any entry opens plan-230 viewer at that identity and navigation crosses parent-message/page boundaries in stable order. | `test/features/groups/presentation/group_shared_media_wired_test.dart::GML-04 typed viewer crosses message and cursor boundaries without skip or duplicate` | host widget / typed viewer harness, tied timestamps, image/video mix | HEAD RED: path-only single-message viewer -> selected id, adjacent order, next-page request, and per-page media type are exact | key pages by local path or fail to fetch at boundary -> GML-04 red | focused wired test; `GROUP_TESTS` |
| TC-237-05 | Multi-select action bar is the safe capability intersection for Save/Share/Bookmark/Delete/Evict; ineligible/missing/policy-denied selections fail closed and multi-item internal Forward is absent. | `test/features/groups/presentation/group_shared_media_screen_test.dart::GML-05 batch capabilities fail closed and batch forward stays deferred` | host widget / eligible, evicted, failed, abstract policy-denied, same-parent typed entries | HEAD compile RED -> only accepted batch actions render/enable, disabled reasons are truthful, and no multi-select Forward callback/label exists; no plan-238 concrete model is required | use capability union, trust first selection, or expose batch Forward -> GML-05 red | add file to `GROUP_TESTS` |
| TC-237-06 | Batch Save/OS Share sends one bounded ordered native request containing each unique eligible selected attachment once; Save maps per-item outcomes, while external Share exposes only aggregate chooser presentation/cancel/failure and never recipient delivery. | `test/features/groups/application/group_media_batch_actions_test.dart::GML-06 batch egress is one ordered request with truthful save and share outcomes` | host application / fake plan-227 service + real temp sources | HEAD compile RED -> one gateway call, stable unique item order, exact Save result map, aggregate Share `presented`/cancel/failure, zero “delivered” state, and untouched sources | call gateway per item, dedupe by path, label `presented` as delivered, or turn Share into per-item results -> GML-06 red | add file to `GROUP_TESTS` |
| TC-237-07 | Bookmark from grid/viewer is one shared attachment state, batch toggles are idempotent, and a fresh mount/repository sees the result. | `test/features/groups/integration/group_shared_media_bookmark_test.dart::GML-07 gallery and viewer share durable local bookmarks across remount` | host integration / production repository over `sqflite_common_ffi` v96 fixture + fresh widget/repository | HEAD compile RED: gallery absent -> exact attachment rows persist; sibling state and wire JSON remain unchanged | keep bookmark only in controller memory or update by message id -> GML-07 red | add file to `GROUP_TESTS`; plan-228 migration/repository AUTO sentinels |
| TC-237-08 | Batch Delete for me confirms the unique parent-message set, makes one delete call per message, removes every selected/sibling entry from those messages, and preserves others. | `test/features/groups/application/group_media_batch_actions_test.dart::GML-08 batch delete dedupes parent messages and explains whole message scope` | host integration / fake plan-235 service + same/different-parent selections | HEAD compile RED -> confirmation names unique message count; cancel no-op; confirm calls sorted unique ids once and clears selection | call by attachment id or delete same parent twice -> GML-08 red | focused application test; `GROUP_TESTS` |
| TC-237-09 | Remove local copy evicts only selected app-owned files while retaining message/library/bookmark state; unavailable egress stays disabled until verified redownload. | `test/features/groups/integration/group_shared_media_eviction_test.dart::GML-09 batch eviction retains entries bookmarks and redownload eligibility` | host integration / real temp media + fake plan-229 download manager, production repository over host SQLite | HEAD compile RED -> files/status transition to evicted, rows/bookmarks remain, later completed verified state re-enables actions | delete attachment row/bookmark or expose egress while evicted -> GML-09 red | add file to `GROUP_TESTS` |
| TC-237-10 | Go to message loads a bounded window around an old scoped anchor, merges deterministically, highlights once, and scrolls after layout; missing/deleted/wrong-group anchors fail truthfully. | `test/features/groups/presentation/group_shared_media_go_to_message_test.dart::GML-10 old media anchor loads bounded timeline window and highlights once` | host repository/widget integration / >50 messages, tied timestamps, cross-group/deleted ids | HEAD RED: current key only sees first page -> one bounded window query, exact ordered merge, one highlight/scroll; invalid anchors do not leak another group | scan every preceding page, accept wrong group, or duplicate anchor -> GML-10 red | add file to `GROUP_TESTS`; repository window test included |
| TC-237-11 | Delete/evict/bookmark/download/new-media updates remove stale selection/viewer identities without reloading unbounded history or disturbing unrelated entries. | `test/features/groups/presentation/group_shared_media_wired_test.dart::GML-11 incremental media changes reconcile identities without phantom selection` | host widget/application / controlled repository change stream/action completions | HEAD compile RED -> only affected ids change; selected deleted id closes/removes safely; unrelated scroll/cursor state remains | full reset on every event or retain deleted selected item -> GML-11 red | focused wired test; `GROUP_TESTS` |
| TC-237-12 | Existing announcement conversation/info authoring and read-only behavior remains unchanged and no announcement library query is made. | `test/features/groups/presentation/group_shared_media_entry_test.dart::GML-12 announcement sentinel has no discussion gallery route or query` | `GREEN sentinel` extension / announcement reader/admin fixtures | HEAD behavior GREEN/no route -> remains green; zero discussion-library calls | reuse route for all group types -> GML-12 red | `GROUP_TESTS`; existing announcement wired/send sentinels |
| TC-237-13 | The library is local/read-only with respect to messaging transport and multi-select does not dispatch internal Forward. | `test/features/groups/integration/group_shared_media_transport_boundary_test.dart::GML-13 library imports no bridge relay publish or group send primitive` | host source-contract / new library files | HEAD compile RED: files absent -> allowed repository/action-service imports only; no bridge/P2P/relay/direct send imports or multi-select forward dispatcher | call transport directly from gallery/controller or wire batch Forward -> GML-13 red | add file to `GROUP_TESTS` |

### Test Notes

- TC-237-02/03/04 use tied timestamps and identity triples so timestamp-only or offset pagination fails causally.
- TC-237-06 asserts exactly one native batch request. The OS chooser can prove presentation/cancel/failure, not whether any external recipient received or opened the media.
- TC-237-08 must fixture two selected attachments under one parent and another under a second parent. The confirmation and calls must count two messages, not three attachments.
- TC-237-10 should prove the repository query itself is bounded (requested before/after limit and SQL result count), not only that the widget happens to render few rows.
- Source-contract tests complement behavior tests; they do not replace plan-227/236 boundary proofs.

## Implementation Steps

1. Verify plans 227-230/235-236 have landed with the named types and DB v96 state; stop and refresh this plan if any accepted contract differs.
2. Snapshot `git status --short`; add TC-237-01 and run its named RED before creating production routes/widgets.
3. Add discussion-only group-info entry/routing and a wired shared-media controller that pages `MediaLibraryScope.group(groupId)` with bounded cursors and lazy grid rendering.
4. Adapt cursor pages to plan-230 typed viewer identities and implement coalesced adjacent-page fetching without path identity or unbounded preload.
5. Add selection state and batch orchestration adapters for plans 227/228/229/235, using capability intersection, identity deduplication, stable ordering, one bounded plan-227 egress request, Save per-item results, and aggregate Share presentation. Keep single-item plan-236 Forward in the viewer; do not add multi-select Forward.
6. Add the bounded group message window repository query and Go-to-message route result; merge/highlight only a validated same-group anchor.
7. Reconcile action/live outcomes by attachment/message identity while preserving scroll/cursor state; add announcement and transport guards.
8. Register new headline files in `GROUP_TESTS`; run focused GREEN, mutations, plan-228 persistence sentinels, group/feature gates, analyzer, and hygiene.

## Risks And Blind Spots

- Large histories can cause memory/jank -> TC-237-02/03/04 require bounded cursor pages, lazy children, and request coalescing.
- Equal timestamps can duplicate/skip items -> identity-triple fixtures in TC-237-02/04.
- Batch actions can use unsafe union eligibility -> TC-237-05 fails closed across every selected item.
- Whole-message deletion can surprise or double-delete -> TC-237-08 requires explicit unique-parent confirmation/dedup.
- Go to message can leak another group or spin through history -> TC-237-10 validates scope and bounded window.
- Lifecycle / derived-state durability: bookmarks/eviction are DB-backed and reconstructed fresh; ephemeral selection/cursor is intentionally route-local -> TC-237-07/09.
- Sibling-surface consistency: grid/viewer share attachment identity/bookmark/action capabilities -> TC-237-04/05/07.
- Destructive-action side effects: TC-237-08/09 distinguish whole-message delete from local-copy eviction and preserve siblings/rows as specified.
- Invariant re-verification under new transitions: TC-237-05/09/11 recompute capabilities after status/policy changes rather than trusting selection-time state.
- Announcement leakage through shared group scope -> TC-237-01/12 rejects before querying.

## Acceptance Gates

```bash
# Accepted dependency artifacts; final symbols are an execution stop before production wiring
test -f Test-Flight-Improv/227-received-media-native-egress-foundation-tdd-plan.md
test -f Test-Flight-Improv/228-shared-media-library-bookmark-persistence-tdd-plan.md
test -f Test-Flight-Improv/229-cross-track-media-download-storage-controls-tdd-plan.md
test -f Test-Flight-Improv/230-shared-typed-media-viewer-tdd-plan.md
test -f Test-Flight-Improv/235-group-received-media-core-actions-tdd-plan.md
test -f Test-Flight-Improv/236-group-received-media-forwarding-tdd-plan.md

# Snapshot before execution
git status --short

# First causal RED; expect non-zero because the discussion shared-media entry/screen do not exist
flutter test test/features/groups/presentation/group_shared_media_entry_test.dart --plain-name 'GML-01 shared media entry and route are discussion only'

# Focused GREEN
flutter test test/features/groups/presentation/group_shared_media_entry_test.dart
flutter test test/features/groups/presentation/group_shared_media_screen_test.dart
flutter test test/features/groups/presentation/group_shared_media_wired_test.dart
flutter test test/features/groups/presentation/group_shared_media_go_to_message_test.dart
flutter test test/features/groups/application/group_media_batch_actions_test.dart
flutter test test/features/groups/integration/group_shared_media_bookmark_test.dart
flutter test test/features/groups/integration/group_shared_media_eviction_test.dart
flutter test test/features/groups/integration/group_shared_media_transport_boundary_test.dart

# Shared persistence/action preservation
flutter test test/core/database/helpers/media_library_db_helpers_test.dart
flutter test test/features/conversation/domain/repositories/media_attachment_repository_impl_test.dart --plain-name 'bookmark and playback state survive reopen and clamp safely'
flutter test test/features/groups/domain/repositories/group_message_repository_impl_test.dart --plain-name 'IR-020 tombstone prevents replay save and unread resurrection'
flutter test test/features/groups/domain/usecases/send_group_message_use_case_test.dart --plain-name 'returns unauthorized for non-admin in announcement group'

# Registered family sweeps
./scripts/run_test_gates.sh groups
./scripts/run_host_test_gates.sh feature-host-all

# Hygiene
flutter analyze
git diff --check
```

## Execution Interpretation And Done Criteria

- Expected RED: TC-237-01 fails because the group shared-media route/screen does not exist.
- Green sentinels: plan-228 group scope/bookmark persistence, IR-020 local deletion, existing conversation scroll behavior, and announcement authorization/read-only tests remain green.
- Pre-existing dirty tree / known failure: record from execution-time snapshot; do not absorb unrelated changes.
- Execution stop rule: plans 227-230/235-236 must land before their production adapters are wired; do not clone or reinterpret their primitives. This known order does not make the plan evidence-gated.
- Environment blocker: N/A for this plan's closure. Native egress device behavior is inherited from plan 227; single-item Forward remains plan 236 and batch Forward is outside this closure.
- Scope drift: announcement/QA gallery, global library, unbounded history loading, message wire/transport, album protocol, or bookmark sync requires a new accepted plan.

- [ ] Every behavior has a named causal test or justified dependency-boundary proof.
- [ ] First RED, focused GREEN, and representative mutation re-red are recorded.
- [ ] Scope/filter/cursor and lazy-grid proofs pass on tied timestamps and multiple pages.
- [ ] Viewer crosses message/page boundaries by stable identity with no duplicate/skip.
- [ ] Batch actions use safe capability intersection and unique identities/parents; Save maps per-item results, external Share is one aggregate presentation result with no delivery claim, and multi-item internal Forward remains absent/deferred to plan 250.
- [ ] Bookmarks/eviction survive fresh state and Delete-for-me remains whole-message/tombstone backed.
- [ ] Go to message uses a bounded same-group window and highlights once.
- [ ] Announcement/no-transport sentinels and registered group/feature gates pass.
- [ ] `flutter analyze` has no new issues; `git diff --check` is clean.
- [ ] Scope Contract And Guard is respected.

## Handoff

- First causal RED command: `flutter test test/features/groups/presentation/group_shared_media_entry_test.dart --plain-name 'GML-01 shared media entry and route are discussion only'`.
- Preservation command: `flutter test test/features/groups/domain/repositories/group_message_repository_impl_test.dart --plain-name 'IR-020 tombstone prevents replay save and unread resurrection'`.
- Harness registration: add every new group shared-media test file to `GROUP_TESTS`; `feature-host-all` also discovers `test/features/**` automatically.
- Migration: none; reuse plan 228's DB v96 media-library/bookmark state and migration-069 group deletion tombstones.
- Boundary closure: host lane orchestration/UI/repository proof; native egress remains plan 227. Single-item real forward crypto remains plan 236; multi-item Forward is plan 250 and not claimed here.
- Unresolved evidence: none; any accepted dependency contract mismatch is handled by refreshing references before production wiring.

## Execution Progress

| Time | Phase | Files | Last command/result | Current evidence | Decision/blocker | Next |
|---|---|---|---|---|---|---|
| - | not started | - | - | accepted dependency contracts identified | stop before adapters until shared/group predecessors land | first causal RED, then dependency verification before wiring |
