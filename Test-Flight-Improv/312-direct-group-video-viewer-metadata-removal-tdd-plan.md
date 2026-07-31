# 312 - Direct And Group Video Viewer Metadata Overlay Removal

Status: implemented / host-green (2026-07-31)
Type: Modification
Spec: free-text intent — remove automatic top-left video metadata for senders
and receivers in 1:1 and group chats while retaining it in the existing Info
surface
Classification: implemented
Closure tier: host

## Planning Progress

| Time | Role | Files inspected | Decision/blocker | Next action |
|---|---|---|---|---|
| 2026-07-31 19:42 CEST | Evidence Collector | `$tdd-plan` and required references; Graphify compact TDD context; Plan 306; shared typed viewer/item; direct/group inline and Shared Media item builders; focused tests and gate arrays | Confirmed four ordinary-chat viewer entrypoints. Direct videos explicitly retain details while group videos inherit the visible default; the shared renderer already supports hiding details without clearing metadata or captions. | Build a caller-owned host-widget contract covering both directions and both Shared Media bypasses. |
| 2026-07-31 19:48 CEST | Planner | current source citations; direct/group Info sheets and authorization; planning probes; dirty-tree and Plan-311 overlap | Selected four minimal caller-policy edits. Eligible existing Info remains unchanged; outgoing group/direct and Shared Media Info authorization is not widened. | Run `$tdd-review`, apply only verified deltas, then execute tests-first. |
| 2026-07-31 19:53 CEST | Reviewer | `$tdd-review` references; review-profile Graphify context; all production typed-viewer call sites; exact tests and gate discovery | Initial verdict `plan-fixes-required`: core bet confirmed; pinned the captionless negative to outgoing fixtures, replaced TC-312-06 shorthand with exact PiP test names, and added the missing literal format gate. Re-audit verdict `ready`. | Execute the corrected contract tests-first. |
| 2026-07-31 20:22 CEST | Executor | four production item builders; four caller-owned widget suites; exact Info/action/private/PiP sentinels; curated `1to1` and `groups`; Graphify impact/refresh; analyzer and hygiene | Four caller-level RED/GREEN cycles and four restored mutation re-reds passed. The first group-lane run had one transient parallel failure; the apparent `KE-012` test passed alone and the complete retry passed all 3,318 Flutter cases and Go tails. | Close as implemented / host-green. |

## Problem And Evidence

- Behavior to improve: when either sender or receiver opens an ordinary video
  from a 1:1 or group conversation, the full-screen viewer currently places
  sender/time/type/size/duration details over the top-left of the video. Those
  automatic details must disappear; eligible users can still request the same
  persisted metadata through the existing Info action.
- Impact: unsolicited technical details obscure the video and duplicate Info.
  A broad removal could accidentally erase captions or typed metadata, weaken
  Info, alter GIF/image behavior, or miss a Shared Media entrypoint.
- Confirmed current renderer: `FullScreenTypedMediaViewer.build` mounts
  `_MediaViewerMetadata(item: current)` for every ordinary page at
  `lib/shared/widgets/media/full_screen_typed_media_viewer.dart:500-506`.
  `_MediaViewerMetadata` independently gates sender/time/type/size/duration on
  `item.showMetadataDetails` while leaving non-empty captions visible at
  `:948-1006`.
- Confirmed direct cause: `_buildDirectViewerItem` classifies the exact media
  kind and sets `showMetadataDetails: kind != MediaViewerKind.image` at
  `lib/features/conversation/presentation/screens/conversation_screen.dart:2071-2075,2101-2126`.
  Therefore both incoming and outgoing videos keep automatic details; only the
  incoming path adds `senderLabel`, while both directions still expose time,
  MIME, size, and duration.
- Confirmed group cause: `_viewerItemFor` creates both incoming and outgoing
  discussion/announcement items at
  `lib/features/groups/presentation/screens/group_conversation_wired.dart:5978-6066`
  without overriding the `MediaViewerItem.showMetadataDetails = true` default
  declared at `lib/shared/widgets/media/media_viewer_item.dart:124-143`.
  `_senderLabelFor` supplies a member name for incoming and localized `You` for
  outgoing at `group_conversation_wired.dart:5965-5975`.
