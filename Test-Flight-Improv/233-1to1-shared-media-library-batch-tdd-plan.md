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

## Problem And Evidence

- Behavior to improve: a user must be able to browse all images/videos shared with one direct contact, filter and bookmark them, open a cross-message viewer, select multiple items, save/share/delete safely, and jump back to the owning message.
- Impact: HEAD makes media discoverable only by scrolling message history. Opening media builds pages from the tapped message's completed paths, so users cannot inspect or manage conversation-wide media efficiently.
- Confirmed current mechanism: `ConversationScreen.mediaTapHandler` opens `FullScreenImageViewer` from only one message's attachments at `lib/features/conversation/presentation/screens/conversation_screen.dart:596-628`.
- Confirmed current mechanism: direct history is page-bounded in `ConversationWired`, with initial and older-page loading at `lib/features/conversation/presentation/screens/conversation_wired.dart:1148-1177` and `:1344-1383`; the reverse `ListView.builder` uses message keys in `conversation_screen.dart:509-516`.
- Confirmed current gap: `MediaAttachmentRepository` only loads attachment rows by one or more already-known message IDs (`lib/features/conversation/domain/repositories/media_attachment_repository.dart:4-45`). HEAD has no conversation-scoped gallery, selection, bookmark UI, or Go to Message result.
- Confirmed destructive boundary: `deleteMessageForMe` removes the whole local message and its owned attachment artifacts, not an individual attachment (`lib/features/conversation/application/delete_message_use_case.dart:17-47`, `:435-463`).
- Existing coverage: direct pagination tests preserve the 50-row window/load-older behavior; viewer tests preserve page swiping; delete tests prove incoming local deletion and sibling preservation. No existing test can fail for a direct media library or cross-message target.
- Missing coverage: scoped navigation, stable paged filters, lazy viewer continuation, selection identity, bookmark durability, batch partial outcomes, message-deduplicated deletion, missing/evicted rows, Go to Message across unloaded pages, virtualization, and accessibility.
- Refuted finding: this feature does not need a new attachment schema or transport query. Plan 228 owns DB v96 and stable `MediaLibraryPage` queries; all 1:1 library actions are local/native egress.
- Unresolved findings: N/A. Individual-attachment deletion is deliberately not claimed; Delete removes each selected item's whole owning message after explicit copy explains that consequence.
- Affected production, test, and gate files: a new direct shared-media screen/wired/controller under `lib/features/conversation/`; direct conversation menu/navigation and bounded scroll targeting; three-locale l10n; new widget/application tests; both 1:1 test arrays.

## Scope Contract And Guard

In scope:
- Add a Shared Media entry within an existing `ConversationWired` direct chat; construct only `MediaLibraryScope.direct(contactPeerId)` and never accept a caller-provided group/announcement scope.
- Page `MediaLibraryEntry` values newest-first through plan 228 `MediaLibraryCursor/Page`, with All, Photos, Videos, and Bookmarked filters; use builder/sliver virtualization and a bounded page size.
- Open plan 230 with typed items spanning parent messages. Preserve stable attachment/message identity, append the next media page lazily near the viewer boundary, and deduplicate by attachment ID.
- Persist bookmark toggles through plan 228 `MediaLibraryRepository.setBookmarked`; reconcile the active filter without losing unrelated selection or scroll state.
- Support batch Save to Photos, Save to Files, and external OS Share through plan 227's list-capable egress request, with per-item typed outcomes and retry of failed-only items.
- Support batch Delete for Me by deduplicating selection by parent message ID, confirming that entire messages/all their attachments are removed locally, invoking the existing use case once per unique message, and reporting partial outcomes.
- Return a Go-to-message result to the still-mounted direct conversation; load older pages until the target message is present or history is exhausted, reveal its stable key, and apply a transient highlight without resetting the loaded window.

