# 313 - Group Keep-in-chat Media Viewer Action Layout Parity

Status: implemented; host-green (2026-07-31)
Type: Modification
Spec: free-text intent — make incoming discussion-group image and video viewer
actions use the existing 1:1 Keep-in-chat layouts
Classification: implemented
Closure tier: host

## Planning Progress

| Time | Role | Files inspected | Decision/blocker | Next action |
|---|---|---|---|---|
| 2026-07-31 20:24 CEST | Evidence Collector | `$tdd-plan` and references; Graphify compact TDD context; group/direct item builders; shared typed viewer; group/direct/shared widget tests; gate arrays | Confirmed the group inline builder leaves every item on the standard-toolbar default while the direct builder already selects the two requested compact presentations. | Define caller-level causal tests plus the announcement/action-preservation guard. |
| 2026-07-31 20:33 CEST | Planner | current source citations; all group viewer action-key tests; Plan 310/312; planning probes; dirty tree | Selected one group caller-policy edit and bounded test adaptations. Scope is incoming ordinary `GroupType.chat` static images/videos only; announcement, GIF, outgoing, private, and Shared Media viewers remain unchanged. | Run `$tdd-review`, revise only verified deltas, then execute tests-first. |
| 2026-07-31 20:39 CEST | Reviewer | `$tdd-review` references; review-profile Graphify context; every group typed-viewer constructor; compact action orders; group action-key census; group/direct Shared Media builders and gates | Initial verdict `plan-fixes-required`: the implementation seam is sound, but the plan incorrectly assigned the announcement mutation to TC-313-01, overclaimed full PiP proof in TC-313-02, named Group Shared Media preservation without a sentinel, and did not name the existing private-presentation sentinel. All four bounded corrections were applied; re-audit verdict `ready`. | Execute the corrected contract tests-first. |
| 2026-07-31 21:10 CEST | Executor | caller presentation branch; causal and preservation widget tests; curated group gate; analyzer/format/diff hygiene; refreshed Graphify impact | Implemented the reviewed seam without shared-renderer, capability, localization, persistence, native, or transport changes. Both causal tests failed on the old standard presentation, passed after the caller edit, and re-failed under representative presentation and scope mutations. Full affected suites and the curated group gate are green. | Complete; defer full `host-all` to the presentation batch/release cadence. |

## Problem And Evidence

- Behavior to improve: when a group member opens an incoming ordinary image or
  video from a discussion message, Save, Share, Reply, Forward, Info, and
  Delete are still laid out side-by-side in the top AppBar. The image should
  use the 1:1 Keep-in-chat three-dot menu plus bottom Forward/Delete controls;
  the video should use the 1:1 all-action three-dot menu.
- Impact: the group viewer is visually inconsistent with the direct viewer and
  can crowd the AppBar. A broad shared-viewer change could hide an authorized
  action, change announcements or Shared Media, or duplicate controls.
- Confirmed current gap: `_viewerItemFor` constructs the displayed group item
  at
  `lib/features/groups/presentation/screens/group_conversation_wired.dart:5978-6067`
  without setting `actionPresentation`, so it inherits
  `MediaViewerActionPresentation.standardToolbar` from
  `lib/shared/widgets/media/media_viewer_item.dart:124-143`.
- Confirmed requested precedent: `_buildDirectViewerItem` selects
  `compactImageOverlay` for incoming ordinary static images and
  `compactVideoOverflow` for incoming ordinary videos while preserving GIF and
  outgoing standard presentation at
  `lib/features/conversation/presentation/screens/conversation_screen.dart:2071-2075,2127-2134`.
- Confirmed renderer behavior:
  `FullScreenTypedMediaViewer.build` branches only on the caller-supplied
  presentation at
  `lib/shared/widgets/media/full_screen_typed_media_viewer.dart:424-508`.
  `_buildCompactTopActions` puts Save/Share/Info/Reply in the image popup and
  `_buildCompactBottomActions` places Forward/Delete at the safe bottom corners
  (`:550-603,703-731`); `_buildCompactVideoTopActions` puts every authorized
  video action, plus conditional PiP, in one popup (`:605-701`).
