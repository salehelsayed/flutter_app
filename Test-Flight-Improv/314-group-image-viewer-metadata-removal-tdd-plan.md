# 314 - Group Image Viewer Metadata Removal

Status: implemented; host-green (2026-07-31)
Type: Modification
Spec: free-text intent — remove automatic top-left metadata when any
participant opens an image from a discussion group
Classification: implemented
Closure tier: host

## Planning Progress

| Time | Role | Files inspected | Decision/blocker | Next action |
|---|---|---|---|---|
| 2026-07-31 21:42 CEST | Evidence Collector | `$tdd-plan` and required references; Graphify compact TDD context; inline group item builder; group Shared Media item builder; shared typed viewer; direct image and group video precedents; group/announcement tests and gate arrays | Confirmed that both displayed discussion-group image entrypoints still opt into automatic details while the shared renderer already has the required presentation-only flag. | Define caller-level causal tests and exact announcement/GIF/Info preservation. |
| 2026-07-31 21:48 CEST | Planner | current source citations; Plan 306/312/313 contracts; five planning probes; current dirty tree; `GROUP_TESTS` registration | Selected two caller predicates with no shared-renderer or capability edit. Scope includes conversation and discussion Group Shared Media so the same image cannot regain metadata through a second real entrypoint; announcements remain visible. | Run the requested independent `$tdd-review`, revise only verified deltas, then execute tests-first. |
| 2026-07-31 21:57 CEST | Reviewer | complete Plan 314; Graphify review context; current production caller census; exact announcement, GIF/video, Info, action, private, and gate sentinels | Verdict after revision: `execution-ready`. The causal boundaries and literal gates are sound; one missing private-viewer preservation command was added. A new public policy enum/renderer edit would add coupling without increasing proof. | Add tests before production edits, capture both causal REDs, then implement only the two item-builder predicates. |
| 2026-07-31 22:09 CEST | Executor | two group item builders; three group widget files; direct/shared/private sentinels; curated groups gate; analyzer/format/diff hygiene; refreshed Graphify impact | Implemented the reviewed presentation-only predicates. Both entrypoint tests failed on the old behavior, passed after the edit, and re-failed under restored-old-behavior mutations; the announcement boundary mutation also re-failed. All host closure gates are green. | Complete; defer aggregate `host-all` to the Keep-in-chat presentation batch/release cadence. |

## Problem And Evidence

- Behavior to improve: when either the sender or a receiver opens an ordinary
  static image from a discussion group, the full-screen page automatically
  overlays sender, timestamp, MIME/type, byte size, and dimensions. Those
  details must disappear from both the conversation route and that group's
  Shared Media route.
- Impact: unsolicited technical details obscure the image and duplicate the
  existing explicit Info surface for eligible incoming media. A broad change
  could also remove user-authored captions, typed metadata, actions, or the
  intentionally unchanged announcement/GIF/default presentation.
- Confirmed root cause, inline route: `_viewerItemFor` classifies the exact
  media kind but sets
  `showMetadataDetails: attachment.mediaType != 'video'` at
  `lib/features/groups/presentation/screens/group_conversation_wired.dart:5978-6059`.
  Therefore both incoming and outgoing static images, plus GIFs, expose
  automatic details; videos are already hidden.
- Confirmed sender/receiver mapping: `_senderLabelFor` supplies a resolved
  member name for incoming messages and localized `You` for outgoing messages
  at `group_conversation_wired.dart:5965-5975`. Both directions then use the
  same `_viewerItemFor` and `FullScreenTypedMediaViewer`; there is no separate
  role-specific overlay implementation.
- Confirmed second displayed entrypoint: Group Shared Media's `_item` repeats
  the same `attachment.mediaType != 'video'` policy at
  `lib/features/groups/presentation/screens/group_shared_media_library_screen.dart:860-888`
  and opens the typed viewer at `:953`. Discussion uses `incomingOnly: false`,
  while the sole production caller sets `incomingOnly: true` for announcements
  at `group_conversation_wired.dart:6527-6530`. That existing discriminator
  permits discussion images to hide without changing announcement images.