Must preserve:
- Existing direct initial/load-older ordering, reverse-list anchoring, and 50-row page behavior -> direct pagination/widget `GREEN sentinels` plus TC-233-10/11.
- Delete for Everyone remains sender-authorized and transport-backed only from its existing message action -> `conversation_wired_test.dart::delivered outgoing rows offer delete-for-me and delete-for-everyone`; `GREEN sentinel`.
- Source media, captions, encryption metadata, and exported copies remain unchanged after bookmark/save/share -> TC-233-05/06/07.
- Missing or `evicted` media never silently auto-downloads; explicit Retry remains plan 229-owned -> TC-233-12.

Hard `Do not`:
- Do not add or alter DB migrations, direct/group payloads, delivery/dedup, relay queries, Bridge commands, Go/libp2p code, group publish, or announcement permissions.
- Do not implement item-only attachment deletion or imply it in confirmation copy.
- Do not route external Share through the internal forwarding picker; plan 232 owns Forward.
- Do not load all conversation history/media eagerly, scan files on build, use offset-only pagination, or identify items by local path.
- Do not delete Photos/Gallery/Files exports or attachments owned by a sibling message after a partial batch failure.

Deferred / accepted difference:
- Item-only deletion while retaining the parent message -> future attachment-deletion product plan.
- Multi-message/multi-source internal Forward from the library -> evidence-gated `Test-Flight-Improv/249-1to1-shared-media-batch-forwarding-tdd-plan.md`, which owns album-versus-individual, caption/order, opaque provenance, selection-cap, and partial-retry decisions. Plan 233 intentionally exposes no batch Forward action.
- Group and announcement libraries -> plans 237 and 241; they own their own permissions, navigation, and gate registration.
- Cache re-download/eviction and video resume mechanics -> plans 229 and 230.

Dependencies:
- `Test-Flight-Improv/227-received-media-native-egress-foundation-tdd-plan.md` for bounded-list native Save/Share requests, typed per-item/aggregate outcomes, and TC-227-05/06 physical Android/iOS single+batch egress proof.
- `Test-Flight-Improv/228-shared-media-library-bookmark-persistence-tdd-plan.md` for DB v96, `MediaLibraryRepository`, `MediaLibraryScope`, `MediaLibraryEntry`, and stable cursor/page behavior.
- `Test-Flight-Improv/229-cross-track-media-download-storage-controls-tdd-plan.md` for `evicted` semantics and explicit retry ownership.
- `Test-Flight-Improv/230-shared-typed-media-viewer-tdd-plan.md` for typed current-item identity and callback-only viewer actions.
- `Test-Flight-Improv/231-1to1-received-media-core-actions-tdd-plan.md` for direct action eligibility and the existing whole-message Delete-for-Me wiring.

## Test Contract

