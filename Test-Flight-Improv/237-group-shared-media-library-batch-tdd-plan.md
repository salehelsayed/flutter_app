# 237 - Group Shared Media Library And Batch Actions

Status: IMPLEMENTED — accepted; independent QA and host closure green
Type: New Feature
Spec: free-text intent — add a paged discussion-group media library with cross-message viewing, batch actions, bookmarks, and Go to message
Classification: implemented
Closure tier: host

## Planning Progress

| Time | Role | Files inspected | Decision/blocker | Next action |
|---|---|---|---|---|
| 2026-07-09 | Evidence Collector / Planner | plan-228 library contract, group conversation/info screens and wiring, group message repository, viewer, media attachment repository, delete/egress/forward/storage plans, group tests and gate scripts | HEAD loads media only for the currently loaded timeline page and has no group gallery. Shared repository/viewer/action primitives are deliberately owned by plans 228-230/235-236. | Land those primitives, then add a discussion-only route/controller and first widget RED. |
| 2026-07-10 | Planner | revised plan-228 owner/cursor/page contracts and plan-235 delete journal | Gallery integration must use exact group scope, reject cursor/filter mismatches, enforce `1..100`, and exclude direct/unresolved same-ID rows. | Add strict caller-contract and production collision rows. |
| 2026-07-10 | Counterexample review | committed HEAD, dirty Plan-236/v99 work, group egress/delete controllers, media-library interface, Group Info route, thumbnail widgets, `GROUP_TESTS` | Audit accepted with bounded corrections. Plan 236 is not closed or committed; batch egress needs dispatch-time qualification and the native cap; delete cannot infer success from a `Future<void>`; no repository change stream exists; current viewer is already typed. | Block execution on concrete committed Plan-236 evidence, use bounded lifecycle/action refresh instead of a new stream, and make route/poison/decode tests causal. |
| 2026-07-10 | Blocker repair audit | committed Plan-236 status/checklist, commit `b1d043eb3`, DB v99 migration/registries, forwarding symbols/tests/device proofs, and `GROUP_TESTS` registrations | The substantive committed prerequisite passes. The extra exact `Closure verdict: accepted` sentence was a Plan-237-only metadata convention and is not part of Plan 236's closeout format. | Replace the brittle sentence check with implemented/device-proven status, completed-checklist, artifact, registration, and clean-path assertions; proceed to GML-01 only while that full preflight stays green. |

## Problem And Evidence

- Behavior to improve: a user needs one shared-media surface for a `GroupType.chat` group, with paged Images/Videos/Bookmarked views, cross-message viewer navigation, bounded multi-select actions, and Go to message.
- Impact: media is currently discoverable only by scrolling message history; older media, bookmarked items, and bulk retention/sharing operations are effectively inaccessible.
- Confirmed timeline limit: `_loadMessages` in `lib/features/groups/presentation/screens/group_conversation_wired.dart` requests a bounded timeline page and builds media only for loaded messages. That is not a media-library query.
- Confirmed repository foundation: Plan 228 provides `MediaLibraryScope.group(groupId)`, group owner isolation, group tombstone filtering, scope/filter-bound opaque cursors, parent metadata, and page limits `1..100`.
- Confirmed viewer state: group production already uses `FullScreenTypedMediaViewer`; the missing capability is a cursor-backed host spanning attachments from different parent messages, not a replacement for a path-only viewer.
- Confirmed navigation gap: `GroupConversationWired._onInfo` pushes Group Info and discards its result. Existing highlight handling uses the immutable initial anchor and cannot consume a later library result or load an off-page target.
- Confirmed action foundation: `GroupReceivedMediaActionsController` reloads the exact group/incoming parent and group-owned attachment, validates type/MIME/integrity/lifecycle/resolved path/file existence immediately before egress. Batch Save/Share must extract or reuse that complete qualifier rather than trust gallery state.
- Confirmed native limit: `ReceivedMediaEgressRequest.maxItems` is ten. A common selection ceiling of ten keeps all Plan-237 multi-select actions bounded and gives Save/Share an exact native boundary.
- Confirmed destructive boundary: Plan 235's delete coordinator returns `Future<void>` and durable cleanup may continue from its v98 journal. The library cannot clear selection merely because the call completed; it must reconcile the bounded affected parents from repository/tombstone state.
- Confirmed refresh boundary: `MediaLibraryRepository` exposes page loading, not a change stream. This plan promises refresh on mount, app resume, and action completion; it does not add a speculative live event bus.
- Confirmed decode boundary: `MediaGridCell` delegates to `MediaThumbnailImage` with a bounded `cacheWidth` for static image/video thumbnails. Reuse and test that production path; animated GIF behavior remains the existing viewer/thumbnail contract.
- Confirmed gate risk: `groups` executes only the static `GROUP_TESTS` array, so every new Plan-237 host file needs an exact registration assertion. The repository-wide analyzer has a known non-zero baseline and cannot be used as a bare pass/fail closure claim.
- Confirmed dependency closure: committed HEAD `b1d043eb3` contains Plan 236's `IMPLEMENTED`/host-green/device-proven status, a fully checked done-criteria list, DB v99, migration/registries, forwarding symbols, host/device proof sources, and exact `GROUP_TESTS` registrations. The substantive prerequisite assertions pass; no separate closeout-sentence convention is required.

