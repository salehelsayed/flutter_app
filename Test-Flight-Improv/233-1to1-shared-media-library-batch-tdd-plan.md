# 233 - 1:1 Shared Media Library And Batch Actions

Status: execution-ready
Type: New Feature
Spec: free-text intent — a paged direct-conversation media library with filters, bookmarks, cross-message viewing, Go to Message, and safe batch actions
Classification: implementation-ready
Closure tier: host

## Planning Progress

| Time | Role | Files inspected | Decision/blocker | Next action |
|---|---|---|---|---|
| 2026-07-09 | Evidence Collector / Planner | `graphify-arch` query; conversation load/pagination/screen/wired files; media repository/model/helpers; delete-for-me use case; share picker/egress plans; plans 227–230 | Plan 228 supplies a bounded direct-scope media repository, while HEAD's conversation only hydrates media for its current message page. A direct-owned library can stay local and return a message identity for bounded Go to Message loading. | Add library navigation, paging, batch, and scroll-target RED tests before production edits. |
| 2026-07-10 | Planner | revised plan 228 direct-owner, unresolved exclusion, visibility, cursor-signature and page-limit contracts; plans 229–231 downstream seams | The library must issue only strict direct-scoped queries/mutations, use opaque scope/filter-bound cursors with a literal valid limit, and preserve same-ID group/unresolved state during batch actions. | Replace permissive fakes with strict contract fixtures and add Plan-228 repository sentinels before execution. |
| 2026-07-10 | Counterexample Reviewer / Replanner | `233-review-fixlist.md`; current plan-228 library/state APIs; egress cap/service; delete-for-me/message lookup; typed viewer; conversation paging/render seams and gates | The architecture remains sound, but bookmark safety belongs to scoped reads rather than a nonexistent owner-aware writer; selection must stop at ten; destructive delete needs confirmation, parent materialization and missing-parent outcomes; viewer actions need wired execution proof. | Execute the corrected test contract and separately review the destructive slice before later work proceeds. |

## Problem And Evidence

- Behavior to improve: a user must be able to browse all images/videos shared with one direct contact, filter and bookmark them, open a cross-message viewer, select multiple items, save/share/delete safely, and jump back to the owning message.
- Impact: HEAD makes media discoverable only by scrolling message history. Opening media builds pages from the tapped message's completed paths, so users cannot inspect or manage conversation-wide media efficiently.
- Confirmed current mechanism: `ConversationScreen.mediaTapHandler` opens a viewer from only one message's visual attachments at `lib/features/conversation/presentation/screens/conversation_screen.dart:639-700`.
- Confirmed current mechanism: direct history is page-bounded in `ConversationWired`, with initial and older-page loading at `lib/features/conversation/presentation/screens/conversation_wired.dart:1148-1177` and `:1344-1383`; the reverse `ListView.builder` uses message keys in `conversation_screen.dart:509-516`.
- Confirmed current gap: `MediaAttachmentRepository` only loads attachment rows by one or more already-known message IDs (`lib/features/conversation/domain/repositories/media_attachment_repository.dart:4-45`). HEAD has no conversation-scoped gallery, selection, bookmark UI, or Go to Message result.
- Confirmed destructive boundary: `deleteMessageForMe` removes the whole local message and its owned attachment artifacts, not an individual attachment (`lib/features/conversation/application/delete_message_use_case.dart:17-47`, `:435-463`).
- Confirmed dependency change: revised plan 228 makes direct library queries require `owner_lane='direct'`, contact scope, `hidden_at IS NULL`, `deleted_at IS NULL`, excludes `unresolved`, binds opaque cursors to scope/filter, and rejects limits outside `1..100`. Plan 231 makes whole-message direct cleanup owner-aware.
- Existing coverage: direct pagination tests preserve the 50-row window/load-older behavior; viewer tests preserve page swiping; delete tests prove incoming local deletion and sibling preservation. No existing test can fail for a direct media library or cross-message target.
- Missing coverage: strict direct-owner navigation, scope/filter cursor validation, literal page limit, unresolved/hidden/deleted exclusion, stable paged filters, lazy viewer continuation and action execution, scoped-page-only bookmark targets, a ten-item selection ceiling, batch partial outcomes, confirmed same-ID sibling-safe message deletion including missing parents, missing/evicted rows, Go to Message across unloaded pages, virtualization, and accessibility.
- Refuted finding: this feature does not need a new attachment schema or transport query. Plan 228 owns DB v96 and stable `MediaLibraryPage` queries; all 1:1 library actions are local/native egress.
- Unresolved findings: N/A. Individual-attachment deletion is deliberately not claimed; Delete removes each selected item's whole owning message after explicit copy explains that consequence.
- Affected production, test, and gate files: a new direct shared-media screen/wired/controller under `lib/features/conversation/`; extraction of Plan 231's current-row candidate qualification without changing its single-item behavior; direct conversation menu/navigation and bounded scroll targeting; three-locale l10n; new widget/application tests; both 1:1 test arrays.

## Scope Contract And Guard