- Confirmed action set: `GroupReceivedMediaActionPolicy.capabilitiesFor`
  authorizes only incoming ordinary group-owned image/video rows and yields
  Save/Share/Info/Delete plus discussion Reply when writable; the wired caller
  adds Forward only when its launch path qualifies at
  `group_conversation_wired.dart:5983-6026`. Therefore selecting the existing
  compact renderers changes placement, not capability or dispatch.
- Confirmed sibling hazard: the same group builder also serves announcements,
  which can add the group-only `MediaViewerAction.messageSender` at
  `group_conversation_wired.dart:6007-6013`. Neither compact menu contains that
  action (`full_screen_typed_media_viewer.dart:129-144`). The change must be
  scoped to `GroupType.chat`; widening it to announcements would omit a real
  action.
- Confirmed bypass/scope sites: `_onMediaTap` is the only inline ordinary group
  route and maps all displayable siblings through `_viewerItemFor` at
  `group_conversation_wired.dart:5882-5957`. Group private media and Group
  Shared Media use separate builders/routes. Direct Shared Media also retains
  standard presentation, so library changes are not part of 1:1 Keep-in-chat
  parity.
- Existing coverage: shared viewer tests prove the compact image geometry,
  exact localized icon-bearing menu rows, capability gating, complete video
  action dispatch, and conditional PiP. Direct caller tests prove the requested
  incoming image/video selection and GIF/outgoing boundary. Group GMA tests
  prove exact capability, action identity, Info, Reply, Forward, Delete, and
  announcement Message-sender behavior.
- Planning probes on 2026-07-31: the exact shared compact-image layout, shared
  complete compact-video menu, direct image selection, direct video selection,
  and group video/Info tests all exited `0`. This confirms the reusable
  renderers and preservation baseline; it does not satisfy group caller
  selection.
- Missing coverage: no group caller test requires either compact presentation;
  current group tests address the standard toolbar's action keys directly and
  would not distinguish a correctly partitioned popup/bottom layout from the
  old top row.
- Refuted findings:
  - Editing `_buildActions` or changing `MediaViewerItem`'s default is too broad;
    explicit caller presentation is the existing policy seam.
  - Adding `messageSender` to both compact renderers is unnecessary for this
    discussion-only request and would broaden the established 1:1 layouts.
  - Changing action capabilities, dispatch handlers, localization, icons, or
    PiP is not required; the shared compact renderers already implement them.
- Unresolved findings: N/A — the inline caller, requested precedents, renderer
  partitions, action capability seam, and announcement bypass are confirmed in
  current source.
- Affected production, test, and gate files:
  `lib/features/groups/presentation/screens/group_conversation_wired.dart` and
  `test/features/groups/presentation/group_conversation_wired_test.dart`, plus
  preservation assertions in
  `test/features/groups/presentation/group_shared_media_wired_test.dart`.
  Gate scripts require no edit.

## Graph Grounding Snapshot

- Graph fingerprint / freshness: `b94121866dc504a3`;
  `stale:lib/features/groups/data/repositories/group_repository_impl.dart`.
  The stale repository file is unrelated to this presentation seam.
- Query / profile:
  `python3 graphify-arch/tdd_context.py query "group chat inline image video viewer actionPresentation compactImageOverlay compactVideoOverflow direct Keep in chat parity _viewerItemFor _buildDirectViewerItem FullScreenTypedMediaViewer tests gates" --profile tdd --budget 700`
  returned `confidence=anchored`; no refinement was required.
- Anchors: `_viewerItemFor` ->
  `lib/features/groups/presentation/screens/group_conversation_wired.dart:5978`;
  `_buildDirectViewerItem` ->
  `lib/features/conversation/presentation/screens/conversation_screen.dart:2064`;
  `actionPresentation` ->
  `lib/shared/widgets/media/media_viewer_item.dart:178`.
- Surfaced proof/gate files: shared media viewer/item, group/direct conversation
  owners, and the curated group test candidate.