- Confirmed renderer seam: `_MediaViewerMetadata` gates sender, timestamp,
  MIME, size, and dimensions/duration on `item.showMetadataDetails`, while a
  non-empty caption remains independently visible at
  `lib/shared/widgets/media/full_screen_typed_media_viewer.dart:933-1017`.
  `MediaViewerItem` retains every typed value and defaults the flag to visible
  at `lib/shared/widgets/media/media_viewer_item.dart:124-174`.
- Confirmed Info independence: `_onViewerAction` routes Info to
  `_showCurrentGroupMediaInfo`, which reloads the exact current ordinary
  incoming parent and attachment before showing `GroupMediaInfoSheet` at
  `group_conversation_wired.dart:5859-5879,6085-6120`. It does not read the
  automatic overlay flag.
- Confirmed bypass census: the only displayed group-owned ordinary typed
  viewer items are `_viewerItemFor` and Group Shared Media `_item`. The
  construction at `group_conversation_wired.dart:5709` is a non-displayed PiP
  authorization snapshot; `group_private_media_viewer.dart:175` is a separate
  `privacyMinimized` protected-media route.
- Existing coverage and planning probes on 2026-07-31:
  - direct incoming/outgoing image removal precedent exited `0`;
  - current group inline video/image baseline exited `0` and proves group
    images are still visible while videos and incoming video Info work;
  - current Group Shared Media video/image baseline exited `0` and proves the
    library's images are still visible while video/PiP remain intact;
  - inline announcement `GMA-13` and announcement-library `AML-04` both exited
    `0`.
- Missing coverage: no group test requires automatic details to be absent for
  both incoming and outgoing static images; no discussion Group Shared Media
  test requires the same policy; and current announcement tests do not lock
  their static-image metadata presentation against a discussion-only edit.
- Refuted findings:
  - Removing `_MediaViewerMetadata` or changing the shared default is not
    required and would widen into direct/default/legacy callers.
  - Clearing sender/time/MIME/size/dimensions is not a presentation fix; it
    would make typed inspection lie and could weaken downstream behavior.
  - `privacyMinimized` is not suitable because it also suppresses actions,
    playback/resume controls, and PiP.
  - The request does not authorize Info for outgoing media or Shared Media;
    current action policy remains unchanged.
- Unresolved findings: N/A — both displayed entrypoints, the direction mapping,
  the presentation seam, and the host proof boundary are current-source
  confirmed.
- Affected production, test, and gate files:
  `lib/features/groups/presentation/screens/group_conversation_wired.dart`,
  `lib/features/groups/presentation/screens/group_shared_media_library_screen.dart`,
  `test/features/groups/presentation/group_conversation_wired_test.dart`,
  `test/features/groups/presentation/group_shared_media_wired_test.dart`,
  `test/features/groups/presentation/announcement_media_library_viewer_test.dart`,
  and existing `GROUP_TESTS` entries in `scripts/run_test_gates.sh`. No gate
  script edit is planned.

## Graph Grounding Snapshot

- Graph fingerprint / freshness: `7a9db1c0eabd546f`;
  `stale:lib/features/push/application/background_message_handler.dart`. The
  stale push file is unrelated to this host-only media presentation seam and
  did not block current-source verification.
- Query / profile:
  `python3 graphify-arch/tdd_context.py query "group discussion image viewer automatic metadata showMetadataDetails _viewerItemFor incoming outgoing Info announcements GIF group shared media" --profile tdd --budget 700`
  returned `confidence=anchored`; no refinement was required.
- Anchors: `showMetadataDetails` ->
  `lib/shared/widgets/media/media_viewer_item.dart:174`; `_viewerItemFor` ->
  `lib/features/groups/presentation/screens/group_conversation_wired.dart:5978`.
- Surfaced proof/gate files: shared viewer/item, inline group conversation,
  Group Shared Media, group presentation tests, and `GROUP_TESTS` candidates.
- Graph gaps requiring source search: the compact result did not surface
  `_MediaViewerMetadata`, Group Shared Media `_item`, the announcement-library
  caller, exact Info tests, or all gate-array registrations; each was verified
  in current source.
- Reuse rule: anchors may be handed to review/execution; all conclusions still
  require current-source or command evidence.