In scope:
- Add a Shared Media entry within an existing `ConversationWired` direct chat; construct only `MediaLibraryScope.direct(contactPeerId)` and never accept a caller-provided group/announcement scope.
- Page direct-owned `MediaLibraryEntry` values newest-first through plan 228 `MediaLibraryCursor/Page`, with All, Photos, Videos, and Bookmarked filters; request the literal `kDirectMediaLibraryPageSize = 50` (valid under the shared `1..100` ceiling), treat cursors as opaque, and discard them whenever scope/filter changes. Use builder/sliver virtualization.
- Open plan 230 with typed items spanning parent messages. Preserve stable attachment/message identity, append the next media page lazily near the viewer boundary, and deduplicate by attachment ID.
- Persist bookmark toggles through the separate plan-228 `MediaLibraryStateRepository.setBookmarked(attachmentId, bookmarked: value)` API. The controller may call it only with attachment IDs obtained from its current `MediaLibraryScope.direct(contactPeerId)` page; the plan-228 read boundary, not a fictional write-side owner argument, excludes group/unresolved rows. Reconcile the active filter without losing unrelated selection or scroll state.
- Cap the selected attachment-ID set at `const kMaxDirectMediaSelection = kMaxMediaEgressItems` (currently ten). Refuse the eleventh selection before any action dispatch so batch Save, Share, and Delete remain bounded and egress never reaches its over-cap blanket rejection with an empty per-item result list.
- Support batch Save to Photos, Save to Files, and external OS Share through plan 227's list-capable egress request, with per-item typed outcomes and retry of failed-only items.
- Support batch Delete for Me behind an explicit confirmation surface. Deduplicate by parent message ID, materialize each unique parent through `MessageRepository.getMessage(id)`, then invoke `deleteMessageForMe(message: ...)` once for each resolved direct parent. A missing parent is a per-message failure that remains selected; other parents continue. Confirmation copy states that entire messages/all their attachments are removed locally, while same-message-ID group/unresolved rows/files and exports remain intact.
- Wire plan 230's current-item `onAction` for cross-message Save, Share, Bookmark, and Delete. Available items reach the same coordinators as batch actions; a missing parent on single-item Delete reports failure without synthesizing a partial `ConversationMessage` or mutating another lane.
- Return a Go-to-message result to the still-mounted direct conversation; load older pages until the target message is present or history is exhausted, reveal its stable key, and apply a transient highlight without resetting the loaded window.

Must preserve:
- Existing direct initial/load-older ordering, reverse-list anchoring, and 50-row page behavior -> direct pagination/widget `GREEN sentinels` plus TC-233-10/11.
- Delete for Everyone remains sender-authorized and transport-backed only from its existing message action -> `conversation_wired_test.dart::delivered outgoing rows offer delete-for-me and delete-for-everyone`; `GREEN sentinel`.
- Source media, captions, encryption metadata, and exported copies remain unchanged after bookmark/save/share -> TC-233-05/06/07.
- Plan 231's single-item current-row reload, denial reasons, destination mapping, and one-service-call behavior remain unchanged while its qualification seam is shared with batching -> `received_media_action_controller_test.dart`; `GREEN sentinel`.
- Missing or `evicted` media never silently auto-downloads; explicit Retry remains plan 229-owned -> TC-233-12.
- Hidden/deleted direct parents, same-ID group parents and unresolved attachments never cross the repository boundary; ordinary replay preserves local owner/bookmark/playback/evicted state -> TC-233-15 plus plan 228 TC-228-06/08 and plan 229 TC-229-12.
- Selection never exceeds the shared native-egress ceiling and the large-library fixture remains virtualized independently of selection count -> TC-233-13/16.

Hard `Do not`:
- Do not add or alter DB migrations, direct/group payloads, delivery/dedup, relay queries, Bridge commands, Go/libp2p code, group publish, or announcement permissions.
- Do not implement item-only attachment deletion or imply it in confirmation copy.
- Do not route external Share through the internal forwarding picker; plan 232 owns Forward.
- Do not load all conversation history/media eagerly, scan files on build, use offset-only pagination, or identify items by local path.
- Do not delete Photos/Gallery/Files exports or attachments owned by a sibling message after a partial batch failure.
- Do not default/infer owner during scope/read construction, display or select `unresolved`, accept group-owned entries, reuse a cursor after scope/filter changes, request limit 0 or above 100, or compensate for repository bugs with UI-side SQL/filter reimplementation. Do not invent an owner parameter for `setBookmarked`.

Deferred / accepted difference:
- Item-only deletion while retaining the parent message -> future attachment-deletion product plan.
- Multi-message/multi-source internal Forward from the library -> evidence-gated `Test-Flight-Improv/249-1to1-shared-media-batch-forwarding-tdd-plan.md`, which owns album-versus-individual, caption/order, opaque provenance, Forward-specific limits, and partial-retry decisions. Plan 233 intentionally exposes no batch Forward action; its ten-item cap applies only to Save, Share, Delete, and their single shared selection controller.
- Group and announcement libraries -> plans 237 and 241; they own their own permissions, navigation, and gate registration.
- Cache re-download/eviction and video resume mechanics -> plans 229 and 230.
- Private/protected/consumed/expired library and egress eligibility -> evidence-gated plan 234's central action policy; Plan 233 must not invent private-state fields or test-only flags.