| Case | Behavior | Named test/proof | Tier / fixture | HEAD -> GREEN | Mutation | Gate / registration |
|---|---|---|---|---|---|---|
| TC-233-01 | A direct conversation exposes one localized Shared Media entry and launches the library with exactly that contact's direct scope. | `test/features/conversation/presentation/screens/conversation_shared_media_library_test.dart::direct chat opens one contact-scoped shared media library` | widget host / `ConversationWired` fixture + recording repository factory | HEAD compile RED: route/screen absent -> one menu action opens `MediaLibraryScope.direct(expectedPeerId)` and no group scope can be injected | pass own peer id, omit contact id, or expose route outside direct chat -> TC-233-01 red | `flutter test test/features/conversation/presentation/screens/conversation_shared_media_library_test.dart --plain-name 'direct chat opens one contact-scoped shared media library'`; AUTO (`test/features/**`) + add file to `ONE_TO_ONE_TESTS` and `ONE_TO_ONE_HOST_TESTS` |
| TC-233-02 | All/Photos/Videos/Bookmarked filters page a stable newest-first grid without duplicates, stale-filter results, or eager exhaustion. | `test/features/conversation/presentation/screens/conversation_shared_media_library_test.dart::filters cancel stale pages and preserve stable paged grid order` | widget/application host / controllable paged `MediaLibraryRepository` | HEAD compile RED -> only requested page size loads; tied timestamps retain repository order; switching filters rejects a delayed old result | append a stale response, key by path, or fetch until `hasMore=false` during first build -> TC-233-02 red | `flutter test test/features/conversation/presentation/screens/conversation_shared_media_library_test.dart --plain-name 'filters cancel stale pages and preserve stable paged grid order'`; AUTO + both 1:1 arrays |
| TC-233-03 | Tapping a tile opens plan-230 typed pages across parent messages at the exact selected attachment and swiping updates metadata/actions to that item. | `test/features/conversation/presentation/screens/conversation_shared_media_viewer_test.dart::library opens cross-message typed viewer at exact attachment identity` | widget host / three entries from different parent messages + fake viewer callback | HEAD compile RED: library absent and viewer caller is per-message paths -> initial identity and every post-swipe attachment/message callback are exact | derive initial index from path or retain the first parent message -> TC-233-03 red | `flutter test test/features/conversation/presentation/screens/conversation_shared_media_viewer_test.dart --plain-name 'library opens cross-message typed viewer at exact attachment identity'`; AUTO + add file to both 1:1 arrays |
| TC-233-04 | Near the viewer boundary, one next page is appended in stable order; duplicate callbacks/results never duplicate pages or lose current identity. | `test/features/conversation/presentation/screens/conversation_shared_media_viewer_test.dart::viewer lazy continuation is fenced deduplicated and current-item stable` | widget/application host / gated page completers | HEAD compile RED -> concurrent boundary signals issue one cursor call; duplicate attachment ID appears once; current page remains selected | remove in-flight fence or replace list while viewing -> TC-233-04 red | `flutter test test/features/conversation/presentation/screens/conversation_shared_media_viewer_test.dart --plain-name 'viewer lazy continuation is fenced deduplicated and current-item stable'`; AUTO + both 1:1 arrays |
| TC-233-05 | Bookmark toggles persist after route/repository recreation and Bookmarked-filter removal does not disturb sibling bookmarks or unrelated selected IDs. | `test/features/conversation/presentation/screens/conversation_shared_media_library_test.dart::bookmark persists across reopen and reconciles active filter narrowly` | widget/repository host / plan-228 fake + fresh controller | HEAD compile RED -> exact attachment update survives reopen; unbookmark removes only that tile from active filter | update by message/scope or clear selection wholesale -> TC-233-05 red | `flutter test test/features/conversation/presentation/screens/conversation_shared_media_library_test.dart --plain-name 'bookmark persists across reopen and reconciles active filter narrowly'`; AUTO + both 1:1 arrays |
| TC-233-06 | Batch Save sends each unique eligible entry once to the chosen Photos/Files destination and preserves successful/failed source state. | `test/features/conversation/application/direct_media_library_batch_actions_test.dart::batch save delegates unique eligible entries and returns per-item outcomes` | application host / fake list-capable `ReceivedMediaEgressService` | HEAD compile RED: batch controller absent -> exact ordered IDs/destination reach egress once; protected/missing rows fail closed; source snapshots remain equal | duplicate a selected ID, map Files to Photos, or mutate bookmark/path on failure -> TC-233-06 red | `flutter test test/features/conversation/application/direct_media_library_batch_actions_test.dart --plain-name 'batch save delegates unique eligible entries and returns per-item outcomes'`; AUTO + add file to both 1:1 arrays |
| TC-233-07 | Batch external Share presents one list-capable OS egress request, never opens internal targets, and failed/cancelled items remain selected for truthful retry. | `test/features/conversation/application/direct_media_library_batch_actions_test.dart::batch external share is one native request with failed-only retry state` | application host / fake egress + throwing share-picker/delivery spies | HEAD compile RED -> one ordered external request, zero picker/P2P calls, and only non-success IDs remain selected | loop one chooser per item, invoke `ShareTargetPickerWired`, or clear all selection on partial result -> TC-233-07 red | `flutter test test/features/conversation/application/direct_media_library_batch_actions_test.dart --plain-name 'batch external share is one native request with failed-only retry state'`; AUTO + both 1:1 arrays |
| TC-233-08 | Batch Delete for Me deduplicates by parent message, confirms whole-message scope, cleans owned rows/files once, preserves siblings/exports, and keeps failed messages selected. | `test/features/conversation/application/direct_media_library_batch_actions_test.dart::batch delete removes unique whole messages locally with partial outcome preservation` | application/widget host / duplicate attachments per message + fake delete use case/file snapshots | HEAD compile RED -> two selected attachments from message A cause one delete; message B failure remains; unrelated message/export survives; zero delete-for-everyone/network calls | delete per attachment, delete exports, or drop failed selection -> TC-233-08 red | `flutter test test/features/conversation/application/direct_media_library_batch_actions_test.dart --plain-name 'batch delete removes unique whole messages locally with partial outcome preservation'`; AUTO + both 1:1 arrays |
| TC-233-09 | A Go to Message result already in the conversation window reveals and transiently highlights exactly its stable message key without replacing scroll history. | `test/features/conversation/presentation/screens/conversation_shared_media_go_to_message_test.dart::loaded target reveals exact message and preserves conversation window` | widget host / fake scroll target delegate + preloaded messages | HEAD compile RED: route result/target coordinator absent -> exact key is revealed once, highlight clears, loaded IDs and composer focus remain | target by attachment/path or rebuild conversation from page one -> TC-233-09 red | `flutter test test/features/conversation/presentation/screens/conversation_shared_media_go_to_message_test.dart --plain-name 'loaded target reveals exact message and preserves conversation window'`; AUTO + add file to both 1:1 arrays |
| TC-233-10 | An unloaded Go to Message target loads older pages serially until found, stops immediately on match, and preserves page order/anchor. | `test/features/conversation/presentation/screens/conversation_shared_media_go_to_message_test.dart::unloaded target pages backward boundedly then reveals exact row` | widget/application host / gated direct pagination fixture | HEAD compile RED -> one page at a time; matching page stops further calls; row is revealed without duplicate IDs or anchor jump | fire all pages concurrently, stop one page early, or reset `_messages` -> TC-233-10 red | `flutter test test/features/conversation/presentation/screens/conversation_shared_media_go_to_message_test.dart --plain-name 'unloaded target pages backward boundedly then reveals exact row'`; AUTO + both 1:1 arrays |
| TC-233-11 | Missing/deleted Go to Message targets terminate when history is exhausted and show a truthful result without an infinite spinner or unrelated navigation. | `test/features/conversation/presentation/screens/conversation_shared_media_go_to_message_test.dart::missing target exhausts history once and settles truthfully` | widget/application host / finite cursor fixture | HEAD compile RED -> finite call count equals available pages, loading settles, current conversation/scroll remain usable | ignore `hasMore`, retry forever, or reveal a nearest row -> TC-233-11 red | `flutter test test/features/conversation/presentation/screens/conversation_shared_media_go_to_message_test.dart --plain-name 'missing target exhausts history once and settles truthfully'`; AUTO + both 1:1 arrays |
| TC-233-12 | Missing, integrity-failed, protected, and `evicted` entries show truthful state; batch egress is disabled and opening the library triggers zero implicit downloads. | `test/features/conversation/presentation/screens/conversation_shared_media_library_test.dart::unavailable media is visible but never auto-downloaded or exported` | widget host / status matrix + throwing downloader/egress | HEAD compile RED -> status/accessibility text is exact; downloader/egress call count zero until explicit plan-229 Retry | treat evicted as pending, hide expiry truth, or auto-retry on grid build -> TC-233-12 red | `flutter test test/features/conversation/presentation/screens/conversation_shared_media_library_test.dart --plain-name 'unavailable media is visible but never auto-downloaded or exported'`; AUTO + both 1:1 arrays |
| TC-233-13 | Large libraries stay virtualized; selection/action semantics and long labels remain reachable in English, German, and RTL Arabic on a small viewport. | `test/features/conversation/presentation/screens/conversation_shared_media_library_test.dart::library is virtualized localized and accessible in small LTR RTL viewports` | widget host / 1,000-entry lazy fixture, semantics tester, 320x568 viewport | HEAD compile RED -> bounded built-child count, selected-count semantics, scrollable action surface, and no overflow/exceptions | replace builder/sliver with eager `Column`, hardcode English, or omit selected semantics -> TC-233-13 red | `flutter test test/features/conversation/presentation/screens/conversation_shared_media_library_test.dart --plain-name 'library is virtualized localized and accessible in small LTR RTL viewports'`; AUTO + both 1:1 arrays; existing ARB parity test |
| TC-233-14 | The direct library imports no transport/group/announcement implementation and existing direct pagination/delete-for-everyone behavior remains unchanged. | `test/features/conversation/application/direct_media_library_boundary_test.dart::library is local direct-scoped and transport-free` plus existing sentinels | host source-contract + `GREEN sentinels` | HEAD compile RED: target sources absent; existing sentinels GREEN -> forbidden imports remain absent, Go/relay paths remain baseline-equal, and sentinels stay GREEN | import Bridge/group repository, change a Go/relay path, or route batch delete through delete-for-everyone -> TC-233-14 red | `flutter test test/features/conversation/application/direct_media_library_boundary_test.dart`; AUTO + both 1:1 arrays; run direct pagination/delete sentinels and baseline status+binary-diff comparison below |