- Graph gaps requiring source search: exact compact action partitioning, the
  announcement-only Message-sender capability, Shared Media bypasses, current
  group action-key tests, and literal gate registration were verified directly
  in source and arrays.
- Reuse rule: anchors may be handed to review/execution; all conclusions still
  require current-source or command evidence.

## Scope Contract And Guard

In scope:

- For an incoming, ordinary, verified visual opened inline from a discussion
  (`GroupType.chat`), select `compactImageOverlay` when the typed kind is static
  image and `compactVideoOverflow` when it is video.
- On group images, require one top-right three-dot control; Save, Share, Info,
  and Reply appear only in its icon-bearing popup; Forward remains bottom-right
  and Delete bottom-left when authorized.
- On group videos, require one top-right three-dot control containing every
  authorized group media action—Save, Share, Info, Reply, Forward, Delete—and
  conditional PiP, with no duplicate top or bottom action buttons.
- Adapt only group tests whose intentional direct toolbar taps become popup
  interactions; retain their exact identity, authorization, and side-effect
  assertions.

Must preserve:

- Exact per-item group capability and callback dispatch for Save/Share/Info/
  Reply/Forward/Delete -> `TC-313-01/02/04`.
- Announcement standard-toolbar behavior and Message-sender eligibility ->
  `TC-313-03`.
- Outgoing media and incoming GIF standard presentation; group private and
  Shared Media routes remain unchanged -> `TC-313-01/02/03`.
- Direct Keep-in-chat image/video layouts, icons, action dispatch, and
  conditional PiP remain unchanged -> `TC-313-05`.
- Existing metadata visibility, captions, playback/resume/PiP qualification,
  media bytes, and all action authorization/side effects ->
  `TC-313-02/04/05`.
- Every unrelated dirty-tree edit, including Plans 303-312, notification,
  native, localization, gate, and Graphify work.

Hard `Do not`:

- Do not change shared viewer action orders, icons, labels, dispatch, effects,
  presentation defaults, or PiP behavior.
- Do not compact announcement, outgoing, GIF, private/protected/view-once, or
  Group Shared Media viewers; do not alter direct or direct Shared Media.
- Do not add/remove capabilities, widen Reply/Forward/Info, change deletion or
  egress coordinators, or infer authorization in the shared viewer.
- Do not change metadata, captions, playback/resume, persistence, schema,
  crypto, relay/Go, transport, native code, or localization.
- Do not overwrite or absorb unrelated dirty-tree work.

Deferred / accepted difference:

- Announcement viewers retain their standard toolbar because their
  Message-sender action is not represented by the established compact layouts;
  announcement redesign requires a separate product contract.
- Group and direct Shared Media libraries retain standard presentation; the
  requested reference is the inline 1:1 Keep-in-chat viewer, not a library
  surface.
- Outgoing and GIF pages retain standard presentation, matching the direct
  Keep-in-chat caller policy.

Dependencies:

- Builds on Plans 307/308's compact image renderer, Plan 310's compact video
  renderer, and Plan 312's group video metadata policy. Stop if execution finds
  another inline ordinary group item builder, if an authorized discussion
  action is absent from the selected compact renderer, or if current work has
  changed announcements to use a compact layout; replan rather than hiding an
  action.

## Test Contract