Dependencies:
- `Test-Flight-Improv/227-received-media-native-egress-foundation-tdd-plan.md` for bounded-list native Save/Share requests, typed per-item/aggregate outcomes, and TC-227-05/06 physical Android/iOS single+batch egress proof.
- Revised `Test-Flight-Improv/228-shared-media-library-bookmark-persistence-tdd-plan.md` for DB v96, `MediaOwnerLane`, fail-closed unresolved rows, direct visibility, replay preservation, the scoped `MediaLibraryRepository`, the separate ID-based `MediaLibraryStateRepository`, scope/filter-bound cursor/page behavior, and the `1..100` limit.
- `Test-Flight-Improv/229-cross-track-media-download-storage-controls-tdd-plan.md` for `evicted` semantics and explicit retry ownership.
- `Test-Flight-Improv/230-shared-typed-media-viewer-tdd-plan.md` for typed current-item identity and callback-only viewer actions.
- `Test-Flight-Improv/231-1to1-received-media-core-actions-tdd-plan.md` for direct action eligibility and the existing whole-message Delete-for-Me wiring.

## Test Contract

| Case | Behavior | Named test/proof | Tier / fixture | HEAD -> GREEN | Mutation | Gate / registration |
|---|---|---|---|---|---|---|
| TC-233-01 | A direct conversation exposes one localized Shared Media entry and every request launches exactly that contact's direct scope with no injectable sibling owner. | `test/features/conversation/presentation/screens/conversation_shared_media_library_test.dart::direct chat opens one strict contact scoped shared media library` | widget host / `ConversationWired` fixture + strict recording repository factory | HEAD compile RED: route/screen absent -> one menu action opens `MediaLibraryScope.direct(expectedPeerId)`; factory rejects group/unresolved ownership and own-peer/wrong-contact scope | pass own peer id, omit contact id, default owner, or expose route outside direct chat -> TC-233-01 red | `flutter test test/features/conversation/presentation/screens/conversation_shared_media_library_test.dart --plain-name 'direct chat opens one strict contact scoped shared media library'`; AUTO (`test/features/**`) + add file to `ONE_TO_ONE_TESTS` and `ONE_TO_ONE_HOST_TESTS` |
| TC-233-02 | All/Photos/Videos/Bookmarked filters page a stable newest-first grid using strict direct scope, complete filter-bound opaque cursors and limit 50, without duplicates, stale results, or eager exhaustion. | `test/features/conversation/presentation/screens/conversation_shared_media_library_test.dart::filters bind direct scope cursor signature and preserve stable paged order` | widget/application host / strict paged `MediaLibraryRepository` that throws on wrong contact/owner/filter/cursor/limit, tied rows and delayed completers | HEAD compile RED -> every request is direct(contact), limit 50 and matching complete filter signature; tied order is retained; filter change drops old cursor/result; only one requested page loads | accept mismatched cursor, pass 0/101, retain old filter cursor, append stale response, key by path, or eagerly exhaust pages -> TC-233-02 red | `flutter test test/features/conversation/presentation/screens/conversation_shared_media_library_test.dart --plain-name 'filters bind direct scope cursor signature and preserve stable paged order'`; AUTO + both 1:1 arrays |
| TC-233-03 | Tapping a tile opens plan-230 typed pages across parent messages at the exact selected attachment and swiping updates metadata/actions to that item. | `test/features/conversation/presentation/screens/conversation_shared_media_viewer_test.dart::library opens cross-message typed viewer at exact attachment identity` | widget host / three entries from different parent messages + fake viewer callback | HEAD compile RED: library absent and viewer caller is per-message paths -> initial identity and every post-swipe attachment/message callback are exact | derive initial index from path or retain the first parent message -> TC-233-03 red | `flutter test test/features/conversation/presentation/screens/conversation_shared_media_viewer_test.dart --plain-name 'library opens cross-message typed viewer at exact attachment identity'`; AUTO + add file to both 1:1 arrays |
| TC-233-04 | Near the viewer boundary, one next page is appended through the matching direct scope/filter cursor; duplicate callbacks/results never duplicate pages or lose current identity. | `test/features/conversation/presentation/screens/conversation_shared_media_viewer_test.dart::viewer continuation keeps direct cursor signature fenced and current item stable` | widget/application host / strict gated page completers that reject changed scope/filter/limit | HEAD compile RED -> concurrent boundary signals issue one matching cursor call at limit 50; duplicate attachment ID appears once; current page remains selected | remove in-flight fence, alter/reuse cursor signature, request another limit, or replace list while viewing -> TC-233-04 red | `flutter test test/features/conversation/presentation/screens/conversation_shared_media_viewer_test.dart --plain-name 'viewer continuation keeps direct cursor signature fenced and current item stable'`; AUTO + both 1:1 arrays |
| TC-233-05 | Bookmark targets come only from the current direct-scoped page. The controller calls the real ID-based state API, re-reads bookmark state on recreation, and Bookmarked-filter removal does not disturb siblings, same-ID group/unresolved rows, or unrelated selection. | `test/features/conversation/presentation/screens/conversation_shared_media_library_test.dart::bookmark uses only current direct page ids and re-reads repository state` | widget/repository host / strict direct-page fake, ID-recording `MediaLibraryStateRepository`, same-ID group/unresolved controls, fresh controller | HEAD compile RED -> only direct page IDs can render/select/call `setBookmarked(id, bookmarked:)`; recreation reads stored state rather than controller cache; malformed sibling/unresolved output fails closed with zero write; plan-228 TC-228-06/08 own DB exclusion/durability | bookmark an ID absent from the scoped page, accept malformed owner output, retain only in-memory state, or clear unrelated selection -> TC-233-05 red | `flutter test test/features/conversation/presentation/screens/conversation_shared_media_library_test.dart --plain-name 'bookmark uses only current direct page ids and re-reads repository state'`; AUTO + both 1:1 arrays |
| TC-233-06 | Batch Save re-qualifies each selected identity against its current incoming parent and direct-owned attachment, then sends at most ten eligible candidates once to the chosen Photos/Files destination and merges preflight plus native per-item outcomes without mutating source state. | `test/features/conversation/application/direct_media_library_batch_actions_test.dart::batch save reloads current direct rows and returns per-item outcomes` | application host / mutable parent+owner-aware attachment repositories, shared plan-231 lane qualifier, raw recording list-capable egress service | HEAD compile RED: batch controller absent -> stale viewer/library path and MIME are ignored; only current qualified rows reach one exact ordered destination request; missing/integrity-failed/protected rows fail before egress; source snapshots remain equal | trust library snapshots, skip parent/direct-row reload, map Files to Photos, or mutate bookmark/path on failure -> TC-233-06 red | `flutter test test/features/conversation/application/direct_media_library_batch_actions_test.dart --plain-name 'batch save reloads current direct rows and returns per-item outcomes'`; AUTO + add file to both 1:1 arrays |
| TC-233-07 | Batch external Share applies TC-233-06's current-row preflight, presents one list-capable OS request for qualified candidates, never opens internal targets, and keeps preflight-failed/cancelled/native-failed items selected for truthful retry. | `test/features/conversation/application/direct_media_library_batch_actions_test.dart::batch external share is one qualified native request with failed-only retry state` | application host / mutable current rows, shared qualifier, raw recording egress + throwing share-picker/delivery spies | HEAD compile RED -> one ordered current-row request, zero picker/P2P calls, and only successful IDs clear; stale or non-success IDs remain selected with typed outcomes | trust page snapshots, loop one chooser per item, invoke `ShareTargetPickerWired`, or clear all selection on partial result -> TC-233-07 red | `flutter test test/features/conversation/application/direct_media_library_batch_actions_test.dart --plain-name 'batch external share is one qualified native request with failed-only retry state'`; AUTO + both 1:1 arrays |
| TC-233-08 | Batch Delete for Me requires explicit confirmation, deduplicates by parent message, materializes each unique direct parent through `MessageRepository.getMessage`, deletes each resolved message once, and reports missing/failed parents without touching sibling lanes or exports. | `test/features/conversation/application/direct_media_library_batch_delete_test.dart::confirmed batch delete materializes unique direct parents and preserves partial failures` | application/widget host / cancel+confirm surface, duplicate direct attachments for A, missing parent B, same-ID group/unresolved controls, real/recording direct delete seam and file snapshots | HEAD compile RED -> cancel causes zero lookup/delete; confirm occurs once; A's two attachments cause one lookup/delete; B null is reported failed and stays selected; group/unresolved rows/files, unrelated message and exports survive; zero delete-for-everyone/network calls | proceed without confirmation, delete once per attachment, synthesize a missing parent, skip/mis-materialize A, or clear failed selection -> TC-233-08 red | `flutter test test/features/conversation/application/direct_media_library_batch_delete_test.dart --plain-name 'confirmed batch delete materializes unique direct parents and preserves partial failures'`; AUTO + add file to both 1:1 arrays |
| TC-233-09 | A Go to Message result already in the conversation window reveals and transiently highlights exactly its stable message key without replacing scroll history. | `test/features/conversation/presentation/screens/conversation_shared_media_go_to_message_test.dart::loaded target reveals exact message and preserves conversation window` | widget host / fake scroll target delegate + preloaded messages | HEAD compile RED: route result/target coordinator absent -> exact key is revealed once, highlight clears, loaded IDs and composer focus remain | target by attachment/path or rebuild conversation from page one -> TC-233-09 red | `flutter test test/features/conversation/presentation/screens/conversation_shared_media_go_to_message_test.dart --plain-name 'loaded target reveals exact message and preserves conversation window'`; AUTO + add file to both 1:1 arrays |
| TC-233-10 | An unloaded Go to Message target loads older pages serially until found, stops immediately on match, and preserves page order/anchor. | `test/features/conversation/presentation/screens/conversation_shared_media_go_to_message_test.dart::unloaded target pages backward boundedly then reveals exact row` | widget/application host / gated direct pagination fixture | HEAD compile RED -> one page at a time; matching page stops further calls; row is revealed without duplicate IDs or anchor jump | fire all pages concurrently, stop one page early, or reset `_messages` -> TC-233-10 red | `flutter test test/features/conversation/presentation/screens/conversation_shared_media_go_to_message_test.dart --plain-name 'unloaded target pages backward boundedly then reveals exact row'`; AUTO + both 1:1 arrays |
| TC-233-11 | Missing/deleted Go to Message targets terminate when history is exhausted and show a truthful result without an infinite spinner or unrelated navigation. | `test/features/conversation/presentation/screens/conversation_shared_media_go_to_message_test.dart::missing target exhausts history once and settles truthfully` | widget/application host / finite cursor fixture | HEAD compile RED -> finite call count equals available pages, loading settles, current conversation/scroll remain usable | ignore `hasMore`, retry forever, or reveal a nearest row -> TC-233-11 red | `flutter test test/features/conversation/presentation/screens/conversation_shared_media_go_to_message_test.dart --plain-name 'missing target exhausts history once and settles truthfully'`; AUTO + both 1:1 arrays |
| TC-233-12 | Missing, integrity-failed, and `evicted` direct entries render truthful state; unresolved/group entries never render or mutate, opening triggers zero implicit downloads, and an action-time Plan-231 qualifier denial produces zero egress. | `test/features/conversation/presentation/screens/conversation_shared_media_library_test.dart::unavailable direct media is truthful and unresolved never crosses the boundary` | widget host / representable status matrix, strict repository, downloader/egress spies, injected qualifier-denial action leg | HEAD compile RED -> status/accessibility text is exact; unresolved/group render/mutation count is zero; downloader/egress stays zero until explicit plan-229 Retry; qualifier denial is truthful without inventing a private lifecycle field before plan 234 | treat evicted as pending, render unresolved, default owner, ignore qualifier denial, or auto-retry on build -> TC-233-12 red | `flutter test test/features/conversation/presentation/screens/conversation_shared_media_library_test.dart --plain-name 'unavailable direct media is truthful and unresolved never crosses the boundary'`; AUTO + both 1:1 arrays |
| TC-233-13 | A 1,000-entry library stays virtualized independently of the ten-item selection ceiling; selection/action semantics and long labels remain reachable in English, German, and RTL Arabic on a small viewport. | `test/features/conversation/presentation/screens/conversation_shared_media_library_test.dart::library is virtualized localized and accessible in small LTR RTL viewports` | widget host / 1,000-entry lazy fixture, semantics tester, 320x568 viewport | HEAD compile RED -> bounded built-child count, at-most-ten selected-count semantics, scrollable action surface, and no overflow/exceptions | replace builder/sliver with eager `Column`, tie fixture size to selected rows, hardcode English, or omit selected semantics -> TC-233-13 red | `flutter test test/features/conversation/presentation/screens/conversation_shared_media_library_test.dart --plain-name 'library is virtualized localized and accessible in small LTR RTL viewports'`; AUTO + both 1:1 arrays; existing ARB parity test |
| TC-233-14 | The direct library imports no transport/group/announcement implementation and existing direct initial/load-older 50-row pagination plus delete-for-everyone behavior remain unchanged. | `test/features/conversation/application/direct_media_library_boundary_test.dart::library is local direct-scoped and transport-free`; `test/features/conversation/presentation/screens/conversation_wired_test.dart::initial fifty and older page append without resetting the window`; existing delete sentinel | host source-contract + `GREEN sentinels` | HEAD compile RED for target sources; new pagination sentinel GREEN on unmodified HEAD -> forbidden imports remain absent, Go/relay paths remain baseline-equal, initial page is 50, older load appends/anchors without reset, and delete-for-everyone stays GREEN | import Bridge/group repository, change Go/relay paths, reset/resize the conversation window, or route batch delete through delete-for-everyone -> TC-233-14 red | boundary command plus the two literal conversation-wired commands in Acceptance Gates; AUTO + both 1:1 arrays for the new boundary file |
| TC-233-15 | The consumed plan-228 repository contract excludes hidden/deleted direct parents, same-ID group parents and unresolved rows, and rejects a cursor whose scope/filter signature or limit is invalid. | `test/core/database/helpers/media_library_db_helpers_test.dart::direct scope is owner isolated and excludes hidden and deleted parents` plus `::keyset cursor binds scope filters and enforces the 100 row ceiling` | `GREEN sentinel` / real DB v96 mixed-parent/collision fixture from plan 228 | GREEN after plan 228 -> remains GREEN while plan 233 composes the UI; only live direct rows for the named contact are eligible and 0/101/mismatched cursors fail before SQL | remove owner/hidden/deleted predicate, expose unresolved, or bypass cursor/limit validation -> sentinel red | the two literal focused commands in Acceptance Gates; AUTO core discovery, but no broad core gate at this plan boundary |
| TC-233-16 | The selection controller refuses the eleventh unique attachment and never dispatches Save, Share, or Delete above `kMaxDirectMediaSelection == kMaxMediaEgressItems`. | `test/features/conversation/application/direct_media_library_batch_actions_test.dart::selection is capped at ten and never over-caps egress` | application/widget host / eleven direct entries, selection semantics, throwing over-cap egress/delete spies | HEAD compile RED -> first ten unique IDs select; eleventh is refused with truthful semantics; every dispatched action has `1..10` IDs and receives per-item-capable handling instead of blanket over-cap rejection | admit the eleventh ID, compare against a drifting literal, or dispatch more than ten candidates -> TC-233-16 red | `flutter test test/features/conversation/application/direct_media_library_batch_actions_test.dart --plain-name 'selection is capped at ten and never over-caps egress'`; AUTO + both 1:1 arrays |
| TC-233-17 | In the cross-message typed viewer, Save, Share, Bookmark, and Delete dispatch for the exact current item. Available items reach the real injected coordinators; Delete for a parent outside the loaded chat window reloads it, while a now-missing parent reports failure and performs no deletion. | `test/features/conversation/presentation/screens/conversation_shared_media_viewer_test.dart::in-viewer current item actions execute across parent messages` | widget host / plan-230 `onAction`, two cross-message items, recording egress/bookmark/delete coordinators, mutable parent loader | HEAD compile RED -> swiping changes action identity; each action reaches only the current item once; resolvable unloaded parent deletes once after confirmation; null parent returns failure with zero delete | retain first item, wire only action visibility, synthesize missing parent, call delivery/share picker directly, or report success without coordinator call -> TC-233-17 red | `flutter test test/features/conversation/presentation/screens/conversation_shared_media_viewer_test.dart --plain-name 'in-viewer current item actions execute across parent messages'`; AUTO + both 1:1 arrays |