## Graph Grounding Snapshot

- Graph fingerprint / freshness: `939c734a3edd83cd`; current.
- Query / profile: `python3 graphify-arch/tdd_context.py query "Plan 237 prerequisite blocker Plan 236 Closure verdict accepted DB v99 group media forwarding GroupMediaForwardSourceGate group_media_forward_policy" --profile tdd --budget 700`.
- Anchor: `groupMediaForwardSourceGate` -> `lib/features/share/application/share_batch_delivery_coordinator.dart:154`.
- Surfaced production/proof files: `lib/features/groups/application/group_media_forward_policy.dart`, `lib/features/groups/application/send_group_message_use_case.dart`, `lib/features/share/application/share_batch_delivery_coordinator.dart`, and `test/features/share/application/share_batch_delivery_coordinator_test.dart` with `GROUP_TESTS` registration.
- Graph gaps requiring source search: plan closeout prose, commit membership, migration/device proof paths, and exact static-array registrations are not graph authorities; all were verified from committed HEAD.
- Reuse rule: these anchors may be reused by execution, but current source and literal commands remain authoritative.

## Scope Contract And Guard

In scope:

- `GroupType.chat` only. Add Shared media from Group Info and reject stale/deep routes for announcement, QA, dissolved, or unavailable groups before any media query.
- Page with exact `MediaLibraryScope.group(groupId)`, a limit in `1..100`, and Images/Videos/Bookmarked filters. Treat cursors as opaque and discard them when group/filter changes.
- Render only group-owned entries for the named group. The UI adapter independently rejects direct/unresolved poisoned entries even if a fake or future repository regression returns them.
- Render a lazy grid using the existing bounded thumbnail component. Large static images and video thumbnails must request bounded decode dimensions; pages are loaded only near the cursor threshold and duplicate in-flight requests coalesce.
- Open the existing typed viewer at the selected attachment and page across parent-message boundaries without path-based identity, duplicate, or skip.
- Define one `kGroupSharedMediaSelectionLimit = 10`. At ten items actions operate normally; item eleven is rejected before state mutation or dependency calls.
- Multi-select shows the safe capability intersection. Save/Share/Bookmark/Delete/Remove-local-copy are supported; internal multi-item Forward remains absent. Single-item Forward dispatches the exact selected item through Plan 236.
- Batch Save/Share reloads and qualifies every selected item at dispatch using the complete current group-parent/attachment/type/MIME/integrity/lifecycle/file contract, then sends exactly one ordered native request for eligible unique identities. It returns typed preflight and native outcomes; retry selection contains failed items only.
- Batch Bookmark uses Plan 228. Remove local copy uses Plan 229 without deleting the message, attachment row, or bookmark.
- Batch Delete confirms unique parent messages and calls Plan 235 once per parent. After each void coordinator call, perform a bounded exact-parent reconciliation; remove identities only when repository/tombstone state proves the parent is locally deleted. No-op, conflict, or failed parents remain selected with a truthful result.
- Add exact shared navigation types `GroupSharedMediaLibraryResult` and `GroupSharedMediaGoToMessage(groupId, messageId)`. `GroupInfoWired` propagates the result to the same mounted `GroupConversationWired` instance.
- Add `getMessagesAround(groupId, anchorMessageId, before, after)` with `before` and `after` each bounded to `0..25`. It validates the live exact-group anchor, returns at most 51 ordered messages, and never scans preceding pages.
- Refresh the bounded current page on mount, app resume, and successful/partial action completion. Preserve unaffected cursor/scroll/selection state where identities still exist. New/downloaded media may appear on one of these explicit refresh boundaries; no continuous live-update promise is made.

Must preserve:

- Plan 228 owner isolation, same-ID collision protection, tombstone filtering, cursor signature, replay-safe local state, and literal `1..100` page limit.
- Plan 230 typed viewer behavior and legacy callers.
- Plan 235 v98 journal, whole-message Delete-for-me semantics, atomic prepare, and restart convergence.
- Plan 236 exact source qualification, destination authorization, fresh per-target encryption, failed-only retry, and forwarded-marker semantics.
- Announcement and QA behavior and ordinary conversation entry scroll/focus.

Hard `Do not`:

- Do not start production work while Plan 236 is merely present, staged, dirty, partially green, or missing any committed status/checklist/artifact/registration assertion. The substantive committed preflight must pass.
- Do not query/display this discussion library for announcements or Q&A; Plan 241 owns announcement shared media.
- Do not alter wire payloads, transport, relay, encryption, membership, Go bridge, or go-libp2p.
- Do not add a media-library change stream/event bus in this slice.
- Do not load all messages/attachments, use offset-only media pagination, use timestamp-only identity, or accept a page limit outside `1..100`.
- Do not trust stale UI capability/path metadata at action dispatch.
- Do not accept direct/unresolved rows, export unavailable/policy-denied media, clear a failed delete selection, or infer native Share recipient delivery from chooser presentation.
- Do not delete a parent twice, treat Remove local copy as message deletion, or claim bookmarks sync to other devices.