- Confirmed bypasses: direct Shared Media repeats the direct static-image-only
  policy at
  `lib/features/conversation/presentation/screens/direct_shared_media_library_screen.dart:845-899`;
  group Shared Media constructs ordinary image/GIF/video items without a
  visibility override at
  `lib/features/groups/presentation/screens/group_shared_media_library_screen.dart:860-914`.
  Private viewers are separate `privacyMinimized` callers; the two remaining
  `MediaViewerItem` constructions in direct/group Wired are authorization
  snapshots for PiP, not displayed viewer pages.
- Confirmed Info independence: direct viewer Info reloads the exact persisted
  attachment through `_handleViewerAction` rather than reading the displayed
  item's overlay values; the existing
  `info follows selected attachment within one message without transport reads`
  test shows video MIME/size/duration. Group viewer Info reloads the exact
  ordinary incoming parent/attachment at
  `group_conversation_wired.dart:5861-5879,6098-6104`, and
  `GroupMediaInfoSheet` renders MIME/size/duration at
  `lib/features/groups/presentation/widgets/group_media_info_sheet.dart:83-120`.
- Planning probes on 2026-07-31: the current direct video/GIF automatic-
  metadata test, direct exact-video Info test, group video Info-sheet test, and
  group Shared Media PiP test each exited `0`. This confirms current visible
  video details and the independent preservation paths; it does not satisfy the
  requested hidden overlay.
- Existing coverage: Plan 306 already proves `showMetadataDetails` hides keys,
  text, and semantics while preserving captions, typed fields, actions, and
  current-item page changes. Plan 310 proves the direct received-video overflow
  and its complete action set. Group tests prove Info field/redaction behavior,
  inline action wiring, and Shared Media PiP composition.
- Missing coverage: no causal test requires hidden automatic details for both
  directions of direct video or group video; direct/group Shared Media tests
  currently allow visible video details; no one test binds hidden group video
  chrome to still-available exact-video Info.
- Refuted findings:
  - A shared-renderer deletion is unnecessary and too broad. The existing
    item-level flag is the established presentation seam and defaults visible
    for non-chat/legacy callers.
  - Clearing sender/time/MIME/size/duration is not a valid visual fix; it makes
    item inspection and downstream behavior lie, while Info already reloads
    persistent truth independently.
  - `privacyMinimized` is not appropriate: it also suppresses actions,
    playback/resume controls, and PiP.
  - Adding Info for outgoing media or Shared Media is not implied. Current
    direct/group authorization intentionally limits that action; this plan
    preserves eligibility and removes only unsolicited overlay details.
- Unresolved findings: N/A — the four displayed ordinary-video entrypoints,
  existing visibility seam, Info independence, and host proof boundary are
  current-source confirmed.
- Affected production, test, and gate files:
  `lib/features/conversation/presentation/screens/conversation_screen.dart`,
  `lib/features/conversation/presentation/screens/direct_shared_media_library_screen.dart`,
  `lib/features/groups/presentation/screens/group_conversation_wired.dart`,
  `lib/features/groups/presentation/screens/group_shared_media_library_screen.dart`,
  `test/features/conversation/presentation/screens/conversation_received_media_actions_test.dart`,
  `test/features/conversation/presentation/screens/conversation_shared_media_viewer_test.dart`,
  `test/features/groups/presentation/group_conversation_wired_test.dart`, and
  `test/features/groups/presentation/group_shared_media_wired_test.dart`.
  Gate scripts require no edit.

## Graph Grounding Snapshot

- Graph fingerprint / freshness: `0b1b367365e8ff32`;
  `stale:ios/Flutter/flutter_export_environment.sh`. The stale generated iOS
  environment file is unrelated to this host presentation seam.
- Query / profile:
  `python3 graphify-arch/tdd_context.py query "FullScreenTypedMediaViewer video metadata top-left overlay MediaViewerInfo sender receiver direct group Info action metadata tests gates" --profile tdd --budget 700`
  returned `confidence=anchored`; no refinement was required.