## Scope Contract And Guard

In scope:

- Hide automatic sender, timestamp, MIME/type, byte-size, and dimensions rows
  for incoming and outgoing ordinary static images opened from a
  `GroupType.chat` conversation.
- Apply the same presentation to static images opened from discussion Group
  Shared Media (`incomingOnly == false`) so the same group image cannot regain
  unsolicited metadata through the library.
- Keep non-empty user-authored captions visible; a captionless hidden image
  must have no `media_viewer_metadata_content` container.
- Keep every original typed field on the `MediaViewerItem` and retain exact
  eligible incoming Info behavior.

Must preserve:

- Group GIF automatic details remain visible, and group video details remain
  hidden under Plan 312 -> `TC-314-01`, `TC-314-02`, `TC-314-04`.
- Inline and library announcement static images retain automatic details ->
  `TC-314-03`.
- Incoming image Info still reloads exact persisted MIME/size/dimensions;
  outgoing and library Info remain unauthorized -> `TC-314-01`.
- Captions, item data, compact image actions/icons, exact action identity,
  group Shared Media paging/bookmark/egress/Forward/Delete, and video PiP remain
  unchanged -> `TC-314-01`, `TC-314-02`, `TC-314-04`.
- Direct 1:1 image removal, default typed-viewer visibility, and private
  `privacyMinimized` behavior remain unchanged -> `TC-314-04`.
- Preserve all unrelated dirty-tree work, especially Plans 303-313, group
  notification/native/relay changes, device-run results, and Graphify output.

Hard `Do not`:

- Do not edit `_MediaViewerMetadata`, change
  `MediaViewerItem.showMetadataDetails`'s default, or clear typed fields.
- Do not hide GIF details or broaden the new static-image policy to
  announcement, QA/default, private, direct, or legacy callers.
- Do not add/widen Info authorization or change captions, action
  presentation/order/icons/effects, playback, resume, PiP, paging, filters,
  media bytes, persistence, schema, wire, crypto, relay/Go, localization,
  notifications, or native code.
- Do not overwrite, revert, or absorb unrelated working-tree changes.

Deferred / accepted difference:

- Announcement images remain metadata-visible because the request is specific
  to discussion group chat; `TC-314-03` locks that difference.
- GIF details remain visible as the established animated-image exception used
  by direct and group callers; changing GIF presentation requires a separate
  product request.
- Eligible incoming Info remains available; outgoing and Group Shared Media
  rows retain their current lack of Info authorization.

Dependencies:

- Builds on Plan 306's additive item-level metadata visibility seam, Plan
  312's video suppression, and Plan 313's compact discussion image actions.
- Stop-if execution discovers another displayed group-owned ordinary image
  builder, or if `incomingOnly` no longer exactly discriminates production
  announcement Shared Media. Replan the caller contract instead of widening
  the shared renderer.

## Test Contract

