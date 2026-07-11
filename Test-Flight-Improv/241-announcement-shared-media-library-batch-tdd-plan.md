# 241 - Announcement Shared-Media Library And Batch Actions

Status: ACCEPTED — implementation, required groups gate, and independent QA complete
Type: New Feature
Spec: free-text intent — browse and manage received announcement images/videos as a scoped library without weakening announcement authorization
Classification: accepted
Closure tier: host

## Planning Progress

| Time | Role | Files inspected | Decision/blocker | Next action |
|---|---|---|---|---|
| 2026-07-09 | Evidence Collector / Planner | Group Info/Conversation; plans 227-230/239; shared library repository | Group Info has no announcement media entry, and the timeline is not a durable cross-message library. | Compose existing persistence, viewer, and action boundaries. |
| 2026-07-10 | Planner refresh | Plan-228 owner/cursor contracts; group deletion and storage seams | Announcement media remains `MediaOwnerLane.group`; no third lane or migration is needed. | Require exact group scope and typed batch outcomes. |
| 2026-07-10 | Independent review revision | current library filter/SQL/cursor; DB v98 delete journal; Plan-235 coordinators; group route/highlight flow; Plan 237 | `MediaLibraryScope.group` is not received-only, deletion ownership and viewer evidence were stale, batch ceilings were incomplete, and Plan 241 duplicated Plan 237's anchor query. | Add an `incomingOnly` query dimension, rebase actions on current seams, and block execution until Plan 237 owns the shared library/navigation foundation. |

## Problem And Evidence

- Behavior to improve: announcement members and admins need a received-only shared-media library with filters, bookmarks, cross-message viewing, Go to message, and bounded single/multi-select actions.
- Impact: without a library, received announcement media is rediscovered only by scrolling. Without a direction filter, an admin's own outgoing announcement media can appear and be selected even though received-media actions reject outgoing parents.
- Confirmed entry gap: `GroupInfoScreen` at `lib/features/groups/presentation/screens/group_info_screen.dart:19-22` has no media-library entry.
- Confirmed received-only gap: `MediaLibraryFilter` at `lib/features/conversation/domain/models/media_library.dart:21-39` contains only kind/bookmark dimensions. Group SQL at `lib/core/database/helpers/media_library_db_helpers.dart:97-151` constrains owner, group, parent, tombstone, kind and bookmark, but never `p.is_incoming = 1`.
- Confirmed persisted authority: both direct and group parent tables persist `is_incoming`; `GroupMessage.isIncoming` is the domain direction bit at `lib/features/groups/domain/models/group_message.dart:60-61`. Current group received-media actions reject outgoing parents at `lib/features/groups/application/group_received_media_actions.dart:101-110`.
- Confirmed cursor impact: `_MediaLibraryCursor` at `media_attachment_repository_impl.dart:773-829` binds scope, kind and bookmark only. A new direction filter must be part of cursor identity while old default-filter cursors remain readable.
- Confirmed viewer baseline and remaining gap: `GroupConversationWired._onMediaTap` already opens `FullScreenTypedMediaViewer` with `MediaViewerItem` at `lib/features/groups/presentation/screens/group_conversation_wired.dart:4644-4703`; however, its item list is still limited to one parent message. The Plan-241 RED is an absent library/cross-parent adapter, not a path-only viewer.
- Confirmed navigation gap: `_onInfo` at `group_conversation_wired.dart:5039-5060` ignores the Group Info route result. `initialHighlightedMessageId` is immutable at `:185`, while `_highlightScrollResolved` is a once-per-State boolean at `:331` and `_scrollToHighlightedMessage` at `:3890-3900` only succeeds for a row already in `_messages`.
- Confirmed shared-navigation ownership conflict: Plan 237 already claims the shared `getMessagesAround(groupId, anchorMessageId, before, after)` repository capability, typed library result, bounded merge, and conversation highlight receiver. Plan 241 must consume that accepted contract rather than create a second query/route implementation.
- Confirmed batch ceiling: native Save/Share accepts exactly `1..kMaxMediaEgressItems`, where the maximum is 10 at `lib/core/media/received_media_egress.dart:5` and `:67-77`.
- Confirmed current egress qualifier: `GroupReceivedMediaActionsController` reloads exact group/parent/attachment state and checks incoming direction, visual type, MIME, integrity, lifecycle restriction, canonical resolution and file existence at `group_received_media_actions.dart:92-168`. Batch egress must extract/reuse this decision rather than partially reproduce it.
- Confirmed deletion owner: `GroupMessageRepositoryImpl.deleteMessage` at `lib/features/groups/domain/repositories/group_message_repository_impl.dart:477-480` only calls the older message tombstone/delete helper. Whole-message media deletion belongs to `DeleteGroupMediaForMeUseCase`, which implements `GroupMediaDeleteForMeCoordinator` over the DB-v98 `group_media_deletion_journal` and single-flight cleanup saga at `lib/features/groups/application/delete_group_media_for_me_use_case.dart:16-80`.
- Confirmed Clear limitation: `MediaViewerAction` has no Clear-local-copy action at `lib/shared/widgets/media/media_viewer_item.dart:20-25`. Plan 241 keeps Clear in the grid/selection surface and does not broaden the shared viewer enum.
- Existing coverage: Plan-228 repository tests lock owner/group/tombstone/cursor/page behavior; Plan-229 locks durable eviction; GMA-04 locks group egress qualification; GMA-07/GMA-08 and IR-020 lock atomic v98 deletion/restart/replay behavior; Plan-230 locks typed viewer actions.
- Missing coverage: incoming-only SQL/cursor compatibility, outgoing-admin exclusion, announcement route specialisation, shared-route result propagation, repeat/racy anchor requests, exact batch ceilings, ordered Bookmark/Clear results, and current v98 batch-delete composition.
- Refuted findings: HEAD is not path-only; Plan 239 does not own a separate deletion implementation; a UI fake cannot prove group/tombstone/direction SQL filtering; Plan 241 must not independently implement the anchor query already assigned to Plan 237.
- Unresolved findings: the exact landed Plan-237 type/file names cannot be source-verified until Plan 237 closes. This is the sole prerequisite blocker; the behavioral contract below is otherwise fixed.
- Affected files after unblocking: media-library model/repository/helper/cursor tests; landed Plan-237 group library/navigation seams; Group Info announcement routing; group batch qualification/action tests; `GROUP_TESTS` registration and l10n only where new copy is unavoidable.