- Anchors: `FullScreenTypedMediaViewer` ->
  `lib/shared/widgets/media/full_screen_typed_media_viewer.dart:45`; displayed
  direct item owner -> `conversation_screen.dart:2064`; displayed group item
  owner -> `group_conversation_wired.dart:5978`.
- Surfaced proof/gate files: shared typed viewer/item, direct conversation and
  Shared Media, group Shared Media, direct received-action tests, and 1:1 gate
  candidates.
- Graph gaps requiring source search: the compact result did not expose
  `_MediaViewerMetadata`, group inline `_viewerItemFor`, the two Shared Media
  item constructors, exact Info-sheet tests, or group gate registrations; all
  were verified directly in current source/arrays.
- Reuse rule: anchors may be handed to review/execution; all conclusions still
  require current-source or command evidence.

## Scope Contract And Guard

In scope:

- Set `showMetadataDetails` false for ordinary video items built by the direct
  conversation and direct Shared Media entrypoints. Direct ordinary static
  images remain hidden from Plan 306; GIF pages remain visible.
- Set `showMetadataDetails` false for video items built by group/announcement
  conversation and group Shared Media entrypoints, for both incoming and
  outgoing messages. Group image/GIF pages retain their current visible
  behavior.
- Hide all automatic detail keys/text/semantics: sender, timestamp, MIME/type,
  size, dimensions/duration. Keep a non-empty user-authored caption visible;
  a captionless hidden video has no metadata-content container.
- Retain every original typed field on `MediaViewerItem`. For users already
  authorized for Info, keep the exact persisted sender/time/type/size/duration
  sheet and current-attachment reload behavior.

Must preserve:

- Existing direct received-video three-dot actions, icons, dispatch, and
  conditional PiP -> `TC-312-01/05/06`.
- Existing group video actions and exact incoming Info behavior; outgoing Info
  remains absent under current authorization -> `TC-312-03/05`.
- Direct/group captions remain visible and video playback/resume/PiP remain
  unchanged -> `TC-312-01/03/04/06`.
- Direct ordinary images remain detail-hidden; direct GIFs remain visible;
  group images/GIFs and default/legacy callers remain visible ->
  `TC-312-01/02/03/04/06`.
- Direct/group Shared Media paging, identity, action capability, egress,
  delete, bookmark, Forward, and PiP qualification remain unchanged ->
  `TC-312-02/04/06`.
- Private/protected/view-once routes retain their stronger
  `privacyMinimized` behavior -> `TC-312-06`.
- Preserve every pre-existing dirty-tree edit, including Plans 303-311,
  generated localization files, action layout/haptics work, device-run result,
  native files, and Graphify artifacts.

Hard `Do not`:

- Do not remove or modify `_MediaViewerMetadata`, change
  `MediaViewerItem.showMetadataDetails`'s default, infer policy inside the
  shared viewer, or clear typed metadata values.
- Do not add or widen Info authorization for outgoing direct/group media or
  either Shared Media library. “Only under Info” means preserve the existing
  eligible on-demand surface, not create a new action policy.
- Do not hide direct GIF details, change group image/GIF details, or change
  non-chat/default/legacy viewer presentation.
- Do not change captions, action presentation/order/icons/effects, playback,
  resume, PiP policy/native behavior, media bytes, persistence, schema, wire,
  crypto, relay/Go, localization, or transport.
- Do not overwrite or absorb unrelated dirty-tree and Plan-311 work.

Deferred / accepted difference:

- Direct ordinary images remain hidden under Plan 306; group images remain
  visible because this request is video-specific.
- Eligible incoming Info remains available. Existing policy intentionally
  leaves outgoing and library items without Info; changing that authorization
  is deferred to a separate product request.
- Non-chat/legacy typed-video callers keep their default visible details; they
  are not sender/receiver chat routes and provide the global-default sentinel.

Dependencies:

- Builds on Plan 306's additive `showMetadataDetails` contract and Plan 310's
  direct video action popup. Group inline and library entrypoints share the
  typed viewer but own separate item construction.
- Stop-if execution finds another displayed ordinary direct/group video item
  builder, or if current Plan-311 edits remove/reshape the group test/caller
  seam before production editing. Replan the entrypoint census rather than
  widening the shared renderer.

## Test Contract