| Case | Behavior | Named test/proof | Tier / fixture | HEAD -> GREEN | Mutation | Gate / registration |
|---|---|---|---|---|---|---|
| TC-314-01 | Inline discussion-group incoming and outgoing static images suppress automatic details; captions, exact typed fields, and compact actions survive; incoming Info still shows exact persisted image MIME/size/dimensions; outgoing Info stays absent; a GIF remains visible. | `test/features/groups/presentation/group_conversation_wired_test.dart::ordinary discussion images hide automatic metadata for sender and receiver while Info and GIF remain` | Widget host / real verified incoming-captioned image, outgoing-captionless image, and GIF files; distinct values; semantics; current repositories and Info sheet | HEAD assertion RED because both static image items have `showMetadataDetails == true` and render details -> both directions expose no keyed/text/semantic details, the captionless page has no metadata container, typed tuples/caption/actions remain, incoming Info is exact, outgoing Info absent, and GIF details visible | Restore `attachment.mediaType != video`, hide only incoming, hide GIF, clear fields, use `privacyMinimized`, or drop Info/action capability -> TC-314-01 red | `flutter test test/features/groups/presentation/group_conversation_wired_test.dart --plain-name 'ordinary discussion images hide automatic metadata for sender and receiver while Info and GIF remain'`; existing `GROUP_TESTS`; AUTO (`feature-host-all` glob), no registration edit |
| TC-314-02 | Discussion Group Shared Media static images suppress automatic details while retaining typed identity/data and bookmark/action capability; GIF details remain visible and video remains hidden with unchanged PiP composition. | `test/features/groups/presentation/group_shared_media_wired_test.dart::discussion Group Shared Media image hides automatic metadata while GIF and video policies remain`; existing `::group Shared Media video hides automatic metadata without changing PiP composition` adapted to use a visible GIF sibling | Widget host / strict library repository, real image/GIF/video files, unique metadata, semantics, current-page swipes, fake PiP gateway/resume/authorization | HEAD assertion RED because the static image renders details -> image rows disappear without clearing item values or capabilities; GIF remains visible; the existing video/PiP sentinel stays GREEN | Omit library predicate, key it to sender, hide all kinds, clear fields, capture first page, or alter PiP/action composition -> one named test red | Exact two `flutter test ... --plain-name` commands in Acceptance Gates; existing `GROUP_TESTS`; AUTO feature glob, no registration edit |
| TC-314-03 | Static images in inline announcements and announcement Shared Media retain automatic details and their current received-only action/paging contracts. | `test/features/groups/presentation/group_conversation_wired_test.dart::GMA-13 announcement member and admin expose core media actions without reply while qa stays excluded`; `test/features/groups/presentation/announcement_media_library_viewer_test.dart::AML-04 typed viewer crosses incoming parents while clear stays grid only` strengthened with positive item/key metadata assertions | `GREEN sentinel` / real verified announcement images for member/admin plus incoming-only paged announcement library | GREEN on HEAD -> discussion-only caller predicates leave both announcement pages visible | Remove the `GroupType.chat` boundary, ignore library `incomingOnly`, or hide every group image -> GMA-13 or AML-04 red | Exact commands in Acceptance Gates; both already in `GROUP_TESTS` and AUTO feature glob, no registration edit |
| TC-314-04 | Shared/default item-level semantics, direct image suppression, group video suppression/Info, compact image actions, private minimization, and PiP remain unchanged. | `test/shared/widgets/media/full_screen_typed_media_viewer_test.dart::metadata detail visibility follows current item while captions and actions remain`; `::private presentation suppresses metadata resume actions and PiP without changing ordinary pages`; `test/features/conversation/presentation/screens/conversation_received_media_actions_test.dart::ordinary keep-in-chat image viewer hides automatic metadata for incoming and outgoing messages`; `test/features/groups/presentation/group_conversation_wired_test.dart::ordinary group videos hide automatic metadata for sender and receiver while Info retains it`; `::incoming discussion image uses compact keep-in-chat controls without losing actions`; `test/features/groups/presentation/group_shared_media_wired_test.dart::GML-PIP ordinary received video forwards exact PiP composition` | `GREEN sentinel` / shared mixed-page and private semantics, direct real images, group real video/GIF, compact actions, and fake PiP fixtures | GREEN on HEAD after Plan-312 image preservation fixtures are narrowed to GIF -> caller-only static-image changes leave all named contracts GREEN | Change the shared default/renderer, hide captions/actions, regress direct/private policy, restore group video details, or alter action/PiP composition -> a named sentinel red | Exact commands in Acceptance Gates; shared tests executed directly; direct/group tests retain existing arrays/AUTO registration |

### Test Notes

- TC-314-01 opens separate incoming and outgoing parent messages because
  sender labels and Info authorization differ by direction. Absence must be
  asserted by stable keys, unique visible text, and semantics, while inspecting
  the route's original `MediaViewerItem` values.
- Adapt Plan 312's inline image preservation fixture to an `image/gif` fixture
  before production editing; adapt its library image sibling the same way.
  Those remain GREEN preservation sentinels and no longer contradict the new
  static-image contract.
- TC-314-02 must start from `incomingOnly: false`; TC-314-03's announcement
  library must use `incomingOnly: true`. This distinguishes the two production
  group types rather than inferring policy from sender text.