Deferred / accepted difference:

- Announcement parity is Plan 241. A global library, search/OCR, albums, backup, and multi-item internal Forward are out of scope.
- No new database migration belongs to Plan 237. It consumes committed v99 from Plan 236 and v98/v96 foundations from Plans 235/228.
- Native Photos/Files/chooser behavior remains Plan 227's device closure. This plan proves qualification, request shaping, and truthful host outcomes.
- Animated-image thumbnail behavior is unchanged; the new decode assertion covers the static image/video path this grid owns.

Dependencies:

- Implemented Plans 227-230 and 235.
- Plan 236 must remain fully implemented, host-green, device-closed, committed at DB v99, fully checked, and registered. Plan-file existence, a status line without artifacts, or worktree-only v99 symbols are insufficient.
- Plan 241 depends on the exact navigation/query contracts named here and is now unblocked by this accepted closure.

## Test Contract

| Case | Behavior | Named test/proof | Tier / fixture | Causal RED -> GREEN | Mutation / gate |
|---|---|---|---|---|---|
| TC-237-01 | Group Info exposes Shared media only for an active chat group; stale/deep non-chat access rejects before querying. | `test/features/groups/presentation/group_shared_media_entry_test.dart::GML-01 shared media entry and route are discussion only` | host widget / chat, announcement, QA, dissolved fixtures + query spy | Route absent -> chat navigates; every rejected route makes zero library calls. | Remove/prepone guard -> red; `GROUP_TESTS`. |
| TC-237-02 | Production queries exclude direct/unresolved collisions, other groups, and tombstoned parents. | `test/features/groups/presentation/group_shared_media_wired_test.dart::GML-02 production gallery is owner isolated under group id collisions` | host repository/widget integration / mixed current-schema SQLite fixture | UI absent -> only live group-owned identities render. | Remove owner/group/tombstone predicate -> red; `GROUP_TESTS`. |
| TC-237-02F | Strict controller inputs use exact scope/filter/cursor/limit, and UI independently refuses poisoned direct/unresolved entries returned by the fake. | `test/features/groups/application/group_shared_media_repository_contract_test.dart::GML-02F strict contract rejects request drift and poisoned owner adaptation` | host application/widget / argument-checking fake that deliberately returns poisoned lanes | Wrong group/filter/cursor, limit 0/101 fail; tab/group clears cursor; poisoned rows cause zero render/selection/viewer adaptation. | Prefilter fake, trust returned owner, or retain cursor -> red; `GROUP_TESTS`. |
| TC-237-03 | Grid paging is lazy/coalesced and large static media uses bounded thumbnail decode dimensions. | `test/features/groups/presentation/group_shared_media_screen_test.dart::GML-03 grid virtualizes pages and bounds static thumbnail decode` | host widget / three tied-timestamp pages + very large static image/video thumbnail + image-provider probe | Initial builds stay bounded; threshold produces one request; every limit is valid; identities occur once; decode width is `<=400`. | Eager-build, remove coalescing/cache bound, or request 101 -> red; `GROUP_TESTS`. |
| TC-237-04 | Typed viewer starts at exact identity and crosses parent/page boundaries without duplicate or skip. | `test/features/groups/presentation/group_shared_media_wired_test.dart::GML-04 typed viewer crosses parent and cursor boundaries` | host widget / tied timestamps, mixed media, different parents | Existing one-parent host cannot satisfy cross-parent order -> stable cursor-backed sequence. | Key by path or omit boundary fetch -> red. |
| TC-237-05 | Selection is capped at ten and exposes safe action intersection; item eleven has zero side effects and multi-item Forward is absent. | `test/features/groups/presentation/group_shared_media_screen_test.dart::GML-05 selection cap and capability intersection fail closed` | host widget / eligible, evicted, failed, same-parent, policy-denied rows | Ten select; eleventh rejected before mutation/call; union-only action absent. | Remove cap, use union/first row, expose batch Forward -> red. |
| TC-237-06 | Save/Share requalifies mutable current rows and parents, rejects aliases/conflicts, sends one ordered request of at most ten, and reports typed preflight/native outcomes with failed-only retry. | `test/features/groups/application/group_media_batch_actions_test.dart::GML-06 batch egress requalifies current rows and honors native cap` | host application / production qualifier extraction, mutable repositories, real temp/hash files, recording native service | Stale state currently can be trusted -> exact group/incoming/owner/MIME/integrity/lifecycle/path checks run before one call; 10 succeeds, 11 and conflicting aliases call zero; failed-only retry preserves order. | Skip a qualifier, split calls, dedupe by path, retry successful/presented rows, or call at 11 -> red. |
| TC-237-06F | Single-item Forward sends the exact current gallery/viewer identity through Plan 236 once. | `test/features/groups/presentation/group_shared_media_wired_test.dart::GML-06F selected item reaches committed group forward adapter exactly once` | host wired / two attachments under one parent plus different-message control, recording request builder/launcher | Gallery absent -> selected attachment/message/group form one Plan-236 request; sibling and stale metadata do not substitute. | Forward first/bubble-all item or bypass request builder -> red. |
| TC-237-07 | Grid/viewer bookmarks share one group-owned local state and survive a new repository/widget instance without touching collision lanes or wire JSON. | `test/features/groups/integration/group_shared_media_bookmark_test.dart::GML-07 bookmarks are owner isolated and durable across remount` | host integration / production repository and current-schema same-ID fixture | Gallery absent -> exact attachment state persists and rehydrates. | Memory-only or untyped update -> red. |
| TC-237-08 | Delete confirms/dedupes parents, cancel is zero-op, and selection clears only after bounded repository/tombstone reconciliation proves deletion. | `test/features/groups/application/group_media_batch_actions_test.dart::GML-08 delete reconciles void coordinator outcomes before clearing selection` | host integration / real Plan-235 coordinator seam, same-parent siblings, other parent, collision rows, no-op/conflict/failure fixtures | Prior plan clears after void call -> selected and sibling disappear only for proven deleted parents; failed/no-op/conflict parents remain selected with typed results. | Treat call completion as success, delete per attachment/twice, or clear all selection -> red. |
| TC-237-09 | Remove local copy retains library/message/bookmark state and re-enables egress only after verified redownload. | `test/features/groups/integration/group_shared_media_eviction_test.dart::GML-09 eviction retains entries and truthful eligibility` | host integration / canonical temp media + production repository + Plan-229 seam | Gallery absent -> exact files evict; rows/bookmarks remain; explicit recovery qualifies again. | Delete rows/bookmarks or allow evicted egress -> red. |
| TC-237-10 | Real Library -> Group Info -> same mounted Conversation result flow loads an exact bounded anchor window and highlights each requested target once. | `test/features/groups/presentation/group_shared_media_go_to_message_test.dart::GML-10 production nested route consumes bounded anchor result` + `GML-10R GML-13W nested repeats scroll without local delivery bypass` | host route/repository/widget integration / >50 messages, repeat targets, late page race, wrong-group/missing/tombstoned controls | `_onInfo` currently discards result -> typed `GroupSharedMediaGoToMessage` propagates, `getMessagesAround(...25,25)` returns `<=51`, merges/dedupes, scrolls after layout, and a later target can highlight again. | Test-only initial anchor, ignore pop result, scan pages, leak wrong group, or one-State latch -> red. |
| TC-237-11 | Mount, resume, and action completion perform bounded refresh/reconciliation without a repository stream or unbounded reset. | `test/features/groups/presentation/group_shared_media_wired_test.dart::GML-11 explicit refresh boundaries remove phantom identities` | host widget/application / mutable paged repository + lifecycle/action triggers | Each boundary updates affected identities/current page, preserves valid selection/cursor/scroll, and safely closes a deleted viewer item. | Invent stream dependency, reset all pages, or retain phantom selection -> red. |
| TC-237-12 | Announcement behavior remains unchanged and never queries the discussion library. | `test/features/groups/presentation/group_shared_media_entry_test.dart::GML-12 announcements retain existing behavior without discussion route` | GREEN sentinel / reader+admin announcement fixtures | Existing behavior stays green and query count is zero. | Reuse chat route for announcements -> red. |
| TC-237-13 | Local batch actions cannot bypass into Bridge/send/publish/internal-forward delivery; single-item Forward is the only allowed forwarding dispatch. | `test/features/groups/integration/group_shared_media_transport_boundary_test.dart::GML-13 local library actions make zero transport or internal delivery calls` + `test/features/groups/presentation/group_shared_media_go_to_message_test.dart::GML-10R GML-13W nested repeats scroll without local delivery bypass` | host behavior contract / lower-level boundary plus real `GroupConversationWired -> GroupInfoWired -> Library` callbacks with recording Bridge/P2P/Forward seams | Import scans are insufficient -> real Save/Share/Bookmark/Delete/Evict/Go-to callbacks cause zero delivery; one Forward carries the exact item; multi-select never calls Forward. | Direct delivery from existing `GroupInfoWired` or gallery bypass -> red. |