| Case | Behavior | Named test/proof | Tier / fixture | HEAD -> GREEN | Mutation | Gate / registration |
|---|---|---|---|---|---|---|
| TC-312-01 | Inline direct ordinary videos hide automatic details for incoming and outgoing messages while retaining captions, original item metadata, received-video actions, and visible GIF details. | `test/features/conversation/presentation/screens/conversation_received_media_actions_test.dart::ordinary 1:1 videos hide automatic metadata for sender and receiver while GIF remains visible` | Widget host / real temporary captioned incoming video + captionless outgoing video + GIF files, unique values, semantics, typed-viewer inspection | HEAD assertion RED because both video items have `showMetadataDetails == true` and render time/type/size/duration -> both video directions expose no detail key/text/semantics, retain exact typed fields, the incoming caption remains, the outgoing page has no metadata-content container, and GIF details remain visible | Restore `kind != image`, key hiding to `isIncoming`, clear fields, or hide the whole caption/action surface -> TC-312-01 red | `flutter test test/features/conversation/presentation/screens/conversation_received_media_actions_test.dart --plain-name 'ordinary 1:1 videos hide automatic metadata for sender and receiver while GIF remains visible'`; existing `ONE_TO_ONE_TESTS` / `ONE_TO_ONE_HOST_TESTS`; AUTO (`feature-host-all` glob), no registration edit |
| TC-312-02 | Direct Shared Media hides automatic details on incoming and outgoing ordinary video pages as well as existing image pages; GIF remains visible and current-page identity/actions/data remain intact. | `test/features/conversation/presentation/screens/conversation_shared_media_viewer_test.dart::direct Shared Media hides automatic metadata for image and video pages while GIF remains visible` | Widget host / ordinary-parent decision loader, incoming/outgoing image+video and GIF entries with distinct metadata, semantics and egress recorder | HEAD assertion RED because video pages still render details -> both directions' video details disappear without stale-page leakage while typed tuples, GIF details, and exact action identity remain | Leave `_viewerItem` on `kind != image`, hide only incoming video, hide GIF, clear fields, or capture first page -> TC-312-02 red | `flutter test test/features/conversation/presentation/screens/conversation_shared_media_viewer_test.dart --plain-name 'direct Shared Media hides automatic metadata for image and video pages while GIF remains visible'`; existing `ONE_TO_ONE_TESTS` / `ONE_TO_ONE_HOST_TESTS`; AUTO (`feature-host-all` glob), no registration edit |
| TC-312-03 | Inline group discussion videos hide automatic details for sender and receiver, retain caption/item data, keep group image details unchanged, and eligible incoming video Info still renders exact persisted MIME/size/duration; outgoing Info remains unauthorized. | `test/features/groups/presentation/group_conversation_wired_test.dart::ordinary group videos hide automatic metadata for sender and receiver while Info retains it` | Widget host / real verified captioned incoming video + captionless outgoing video + image, current repositories, Info sheet and semantics | HEAD assertion RED because group video items inherit visible details -> both directions hide all automatic rows, the incoming caption remains, the outgoing page has no metadata-content container, image remains visible, incoming Info shows exact video fields, outgoing Info remains absent, and item fields survive | Omit the group flag, gate by sender label/incoming only, clear fields, hide captions/actions, or widen outgoing Info -> TC-312-03 red | `flutter test test/features/groups/presentation/group_conversation_wired_test.dart --plain-name 'ordinary group videos hide automatic metadata for sender and receiver while Info retains it'`; existing `GROUP_TESTS`; AUTO (`feature-host-all` glob), no registration edit |
| TC-312-04 | Group Shared Media video pages hide automatic details while retaining item data, image details, current-page identity and the existing PiP composition. | `test/features/groups/presentation/group_shared_media_wired_test.dart::group Shared Media video hides automatic metadata without changing PiP composition` | Widget host / verified video+image entries, fake PiP gateway/resume/authorization, typed item inspection | HEAD assertion RED because the displayed video inherits visible details -> video detail keys/text are absent, image details remain, all typed fields and exact PiP owner/composition stay intact | Omit the library flag, hide every kind, clear item data, or alter PiP capability/controller wiring -> TC-312-04 red | `flutter test test/features/groups/presentation/group_shared_media_wired_test.dart --plain-name 'group Shared Media video hides automatic metadata without changing PiP composition'`; existing `GROUP_TESTS`; AUTO (`feature-host-all` glob), no registration edit |
| TC-312-05 | Existing eligible direct/group Info surfaces retain video MIME, size, duration, current attachment, and redaction without transport reads or overlay dependence. | `test/features/conversation/presentation/screens/conversation_received_media_actions_test.dart::info follows selected attachment within one message without transport reads`; `test/features/groups/presentation/group_conversation_screen_test.dart::GMA-12M group media info includes MIME and conditional dimensions or duration` | `GREEN sentinel` / persisted direct metadata fake plus group Info-sheet fixture | GREEN on HEAD -> remains GREEN after caller-only presentation flags | Remove/mis-map the video MIME, size, or duration Info row; route direct Info to the first attachment; or make Info authority depend on overlay visibility -> named sentinel red | Exact `flutter test ... --plain-name` commands in Acceptance Gates; direct in 1:1 arrays, group screen in `GROUP_TESTS`, both AUTO feature glob |
| TC-312-06 | Default/legacy video metadata, direct compact video actions, private minimization, and standard/group PiP behavior remain unchanged. | `test/shared/widgets/media/full_screen_typed_media_viewer_test.dart::metadata and action semantics follow current item in LTR and RTL`; `::compact video overflow lists and dispatches every authorized media action`; `::private presentation suppresses metadata resume actions and PiP without changing ordinary pages`; `test/features/conversation/presentation/screens/conversation_received_media_actions_test.dart::direct received-video route forwards exact PiP composition to the typed viewer`; `test/features/groups/presentation/group_shared_media_wired_test.dart::GML-PIP ordinary received video forwards exact PiP composition` | `GREEN sentinel` / shared default, compact-video, private, and fake PiP fixtures | GREEN on HEAD -> additive caller flags leave non-chat/default/private/action/PiP behavior GREEN | Change the shared default/renderer, hide all kinds/callers, reuse `privacyMinimized`, or alter action/PiP composition -> one named sentinel red | Exact shared/direct/group PiP commands in Acceptance Gates; shared AUTO (`host-all` discovery only), direct/group paths already in named arrays |