## Graph Grounding Snapshot

- Graph fingerprint / freshness: `cbf4b6bc9b275d27`; graph reported `stale:lib/main.dart`, so all material conclusions above were re-verified in current source.
- Query / profile: `python3 graphify-arch/tdd_context.py query "Plan 241 announcement shared media library incomingOnly MediaLibraryScope media_library_db_helpers GroupMediaDeleteForMeCoordinator go to message GroupInfo route initialHighlightedMessageId batch actions" --profile review --budget 1000`.
- Anchors: `MediaLibraryScope` -> `lib/features/conversation/domain/models/media_library.dart`; `initialHighlightedMessageId` -> `group_conversation_wired.dart`; `groupMediaDeleteForMeCoordinator` -> production group-shell wiring.
- Surfaced proof/gate files: group conversation/info, media-library models, DB helper/repository, delete coordinator, and group tests.
- Graph gaps requiring source search: the compact result did not surface `incomingOnly` absence, cursor codec, GMA tests, or Plan-237 overlap; exact source/test searches supplied those facts.
- Reuse rule: anchors guide execution only; current source and the persisted Plan-237 closure remain authoritative.

## Scope Contract And Guard

In scope after Plan 237 closes:
- Reuse Plan 237's shared group-library screen/controller, typed cross-message viewer adapter, batch orchestration primitives, typed library result, `getMessagesAround` query, and conversation merge/highlight receiver. Plan 241 adds announcement-specific received-only policy and routing, not parallel architecture.
- Add `incomingOnly` to `MediaLibraryFilter`, defaulting to `false` for backward compatibility. Apply it as `p.is_incoming = 1` in SQL before keyset/`LIMIT` for either parent table when requested.
- Bind `incomingOnly` into opaque cursor identity. Encode new cursors with a version/dimension that carries the bit; decode existing v1 cursors as `incomingOnly=false`. Reusing a cursor across true/false must fail before SQL.
- Open the shared group library from announcement Group Info for both member and admin with exactly `MediaLibraryScope.group(groupId)` and `MediaLibraryFilter(..., incomingOnly:true)`. Q&A remains excluded; discussion behavior remains Plan 237's default `incomingOnly:false`.
- Keep the UI/controller fake strict only about caller inputs: scope, incoming-only filter, cursor, limit and generation. Prove owner/group/tombstone/direction exclusion with a production-repository fixture containing incoming/outgoing, other-group, tombstoned, direct and unresolved rows; never post-filter `MediaLibraryEntry` in the UI.
- Reuse the shared typed viewer across incoming announcement parents/pages. Save/Share/Bookmark/Delete/Info capability parity may appear in grid and viewer; Clear local copy is deliberately grid/selection-only because the shared viewer enum has no Clear action.
- Reuse Plan 237's typed `Library -> Group Info -> mounted Group Conversation` Go-to-message result. The exact group/target must flow back through the real route stack, invoke one bounded same-group anchor query, merge/dedupe with latest rows, and highlight once per request. Repeated targets, late latest-page/anchor races, resume and group changes must settle deterministically.
- Use one exact batch selection ceiling of 10 for Save, external Share, Bookmark, Clear local copy and Delete for me. Validate empty/11-item selections and more than 10 unique delete parents before any reload, native call, write, confirmation or delete dispatch.
- Extract/reuse the complete current group-media qualifier for batch Save/Share: exact group parent, incoming direction, no matching local-deletion tombstone, exact group-owned visual attachment, MIME agreement, integrity/display state, lifecycle restriction, canonical stored path and current file existence. Send the eligible subset in exactly one ordered Plan-227 call and merge typed denials/results back into original selection order.
- Implement Bookmark and Clear as true batch operations, returning one deterministic item result in first-selection order and continuing after an item failure. Bookmark uses current incoming group-owned identity; Clear delegates each qualified item to Plan-229 `MediaStorageManager` and retains descriptor/bookmark/message state.
- Implement Delete through `GroupMediaDeleteForMeCoordinator`/`DeleteGroupMediaForMeUseCase`, never raw `GroupMessageRepository.deleteMessage`. Deduplicate parents in first-selection order, cap at 10 unique parents, make cancellation a zero-op, serialize overlapping batches, continue after one parent failure, and report truthful per-parent dispatch/visibility results. One selected attachment deletes its whole parent, including unselected sibling attachments, after explicit warning.