- TC-314-03 adds positive metadata assertions before invoking existing actions;
  action success alone cannot prove the announcement presentation boundary.

## Implementation Steps

1. Snapshot `git status --short`. Add TC-314-01/02 and strengthen TC-314-03
   before production edits; narrow Plan 312's static-image preservation
   fixtures to GIF and run them GREEN. Capture both causal REDs for visible
   static-image metadata.
2. In inline `_viewerItemFor`, derive `showMetadataDetails` from the exact
   `kind` and `_group.type`: discussion static images/videos hidden, GIF
   visible; non-discussion static images retain current visibility and videos
   remain hidden. Keep every item value and action input unchanged.
3. In Group Shared Media `_item`, derive the same display flag from exact kind
   plus the existing production `incomingOnly` announcement discriminator:
   discussion static images/videos hidden, GIF visible; announcement static
   images/GIF visible and video hidden. Stop-if that boolean is no longer an
   exact production group-type discriminator.
4. Run focused GREEN, representative inline/library and boundary mutation
   re-reds, complete touched suites, exact cross-feature/shared preservation,
   the curated `groups` gate, analyzer/format/diff hygiene, and one incremental
   architecture-graph refresh.

## Risks And Blind Spots

- A one-caller fix would leak again through Group Shared Media -> TC-314-01/02
  bind both displayed builders.
- An incoming-only predicate would leave the sender's image visible ->
  TC-314-01 uses separate incoming and outgoing messages.
- A global group predicate would silently change announcements -> TC-314-03
  positively asserts both inline and library announcement metadata.
- A blanket image predicate could hide GIFs, while restoring old logic could
  re-show videos -> TC-314-01/02/04 use mixed kinds.
- Clearing fields or hiding the whole overlay could make negative assertions
  pass while breaking captions/actions/Info -> causal tests inspect typed
  values, captions, capabilities, semantics, and exact Info output.
- Lifecycle / derived-state durability: N/A — visibility is immutable per item
  and existing current-page swipe tests reconstruct it on each route/page.
- Destructive-action side effects: N/A — no delete, cleanup, persistence, or
  file mutation changes.
- Invariant re-verification under new transitions: current-page image/GIF/video
  swipes in TC-314-02 and the shared sentinel prevent stale first-page state.

## Gate Cadence

- Per-plan closure: two causal exact tests; exact announcement, Info, action,
  video/GIF, direct, shared, private/PiP sentinels; complete three touched test
  files; curated `groups`; analyzer and hygiene.
- Do not run full `host-all` for this individual plan. The Keep-in-chat media
  presentation batch (Plans 306-314) owns one aggregate
  `./scripts/run_host_test_gates.sh host-all` run at explicit batch closure;
  final rollout/release owns the final aggregate run.
- Shared tests outside feature/core globs: run
  `test/shared/widgets/media/full_screen_typed_media_viewer_test.dart` by exact
  command. The direct precedent is also run exactly rather than widening this
  group-only plan into the curated `1to1` gate.

## Acceptance Gates