### Test Notes

- Every hidden-video assertion checks stable keys, unique visible text, and
  semantics; it also inspects the route's `MediaViewerItem` values. This
  prevents key renaming or metadata clearing from satisfying the contract.
- TC-312-01/03 open separate incoming and outgoing parent messages because
  sender labels and Info authorization differ by direction. Captionless
  coverage must require no `media_viewer_metadata_content` container.
- TC-312-02/04 swipe across mixed kinds and assert the current page after each
  transition so a stale first-page flag cannot pass.
- TC-312-03 opens Info only on the eligible incoming video and asserts the
  existing outgoing absence separately; this plan must not widen capability.

## Implementation Steps

1. Snapshot `git status --short` and preserve all overlapping Plans 303-311.
   Add/adjust TC-312-01 through TC-312-04 before production edits and record
   assertion REDs; run TC-312-05/06 sentinels GREEN.
2. Change direct inline and direct Shared Media visibility predicates from
   image-only suppression to image-or-video suppression, leaving GIF visible
   and all typed values intact.
3. Set `showMetadataDetails` false only for video kinds in group inline and
   group Shared Media item constructors. Do not edit the shared renderer,
   default, Info handlers/sheets, action policy, or private viewers.
4. Run focused GREEN, one representative per-caller mutation re-red, exact
   preservation, complete touched small suites, registration discovery, the
   curated `1to1` and `groups` lanes, analyzer/hygiene, and one incremental
   Graphify refresh.

## Risks And Blind Spots

- A one-caller fix would leave Shared Media or group routes leaking ->
  TC-312-01 through TC-312-04 bind all four displayed item builders.
- An incoming-only condition would miss the sender -> TC-312-01/03 use
  separate outgoing messages; TC-312-02 uses both parent directions.
- Clearing metadata could make the overlay disappear while breaking Info or
  diagnostics -> every causal row inspects typed values and TC-312-05 binds
  persisted Info.