Must preserve:
- Plan-237 discussion library remains available only to its accepted group types and uses `incomingOnly:false`; its outgoing media behavior is unchanged.
- Default `MediaLibraryFilter()` and existing v1 cursors remain compatible with pre-241 direct/discussion callers.
- Owner/group/tombstone isolation and SQL-before-limit behavior remain repository authority; direct/unresolved rows never become UI-filterable candidates.
- Save/Share keeps GMA-04 current-row qualification and one native boundary call; OS Share means presented/cancelled/failure, never recipient delivery.
- Bookmark remains local/replay-safe; Clear preserves message, descriptor, keys and bookmark while marking `evicted`; no implicit redownload is introduced.
- Delete retains DB-v98 GMA-07 atomic prepare, GMA-08 restart convergence, IR-020 replay suppression, and same-ID/direct/unresolved/export preservation.
- Announcement members remain unable to compose/quote/publish; admins do not gain received-media access to their own outgoing rows.
- Existing typed viewer/video behavior and library selection identity remain attachment/message/owner based.

Hard `Do not`:
- Do not execute Plan 241 before Plan 237 has accepted closure and the shared query/result/receiver symbols are verified in source.
- Do not implement another group-library screen, anchor SQL query, route-result type, or highlight receiver beside Plan 237.
- Do not create an announcement owner/scope, schema migration, direction column, UI post-filter, unbounded history scan, offset media pagination, or cursor that omits `incomingOnly`.
- Do not display or act on outgoing announcement parents, even for admins; do not trust selection-time `MediaLibraryEntry` as action authority.
- Do not exceed ten selected items/parents, split Save/Share into per-item native calls, or begin partial side effects before cap validation.
- Do not expose Clear local copy in `MediaViewerAction` in this plan; it is grid/selection-only.
- Do not call raw group message deletion, infer deletion journals from orphan rows, delete a selected attachment only, or delete exported copies.
- Do not publish/forward into the source announcement or change Go/libp2p, group authorization, relay, crypto, retry or wire formats.

Deferred / accepted difference:
- Audio/files/links, global search/OCR/albums/duplicate detection and cloud backup remain outside this visual-media plan.
- Single-item internal Forward remains plan 240; multi-item Forward remains plan 251. Neither appears in Plan-241 multi-select.
- Clear local copy is grid-only. Adding it to every typed viewer is a separate shared-viewer product change, not required for a usable batch storage action.
- Selection/cursor/highlight request state is route-local and need not survive process death; durable bookmark/eviction/deletion state reconstructs after restart through existing repositories.

Dependencies:
- Blocking: `Test-Flight-Improv/237-group-shared-media-library-batch-tdd-plan.md` must be accepted and landed first. It exclusively owns the shared group-library screen/controller, `getMessagesAround` repository capability, typed library result, and conversation merge/highlight receiver.
- Current source provides Plan-227 native egress, Plan-228 DB-v96 library/bookmark persistence, Plan-229 storage/eviction, Plan-230 typed viewer, and Plan-235 DB-v98 group deletion. Plan 239's announcement media policy is now present in source.
- Plan 241 adds no database migration and no device/relay/Go production boundary. Current identity DB stays v98.

## Test Contract