### Test Notes

- TC-237-02 proves repository SQL. TC-237-02F intentionally violates the repository's normal output contract so the UI defense cannot pass vacuously.
- TC-237-03 asserts the production `MediaGridCell`/`MediaThumbnailImage` static decode bound, not merely lazy child count. It does not redefine animated GIF behavior.
- TC-237-06 should extract a reusable group egress qualifier from the existing single-item controller or call an equivalent shared adapter; duplicated weaker policy is not accepted.
- TC-237-08 does not wait for every file/key cleanup stage. It reconciles the durable parent/tombstone/library visibility boundary; Plan 235 GMA-08 remains authority for restart cleanup convergence.
- TC-237-10 owns `GroupSharedMediaLibraryResult`, `GroupSharedMediaGoToMessage`, and `getMessagesAround`; Plan 241 must reuse them rather than add a competing route/query.
- TC-237-11 deliberately replaces the audit's proposed unnamed change stream with existing lifecycle and action-completion boundaries.

## Implementation Steps

1. Run the committed Plan-236 stop gate. Do not add Plan-237 tests or production until every assertion passes.
2. Snapshot the worktree and analyzer baseline. Add TC-237-01, then run its named causal RED after the file exists; exit 79 because a path is absent is not causal evidence.
3. Add discussion-only Group Info entry/routing and a strict group library controller with poisoned-output defense, opaque cursor reset, valid page limits, lazy pages, and bounded thumbnails.
4. Add the cross-parent typed viewer host and common ten-item selection model.
5. Reuse/extract complete action-time group qualification; implement one-call Save/Share outcomes, bookmark, eviction, and delete reconciliation. Wire the exact selected item to Plan 236 only for single-item Forward.
6. Add the shared typed route result and bounded `getMessagesAround` query. Await and propagate Library -> Group Info -> mounted Conversation; merge/dedupe and apply a transient per-request highlight.
7. Add bounded mount/resume/action-completion refresh. Do not add a repository stream.
8. Register every new host file exactly once in `GROUP_TESTS`, run focused tests, preservation sentinels, the curated groups lane, scoped/baseline analyzer closure, and hygiene.