### Test Notes

- TC-233-02/04 use strict fakes: a caller that omits direct contact scope, changes the complete filter signature, fabricates/reuses a cursor, or requests anything except 50 fails the test before returning data.
- TC-233-05 does not claim that `setBookmarked` is owner-aware. Plan-228 TC-228-06 proves owner exclusion at the real page boundary and TC-228-08 proves DB replay durability; TC-233-05 proves controller provenance and repository re-read rather than in-memory caching.
- TC-233-06/07 share one current-row candidate qualification function with Plan 231's single-item controller; the batch coordinator aggregates qualified candidates and calls native egress once. It must not call the single-item egress method in a loop.
- TC-233-08 deliberately selects two direct attachments from message A and one from now-missing message B, with a group parent sharing A's ID. The expected delete-call count is one for A after confirmation; B remains a typed failure; group/unresolved controls remain unchanged.
- TC-233-09/10 must assert the stable message key and final visible/highlight state. Merely asserting that `loadOlder()` was called is vacuous.
- TC-233-13 records built/rendered child count before and after scrolling; total fixture size alone does not prove virtualization, and its 1,000 rows are not all selected.
- TC-233-16 uses the exported egress ceiling rather than a duplicated literal: `kMaxDirectMediaSelection` is a UI-domain alias of `kMaxMediaEgressItems`, so the values cannot drift silently.