### Test Notes

- TC-233-08 deliberately selects two attachments from one message and one from another. The expected delete-call count is two unique message IDs, never three attachment IDs.
- TC-233-09/10 must assert the stable message key and final visible/highlight state. Merely asserting that `loadOlder()` was called is vacuous.
- TC-233-13 records built/rendered child count before and after scrolling; total fixture size alone does not prove virtualization.

## Implementation Steps

1. Snapshot `git status --short`; confirm dependencies 227–231 and plan-228 DB v96 contract have landed. Add TC-233-01/02/06/08/10/14 before production edits and record their causal REDs.
2. Add direct-owned library route, state/controller, stable cursor/filter paging, and builder/sliver grid. Stop-if any repository query needs a Bridge/relay/group implementation.
3. Adapt library entries to plan-230 typed items and add in-flight-fenced lazy continuation, exact-current-item actions, bookmark reconciliation, and unavailable states.
4. Add the batch coordinator over plan 227 and the existing delete-for-me use case; preserve failed-only selection and whole-message confirmation semantics.
5. Add bounded Go to Message return/load/reveal/highlight coordination inside `ConversationWired` without replacing its existing pagination window.
6. Add three-locale copy, register the new direct files in both 1:1 arrays, run focused GREEN/sentinels/gates, exercise representative mutations, and enforce the Go/relay no-diff guard.