## Risks And Blind Spots

- Worktree-only dependency can masquerade as landed architecture -> committed Plan-236 closure/symbol/migration/test/registration stop gate.
- Stale UI eligibility can export changed or wrong media -> TC-237-06 dispatch-time qualification and mutable fixtures.
- Batch size/aliases can exceed native semantics -> common cap, at-cap/cap+1 and conflicting-alias zero-call cases.
- Void destructive API can report false success -> TC-237-08 bounded durable-state reconciliation.
- Poisoned output can bypass repository SQL defenses -> TC-237-02F independent UI adapter rejection.
- Lazy grids can still decode huge images -> TC-237-03 production decode-dimension assertion.
- Go-to-message can pass through a test-only initial anchor or leak another group -> TC-237-10 real nested route and bounded scoped query.
- A new event system would overcomplicate this slice -> explicit refresh boundaries in TC-237-11.

## Gate Cadence

- Per-plan closure: focused Plan-237 tests, exact shared persistence/action/forward sentinels, and `./scripts/run_test_gates.sh groups`.
- `feature-host-all`, `core-host-all`, and full `host-all` are not Plan-237 closure gates.
- Full `host-all` runs once after the complete library/batch wave (`233`, `237`, `241`) and once at final rollout closure.

## Acceptance Gates