## Implementation Steps

1. Snapshot `git status --short`; verify the landed source symbols from plans 227–231 and DB v96. Before each slice below, add its named RED tests and record the causal failure; do not front-load implementation ahead of later tests.
2. Add TC-233-01/02/14/15, then implement the direct-owned route/controller, opaque cursor/filter paging at limit 50, builder/sliver grid, and the direct pagination sentinel. Run a stale-result/cursor mutation in this slice. Stop if owner is inferred, a cursor crosses scope/filter, or any query needs Bridge/relay/group code.
3. Add TC-233-03/04/05/12/17, then adapt entries to plan-230 typed items, fence lazy continuation, wire exact-current-item coordinators, use only scoped-page IDs for the real bookmark API, and render truthful unavailable states. Run current-item and out-of-page bookmark mutations before continuing.
4. **Non-destructive batch slice:** add TC-233-06/07/16, extract/reuse Plan 231's current-row candidate qualification without changing its behavior, cap selection at the shared ten-item ceiling, aggregate one qualified native request, and preserve failed-only state. Run stale-snapshot, over-cap, destination, and clear-all mutations in this slice.
5. **Destructive batch-delete slice:** add TC-233-08 in `direct_media_library_batch_delete_test.dart` before production edits. Add confirmation, unique-parent materialization through `MessageRepository.getMessage`, once-per-resolved-parent `deleteMessageForMe`, and typed missing/failure outcomes. Stop if duplicate attachments fan out to multiple deletes for one parent, any selected entry is not direct-scoped, a null parent is synthesized/skipped without a failed outcome, or confirmation can be bypassed. Review this slice's diff and run its focused test plus confirmation/dedup/materialization mutations before Step 6.
6. Add TC-233-09/10/11, then implement bounded Go to Message return/load/reveal/highlight coordination inside `ConversationWired` without replacing its pagination window. Run early-stop and infinite-pagination mutations in this slice.
7. Add TC-233-13 and three-locale copy, register all six new direct test files in both 1:1 arrays, then run focused GREEN, sentinels, lane gates, remaining representative mutations, and the Go/relay no-diff guard.