- A global shared-renderer change could regress legacy/default or group image
  behavior -> TC-312-03/04/06 retain visible image/default details.
- Lifecycle / derived-state durability: immutable per-item flags are rebuilt
  on each route open and selected per page; mixed-page reverse swipes in
  TC-312-02/04 guard stale state. No durable marker exists.
- Sibling-surface consistency: inline and Shared Media are intentionally equal
  for video, while direct/group image and GIF differences remain source-owned
  accepted behavior under TC-312-01 through TC-312-04.
- Destructive-action side effects: N/A — no delete/cleanup implementation
  changes; action presence/dispatch preservation is covered by TC-312-01/06.
- Invariant re-verification under new transitions: page changes read the exact
  current item's immutable flag; mixed pages and reopen behavior are covered by
  TC-312-02/04 and existing viewer current-item tests.

## Gate Cadence

- Per-plan closure: four exact causal tests, exact Info/default/private/action/
  PiP sentinels, complete direct received-actions/direct Shared Media/group
  Shared Media suites, and the affected curated `1to1` plus `groups` lanes.
  No core/feature/performance, simulator, device, native, relay-specific,
  migration, or localization sweep is justified.
- Do not run full `host-all` for this individual plan. The 1:1/group media-
  presentation batch owns one `./scripts/run_host_test_gates.sh host-all` run
  after Plans 306-312 settle together; final rollout/release owns the next.
- Shared tests outside feature/core globs run by exact command; `host-all`
  list mode verifies later aggregate discovery without executing it here.

## Acceptance Gates

```bash
# Dirty-tree snapshot; preserve unrelated and overlapping work.
git status --short

# Causal REDs before production edits; each expects non-zero because video
# details are currently visible at its independent caller.
flutter test test/features/conversation/presentation/screens/conversation_received_media_actions_test.dart \
  --plain-name 'ordinary 1:1 videos hide automatic metadata for sender and receiver while GIF remains visible'
flutter test test/features/conversation/presentation/screens/conversation_shared_media_viewer_test.dart \
  --plain-name 'direct Shared Media hides automatic metadata for image and video pages while GIF remains visible'
flutter test test/features/groups/presentation/group_conversation_wired_test.dart \
  --plain-name 'ordinary group videos hide automatic metadata for sender and receiver while Info retains it'
flutter test test/features/groups/presentation/group_shared_media_wired_test.dart \
  --plain-name 'group Shared Media video hides automatic metadata without changing PiP composition'

# Focused/complete GREEN; expect exit 0 and zero failed tests.
flutter test test/features/conversation/presentation/screens/conversation_received_media_actions_test.dart
flutter test test/features/conversation/presentation/screens/conversation_shared_media_viewer_test.dart
flutter test test/features/groups/presentation/group_shared_media_wired_test.dart
flutter test test/features/groups/presentation/group_conversation_wired_test.dart \
  --plain-name 'ordinary group videos hide automatic metadata for sender and receiver while Info retains it'

# Exact Info preservation; expect the current persisted video fields and no
# transport/secret leakage.
flutter test test/features/conversation/presentation/screens/conversation_received_media_actions_test.dart \
  --plain-name 'info follows selected attachment within one message without transport reads'
flutter test test/features/groups/presentation/group_conversation_screen_test.dart \
  --plain-name 'GMA-12M group media info includes MIME and conditional dimensions or duration'

# Default, action, private, and PiP preservation; expect exit 0.
flutter test test/shared/widgets/media/full_screen_typed_media_viewer_test.dart \
  --plain-name 'metadata and action semantics follow current item in LTR and RTL'
flutter test test/shared/widgets/media/full_screen_typed_media_viewer_test.dart \
  --plain-name 'compact video overflow lists and dispatches every authorized media action'
flutter test test/shared/widgets/media/full_screen_typed_media_viewer_test.dart \
  --plain-name 'private presentation suppresses metadata resume actions and PiP without changing ordinary pages'
flutter test test/features/conversation/presentation/screens/conversation_received_media_actions_test.dart \
  --plain-name 'direct received-video route forwards exact PiP composition to the typed viewer'
flutter test test/features/groups/presentation/group_shared_media_wired_test.dart \
  --plain-name 'GML-PIP ordinary received video forwards exact PiP composition'

# Existing discovery; expect each exact target selected and no gate edit.
./scripts/run_host_test_gates.sh 1to1 --list \
  --only test/features/conversation/presentation/screens/conversation_received_media_actions_test.dart
./scripts/run_host_test_gates.sh 1to1 --list \
  --only test/features/conversation/presentation/screens/conversation_shared_media_viewer_test.dart
./scripts/run_host_test_gates.sh feature-host-all --list \
  --only test/features/groups/presentation/group_conversation_wired_test.dart
./scripts/run_host_test_gates.sh feature-host-all --list \
  --only test/features/groups/presentation/group_shared_media_wired_test.dart
./scripts/run_host_test_gates.sh host-all --list \
  --only test/shared/widgets/media/full_screen_typed_media_viewer_test.dart

# Both affected curated lanes; expect exit 0, zero failed Flutter cases, and
# their existing Go tails green.
./scripts/run_test_gates.sh 1to1
./scripts/run_test_gates.sh groups

# App-owned impact and hygiene; expect successful refresh, no analyzer issues,
# unchanged formatting, and no whitespace errors.
python3 graphify-arch/tdd_context.py affected \
  lib/features/conversation/presentation/screens/conversation_screen.dart \
  lib/features/conversation/presentation/screens/direct_shared_media_library_screen.dart \
  lib/features/groups/presentation/screens/group_conversation_wired.dart \
  lib/features/groups/presentation/screens/group_shared_media_library_screen.dart \
  --budget 600
./graphify-arch/refresh_arch_graph.sh --incremental
flutter analyze
dart format --output=none --set-exit-if-changed \
  lib/features/conversation/presentation/screens/conversation_screen.dart \
  lib/features/conversation/presentation/screens/direct_shared_media_library_screen.dart \
  lib/features/groups/presentation/screens/group_conversation_wired.dart \
  lib/features/groups/presentation/screens/group_shared_media_library_screen.dart \
  test/features/conversation/presentation/screens/conversation_received_media_actions_test.dart \
  test/features/conversation/presentation/screens/conversation_shared_media_viewer_test.dart \
  test/features/groups/presentation/group_conversation_wired_test.dart \
  test/features/groups/presentation/group_shared_media_wired_test.dart
git diff --check
```