| Case | Behavior | Named test/proof | Tier / fixture | HEAD -> GREEN | Mutation | Gate / registration |
|---|---|---|---|---|---|---|
| TC-241-01 | Announcement Group Info exposes received media to member/admin only, passing exact group scope plus `incomingOnly:true`; Q&A remains excluded and no write control is enabled. | `test/features/groups/presentation/announcement_media_library_entry_test.dart::AML-01 member and admin open received only group library while qa stays excluded` | host widget / real Group Info route with strict library builder spy | After Plan 237, shared media is discussion-only -> announcement member/admin route with exact scope/filter; Q&A makes zero library calls | gate entry on `canWrite`, omit incoming-only, invent announcement scope, or admit Q&A -> TC red | focused selector; add file once to `GROUP_TESTS` |
| TC-241-02 | Production repository excludes outgoing admin rows before `LIMIT`, preserves owner/group/tombstone isolation, binds direction to cursors, and keeps default/v1 behavior backward compatible. | `test/features/groups/integration/announcement_media_library_repository_test.dart::AML-02 incoming only SQL and cursors exclude outgoing before limit without breaking defaults` | host repository integration / production v98 registry fixture with newer outgoing noise, older incoming rows, same-ID direct/unresolved, other-group and tombstoned parents | HEAD `incomingOnly` absent -> limit-1 still returns the eligible incoming row; true/false cursor reuse fails pre-SQL; default false includes incoming/outgoing and old v1 cursor decodes false | remove `p.is_incoming`, filter after limit, omit cursor bit, or reject all v1 cursors -> TC red | focused file; add once to `GROUP_TESTS` |
| TC-241-03 | All/Image/Video/Bookmarked paging always sends exact group/incoming-only/filter/cursor/`1..100` inputs, coalesces edge loads and ignores late old-filter/group results. | `test/features/groups/presentation/announcement_media_library_paging_test.dart::AML-03 pager preserves incoming only cursor identity across filters and races` | host widget/application / strict async fake that throws on wrong arguments and returns outgoing sentinel only when incoming-only is omitted | Announcement adapter absent -> every request is exact, 1/100 pass, 0/101 make zero fake calls, stale results never render | retain cursor across filter/group, drop incoming-only, issue duplicate edge load, or accept stale generation -> TC red | focused file; add once to `GROUP_TESTS` |
| TC-241-04 | Grid opens the shared typed viewer across incoming parent/page boundaries with stable identity and capability parity; Clear remains grid-only. | `test/features/groups/presentation/announcement_media_library_viewer_test.dart::AML-04 typed viewer crosses incoming parents while clear stays grid only` | host widget / landed Plan-237 viewer host with tied timestamps and mixed image/video entries | HEAD already has a typed one-parent conversation viewer, but no announcement library adapter -> exact selected identity and adjacent-page order work; viewer contains no Clear action | key by path/index, allow outgoing page, duplicate edge load, or add viewer Clear -> TC red | focused file; add once to `GROUP_TESTS`; Plan-230 viewer sentinels remain direct |
| TC-241-05 | A library Go-to-message target flows through the actual Library -> Group Info -> mounted Conversation route, performs one bounded anchor query, survives a late latest-page race/resume, and supports a second target in the same State with one highlight each. | `test/features/groups/presentation/announcement_media_go_to_message_test.dart::AML-05 production route repeats old targets safely across load race and resume` | host wired widget/repository / real route stack, controlled latest/anchor futures, app lifecycle events, >50 rows | Plan-237 shared receiver exists but announcement route absent -> exact typed result reaches conversation; merged rows retain live edge, each request highlights once and later request is not blocked by the prior boolean | pop only library, mutate only `initialHighlightedMessageId`, let latest load overwrite anchor, or retain once-per-State latch -> TC red | focused selector; add file once to `GROUP_TESTS`; GML-10 preservation required |
| TC-241-06 | Wrong-group, missing or tombstoned target, late result after group change, and failed anchor query settle unavailable without synthesizing/replaying/highlighting another row. | `test/features/groups/presentation/announcement_media_go_to_message_test.dart::AML-06 invalid or stale route targets fail closed without wrong highlight` | host wired repository/widget / typed invalid outcomes, tombstone and group-switch fixtures | Announcement route absent -> each invalid case makes no save/replay and preserves conversation/scroll; stale old-group completion is ignored | validate message ID without group, substitute nearest row, synthesize from media metadata, or apply old-group result -> TC red | focused selector; existing file registration |
| TC-241-07 | Multi-select uses capability intersection and one literal 10-item ceiling for every action; item 10 is accepted, item/unique-parent 11 is rejected before side effects; Forward is absent and Clear is grid-only. | `test/features/groups/presentation/announcement_media_library_actions_test.dart::AML-07 selection cap and capability intersection fail closed for every batch action` | host widget / mixed eligible/evicted/pending/outgoing selections with recording dispatchers | Batch policy absent -> exact actions/disabled reasons render; 10 dispatches, 11 leaves zero reload/native/write/confirm/delete calls | use union/first-item capability, cap only egress, expose Forward, or expose viewer Clear -> TC red | focused file; add once to `GROUP_TESTS` |
| TC-241-08 | Batch Save/Share reuses the complete current-row qualifier, rejects stale outgoing/tombstoned/wrong-group/MIME/integrity/lifecycle/file states, and sends at most ten unique eligible items in one ordered native call with truthful ordered results. | `test/features/groups/application/announcement_media_library_batch_actions_test.dart::AML-08 ten item egress requalifies every current row in one call and eleven is zero side effect` | host application / production group qualifier, temp canonical files, recording egress service and mixed collision states | Batch coordinator absent -> ten eligible items make exactly one call; eleven throws before reload/call; mixed denials stay in selection order and all-source rows/bytes remain | duplicate a partial qualifier, trust entry path/MIME/direction, call per item, reorder results, or permit 11 -> TC red | focused selector; add file once to `GROUP_TESTS`; GMA-04 sentinel required |
| TC-241-09 | Batch Bookmark and Clear process up to ten qualified incoming group items in order, continue after mixed failures, persist bookmark/evicted outcomes across remount, and preserve message/descriptor/keys/bookmarks/collision siblings. | `test/features/groups/application/announcement_media_library_batch_actions_test.dart::AML-09 bookmark and clear return ordered mixed results and preserve durable siblings` | host application/repository / production v98 repo, Plan-229 manager, canonical temp files, injected item failures and fresh instances | Batch local actions absent -> one result per selected id in input order; successful state persists, failed items remain selected/retryable, outgoing/direct/unresolved/other-parent state stays byte-equal | make actions singular, abort on first error, clear bookmark/row, mutate outgoing, or report failure as success -> TC red | focused selector; same file registration; Plan-228 replay and Plan-229 eviction sentinels required |
| TC-241-10 | Confirmed Delete is capped/deduped by first-seen parent, calls the existing v98 coordinator once per parent, deletes selected parents including unselected sibling attachments, returns deterministic partial results, serializes overlap, and preserves another parent/collision/export state. | `test/features/groups/application/announcement_media_library_batch_delete_test.dart::AML-10 v98 batch delete is capped whole message deterministic and overlap safe` | host integration / `DeleteGroupMediaForMeUseCase`, production v98 prepare+journal helpers, controlled cleanup/failures and real temp tree | Batch delete absent -> cancel zero-op; one selected + one unselected sibling are removed together; another parent survives; partial results keep first-parent order; concurrent second batch is busy/zero-call; 11 parents make zero calls | use raw repository delete, delete attachment-only, omit cap/single-flight, stop after first failure, or report cleanup completion optimistically -> TC red | focused file; add once to `GROUP_TESTS`; exact GMA-07/GMA-08/IR-020 sentinels required |
| TC-241-11 | Library/viewer/actions never grant source-announcement publish/Reply capability or touch messaging transport. | `test/features/groups/presentation/announcement_media_library_entry_test.dart::AML-11 library actions preserve announcement authorization and transport silence`; existing announcement read-only and Go validator tests | host widget/source boundary + Go GREEN sentinels | Library absent; authorization sentinels GREEN -> local actions make zero send/publish/inbox/forward calls and sentinels stay GREEN | reuse `canWrite` for library eligibility, import/call delivery seams, or weaken Go validator -> TC red/sentinel red | focused selector plus exact Flutter/Go preservation commands; existing/new `GROUP_TESTS` registration |