| Case | Behavior | Named test/proof | Tier / fixture | HEAD -> GREEN | Mutation | Gate / registration |
|---|---|---|---|---|---|---|
| TC-313-01 | Incoming ordinary discussion static images select `compactImageOverlay`; the top AppBar has only More, the popup has exactly authorized Save/Share/Info/Reply with icons, Forward/Delete occupy bottom end/start, and all six capabilities survive. An incoming GIF remains standard. | `test/features/groups/presentation/group_conversation_wired_test.dart::incoming discussion image uses compact keep-in-chat controls without losing actions` | Widget host / real verified image and GIF bytes, writable chat, media controller, delete coordinator, Forward launcher, typed-viewer and popup inspection | HEAD RED because the image item defaults `standardToolbar` and renders authorized actions side-by-side -> GREEN requires the exact compact partition, no duplicates/omissions, correct kind boundary, and unchanged capability set | Remove the caller assignment, choose video compact, classify by `mediaType == image` so GIF compacts, or drop an allowed action -> TC-313-01 red; omit the chat-type guard -> TC-313-03 red | `flutter test test/features/groups/presentation/group_conversation_wired_test.dart --plain-name 'incoming discussion image uses compact keep-in-chat controls without losing actions'`; existing `GROUP_TESTS`; AUTO (`feature-host-all` glob), no registration edit |
| TC-313-02 | Incoming ordinary discussion videos select `compactVideoOverflow`; all authorized Save/Share/Info/Reply/Forward/Delete actions are icon-bearing popup rows with no top/bottom duplicates, while outgoing video stays standard and the caller's typed PiP eligibility input is unchanged. | `test/features/groups/presentation/group_conversation_wired_test.dart::incoming discussion video uses all-action keep-in-chat overflow without losing actions` | Widget host / real verified incoming and outgoing video files, writable chat, all wired action dependencies, typed-viewer and popup inspection | HEAD RED because incoming video inherits `standardToolbar` -> GREEN requires one More button, every authorized action only inside the popup, outgoing standard presentation, exact capabilities, and unchanged `canEnterPictureInPicture`; TC-313-05 owns actual conditional popup/PiP dispatch | Remove assignment, select image compact, gate both directions, omit Forward/Delete, duplicate a toolbar action, or change PiP qualification -> TC-313-02 red | `flutter test test/features/groups/presentation/group_conversation_wired_test.dart --plain-name 'incoming discussion video uses all-action keep-in-chat overflow without losing actions'`; existing `GROUP_TESTS`; AUTO (`feature-host-all` glob), no registration edit |
| TC-313-03 | Announcement actions, including eligible Message sender, remain on the existing standard toolbar; mismatched attachments remain ineligible; Group Shared Media image/video items also retain standard presentation. | `test/features/groups/presentation/group_conversation_wired_test.dart::GMA-13 announcement member and admin expose core media actions without reply while qa stays excluded`; `::Plan 247 mismatched viewer attachments never receive Message sender or open`; `test/features/groups/presentation/group_shared_media_wired_test.dart::GML-04 typed viewer crosses parent and cursor boundaries`; `::GML-PIP ordinary received video forwards exact PiP composition` | `GREEN sentinel` / announcement member/admin, mixed-owner/current-parent, and group library image/video fixtures | GREEN on HEAD -> remains GREEN after discussion-only caller selection | Remove the `GroupType.chat` guard, compact every group visual or either library kind, alter capability policy, or publish Message sender to mismatched rows -> named sentinel red | Four exact `flutter test ... --plain-name` commands in Acceptance Gates; existing `GROUP_TESTS`; AUTO feature glob |
| TC-313-04 | Existing group viewer actions still dispatch exact selected identity and reuse the current Info, Reply, Forward, egress, and deletion paths after their intentional popup interaction updates. | `test/features/groups/presentation/group_conversation_wired_test.dart::ordinary group videos hide automatic metadata for sender and receiver while Info retains it`; `::GMA-03 viewer selection and reopen preserve exact attachment identity`; `::GMA-05 media reply reuses existing group quote flow`; `::GMA-11 wired media actions reach only injected coordinators`; `::GPL-04F injected Forward launcher requalifies after attachment await before picker` | `GREEN sentinel` / current real-file group fixtures and injected coordinators | GREEN on HEAD; intentional action-key taps are adapted to open More first where required -> remains GREEN with the same exact metadata, authorization, identity, and side-effect assertions | Route to first attachment, remove/relabel an action, bypass a coordinator, widen Reply, or change Forward/delete behavior -> named sentinel red | Exact commands in Acceptance Gates; existing `GROUP_TESTS`; AUTO feature glob |
| TC-313-05 | Shared compact renderers and direct caller selection retain existing image corner geometry, icon-bearing popup order, complete video dispatch, current-page identity, conditional PiP, and private minimization without shared production edits. | `test/shared/widgets/media/full_screen_typed_media_viewer_test.dart::compact image layout places overflow forward and delete on safe corners`; `::compact overflow lists localized image actions in order and targets the current item`; `::compact video overflow lists and dispatches every authorized media action`; `::compact video overflow nests conditional PiP and starts exact current owner`; `::private presentation suppresses metadata resume actions and PiP without changing ordinary pages`; `test/features/conversation/presentation/screens/conversation_received_media_actions_test.dart::incoming keep-in-chat images select compact actions while sibling media stays standard`; `::received keep-in-chat video selects its all-action overflow without widening sibling media` | `GREEN sentinel` / shared LTR/RTL/locales, private-minimized, and direct real-file fixtures | GREEN on HEAD -> remains GREEN after group caller-only edit | Change compact orders/icons/geometry/dispatch, duplicate PiP, weaken private minimization, capture stale item, or widen direct outgoing/GIF presentation -> named sentinel red | Exact direct commands in Acceptance Gates; shared file is run directly because it is outside feature/core globs; direct tests are in existing 1:1 arrays/AUTO feature glob |