## Execution Interpretation And Done Criteria

- Expected RED: TC-312-01/02 fail on visible direct video details;
  TC-312-03/04 fail because group videos inherit the visible default.
- Green sentinels: exact direct/group video Info fields, default/legacy
  metadata, direct action overflow, private minimization, and PiP composition.
- Pre-existing dirty tree / known failure: Plans 303-311, shared viewer/action
  tests, localization outputs, native/config files, Graphify outputs, and the
  latest three-phone result are baseline and must not be reverted or absorbed.
  All Plan-312 tests were added and completed without reverting that baseline.
- Environment blocker: none; closure is host-only. No native or device boundary
  changes or parity claims are made.
- Scope drift: any need to change shared renderer/default, Info authorization,
  image/GIF/private behavior, persistence, action/PiP policy, schema,
  localization, native code, or transport requires replanning.

- [x] All four displayed ordinary-video entrypoints hide automatic details.
- [x] Both sender/receiver directions, captions, typed values, and mixed pages
      have causal RED/GREEN and representative mutation re-red evidence.
- [x] Direct/group Info and default/private/action/PiP sentinels pass.
- [x] Existing 1:1/group/host discovery is verified without gate edits.
- [x] Curated `1to1` and `groups`, analyzer, format/diff hygiene, and Graphify
      refresh pass.
- [x] Scope Contract And Guard and dirty-tree preservation are respected.

## Handoff

- First causal RED command:
  `flutter test test/features/conversation/presentation/screens/conversation_received_media_actions_test.dart --plain-name 'ordinary 1:1 videos hide automatic metadata for sender and receiver while GIF remains visible'`.
- Preservation command:
  `flutter test test/features/conversation/presentation/screens/conversation_received_media_actions_test.dart --plain-name 'info follows selected attachment within one message without transport reads'`.