## Risks And Blind Spots

- Stable selection can drift when filters/pages change -> TC-233-02/04/05 bind direct owner, opaque cursor signature and attachment ID while retaining exact current identity.
- Batch delete can over-delete when several attachments or lanes share one message ID -> TC-233-08 deduplicates by `(direct, parentMessageId)` and proves same-ID group/unresolved/export preservation.
- Go to Message can loop or jump the scroll anchor -> TC-233-09/10/11 cover loaded, older, and absent targets.
- Lifecycle / derived-state durability: TC-233-05 recreates the controller and re-reads bookmark state from the repository; plan-228 TC-228-08 owns real DB/replay durability.
- Sibling-surface consistency: library and conversation viewer use the same plan-230 typed item/action contract in TC-233-03/04.
- Destructive-action side effects: TC-233-08 asserts explicit confirm/cancel, parent materialization, direct removals, null-parent partial failure, same-ID group/unresolved preservation, exports, unrelated messages, and zero transport calls.
- Invariant re-verification under new transitions: delayed filter/page completions recheck generation, membership, `mounted`, and selection before applying in TC-233-02/04; Go to Message rechecks target existence after each page in TC-233-10/11.

## Gate Cadence

- Per-plan closure: run the focused Plan-233 tests, exact preservation sentinels, and the curated `1to1` lane gate. `feature-host-all`, `core-host-all`, and full `host-all` are not Plan-233 closure gates.
- Destructive checkpoint: Step 5's batch-delete diff, focused test, and confirmation/dedup/materialization mutations must pass review before Go to Message or later slices proceed.
- Registration is verified by the existing `1to1 --list` command; it is discovery evidence, not an additional broad sweep.
- Full `host-all` runs once after the complete library/batch wave (`233`, `237`, and `241`) and once at final rollout closure, not after this individual plan.