```bash
# Snapshot before execution; record unrelated changes
git status --short

# Causal RED before production edits; each exits non-zero because static group
# images still have showMetadataDetails == true and render automatic rows
flutter test test/features/groups/presentation/group_conversation_wired_test.dart --plain-name 'ordinary discussion images hide automatic metadata for sender and receiver while Info and GIF remain'
flutter test test/features/groups/presentation/group_shared_media_wired_test.dart --plain-name 'discussion Group Shared Media image hides automatic metadata while GIF and video policies remain'

# Focused GREEN and complete touched suites; exit 0 with zero failures
flutter test test/features/groups/presentation/group_conversation_wired_test.dart --plain-name 'ordinary discussion images hide automatic metadata for sender and receiver while Info and GIF remain'
flutter test test/features/groups/presentation/group_shared_media_wired_test.dart --plain-name 'discussion Group Shared Media image hides automatic metadata while GIF and video policies remain'
flutter test test/features/groups/presentation/group_conversation_wired_test.dart
flutter test test/features/groups/presentation/group_shared_media_wired_test.dart
flutter test test/features/groups/presentation/announcement_media_library_viewer_test.dart

# Exact announcement, video/GIF, Info/action, direct, shared/default and PiP
# preservation; every command exits 0
flutter test test/features/groups/presentation/group_conversation_wired_test.dart --plain-name 'GMA-13 announcement member and admin expose core media actions without reply while qa stays excluded'
flutter test test/features/groups/presentation/announcement_media_library_viewer_test.dart --plain-name 'AML-04 typed viewer crosses incoming parents while clear stays grid only'
flutter test test/features/groups/presentation/group_conversation_wired_test.dart --plain-name 'ordinary group videos hide automatic metadata for sender and receiver while Info retains it'
flutter test test/features/groups/presentation/group_conversation_wired_test.dart --plain-name 'incoming discussion image uses compact keep-in-chat controls without losing actions'
flutter test test/features/groups/presentation/group_shared_media_wired_test.dart --plain-name 'group Shared Media video hides automatic metadata without changing PiP composition'
flutter test test/features/groups/presentation/group_shared_media_wired_test.dart --plain-name 'GML-PIP ordinary received video forwards exact PiP composition'
flutter test test/features/conversation/presentation/screens/conversation_received_media_actions_test.dart --plain-name 'ordinary keep-in-chat image viewer hides automatic metadata for incoming and outgoing messages'
flutter test test/shared/widgets/media/full_screen_typed_media_viewer_test.dart --plain-name 'metadata detail visibility follows current item while captions and actions remain'
flutter test test/shared/widgets/media/full_screen_typed_media_viewer_test.dart --plain-name 'private presentation suppresses metadata resume actions and PiP without changing ordinary pages'

# Curated affected lane; target files are already selected by GROUP_TESTS and
# all Flutter cases plus registered Go tails exit 0
./scripts/run_test_gates.sh groups

# Hygiene; no new analyzer issue, format drift, or whitespace error
dart format --output=none --set-exit-if-changed lib/features/groups/presentation/screens/group_conversation_wired.dart lib/features/groups/presentation/screens/group_shared_media_library_screen.dart test/features/groups/presentation/group_conversation_wired_test.dart test/features/groups/presentation/group_shared_media_wired_test.dart test/features/groups/presentation/announcement_media_library_viewer_test.dart
flutter analyze
git diff --check

# Required post-change architecture refresh and focused impact evidence
./graphify-arch/refresh_arch_graph.sh --incremental
python3 graphify-arch/tdd_context.py affected lib/features/groups/presentation/screens/group_conversation_wired.dart lib/features/groups/presentation/screens/group_shared_media_library_screen.dart test/features/groups/presentation/group_conversation_wired_test.dart test/features/groups/presentation/group_shared_media_wired_test.dart test/features/groups/presentation/announcement_media_library_viewer_test.dart --budget 600
```

## Execution Interpretation And Done Criteria

- Expected RED: TC-314-01/02 fail only because static discussion-group images
  retain automatic metadata; announcement and narrowed GIF/video sentinels stay
  green.
- Green sentinel: TC-314-03/04 preserve announcements, GIF/video policy,
  captions, typed values, exact Info/action identity, direct/default/private,
  and PiP.
- Pre-existing dirty tree / known failure: extensive user-owned media,
  notification/native/relay, plans, device-run, and Graphify changes are
  present. The five planning probes pass; unrelated diffs are not plan failures
  and must not be reverted.
- Environment blocker: none expected. This is deterministic host-only widget
  presentation with no DB, OS, device, relay, crypto, or real-network claim.
- Scope drift: any required shared-renderer/default, action authorization,
  persistence, localization, native, or transport edit—or another displayed
  group image item builder—blocks completion pending a plan delta.

- [x] Every behavior has a named test or justified proof.
- [x] Causal RED, focused GREEN, and representative mutation re-red are
      recorded.
- [x] Preservation and named gates pass with semantic outcomes.
- [x] Existing AUTO and `GROUP_TESTS` registration is verified; no new manual
      registration is needed.
- [x] `flutter analyze` has no new issues; format and `git diff --check` are
      clean.
- [x] Scope Contract And Guard is respected.

## Handoff