### Test Notes

- TC-241-02 must prove SQL-before-limit causally: insert enough newer outgoing admin rows to fill the requested page ahead of an older incoming row, request `limit:1`, and require that incoming row. A UI fake cannot substitute for this fixture.
- Cursor compatibility: existing v1 cursor payloads have no direction bit and decode only as `incomingOnly:false`; newly encoded cursors carry the direction dimension. Any true/false signature mismatch throws before `dbLoadMediaLibraryPage` is called.
- TC-241-03's fake validates request construction only. It must not pretend to prove owner/group/tombstone filtering from `MediaLibraryEntry`, which lacks those parent facts.
- TC-241-05/06 exercise the production route chain, not a direct construction of `GroupConversationWired(initialHighlightedMessageId: ...)`. Use request generations so old route/load completions cannot win after a repeat target or group change.
- The shared selection maximum is literally 10. Deduplicate attachment IDs before cap validation, then validate unique delete parent IDs separately; over-cap rejection precedes every read/write/native/confirm/delete side effect.
- TC-241-08 should extract a reusable current-row qualification decision from `GroupReceivedMediaActionsController` and keep GMA-04 green. Share success is aggregate `presented`; Save may have per-item native outcomes.
- TC-241-09 local batches are deliberately non-atomic across items: each item has its own typed result, processing continues after failure, and only failed IDs remain selected. This is truthful retry behavior, not an all-or-nothing claim.
- TC-241-10 reports local message visibility/dispatch truth, not that every cleanup byte was synchronously removed. Durable GMA-08 reconciliation owns deferred file/key cleanup.

## Implementation Steps

1. Preflight Plan 237. Require a persisted accepted status plus landed shared group-library screen/controller, typed `GroupSharedMediaLibraryResult`/Go-to-message result, `getMessagesAround` repository capability, and conversation merge/highlight receiver. Stop and refresh exact symbol references if its accepted contract differs; do not implement substitutes in Plan 241.
2. Snapshot `git status --short` and an execution-time analyzer baseline. Add TC-241-02 first, then the announcement entry/paging/navigation/action tests before production edits.
3. Add backward-compatible `MediaLibraryFilter.incomingOnly`, cursor identity/version compatibility, repository propagation and SQL-before-limit direction filtering. Extend the real fixture with explicit incoming/outgoing parent direction.
4. Add announcement policy/routing over the landed Plan-237 shared library: exact group scope, incoming-only filter for every tab/page, member/admin entry, Q&A exclusion, typed viewer adapter and grid-only Clear.
5. Wire Plan-237's typed library result through Group Info back to the mounted conversation. Reuse its bounded anchor query/merge receiver; add request generations/repeat-target reset only if the accepted shared receiver does not already close race/resume/group-change behavior. Stop-if: work would create a second anchor query/result/receiver.
6. Extract the existing complete group-media egress qualifier and build bounded batch Save/Share around one Plan-227 call. Add ordered batch Bookmark/Clear results with current incoming parent revalidation.
7. Add bounded batch Delete over `GroupMediaDeleteForMeCoordinator` with pre-confirm cap validation, parent dedupe/order, batch single-flight, per-parent isolation and post-call visibility checks. Reuse DB v98; add no persistence schema.
8. Register new Plan-241 files once in `GROUP_TESTS`; run focused causal tests, Plan-237/GMA/IR/l10n/authorization sentinels, representative mutations, groups gate, analyzer comparison and diff hygiene.

## Risks And Blind Spots

- Outgoing admin media can fill a page and hide incoming rows -> TC-241-02 requires SQL-before-limit direction filtering.
- Cursor compatibility can break existing direct/discussion libraries -> TC-241-02 covers default false, old v1 decode and true/false rejection.
- UI-only filtering could leak wrong group/tombstone rows -> TC-241-02 uses production repository; TC-241-03 limits the fake to caller-contract proof.
- Shared library/navigation duplication could diverge between discussion and announcement -> Plan-237 prerequisite/ownership guard plus GML-10 preservation.
- Late route/latest/anchor results can highlight the wrong group or block a second request -> TC-241-05/06 use request generations, repeat targets, resume and group changes.
- Batch over-cap/partial execution can mutate before refusal -> TC-241-07/08/10 require cap validation before all side effects.
- Destructive Delete can misreport deferred cleanup or remove the wrong parent -> TC-241-10 plus GMA-07/GMA-08/IR-020 distinguish immediate local visibility from durable cleanup convergence.
- Lifecycle / derived-state durability: bookmark/eviction/deletion rebuild from DB; route selection/cursor/highlight state is intentionally ephemeral. TC-241-05 covers resume while mounted, TC-241-09/10 cover fresh instances.
- Sibling-surface consistency: TC-241-04/07 lock grid/viewer actions and the deliberate grid-only Clear difference.
- Invariant re-verification under new transitions: TC-241-08/09/10 reload exact parent/attachment state at action time; stale outgoing/tombstoned/group-changed selections fail closed.

## Gate Cadence

- While prerequisite-blocked, run no Plan-241 implementation gates; only verify Plan-237 closure/source preflight.
- Per-plan closure after unblocking: focused Plan-241 tests, exact Plan-237 navigation and Plan-228/229/230/235 preservation sentinels, l10n integrity, the curated `groups` lane, and Go authorization.
- Do not run `core-host-all`, `feature-host-all`, or full `host-all` for Plan 241. Full `host-all` runs once after the ordered library/batch wave (`233 -> 237 -> 241`) and once at final media rollout/release closure.
- Shared tests outside group globs: run core media-library and l10n sentinels directly; new Plan-241 files must each be present once in `GROUP_TESTS`.