```bash
# Hard prerequisite: Plan 236 must remain substantively closed and committed.
# Its closeout contract is the implemented/device-proven status plus completed
# criteria and the exact committed artifacts below; no duplicate verdict line.
git show HEAD:Test-Flight-Improv/236-group-received-media-forwarding-tdd-plan.md \
  | rg -q '^Status: IMPLEMENTED .*host-green.*device-proven'
if git show HEAD:Test-Flight-Improv/236-group-received-media-forwarding-tdd-plan.md \
  | rg -q '^- \[ \]'; then
  echo 'Plan 236 has incomplete done criteria' >&2
  exit 1
fi
test "$(git show HEAD:lib/core/database/app_database_version.dart | sed -n 's/^const int currentIdentityDatabaseVersion = \([0-9][0-9]*\);$/\1/p')" -eq 99
git cat-file -e HEAD:lib/core/database/migrations/099_group_messages_is_forwarded.dart
test "$(git show HEAD:lib/core/database/production_migration_registry.dart | rg -c "ProductionMigrationEntry\(99, '099_group_messages_is_forwarded'")" -eq 2
git show HEAD:lib/features/groups/application/group_media_forward_policy.dart | rg -q 'class GroupMediaForwardSourceGate'
git show HEAD:lib/features/groups/application/group_media_forward_intent.dart | rg -q 'class GroupMediaForwardRequest'
git show HEAD:lib/features/groups/presentation/screens/group_conversation_wired.dart | rg -q 'MediaViewerAction.forward'
git show HEAD:test/features/groups/application/group_media_forward_policy_test.dart | rg -q 'GMF-01R dispatch reloads exact group source and verifies current file hash'
git show HEAD:test/core/database/migrations/099_group_messages_is_forwarded_test.dart | rg -q 'GMF-06 v99 extends registries and preserves populated complete v98 state'
git show HEAD:go-mknoon/bridge/bridge_test.go | rg -q 'TestGMF11ForwardedMarkerMapsToPublishOptions'
git show HEAD:integration_test/group_forwarded_marker_db_proof_test.dart | rg -q 'GMF-06D encrypted v99 rejects downgrade and preserves complete group predecessor'
git show HEAD:integration_test/group_real_crypto_onboarding_test.dart | rg -q 'GMF-11 forwarded marker survives real Go bridge group encryption and legacy absence defaults false'

plan236_group_files=(
  test/features/groups/application/group_media_forward_policy_test.dart
  test/features/groups/application/group_media_forward_intent_test.dart
  test/features/groups/presentation/group_media_forward_flow_test.dart
  test/features/share/application/share_batch_delivery_coordinator_test.dart
  test/features/share/presentation/share_target_picker_wired_test.dart
  test/features/groups/application/send_group_message_use_case_test.dart
  test/features/groups/application/retry_failed_group_messages_use_case_test.dart
  test/features/groups/application/retry_incomplete_group_uploads_use_case_test.dart
  test/features/groups/application/group_message_listener_test.dart
  test/features/groups/application/drain_group_offline_inbox_use_case_test.dart
  test/features/groups/presentation/group_conversation_screen_test.dart
  test/features/groups/integration/group_forwarding_transport_boundary_test.dart
)
for file in "${plan236_group_files[@]}"; do
  test "$(git show HEAD:scripts/run_test_gates.sh | awk '/^readonly GROUP_TESTS=\(/,/^\)/' | rg -F -x -c "  \"$file\"")" -eq 1
done
plan236_owned_paths=(
  Test-Flight-Improv/236-group-received-media-forwarding-tdd-plan.md
  go-mknoon/bridge/bridge.go
  go-mknoon/bridge/bridge_test.go
  integration_test/group_forwarded_marker_db_proof_test.dart
  integration_test/group_real_crypto_onboarding_test.dart
  lib/core/bridge/bridge_group_helpers.dart
  lib/core/database/app_database_version.dart
  lib/core/database/migrations/099_group_messages_is_forwarded.dart
  lib/core/database/production_migration_registry.dart
  lib/features/groups/application/group_media_forward_policy.dart
  lib/features/groups/application/group_media_forward_intent.dart
  lib/features/groups/application/drain_group_offline_inbox_use_case.dart
  lib/features/groups/application/group_message_listener.dart
  lib/features/groups/application/handle_incoming_group_message_use_case.dart
  lib/features/groups/application/retry_failed_group_messages_use_case.dart
  lib/features/groups/application/retry_incomplete_group_uploads_use_case.dart
  lib/features/groups/application/send_group_message_use_case.dart
  lib/features/groups/domain/models/group_message.dart
  lib/features/groups/presentation/screens/group_conversation_screen.dart
  lib/features/groups/presentation/screens/group_conversation_wired.dart
  lib/features/share/application/share_batch_delivery_coordinator.dart
  lib/features/share/presentation/navigation/share_target_picker_route.dart
  lib/features/share/presentation/screens/share_target_picker_wired.dart
  lib/main.dart
  scripts/run_test_gates.sh
  test/core/database/integration/full_migration_chain_test.dart
  test/core/database/migrations/099_group_messages_is_forwarded_test.dart
  "${plan236_group_files[@]}"
)
test -z "$(git status --porcelain --untracked-files=all -- "${plan236_owned_paths[@]}")"

# Snapshot + analyzer baseline before Plan-237 edits.
git status --short
flutter analyze --no-pub > /tmp/plan-237-analyze.before 2>&1 || true

# First causal RED. Add the named test first; expect behavior/compile failure, not a missing-file exit.
flutter test test/features/groups/presentation/group_shared_media_entry_test.dart --plain-name 'GML-01 shared media entry and route are discussion only'

# Focused GREEN.
flutter test test/features/groups/presentation/group_shared_media_entry_test.dart
flutter test test/features/groups/application/group_shared_media_repository_contract_test.dart
flutter test test/features/groups/presentation/group_shared_media_screen_test.dart
flutter test test/features/groups/presentation/group_shared_media_wired_test.dart
flutter test test/features/groups/presentation/group_shared_media_go_to_message_test.dart
flutter test test/features/groups/application/group_media_batch_actions_test.dart
flutter test test/features/groups/integration/group_shared_media_bookmark_test.dart
flutter test test/features/groups/integration/group_shared_media_eviction_test.dart
flutter test test/features/groups/integration/group_shared_media_transport_boundary_test.dart

# Shared preservation sentinels.
flutter test test/core/database/helpers/media_library_db_helpers_test.dart --plain-name 'group scope is owner isolated and respects durable deletion tombstones'
flutter test test/core/database/helpers/media_library_db_helpers_test.dart --plain-name 'keyset cursor binds scope filters and enforces the 100 row ceiling'
flutter test test/features/groups/application/group_received_media_actions_test.dart --plain-name 'GMA-04 egress reloads exact group owner and delegates only currently eligible media'
flutter test test/features/groups/application/delete_group_media_for_me_use_case_test.dart --plain-name 'GMA-07 delete prepare is exact group scoped atomic and reaction safe'
flutter test test/features/groups/integration/group_received_media_delete_replay_test.dart --plain-name 'GMA-08 self contained journal saga converges per item across every restart boundary'
flutter test test/features/groups/domain/repositories/group_message_repository_impl_test.dart --plain-name 'IR-020 tombstone prevents replay save and unread resurrection'
flutter test test/features/groups/application/group_media_forward_policy_test.dart --plain-name 'GMF-01R dispatch reloads exact group source and verifies current file hash'
flutter test test/features/groups/presentation/group_media_forward_flow_test.dart --plain-name 'GMF-04 editable caption and selected item are forwarded without source mutation'
flutter test test/features/groups/application/send_group_message_use_case_test.dart --plain-name 'returns unauthorized for non-admin in announcement group'

# Exact host registration; groups only executes this static array.
plan237_group_files=(
  test/features/groups/presentation/group_shared_media_entry_test.dart
  test/features/groups/application/group_shared_media_repository_contract_test.dart
  test/features/groups/presentation/group_shared_media_screen_test.dart
  test/features/groups/presentation/group_shared_media_wired_test.dart
  test/features/groups/presentation/group_shared_media_go_to_message_test.dart
  test/features/groups/application/group_media_batch_actions_test.dart
  test/features/groups/integration/group_shared_media_bookmark_test.dart
  test/features/groups/integration/group_shared_media_eviction_test.dart
  test/features/groups/integration/group_shared_media_transport_boundary_test.dart
)
for file in "${plan237_group_files[@]}"; do
  test "$(awk '/^readonly GROUP_TESTS=\(/,/^\)/' scripts/run_test_gates.sh | rg -F -x -c "  \"$file\"")" -eq 1
done
./scripts/run_test_gates.sh groups

# Analyzer closure: no new normalized diagnostics plus zero issues in Plan-237-owned paths.
flutter analyze --no-pub > /tmp/plan-237-analyze.after 2>&1 || true
for side in before after; do
  sed -E '/^Analyzing /d; /^[0-9]+ issues? found/d; s/:[0-9]+:[0-9]+//g' \
    "/tmp/plan-237-analyze.$side" | sed '/^[[:space:]]*$/d' | sort -u \
    > "/tmp/plan-237-analyze.$side.normalized"
done
comm -13 /tmp/plan-237-analyze.before.normalized /tmp/plan-237-analyze.after.normalized \
  > /tmp/plan-237-analyze.new
test ! -s /tmp/plan-237-analyze.new
if rg -n 'lib/features/groups/(application|presentation/screens)/group_shared_media_|test/features/groups/.*/group_shared_media_' \
  /tmp/plan-237-analyze.after; then
  echo 'Plan-237-owned analyzer diagnostics remain' >&2
  exit 1
fi

git diff --check
```