## Acceptance Gates

```bash
# Snapshot and dependency preconditions
git status --short
git status --short --untracked-files=all -- go-mknoon go-relay-server > /tmp/plan-233-go-relay-status.before
git diff --binary -- go-mknoon go-relay-server > /tmp/plan-233-go-relay-diff.before
rg -n '^abstract class MediaLibraryRepository' lib/features/conversation/domain/repositories/media_attachment_repository.dart
rg -n '^abstract class MediaLibraryStateRepository' lib/features/conversation/domain/repositories/media_attachment_repository.dart
rg -n '^const int kMaxMediaEgressItems = 10;$' lib/core/media/received_media_egress.dart
rg -n 'final MediaViewerActionCallback\? onAction;' lib/shared/widgets/media/full_screen_typed_media_viewer.dart
rg -n 'Future<ConversationMessage\?> getMessage\(String id\);' lib/features/conversation/domain/repositories/message_repository.dart

# First causal RED; expect non-zero because the strict direct-owned library route/screen is absent
flutter test test/features/conversation/presentation/screens/conversation_shared_media_library_test.dart --plain-name 'direct chat opens one strict contact scoped shared media library'

# Focused GREEN; expect exit 0 and zero failed tests
flutter test test/features/conversation/presentation/screens/conversation_shared_media_library_test.dart
flutter test test/features/conversation/presentation/screens/conversation_shared_media_viewer_test.dart
flutter test test/features/conversation/presentation/screens/conversation_shared_media_go_to_message_test.dart
flutter test test/features/conversation/application/direct_media_library_batch_actions_test.dart
flutter test test/features/conversation/application/direct_media_library_batch_delete_test.dart
flutter test test/features/conversation/application/direct_media_library_boundary_test.dart
flutter test test/core/database/helpers/media_library_db_helpers_test.dart --plain-name 'direct scope is owner isolated and excludes hidden and deleted parents'
flutter test test/core/database/helpers/media_library_db_helpers_test.dart --plain-name 'keyset cursor binds scope filters and enforces the 100 row ceiling'

# Preservation and named gate selection
flutter test test/features/conversation/presentation/screens/conversation_wired_test.dart --plain-name 'initial fifty and older page append without resetting the window'
flutter test test/features/conversation/presentation/screens/conversation_wired_test.dart --plain-name 'delivered outgoing rows offer delete-for-me and delete-for-everyone'
flutter test test/features/conversation/application/delete_message_use_case_test.dart
flutter test test/features/conversation/application/received_media_action_controller_test.dart
flutter test test/shared/widgets/media/full_screen_image_viewer_test.dart
flutter test test/shared/widgets/media/full_screen_typed_media_viewer_test.dart
flutter test test/l10n/l10n_integrity_test.dart --plain-name 'ARB files have identical non-empty key and placeholder sets'
./scripts/run_test_gates.sh 1to1

# Exact dual-array registration and host planner selection; do not execute full host-all
host_files=(
  test/features/conversation/presentation/screens/conversation_shared_media_library_test.dart
  test/features/conversation/presentation/screens/conversation_shared_media_viewer_test.dart
  test/features/conversation/presentation/screens/conversation_shared_media_go_to_message_test.dart
  test/features/conversation/application/direct_media_library_batch_actions_test.dart
  test/features/conversation/application/direct_media_library_batch_delete_test.dart
  test/features/conversation/application/direct_media_library_boundary_test.dart
)
for file in "${host_files[@]}"; do
  test "$(awk '/^readonly ONE_TO_ONE_TESTS=\(/,/^\)/' scripts/run_test_gates.sh | rg -F -x -c "  \"$file\"")" -eq 1
  test "$(awk '/^readonly ONE_TO_ONE_HOST_TESTS=\(/,/^\)/' scripts/run_host_test_gates.sh | rg -F -x -c "  \"$file\"")" -eq 1
done
host_plan="$(mktemp)"
./scripts/run_host_test_gates.sh 1to1 --list >"$host_plan"
for file in "${host_files[@]}"; do
  test "$(rg -F -c "$file" "$host_plan")" -eq 1
done
rm -f "$host_plan"

# Scope and hygiene
git status --short --untracked-files=all -- go-mknoon go-relay-server | cmp -s - /tmp/plan-233-go-relay-status.before
git diff --binary -- go-mknoon go-relay-server | cmp -s - /tmp/plan-233-go-relay-diff.before
flutter analyze
git diff --check
```

## Execution Interpretation And Done Criteria

- Expected RED: TC-233-01 compile-fails because no strict direct-owner Shared Media route/screen exists.
- Green sentinel: direct initial/load-older 50-row pagination, incoming local delete, outgoing Delete for Everyone, plan-231 current-row qualification, and both viewer suites remain GREEN.
- Pre-existing dirty tree / known failure: snapshot at execution start; preserve unrelated current messaging/push/graph changes.
- Environment blocker: none for this host composition/result-handling slice; plan 227 independently closes single and bounded-list native egress on physical Android/iOS.
- Scope drift: any migration, payload, group/announcement permission, download automation, Bridge/P2P/relay, or Go edit blocks completion.