## Acceptance Gates

```bash
# Prerequisite/source ownership — these fail today and keep Plan 241 blocked
rg -qi '^Status: (CLOSED|accepted)|Final verdict:.*accepted|accepted closure' Test-Flight-Improv/237-group-shared-media-library-batch-tdd-plan.md
rg -q 'getMessagesAround' lib/features/groups/domain/repositories/group_message_repository.dart
rg -q 'GroupSharedMediaLibraryResult|GroupSharedMediaGoToMessage' lib/features/groups/presentation/screens/*.dart
rg -q 'GML-10 old media anchor loads bounded timeline window and highlights once' test/features/groups/presentation/group_shared_media_go_to_message_test.dart
test "$(rg -o 'currentIdentityDatabaseVersion[[:space:]]*=[[:space:]]*[0-9]+' lib/core/database/app_database_version.dart | rg -o '[0-9]+$')" -eq 98

# Snapshot and accepted analyzer baseline before Plan-241 edits
git status --short
flutter analyze --no-pub > /tmp/plan241-analyze-before.txt 2>&1 || true
sed -E 's/:[0-9]+:[0-9]+/:LINE:COL/g' /tmp/plan241-analyze-before.txt | rg -v '^(Analyzing|[[:space:]]*[0-9]+ issues found|No issues found|$)' | sort -u > /tmp/plan241-diagnostics-before.txt || true

# First causal RED after adding the named repository test; expect non-zero because incomingOnly is absent
flutter test test/features/groups/integration/announcement_media_library_repository_test.dart --plain-name 'AML-02 incoming only SQL and cursors exclude outgoing before limit without breaking defaults'

# Focused GREEN; expect exit 0 and zero failed tests
flutter test test/features/groups/integration/announcement_media_library_repository_test.dart
flutter test test/features/groups/presentation/announcement_media_library_entry_test.dart
flutter test test/features/groups/presentation/announcement_media_library_paging_test.dart
flutter test test/features/groups/presentation/announcement_media_library_viewer_test.dart
flutter test test/features/groups/presentation/announcement_media_go_to_message_test.dart
flutter test test/features/groups/presentation/announcement_media_library_actions_test.dart
flutter test test/features/groups/application/announcement_media_library_batch_actions_test.dart
flutter test test/features/groups/application/announcement_media_library_batch_delete_test.dart

# Shared repository/navigation/action preservation
flutter test test/core/database/helpers/media_library_db_helpers_test.dart --plain-name 'group scope is owner isolated and respects durable deletion tombstones'
flutter test test/core/database/helpers/media_library_db_helpers_test.dart --plain-name 'keyset cursor binds scope filters and enforces the 100 row ceiling'
flutter test test/features/groups/presentation/group_shared_media_go_to_message_test.dart --plain-name 'GML-10 old media anchor loads bounded timeline window and highlights once'
flutter test test/features/groups/application/group_received_media_actions_test.dart --plain-name 'GMA-04 egress reloads exact group owner and delegates only currently eligible media'
flutter test test/features/groups/application/delete_group_media_for_me_use_case_test.dart --plain-name 'GMA-07 delete prepare is exact group scoped atomic and reaction safe'
flutter test test/features/groups/integration/group_received_media_delete_replay_test.dart --plain-name 'GMA-08 self contained journal saga converges per item across every restart boundary'
flutter test test/features/groups/domain/repositories/group_message_repository_impl_test.dart --plain-name 'IR-020 tombstone prevents replay save and unread resurrection'
flutter test test/features/conversation/domain/repositories/media_attachment_repository_impl_test.dart --plain-name 'ordinary replay preserves local viewer state and path while explicit clears win'
flutter test test/l10n/l10n_integrity_test.dart

# Every new headline file is selected exactly once by the group lane
for f in \
  test/features/groups/integration/announcement_media_library_repository_test.dart \
  test/features/groups/presentation/announcement_media_library_entry_test.dart \
  test/features/groups/presentation/announcement_media_library_paging_test.dart \
  test/features/groups/presentation/announcement_media_library_viewer_test.dart \
  test/features/groups/presentation/announcement_media_go_to_message_test.dart \
  test/features/groups/presentation/announcement_media_library_actions_test.dart \
  test/features/groups/application/announcement_media_library_batch_actions_test.dart \
  test/features/groups/application/announcement_media_library_batch_delete_test.dart; do
  test "$(rg -F -c "\"$f\"" scripts/run_test_gates.sh)" -eq 1
done
./scripts/run_test_gates.sh groups

# Announcement publisher authorization remains unchanged
flutter test test/features/groups/presentation/group_conversation_wired_test.dart --plain-name 'non-admin in announcement group cannot write'
(cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test ./node -run 'TestIsAllowedWriter_AnnouncementMemberBlocked|TestGroupTopicValidator_AnnouncementNonAdminRejected' -count=1)

# Baseline-qualified analyzer and hygiene; existing repository findings are accepted, new normalized diagnostics are not
flutter analyze --no-pub > /tmp/plan241-analyze-after.txt 2>&1 || true
sed -E 's/:[0-9]+:[0-9]+/:LINE:COL/g' /tmp/plan241-analyze-after.txt | rg -v '^(Analyzing|[[:space:]]*[0-9]+ issues found|No issues found|$)' | sort -u > /tmp/plan241-diagnostics-after.txt || true
comm -13 /tmp/plan241-diagnostics-before.txt /tmp/plan241-diagnostics-after.txt > /tmp/plan241-new-diagnostics.txt
test ! -s /tmp/plan241-new-diagnostics.txt
git diff --check
```