## Implementation Steps

1. Snapshot `git status --short`. Add TC-313-01 and TC-313-02 to the existing
   group received-media test scope before any production edit and capture their
   causal HEAD failures.
2. In `_viewerItemFor`, compute/reuse the typed `kind` and set
   `actionPresentation` only when `_group.type == GroupType.chat`, the parent is
   incoming and ordinary, and the kind is static image or video. Use the
   existing standard default for every sibling. Stop if this requires changing
   a shared action list or capability policy.
3. Update the bounded existing group tests that intentionally tap Save, Share,
   Info, or Reply in the viewer to open More first. Do not weaken their exact
   identity, availability, or side-effect assertions. Add standard-presentation
   assertions to the existing Group Shared Media image and video sentinels. No
   harness registration edit is expected.
4. Run focused GREEN, the exact announcement/direct/shared sentinels, the full
   three affected test files, the curated `groups` lane, analyzer/hygiene, then
   refresh the architecture graph incrementally once.

## Risks And Blind Spots

- Missing action after compaction -> TC-313-01/02 compare the complete item
  capability set with every rendered popup/bottom slot.
- Over-broad group selection hides announcement Message sender -> TC-313-03
  or changes library presentation -> TC-313-03 and the hard chat-type guard.
- Media-type shortcut compacts GIF or outgoing pages -> negative fixtures in
  TC-313-01/02.
- Existing action tests fail only because controls moved -> TC-313-04 adapts
  interactions but preserves exact downstream assertions.
- Stale-page or duplicated action controls -> TC-313-01/02 and TC-313-05.
- Lifecycle / derived-state durability: N/A — presentation is derived per
  immutable viewer item on every route open; no persisted or cached state is
  introduced.
- Sibling-surface consistency: guarded by announcement, GIF, outgoing, direct,
  private/library scope and exact sentinels.
- Destructive-action side effects: existing GMA delete cancellation/confirmation
  remains under TC-313-04; production delete behavior is not changed.
- Invariant re-verification under new transitions: current action dispatch
  rechecks exact item eligibility immediately before callback; TC-313-04/05
  preserve it. No new state transition is introduced.

## Gate Cadence

- Per-plan closure: two causal group tests; exact group announcement/action,
  Group Shared Media, shared compact-renderer, and direct caller sentinels; complete
  `group_conversation_wired_test.dart` and
  `full_screen_typed_media_viewer_test.dart`; curated `groups`; analyzer and
  hygiene.
- Do not run full `host-all` for this individual plan. The Keep-in-chat media
  presentation batch (Plans 306-313) owns one aggregate
  `./scripts/run_host_test_gates.sh host-all` run at its explicit batch closure;
  final rollout/release owns the final aggregate run.
- Shared tests outside feature/core globs: run
  `test/shared/widgets/media/full_screen_typed_media_viewer_test.dart` directly.

## Acceptance Gates