The scoped analyzer pattern covers the intended new production/test file prefix. Existing touched files such as `group_info_wired.dart` and `group_conversation_wired.dart` are protected by the normalized before/after comparison. If execution chooses a different Plan-237-owned filename, update the pattern and record why; do not fall back to a bare repository-wide pass/fail claim.

## Execution Interpretation And Done Criteria

- Current verdict: accepted after a bounded `tdd-exec` independent-QA-only closeout and one successful QA recheck.
- Expected first RED: after creating GML-01, it fails because the discussion shared-media route/screen behavior is absent. Missing-file exit 79 is not accepted.
- Green sentinels: Plan-228 library ownership/cursor, Plan-235 qualification/delete saga, Plan-236 exact source Forward, IR-020 deletion, and announcement authorization remain green.
- Environment blocker: none. Plan 237 is host-only and inherits native/SQLCipher/Go proof from its accepted dependencies.
- Scope drift: a new migration, change stream, announcement/QA library, global library, transport/wire change, or multi-item internal Forward requires replanning.

- [x] Plan 236 has implemented/device-proven status, completed done criteria, committed v99/migration/registries/symbols/tests/gates, and no dirty dependency artifacts.
- [x] Every behavior has a named causal test or dependency-boundary sentinel.
- [x] First causal RED, focused GREEN, and representative mutation re-red are recorded.
- [x] Exact group scope, poisoned-owner rejection, opaque cursor, page limit, tied timestamps, lazy paging, and bounded static decode are causal.
- [x] Selection stops at ten; egress requalifies current state, sends at most one native request, and keeps failed-only retry.
- [x] Delete selection clears only after bounded durable-state reconciliation; no-op/conflict/failure remains visible and selected.
- [x] Single-item Forward reaches Plan 236; multi-item/local actions make zero internal delivery calls.
- [x] Real nested Go-to-message route uses `getMessagesAround` with `<=25` per side, scrolls after layout, and supports `m02 -> m40 -> m02` in the same mounted conversation.
- [x] Refresh is bounded to mount/resume/action completion; no new change stream exists.
- [x] Every Plan-237 host file is registered exactly once; focused/groups/analyzer/hygiene gates pass.
- [x] Full `host-all` remains deferred to wave/final closure.

## Handoff

- Execution order: `236 -> 237 -> 241`. Plans 236 and 237 are closed; Plan 241 is unblocked.
- Maintenance entry: rerun the exact GML-10R/GML-13W proof for nested-route, scroll-latch, or local-delivery regressions before the proportional `groups` lane.
- Migration: none. Consume committed DB v99.
- Boundary closure: host UI/application/repository behavior. Native egress, SQLCipher, and Go forwarding remain accepted dependency proofs.
- Full host cadence: wave/final only, never per Plan 237.