- Manual registration: none; existing 1:1 and group arrays own all feature
  paths, and shared viewer tests are `host-all` glob-discovered.
- Migration: none.
- Boundary closure: host-only widget/application proof; no simulator/device,
  SQLCipher, OS callback, native, crypto, or relay behavior changes.
- Unresolved evidence: none.

## Reviewer Findings

- Verdict: `ready`; plan classification `implementation-ready`; core bet
  `confirmed`; disposition `execute`. The initial `plan-fixes-required`
  findings were patched in place and the five lenses were rerun.
- L1 evidence/classification: `clear`; current source has exactly four
  displayed ordinary direct/group item builders, plus two private minimized
  routes and two non-displayed PiP authorization snapshots.
- L2 causality: `clear` after pinning captionless output to the outgoing direct
  and group fixtures and making every PiP sentinel exact. Causal tests use real
  caller routes, retain typed values, and check keys/text/semantics, so flag
  changes, key renames, field clearing, incoming-only fixes, and global hiding
  cannot pass accidentally.
- L3 bypass/scope: `clear`; all six production typed-viewer call sites were
  enumerated. The four ordinary displayed builders are in scope; both private
  callers already use `privacyMinimized`. The injected legacy direct builder
  has no production `lib/` caller and is outside the typed overlay seam.
- L4 gates: `clear` after adding the literal format command. Review list mode
  selected direct actions at 1:1 item 82, direct Shared Media at item 88, group
  Wired at feature item 475, group Shared Media at item 488, and the shared
  viewer at host-all item 1239. Full `host-all` remains batch/final-owned.
- L5 boundary/reversibility: `N/A`; immutable host presentation inputs only,
  with no persistence, migration, OS, native, crypto, relay, cross-device, or
  destructive behavior change.
- Blind-spot sweep: B2/B3/B4/B7/B9 were triggered and are clear after the
  verified deltas; B1/B5/B6/B8/B10 are N/A. No user-owned decision remains.

## Execution Progress

| Time | Phase | Files | Last command/result | Current evidence | Decision/blocker | Next |
|---|---|---|---|---|---|---|
| 2026-07-31 20:02 CEST | causal RED | four caller-owned widget tests | four exact `flutter test --plain-name` commands exited `1` on `showMetadataDetails == true` or visible `media_meta_sender` | Direct inline, direct Shared Media, group inline, and group Shared Media each failed independently against the old policy. | REDs were causal; one concurrent native-assets race and one default-filter fixture issue were corrected before production edits. | Apply only caller visibility predicates. |
| 2026-07-31 20:08 CEST | focused GREEN + mutation | four production builders and four widget tests | all four exact tests exited `0`; restoring each old caller predicate then produced four independent expected REDs, followed by restored GREEN | Incoming/outgoing video details are hidden; captions/typed fields, direct GIFs, group images, actions, Info, and PiP remain intact. | No shared renderer/default or authorization edit required. | Run complete touched suites and sentinels. |
| 2026-07-31 20:10 CEST | preservation | direct actions `+19`; direct Shared Media `+6`; group Shared Media `+6`; group inline exact `+1`; group Info `+1`; three shared-viewer sentinels `+1` each | every command exited `0` | Exact video Info, compact overflow dispatch, private minimization, default metadata, and direct/group PiP composition are green. | No preservation blocker. | Run curated lanes. |
| 2026-07-31 20:20 CEST | curated lanes | existing gate inventories | `1to1` passed `+2525` plus Go; initial `groups` ended with one transient parallel failure, apparent `KE-012` passed exact `+1`, full retry passed `+3318` plus Go | Both required affected lanes have a clean final run. | The retry was diagnostic only; no production/test change followed it. | Run static/graph closure. |
| 2026-07-31 20:22 CEST | closure | eight scoped source/test files plus Graphify artifacts and this plan/index | affected query exit `0`; incremental refresh updated 22 changed code files; `flutter analyze` found no issues in 121.6s; 8-file format check and `git diff --check` exited `0` | Host closure complete; list-mode registration proof from review remains valid and no gate file changed. | No blocker; device/native proof is N/A for this caller-owned presentation change. | Complete. |