- [ ] Every behavior has a named causal test or explicit sentinel.
- [ ] Strict direct scope/filter/cursor paging, unresolved/hidden/deleted exclusion, cross-message viewing/actions, scoped-page-only bookmarks, ten-item selection, current-row-qualified egress, confirmed sibling-safe delete outcomes, Go to Message, missing state, virtualization, and localization pass.
- [ ] New direct tests occur exactly once in both 1:1 arrays and the host planner lists all six.
- [ ] Representative stale-page, stale-egress-snapshot, out-of-page bookmark, over-cap, confirmation bypass, per-attachment delete, null-parent synthesis, infinite-page, eager-build, and forbidden-import mutations re-red.
- [ ] Existing direct pagination/delete/viewer sentinels and the curated `1to1` gate pass.
- [ ] `flutter analyze` has no new issues; `git diff --check` and Go/relay no-diff guard are clean.
- [ ] Scope Contract And Guard is respected.

## Handoff

- First causal RED command: `flutter test test/features/conversation/presentation/screens/conversation_shared_media_library_test.dart --plain-name 'direct chat opens one strict contact scoped shared media library'`.
- Preservation command: `flutter test test/features/conversation/presentation/screens/conversation_wired_test.dart --plain-name 'delivered outgoing rows offer delete-for-me and delete-for-everyone'`.
- Manual registration: add the six new direct library/action/delete files exactly once to both `scripts/run_test_gates.sh::ONE_TO_ONE_TESTS` and `scripts/run_host_test_gates.sh::ONE_TO_ONE_HOST_TESTS`; verify both arrays and host planner output without running full `host-all`.
- Migration: none; consumes plan-228 DB v96 direct-owner, unresolved-exclusion, visibility, cursor-signature and limit contracts.
- Boundary closure: host widget/application proof over injected repository/egress seams; plan 227 owns physical Android/iOS single and bounded-list egress proof. No relay/device/Go run is required here.
- Unresolved evidence: none. Item-only deletion and internal Forward integration are explicit deferred owners, not hidden gaps.

## Execution Progress

| Time | Phase | Files | Last command/result | Current evidence | Decision/blocker | Next |
|---|---|---|---|---|---|---|
| - | not started | - | - | - | awaiting accepted plan and dependencies 227–231 | contract extraction |
| 2026-07-10 | Slice 1 (TC-233-01/02/14/15) | `direct_media_library_controller.dart`, `direct_shared_media_library_screen.dart`, wired menu entry, 3-locale ARB keys, boundary test, new wired pagination sentinel | first causal RED: TC-233-01 compile-fails (library route/screen absent); then focused GREEN | strict `MediaLibraryScope.direct` construction, literal limit 50, filter-bound opaque cursors, stale-fence; pagination sentinel GREEN on unmodified HEAD before wired edits | stale-result + cursor-across-filter mutations re-red (fixture reordered so the cursor is live at the filter switch) | slice 2 |
| 2026-07-10 | Slice 2 (TC-233-03/04/05/12/17) | viewer `onPageChanged` (additive), viewer host + exact-current-item actions, scoped-page-only bookmarks, truthful unavailable states | focused GREEN; both plan-230 viewer sentinels GREEN | cross-message identity, fenced lazy continuation with dedup, ID-based `setBookmarked` provenance, unresolved/group rows never render | first-item-dispatch + out-of-page-bookmark mutations re-red | slice 3 |
| 2026-07-10 | Slice 3 (TC-233-06/07/16) | `qualifyCurrentDirectMediaRow` extracted from plan-231 controller (231 suite GREEN unchanged), `DirectMediaLibraryBatchActionsCoordinator`, ten-item ceiling | focused GREEN | one list-capable native call per dispatch, merged preflight+native per-item outcomes, failed-only retry, `kMaxDirectMediaSelection == kMaxMediaEgressItems` | synthesized-parent, over-cap, Files→Photos, clear-all mutations re-red | destructive slice |
| 2026-07-10 | Slice 4 (TC-233-08, destructive checkpoint) | `deleteDirectMediaSelectionForMe`, confirmation dialog, wired production dispatch | focused GREEN; `delete_message_use_case_test` GREEN | cancel = zero lookups; one `getMessage` per unique parent; one delete per resolved parent; missing parent = typed failure, stays selected; same-ID group/unresolved rows+files and exports survive | confirmation-bypass, per-attachment fan-out, null-parent-synthesis mutations re-red | Go to Message |
| 2026-07-10 | Slice 5 (TC-233-09/10/11) | wired `_goToLibraryMessage` (serial bounded paging, truthful missing settle, transient highlight), reveal delegate seam, `ConversationScreen.highlightedMessageId` | focused GREEN | loaded target: zero extra pages, exact key, highlight clears; unloaded: serial gated pages, stop-on-match; missing: call count == available pages, truthful snackbar | early-stop + ignore-hasMore mutations re-red | closure gates |
| 2026-07-10 | Slice 6 (TC-233-13 + closure) | 1,000-entry virtualization + en/de/ar + RTL + semantics; six files registered in both 1:1 arrays; host planner lists all six | `run_test_gates.sh 1to1` GREEN after fix; `flutter analyze` clean for all plan files; `git diff --check` clean; Go/relay untouched | eager-Column and forbidden-import mutations re-red; 231 frozen transport inventory preserved by routing BOTH delete paths through the single `_deleteMessageForMeLocally` call site | none | committed |