```bash
# Snapshot before execution; record unrelated changes
git status --short

# Causal RED before production edits; each must exit non-zero for the documented
# inherited-standard-toolbar reason
flutter test test/features/groups/presentation/group_conversation_wired_test.dart --plain-name 'incoming discussion image uses compact keep-in-chat controls without losing actions'
flutter test test/features/groups/presentation/group_conversation_wired_test.dart --plain-name 'incoming discussion video uses all-action keep-in-chat overflow without losing actions'

# Focused GREEN; exact tests and complete changed test file must exit 0
flutter test test/features/groups/presentation/group_conversation_wired_test.dart --plain-name 'incoming discussion image uses compact keep-in-chat controls without losing actions'
flutter test test/features/groups/presentation/group_conversation_wired_test.dart --plain-name 'incoming discussion video uses all-action keep-in-chat overflow without losing actions'
flutter test test/features/groups/presentation/group_conversation_wired_test.dart

# Announcement and action preservation; each exits 0
flutter test test/features/groups/presentation/group_conversation_wired_test.dart --plain-name 'GMA-13 announcement member and admin expose core media actions without reply while qa stays excluded'
flutter test test/features/groups/presentation/group_conversation_wired_test.dart --plain-name 'Plan 247 mismatched viewer attachments never receive Message sender or open'
flutter test test/features/groups/presentation/group_shared_media_wired_test.dart --plain-name 'GML-04 typed viewer crosses parent and cursor boundaries'
flutter test test/features/groups/presentation/group_shared_media_wired_test.dart --plain-name 'GML-PIP ordinary received video forwards exact PiP composition'
flutter test test/features/groups/presentation/group_conversation_wired_test.dart --plain-name 'ordinary group videos hide automatic metadata for sender and receiver while Info retains it'
flutter test test/features/groups/presentation/group_conversation_wired_test.dart --plain-name 'GMA-03 viewer selection and reopen preserve exact attachment identity'
flutter test test/features/groups/presentation/group_conversation_wired_test.dart --plain-name 'GMA-05 media reply reuses existing group quote flow'
flutter test test/features/groups/presentation/group_conversation_wired_test.dart --plain-name 'GMA-11 wired media actions reach only injected coordinators'
flutter test test/features/groups/presentation/group_conversation_wired_test.dart --plain-name 'GPL-04F injected Forward launcher requalifies after attachment await before picker'

# Shared/direct presentation preservation; exact tests and shared file exit 0
flutter test test/shared/widgets/media/full_screen_typed_media_viewer_test.dart
flutter test test/features/conversation/presentation/screens/conversation_received_media_actions_test.dart --plain-name 'incoming keep-in-chat images select compact actions while sibling media stays standard'
flutter test test/features/conversation/presentation/screens/conversation_received_media_actions_test.dart --plain-name 'received keep-in-chat video selects its all-action overflow without widening sibling media'

# Curated affected lane; target is selected through GROUP_TESTS and all Flutter
# cases plus registered Go tails exit 0
./scripts/run_test_gates.sh groups

# Hygiene; no new analyzer issue, format drift, or whitespace error
dart format --output=none --set-exit-if-changed lib/features/groups/presentation/screens/group_conversation_wired.dart test/features/groups/presentation/group_conversation_wired_test.dart test/features/groups/presentation/group_shared_media_wired_test.dart
flutter analyze
git diff --check

# Required post-change graph refresh and focused impact evidence
./graphify-arch/refresh_arch_graph.sh --incremental
python3 graphify-arch/tdd_context.py affected lib/features/groups/presentation/screens/group_conversation_wired.dart test/features/groups/presentation/group_conversation_wired_test.dart test/features/groups/presentation/group_shared_media_wired_test.dart --budget 600
```

## Execution Interpretation And Done Criteria

- Expected RED: TC-313-01/02 fail because group items inherit
  `standardToolbar`, More is absent, and authorized actions render in the
  AppBar.
- Green sentinel: TC-313-03/04/05 preserve announcements, exact group action
  behavior, the shared renderers, and direct selection.
- Pre-existing dirty tree / known failure: extensive user-owned Plans 303-312,
  group notification/native/relay, l10n, scripts, Graphify, and phone-run edits
  are present. The five planning probes pass; unrelated diffs are not plan
  failures and must not be reverted.