## Risks And Blind Spots

- Stable selection can drift when filters/pages change -> TC-233-02/04/05 key only by attachment ID and retain exact current identity.
- Batch delete can over-delete when several attachments share one message -> TC-233-08 deduplicates by parent message and proves sibling/export preservation.
- Go to Message can loop or jump the scroll anchor -> TC-233-09/10/11 cover loaded, older, and absent targets.
- Lifecycle / derived-state durability: TC-233-05 recreates route/repository for bookmark state; plan 228 owns DB durability.
- Sibling-surface consistency: library and conversation viewer use the same plan-230 typed item/action contract in TC-233-03/04.
- Destructive-action side effects: TC-233-08 asserts removals, partial failure, exports, unrelated messages, and zero transport calls.
- Invariant re-verification under new transitions: delayed filter/page completions recheck generation, membership, `mounted`, and selection before applying in TC-233-02/04; Go to Message rechecks target existence after each page in TC-233-10/11.

## Acceptance Gates

```bash
# Snapshot and dependency preconditions
git status --short
git status --short --untracked-files=all -- go-mknoon go-relay-server > /tmp/plan-233-go-relay-status.before
git diff --binary -- go-mknoon go-relay-server > /tmp/plan-233-go-relay-diff.before
test -f Test-Flight-Improv/228-shared-media-library-bookmark-persistence-tdd-plan.md
test -f Test-Flight-Improv/230-shared-typed-media-viewer-tdd-plan.md

# First causal RED; expect non-zero because the direct library route/screen is absent
flutter test test/features/conversation/presentation/screens/conversation_shared_media_library_test.dart --plain-name 'direct chat opens one contact-scoped shared media library'

# Focused GREEN; expect exit 0 and zero failed tests
flutter test test/features/conversation/presentation/screens/conversation_shared_media_library_test.dart
flutter test test/features/conversation/presentation/screens/conversation_shared_media_viewer_test.dart
flutter test test/features/conversation/presentation/screens/conversation_shared_media_go_to_message_test.dart
flutter test test/features/conversation/application/direct_media_library_batch_actions_test.dart
flutter test test/features/conversation/application/direct_media_library_boundary_test.dart

# Preservation and named gate selection
flutter test test/features/conversation/presentation/screens/conversation_wired_test.dart --plain-name 'delivered outgoing rows offer delete-for-me and delete-for-everyone'
flutter test test/features/conversation/application/delete_message_use_case_test.dart
flutter test test/shared/widgets/media/full_screen_image_viewer_test.dart
flutter test test/l10n/l10n_integrity_test.dart --plain-name 'ARB files have identical non-empty key and placeholder sets'
./scripts/run_test_gates.sh 1to1
./scripts/run_host_test_gates.sh 1to1 --list
./scripts/run_host_test_gates.sh feature-host-all

# Scope and hygiene
git status --short --untracked-files=all -- go-mknoon go-relay-server | cmp -s - /tmp/plan-233-go-relay-status.before
git diff --binary -- go-mknoon go-relay-server | cmp -s - /tmp/plan-233-go-relay-diff.before
flutter analyze
git diff --check
```