## Execution Interpretation And Done Criteria

- Expected preflight now: Plan-237 closure/source checks fail, which is the documented prerequisite blocker. Do not create Plan-241 tests or production code until they pass.
- First causal RED after unblocking: TC-241-02 fails because `incomingOnly` is not a `MediaLibraryFilter`/cursor/SQL dimension.
- Other causal REDs: announcement entry/adapters are absent; production route result cannot traverse Group Info; batch Bookmark/Clear/Delete contracts and exact announcement selection cap are absent.
- Green sentinels: Plan-237 GML-10, Plan-228 owner/cursor/replay, Plan-229 eviction, Plan-230 viewer, GMA-04/GMA-07/GMA-08, IR-020, l10n and announcement Go authorization remain green.
- Pre-existing dirty tree / known failure: preserve unrelated edits. Repository-wide analyzer has a known non-zero baseline; only normalized diagnostics added after the execution snapshot fail Plan 241.
- Environment blocker: N/A after Plan 237 lands. Native Save/Share and SQLCipher v98 boundaries are inherited; no simulator/device/relay proof is repeated.
- Scope drift: parallel Plan-237 implementation, a new query/result/receiver, schema/version change, UI direction filtering, >10 selection, viewer Clear, raw group delete, attachment-only delete, or transport change blocks completion.

- [x] Plan 237 is accepted/landed first and its exact shared symbols replace any provisional names in this plan.
- [x] TC-241-01 through TC-241-11 have causal or preservation evidence and representative mutation re-reds.
- [x] Incoming-only is SQL-before-limit, cursor-bound and backward compatible; outgoing admins, wrong groups, tombstones, direct and unresolved rows are absent.
- [x] The real Library -> Group Info -> Conversation path handles old/repeat/invalid targets, races, resume and group changes without duplicate/wrong highlights.
- [x] Every multi-select action accepts at most 10 and cap+1 causes zero side effects; Clear is grid-only and Forward absent.
- [x] Save/Share makes one native call after complete current-row qualification; Bookmark/Clear results are ordered/mixed/retryable.
- [x] Delete uses `DeleteGroupMediaForMeUseCase` on the current DB-v99 schema with cancellation, whole-message sibling behavior, parent dedupe/cap, partial isolation, overlap safety and other-parent preservation.
- [x] New files are registered exactly once in `GROUP_TESTS`; focused, preservation, `groups`, l10n, Go, analyzer-diff and hygiene gates pass.
- [x] Scope Contract And Guard is respected.

## Handoff

- Current action: wait for/execute Plan 237 first; Plan 241 is no longer parallel-safe with Plan 237 because both otherwise own the same shared query/result/receiver.
- First causal RED after unblocking: `flutter test test/features/groups/integration/announcement_media_library_repository_test.dart --plain-name 'AML-02 incoming only SQL and cursors exclude outgoing before limit without breaking defaults'`.
- Preservation command: `flutter test test/features/groups/application/group_received_media_actions_test.dart --plain-name 'GMA-04 egress reloads exact group owner and delegates only currently eligible media'`.
- Manual registration: add the eight named Plan-241 test files once to `GROUP_TESTS`; core/l10n tests remain direct preservation commands.
- Migration: none is intended, but current source is already DB v99 rather than this plan's v98 assumption; refresh inherited migration/version references after Plan 237 closes. `incomingOnly` itself changes query/filter/cursor behavior, not schema.
- Boundary closure: host-only after Plan 237. Existing Plan-227 native and Plan-235 SQLCipher/device proof are referenced, not rerun.
- Aggregate cadence: no per-plan full `host-all`; run it after `233 -> 237 -> 241` and at final rollout.
- Unresolved evidence: exact accepted Plan-237 symbol names until its closure lands.

## Execution Progress

| Time | Phase | Files | Last command/result | Current evidence | Decision/blocker | Next |
|---|---|---|---|---|---|---|
| 2026-07-10 | tdd-exec prerequisite preflight | Plan 237 status/result, shared query/result sources, GML-10 path, DB version | exact Plan-241 prerequisite block: 2 pass, 3 fail | dirty source contains provisional query/result types; Plan 237 still says implementation not started; GML-10 is absent; DB is v99 rather than the plan's v98 assertion | BLOCKED; no Plan-241 RED or production edit permitted | execute and accept Plan 237, then refresh Plan 241 against its landed symbols and DB-v99 contract |
| 2026-07-10 | tdd-exec resume audit | Plan 237 durable result, shared query/result sources, current GML-10 test, DB version | acceptance check FAIL; source symbol checks PASS; contracted GML-10 name FAIL with an unaccepted current equivalent present; DB remains v99 | Plan 237 is implemented and host-green but persists `ready_for_full_orchestrator`; its own nested-route criterion remains unchecked pending independent counterexample review | BLOCKED; the prerequisite has advanced but is not accepted | finish Plan-237 orchestrated acceptance, then refresh Plan 241 against the accepted route proof and DB-v99 contract |
| 2026-07-11 | lean TDD execution | incoming-only repository/cursor/SQL, shared group library/routing/actions, eight Plan-241 tests, gate registration | focused/preservation/Go/analyzer/mutation/Graphify PASS; `groups` FAIL twice | Plan 237 is accepted; implementation is coherent and attributable; required curated lane has unrelated committed baseline failures outside Plan-241 scope | BLOCKED on mandatory gate | repair the four current groups-lane baseline failures in their own scope, rerun `groups`, then resume Plan 241 for finalization |
| 2026-07-11 | superseding closure | Plan-254 group-send repair plus Plan-241 anchor/tombstone hardening (`f243b2788`, `61cda3415`, `e3e5bfa7d`) | final causal set 14/14; scoped analyzer and diff check clean; `groups` PASS with 1,926 Flutter tests plus Go bridge/node; independent QA ACCEPTED | all previously blocking group-send failures and the final anchor/tombstone counterexamples are closed on the committed tree | ACCEPTED | maintenance only; reopen on a demonstrated regression |