- Environment blocker: none expected. This is deterministic host-only widget
  presentation with no OS, device, relay, crypto, or real-network claim.
- Scope drift: any required shared-renderer/capability/localization edit,
  announcement compaction, another inline builder, or unrelated failure blocks
  completion pending a plan delta.

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
  `flutter test test/features/groups/presentation/group_conversation_wired_test.dart --plain-name 'incoming discussion image uses compact keep-in-chat controls without losing actions'`.
- Preservation command:
  `flutter test test/shared/widgets/media/full_screen_typed_media_viewer_test.dart`.
- Manual registration: none; both group files are already in `GROUP_TESTS` and
  all three test files retain their current auto/direct ownership.
- Migration: none.
- Boundary closure: host-only; no device/relay proof is justified for an
  item-presentation branch over existing renderers.
- Unresolved evidence: none.

## Reviewer Findings

Verdict: **ready** after bounded revise-in-place corrections.
Plan classification: implementation-ready; core bet: **confirmed**.
Disposition: **execute**.

- L1 evidence truth: `clear` — the inherited standard-toolbar cause, direct
  precedent, group capability set, and inline/library/private caller census are
  current-source confirmed.
- L2 test causality: `clear` after correcting TC-313-01's announcement mutation
  owner and narrowing TC-313-02 to the PiP input it can actually observe. The
  two causal rows distinguish no-op, wrong compact kind, wrong direction, GIF
  widening, missing action, and duplicated-control implementations.
- L3 bypass/scope safety: `clear` after adding explicit standard-presentation
  sentinels for both Group Shared Media kinds. Announcement Message sender,
  private `privacyMinimized`, direct callers, and the PiP authorization snapshot
  remain outside the single production seam.
- L4 execution/gates: `clear` — literal focused commands, existing
  `GROUP_TESTS`/AUTO registration, the affected curated lane, and proportionate
  hygiene are present; per-plan full `host-all` remains correctly deferred.
- L5 boundary/reversibility: `N/A` — immutable host UI presentation only; no
  persistence, migration, OS callback, relay, crypto, destructive mutation, or
  cross-device claim.
- Blind-spot hits: B-2/B-3/B-4/B-9 were exercised and are now closed by the
  explicit announcement/library census, causal negative fixtures, complete
  action assertions, and named preservation sentinels. B-1/B-5/B-6/B-8/B-10
  are N/A; B-7 is clear because the existing compact renderers are directly
  proven and require no fallback.
- User-owned decisions: none.

## Execution Progress

| Time | Phase | Files | Last command/result | Current evidence | Decision/blocker | Next |
|---|---|---|---|---|---|---|
| 2026-07-31 | RED | `group_conversation_wired_test.dart` | both TC-313-01/02 exact commands exited `1` | Actual group items were `standardToolbar` where the tests required `compactImageOverlay` / `compactVideoOverflow` | expected causal RED | implement only the group caller presentation selection |
| 2026-07-31 | GREEN + mutation | `group_conversation_wired.dart`; group widget tests | both causal tests exited `0`; forcing standard made both exit `1`; removing the `GroupType.chat` guard made the announcement Message-sender sentinel exit `1` | Correct compact kind and discussion-only scope are independently causal | none | run preservation and complete-file suites |
| 2026-07-31 21:05 CEST | Preservation | group conversation/library tests; shared viewer; direct received-media tests | group conversation `230/230`; combined library/shared/direct run `45/45` | All actions/icons remain reachable; announcements, outgoing, GIF, private, library, direct, metadata, PiP input, identity, reply, forwarding, sharing, and deletion boundaries remain green | none | run affected curated lane and hygiene |
| 2026-07-31 21:10 CEST | Closure | affected source/tests; Graphify architecture graph | `./scripts/run_test_gates.sh groups`: `3320/3320` Flutter plus all Go/relay tails; `flutter analyze`: no issues; format and `git diff --check`: clean; incremental Graphify refresh and affected query succeeded | Host closure is green with no migration/device claim and no shared production widening | none | complete; aggregate `host-all` remains deferred by project cadence |