- First causal RED command:
  `flutter test test/features/groups/presentation/group_conversation_wired_test.dart --plain-name 'ordinary discussion images hide automatic metadata for sender and receiver while Info and GIF remain'`.
- Preservation command:
  `flutter test test/features/groups/presentation/group_conversation_wired_test.dart --plain-name 'GMA-13 announcement member and admin expose core media actions without reply while qa stays excluded'`.
- Manual registration: none; all three group test files already belong to
  `GROUP_TESTS` and AUTO feature discovery. The exact shared/direct sentinels
  retain their existing discovery.
- Migration: none.
- Boundary closure: host-only; the change selects an existing immutable item
  presentation and makes no platform/cross-device claim.
- Unresolved evidence: none.

## Reviewer Findings

Verdict: `execution-ready` after one necessary preservation-gate revision.

- Problem-definition audit: the plan identifies the user-visible overlay, both
  real discussion-group entrypoints, and the existing presentation-only flag.
  Sender and receiver use the same inline builder; no role-specific production
  branch is missing.
- Test-contract audit: TC-314-01 and TC-314-02 fail on HEAD and distinguish a
  no-op, incoming-only change, one-entrypoint change, blanket kind change, and
  field-clearing fake. TC-314-03 makes the announcement boundary positive,
  while GIF and video sentinels prevent a static-image-only fix from widening.
- Scope/architecture audit: caller-level predicates are the narrowest coherent
  seam. Editing the shared renderer/default, adding a new public policy enum,
  or changing action/Info authorization would widen scope without adding
  user-visible value. The existing `incomingOnly` production mapping is exact
  and has a stop-if guard if that ceases to be true.
- Integration audit: the current files are already in `GROUP_TESTS` and AUTO
  discovery; exact shared/direct tests cover non-group preservation. No DB,
  relay, native, device, or migration gate is justified for an immutable
  widget item flag.
- Rejected-path audit: the original plan stated that private presentation must
  remain unchanged but omitted its literal test command. The existing private
  sentinel is now named in TC-314-04 and Acceptance Gates. No other change
  materially increased counterexample coverage.

## Execution Progress

| Time | Phase | Files | Last command/result | Current evidence | Decision/blocker | Next |
|---|---|---|---|---|---|---|
| 2026-07-31 21:57 CEST | review complete | plan only | Graphify `--profile review` returned `confidence=anchored`; caller/test census verified | One missing private sentinel command corrected; all five review lenses pass | none | add causal tests and capture RED |
| 2026-07-31 21:59 CEST | RED | both group presentation test files | TC-314-01 and TC-314-02 each exited `1`: expected `false`, actual `true` | Unchanged inline and library static-image items still exposed automatic details; adapted GIF/video and both announcement sentinels were GREEN first | expected causal RED | implement only the two item-builder predicates |
| 2026-07-31 22:01 CEST | GREEN + mutation | both group item builders and causal tests | both causal tests exited `0`; restoring each old `mediaType != video` expression made its test exit `1`; hiding all inline static images made GMA-13 exit `1` | Each entrypoint and the discussion/announcement boundary are independently causal. One initial compile typo exposed that `_item` belongs to the nested host and was corrected to `widget.screen.incomingOnly` before GREEN | none | run complete suites and preservation |
| 2026-07-31 22:03 CEST | Preservation | three group widget files; direct/shared viewer tests | group conversation `231/231`, Group Shared Media `7/7`, announcement library `1/1`; exact direct image, shared/default metadata, and private presentation sentinels passed | Incoming/outgoing typed data, captions, eligible incoming Info, compact actions, GIF visibility, video suppression/PiP, announcements, direct/default, and private behavior remain intact | none | run curated lane and hygiene |
| 2026-07-31 22:09 CEST | Closure | affected production/tests; Graphify architecture graph | `./scripts/run_test_gates.sh groups`: `3272/3272` Flutter plus all Go bridge/node and relay tails; `flutter analyze`: no issues in 121.0s; format and `git diff --check`: clean; incremental Graphify refresh and affected query succeeded | Host closure is green with no shared-renderer, capability, persistence, localization, native, device, schema, wire, crypto, or transport widening | none | complete; aggregate `host-all` remains deferred by project cadence |