## Execution Result

- Final verdict: `blocked`
- Execution mode: `tdd-exec (helper-assisted)`; one read-only gap audit and one isolated repository/SQL slice. The controller owned UI/application integration, failure triage, review, gates, and verdict.
- Assurance mode: full orchestrator remained recommended for the cross-layer/destructive scope; the user explicitly repeated `$tdd-exec`, so implementation proceeded leanly without recreating that workflow.
- Independent QA: not performed; the mandatory groups gate did not resolve, so the QA-only tier was not eligible.
- Substitutions: accepted Plan-237 symbols are now authoritative; current GML selectors are `GML-10 production nested route consumes bounded anchor result` and `GML-10R GML-13W nested repeats scroll without local delivery bypass`; current identity DB is v99, with no Plan-241 migration.
- Production changed: `MediaLibraryFilter.incomingOnly`; SQL-before-limit direction filtering; v2 cursor direction identity with v1/default-false compatibility; typed DB closure forwarding; shared library All filter/incoming-only policy; announcement Group Info/conversation routing; ordered Bookmark/Clear; incoming-only, bounded, single-flight whole-parent Delete; announcement Forward suppression.
- Tests added: the eight named AML files for AML-01 through AML-11. Updated Plan-237 entry expectations, shared fakes, typed seam tests, and exact `GROUP_TESTS` registration.
- RED: exact AML-02 command failed before production because `incomingOnly` was absent (`/tmp/plan241-aml02-red.log`), then passed (`/tmp/plan241-aml02-green.log`).
- Focused proof: all eight Plan-241 files PASS. Root logs: `/tmp/plan241-entry.log`, `/tmp/plan241-paging.log`, `/tmp/plan241-viewer-green.log`, `/tmp/plan241-goto-green.log`, `/tmp/plan241-actions-green.log`, `/tmp/plan241-batch-actions-first.log`, `/tmp/plan241-batch-delete-final.log`; repository log above.
- Mutation: dropping `incomingOnly` from the controller re-red AML-03 (`/tmp/plan241-mutation-red.log`); restoration PASS (`/tmp/plan241-mutation-restored-green.log`).
- Preservation: current GML-10/GML-10R, Plan-228 tombstone/cursor, ordinary replay, GMA-04/GMA-07/GMA-08, IR-020, GML-08, l10n, and non-admin announcement compose sentinels PASS (`/tmp/plan241-preservation.log` plus repository/helper logs).
- Registration/Go: every new file occurs exactly once in `GROUP_TESTS`; announcement authorization Go tests PASS (`/tmp/plan241-go-auth.log`).
- Analyzer/hygiene: normalized analyzer baseline and final are both 494 with zero additions; `git diff --check` PASS.
- Graphify: affected-impact query completed (`/tmp/plan241-graph-affected.txt`); final incremental refresh PASS (`/tmp/plan241-graph-refresh-final.log`).
- Required gate: `./scripts/run_test_gates.sh groups` — **blocking failure** twice (`/tmp/plan241-groups.log`, `/tmp/plan241-groups-rerun.log`). The first run had a midnight-sensitive date test and flaky GCA-103; both later passed in isolation. The second run completed 1,890 passing tests but four failures remained.
- Remaining failures: outgoing inserted-event observation; two send-media persistence expectations; failed-media retry. Exact focused reruns remain red in `/tmp/plan241-groups-rerun-triage.log`.
- Failure classification: unrelated-but-required/pre-existing. None of the failing production/test files was changed by Plan 241; the send-media expectations conflict with the current committed send path. The plan does not allow a nonzero groups gate, and repairing messaging delivery would violate its transport scope guard.
- Blocking issue: repair those four groups-lane baseline failures in their owning plan, rerun the full `groups` gate, then resume this plan for final review/finalization. The implementation is not safe to call accepted until that mandatory gate exits 0.

## Closure Audit — 2026-07-11 (supersedes the historical blocked result)

- **Final verdict:** `accepted`.
- **Owning commits:** shared library/announcement implementation `21b6b54e2`; egress and anchor hardening `61cda3415`; final fail-closed anchor/tombstone repair `e3e5bfa7d`. Plan-254 commit `f243b2788` repaired the unrelated group-send failures that had blocked this plan's required lane.
- **Final causal proof:** the last-fix combined set passed 14/14, including repository-query failure clearing on the production Library -> Info -> same mounted Conversation route and surviving-row local-deletion tombstones across single/batch Save, Share, Bookmark, and Clear. Scoped analyzer and `git diff --check` were clean.
- **Required curated gate:** `./scripts/run_test_gates.sh groups` passed on the final source tree with 1,926 Flutter tests and both Go bridge/node packages green.
- **Independent QA:** accepted with no remaining functional blocker. The reviewer verified fail-closed anchor navigation, no stale highlight or delivery bypass, and tombstone authority before every native or local-write side effect.
- **Schema correction:** Plan 241 adds no migration; the accepted dependency stack runs on DB v99. Historical v98 references above describe the original planning snapshot only.
- **Maintenance rule:** keep this plan closed unless a real regression reintroduces announcement outgoing rows, wrong-group/tombstoned media, cap bypass, destructive side effects, or stale/wrong Go-to-message highlights.