## Execution Progress

| Time | Phase | Files | Last command/result | Current evidence | Decision/blocker | Next |
|---|---|---|---|---|---|---|
| 2026-07-10 | prerequisite audit | Plan 236/237, DB version/registry/migration, forwarding tests, group actions/routes/gates | committed HEAD v98; worktree contains partial v99/Forward changes; Plan 236 still `execution-ready` | dependency docs exist but committed closure does not | BLOCKED until exact Plan-236 preflight passes | finish and accept Plan 236; rerun prerequisite block before GML-01 |
| 2026-07-10 | tdd-exec prerequisite audit | committed Plan 236/237 stop gate | committed status assertion passed; exact committed closure-verdict assertion failed | HEAD is DB v99 and Plan 236 is marked implemented, but lacks `Closure verdict: accepted` | BLOCKED; no Plan-237 RED or implementation permitted | close and commit Plan 236, then rerun the full prerequisite block |
| 2026-07-10 | blocker repair audit | committed Plan 236 and every remaining prerequisite assertion | implemented/host-green/device-proven status, completed checklist, DB v99, migration/registry, forwarding symbols/proofs, and exact `GROUP_TESTS` registration PASS; dependency pathset is clean | the failed sentence was redundant Plan-237-only metadata, not missing implementation evidence | UNBLOCKED; Plan 237 is execution-ready | rerun the substantive preflight, snapshot analyzer baseline, then create and run GML-01 RED |
| 2026-07-10 | lean TDD execution | group shared-media application/UI/repository/DB wiring, nine registered host files, preservation sentinels, `groups` gate | focused files PASS; preservation PASS; `groups` PASS (`+1875`); analyzer diagnostics equal baseline (`494/494` normalized); `git diff --check` PASS; Graphify incremental refresh PASS | implementation and proportional host proof are green; durable preflight still requires managed full-orchestrator acceptance, including an independent real nested-route counterexample check | READY FOR FULL ORCHESTRATOR | hand the persisted implementation and artifacts to the full execution/QA orchestrator; keep full `host-all` for wave/final closure |
| 2026-07-10 | independent QA-only closeout + one recheck | real nested route, repeated scroll targets, production-wired local actions, transport/Forward counters, plan closeout | GML-10R/GML-13W PASS; latch mutation RED; scoped analyzer PASS; `groups` PASS (`+1889`) plus bridge/node gates; `git diff --check` PASS | initial QA B1/B2 were closed by one bounded test-only fix pass; fresh QA recheck PASS with no behavioral blockers | ACCEPTED | Plan 237 closed; proceed to Plan 241 and retain `host-all` for wave/final closure |

## Execution Result

- Final verdict: `accepted`.
- Execution mode: `tdd-exec (local)` for the bounded test-only closeout.
- Assurance mode: independent QA-only; initial QA found B1/B2, one bounded fix pass closed both, and one fresh QA recheck passed.
- Independent QA: passed. The real `GroupConversationWired -> GroupInfoWired -> GroupSharedMediaLibraryScreen` flow is causal for repeated targets and local delivery boundaries.
- Files changed by this closeout: `test/features/groups/presentation/group_shared_media_go_to_message_test.dart` and this plan. Production behavior was not changed.
- Route proof: GML-10R/GML-13W drives `m02 -> m40 -> m02` through the same mounted conversation, records exact `(group-a, target, 25, 25)` calls, and proves every lazy highlight overlaps the visible timeline viewport (`/tmp/plan-237-gml10r-fix-pass.log`).
- Mutation proof: temporarily changing `_highlightScrollResolved = false` to `true` causally fails on the missing `grp-highlight-m02`; production was restored (`/tmp/plan-237-gml10r-latch-mutation-red.log`).
- Transport/Forward proof: real production-wired Save, Share, Bookmark, Delete, Evict, and Go-to keep Bridge/P2P delivery counters unchanged; single Forward carries exact `group-a/m02/target-02`; multi-select exposes no Forward.
- Focused command: `flutter test test/features/groups/presentation/group_shared_media_go_to_message_test.dart` PASS (2 tests).
- Analyzer: `flutter analyze --no-pub test/features/groups/presentation/group_shared_media_go_to_message_test.dart` PASS with no issues.
- Curated gate: `./scripts/run_test_gates.sh groups` PASS with 1,889 Flutter tests plus Group Forwarding Go bridge/node gates (`/tmp/plan-237-groups-fix-pass.log`). The earlier unrelated GDR-001 timing failure passed standalone and on two complete lane reruns.
- Registration/hygiene: all nine Plan-237 files occur exactly once in `GROUP_TESTS`; `git diff --check` PASS.
- Reused evidence: original focused/preservation/analyzer/Graphify proof remains valid because this closeout changed no production code. Full `host-all` remains deferred to wave/final closure by repository cadence.
- Blocking issues: none. Plan 237 is safe to consider complete; Plan 241 is unblocked.
- Worktree safety: unrelated pre-existing and concurrent dirty files were preserved and excluded from this verdict.