## Execution Interpretation And Done Criteria

- Expected RED: TC-233-01 compile-fails because no direct Shared Media route/screen exists.
- Green sentinel: existing direct page loading, incoming local delete, outgoing Delete for Everyone, and path-based viewer tests remain GREEN.
- Pre-existing dirty tree / known failure: snapshot at execution start; preserve unrelated current messaging/push/graph changes.
- Environment blocker: none for this host composition/result-handling slice; plan 227 independently closes single and bounded-list native egress on physical Android/iOS.
- Scope drift: any migration, payload, group/announcement permission, download automation, Bridge/P2P/relay, or Go edit blocks completion.

- [ ] Every behavior has a named causal test or explicit sentinel.
- [ ] Scope/filter paging, cross-message viewing, bookmarks, batch outcomes, Go to Message, missing state, virtualization, and localization pass.
- [ ] New direct tests are selected by both 1:1 arrays.
- [ ] Representative stale-page, duplicate-ID, over-delete, infinite-page, eager-build, and forbidden-import mutations re-red.
- [ ] Existing direct pagination/delete/viewer sentinels and named host gates pass.
- [ ] `flutter analyze` has no new issues; `git diff --check` and Go/relay no-diff guard are clean.
- [ ] Scope Contract And Guard is respected.

## Handoff

- First causal RED command: `flutter test test/features/conversation/presentation/screens/conversation_shared_media_library_test.dart --plain-name 'direct chat opens one contact-scoped shared media library'`.
- Preservation command: `flutter test test/features/conversation/presentation/screens/conversation_wired_test.dart --plain-name 'delivered outgoing rows offer delete-for-me and delete-for-everyone'`.
- Manual registration: add the five new direct library/action files to both `scripts/run_test_gates.sh::ONE_TO_ONE_TESTS` and `scripts/run_host_test_gates.sh::ONE_TO_ONE_HOST_TESTS`; widget/application tests also AUTO-glob into `feature-host-all`.
- Migration: none; consumes plan-228 DB v96 repository state.
- Boundary closure: host widget/application proof over injected repository/egress seams; plan 227 owns physical Android/iOS single and bounded-list egress proof. No relay/device/Go run is required here.
- Unresolved evidence: none. Item-only deletion and internal Forward integration are explicit deferred owners, not hidden gaps.

## Execution Progress

| Time | Phase | Files | Last command/result | Current evidence | Decision/blocker | Next |
|---|---|---|---|---|---|---|
| - | not started | - | - | - | awaiting accepted plan and dependencies 227–231 | contract extraction |
