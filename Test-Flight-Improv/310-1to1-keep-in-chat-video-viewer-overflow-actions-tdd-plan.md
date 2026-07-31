# 310 - 1:1 Keep-in-chat Received Video Viewer Overflow Actions

Status: implemented / host-green (2026-07-31)
Type: Modification
Spec: free-text intent — in a received 1:1 `Keep in chat` video viewer,
replace the row of top action icons with one three-dot menu and retain every
currently available action
Classification: implemented
Closure tier: host

## Planning Progress

| Time | Role | Files inspected | Decision/blocker | Next action |
|---|---|---|---|---|
| 2026-07-31 19:04 CEST | Evidence Collector | `$tdd-plan` instructions and required references; Graphify compact context; Plans 307/308; typed viewer, item model, direct conversation caller, focused tests, l10n, and gate scripts | Confirmed that received ordinary videos alone retain the standard toolbar; the direct item already authorizes six media actions and may expose PiP as a seventh top action. | Build a video-specific overflow contract without changing photo or default callers. |
| 2026-07-31 19:13 CEST | Planner | current source/test citations, all `MediaViewerItem` callers, PiP request path, direct/shared/group preservation seams, dirty-tree snapshot | Selected an additive `compactVideoOverflow` presentation. All six authorized media actions and conditional PiP belong inside its one menu; no bottom or duplicate top actions remain. | Run `$tdd-review`, apply only verified deltas, then execute tests-first. |
| 2026-07-31 19:21 CEST | Reviewer | `$tdd-review` instructions/references; review-profile Graphify context; plan contract; exact test names, action-presentation/PiP call sites, and gate discovery | Initial verdict `plan-fixes-required`: core design confirmed; tightened one vague proof row, one missing literal preservation command, the popup-local PiP discriminator, and an overclaimed restore assertion. All verified deltas were applied; re-audit verdict `ready`. | Execute the reviewed contract tests-first. |
| 2026-07-31 19:35 CEST | Executor | reviewed contract, causal widget/direct tests, all changed production seams, preservation sentinels, curated `1to1` lane, analyzer/hygiene, and affected Graphify context | Implemented the received-video-only overflow. All six media actions plus conditional PiP remain reachable exactly once; causal mutations re-red and all required host gates are green. | Close as implemented / host-green. |

## Problem And Evidence

- Behavior to improve: when the receiver opens an ordinary (`Keep in chat`)
  video from a 1:1 conversation, replace the separate top Save, Share, Info,
  Reply, Forward, Delete, and conditional Picture-in-Picture controls with one
  circular three-dot control. Opening it must expose every action that was
  available before the change, with its icon and localized label.
- Impact: the video toolbar is crowded and differs from the compact received-
  photo treatment; omitting an action while consolidating it would regress a
  working media operation.
- Confirmed current gap: `_buildDirectViewerItem` selects
  `compactImageOverlay` only for incoming ordinary images and leaves video on
  `standardToolbar` at
  `lib/features/conversation/presentation/screens/conversation_screen.dart:2127-2132`.
  `FullScreenTypedMediaViewer.build` renders conditional PiP and every allowed
  `_actionOrder` entry as separate `AppBar.actions` at
  `lib/shared/widgets/media/full_screen_typed_media_viewer.dart:404-457`.
- Confirmed current action inventory: the direct caller independently grants
  Save, Share, Reply, Info, Forward, and Delete at
  `conversation_screen.dart:2076-2100`; incoming ordinary video may also be
  authorized for PiP at `:2133-2136`. The PiP visibility path rechecks platform
  capability and current-item policy at
  `full_screen_typed_media_viewer.dart:204-243`.
- Confirmed effect boundary: all six media selections continue through the
  existing `_dispatch` current-item/capability recheck at
  `full_screen_typed_media_viewer.dart:360-381` and the kind-neutral direct
  callback switch at `conversation_screen.dart:2153-2213`. PiP must continue
  through `_requestPictureInPicture` at
  `full_screen_typed_media_viewer.dart:245-297`; this plan changes only how
  those existing entrypoints are reached.
- Existing coverage:
  `conversation_received_media_actions_test.dart::incoming keep-in-chat images select compact actions while sibling media stays standard`
  currently proves video is standard;
  `::same message bubble and viewer parity follows selected attachment` and
  the selected-attachment Info test prove video page-current dispatch;
  `::direct received-video route forwards exact PiP composition to the typed viewer`
  proves direct PiP wiring;
  `full_screen_typed_media_viewer_test.dart::supported Android PiP control targets and restores the exact current video owner`
  proves the existing PiP request path; Plans 307/308 tests prove the photo
  popup style, icons, capability filtering, and photo-only bottom controls.
- Planning probes: the exact direct image/video presentation test and the exact
  direct received-video PiP-composition test each exited `0` on 2026-07-31.
  They confirm the current separate-toolbar mechanism; they do not prove the
  requested overflow.
- Missing coverage: no test requires a video-only compact presentation, binds
  all six authorized media actions plus conditional PiP to one popup, rejects
  duplicate top/bottom controls, proves all rows remain reachable in en/de/ar,
  or dispatches the popup's PiP row through the exact-current-video owner.
- Refuted findings:
  - Reusing `compactImageOverlay` unchanged is insufficient: it intentionally
    leaves Forward/Delete at bottom and its popup contains only Save image,
    Share, Info, and Reply.
  - Leaving PiP beside the ellipsis would violate “all under three dots” on
    supported incoming videos; current production wiring can make PiP visible.
  - A controller, repository, native, or transport rewrite is unnecessary;
    all effects already have callback-only entrypoints.
  - New localization is unnecessary. Reuse the existing generic localized
    Save label for video and all existing action/PiP labels; `Save image`
    remains photo-only.
- Unresolved findings: N/A — the surface, complete current action set,
  presentation seam, callback routes, test tier, and gate ownership are
  source-confirmed.
- Affected production, test, and gate files:
  `lib/shared/widgets/media/media_viewer_item.dart`,
  `lib/shared/widgets/media/full_screen_typed_media_viewer.dart`,
  `lib/features/conversation/presentation/screens/conversation_screen.dart`,
  `test/shared/widgets/media/full_screen_typed_media_viewer_test.dart`, and
  `test/features/conversation/presentation/screens/conversation_received_media_actions_test.dart`.
  Gate scripts require no edit.

## Graph Grounding Snapshot

- Graph fingerprint / freshness: `fe988d87225d0a2c`;
  `stale:ios/Flutter/flutter_export_environment.sh`. The stale generated iOS
  environment file is unrelated to this host widget seam; every load-bearing
  conclusion was verified in current source.
- Query / profile:
  `python3 graphify-arch/tdd_context.py query "1:1 kept video viewer action toolbar share reply download delete info three-dot overflow and photo viewer precedent" --profile tdd --budget 700`
  returned `confidence=broad`; the permitted refinement was
  `python3 graphify-arch/tdd_context.py query "direct_private_media_viewer.dart DirectPrivateMediaViewer video top action toolbar photo overflow action menu tests ONE_TO_ONE_TESTS" --profile tdd --budget 700`
  and returned `confidence=anchored`.
- Anchors: `DirectPrivateMediaViewer` ->
  `lib/features/conversation/presentation/screens/direct_private_media_viewer.dart:19`;
  direct ordinary typed-viewer caller ->
  `lib/features/conversation/presentation/screens/conversation_screen.dart:2022`;
  shared action presenter ->
  `lib/shared/widgets/media/full_screen_typed_media_viewer.dart:404`;
  `ONE_TO_ONE_TESTS` -> `scripts/run_test_gates.sh:25`.
- Surfaced proof/gate files:
  `direct_private_media_viewer.dart`, `conversation_screen.dart`,
  `full_screen_typed_media_viewer.dart`, `media_viewer_item.dart`,
  `direct_private_media_viewer_test.dart`, and both 1:1 gate arrays.
- Graph gaps requiring source search: the graph did not surface the Plan-307
  presentation enum, the conditional PiP control, exact received-media tests,
  all `MediaViewerItem` callers, or current line-level gate registration; each
  was verified directly.
- Reuse rule: anchors may be handed to review/execution; all conclusions still
  require current-source or command evidence.

## Scope Contract And Guard

In scope:

- Add `MediaViewerActionPresentation.compactVideoOverflow` as an explicit,
  default-off presentation choice. Select it only for incoming ordinary videos
  opened from the 1:1 conversation.
- Render exactly one top-end circular `media_action_more` control using the
  existing Plan-307 shape, hit target, tooltip, and directional placement.
- Inside that popup, render the authorized media actions in this exact order:
  Save, Share, Info, Reply, Forward, Delete. Each row reuses its canonical icon,
  stable key, localized label, capability/eligibility gate, and `_dispatch`.
- When current PiP policy/capability makes the existing PiP control visible,
  insert Picture in Picture immediately before destructive Delete, with its
  existing key, icon, localized label, playback readiness gate, and
  `_requestPictureInPicture` callback. When unavailable, omit only that row.
- Keep Forward and Delete inside the video popup—no video bottom actions—and
  suppress every standalone media/PiP AppBar icon for this presentation.

Must preserve:

- Photo behavior remains exactly Plan 307/308: Save image/Share/Info/Reply in
  the icon-labeled popup, Forward bottom-end, Delete bottom-start -> `TC-310-04`.
- Exact current item/owner, capability absence, ineligible/pending fencing,
  result truth, PiP reauthorization/start, and unchanged restore behavior ->
  `TC-310-02/03/05/06`.
- Save destination, native Share, persisted Info, quote Reply, internal
  Forward, and whole-message Delete-for-Me effects -> `TC-310-05`.
- Outgoing video/image, GIF, direct Shared Media, group/announcement, private,
  and every default item remain standard or privacy-minimized as today ->
  `TC-310-01/04/06`.
- Video playback controls, metadata/resume, captions, page indicator, Back,
  and PiP authorization policy remain unchanged -> `TC-310-03/06`.
- Preserve every pre-existing dirty-tree edit, including Plans 303-309,
  localization outputs, native/evidence files, and Graphify artifacts.

Hard `Do not`:

- Do not infer video compactness in the shared viewer from MIME/path/owner;
  only the direct lane owner selects the presentation.
- Do not omit PiP when it would currently be visible, leave it beside the
  ellipsis, or put video Forward/Delete at the photo bottom positions.
- Do not add unauthorized rows, change action authority/order/side effects,
  rename stable keys, or bypass `_dispatch` / `_requestPictureInPicture`.
- Do not apply the new layout to outgoing, GIF, Shared Media, group,
  announcement, private, protected, view-once, disappearing, or path-only
  viewers.
- Do not change media bytes, playback/PiP policy, persistence, schema, wire,
  crypto, relay/Go, or native platform code.

Deferred / accepted difference:

- Photos retain their split overflow/bottom layout. “Like photos” supplies the
  ellipsis and icon-row visual precedent; the video request explicitly puts
  all actions—including Forward/Delete and conditional PiP—inside one menu.
- Unsupported/unauthorized PiP remains absent rather than a disabled promise,
  matching current behavior.
- Direct Shared Media videos intentionally retain the standard toolbar because
  the request names the in-chat receiver surface.

Dependencies:

- Builds on Plans 307/308's additive action-presentation enum, compact control,
  icon rows, and current-item dispatch; on the existing direct PiP controller
  composition; and on the current six-action direct capability policy.
- Stop-if current-source execution finds another in-chat ordinary video item
  builder, a seventh non-PiP top action, or a kind-specific effect branch that
  bypasses the cited seams; replan the action census before editing production.

## Test Contract

| Case | Behavior | Named test/proof | Tier / fixture | HEAD -> GREEN | Mutation | Gate / registration |
|---|---|---|---|---|---|---|
| TC-310-01 | Only received ordinary 1:1 videos select `compactVideoOverflow`; received images keep `compactImageOverlay`, while GIF and outgoing video remain standard. | `test/features/conversation/presentation/screens/conversation_received_media_actions_test.dart::received keep-in-chat video selects its all-action overflow without widening sibling media` | Widget host / incoming video+image+GIF and outgoing video with real direct item builder | HEAD assertion RED because received video is `standardToolbar` -> exact four-way presentation map and one video ellipsis pass | Remove the incoming predicate or leave video standard -> TC-310-01 red | `flutter test test/features/conversation/presentation/screens/conversation_received_media_actions_test.dart --plain-name 'received keep-in-chat video selects its all-action overflow without widening sibling media'`; existing `ONE_TO_ONE_TESTS` and `ONE_TO_ONE_HOST_TESTS`; AUTO (`feature-host-all` glob), no registration edit |
| TC-310-02 | The video ellipsis contains every and only authorized media action—Save, Share, Info, Reply, Forward, Delete—in order, with canonical icon/label, small-viewport reachability, no standalone/bottom duplicates, exact current-page dispatch, and capability/pending fencing. | `test/shared/widgets/media/full_screen_typed_media_viewer_test.dart::compact video overflow lists and dispatches every authorized media action` | Widget host / two compact-video items, all/subset capabilities, callback recorder, en/de/ar at 320x568, fake playback adapter | HEAD compile/assertion RED because `compactVideoOverflow` and its menu do not exist -> exact six-row set/order/icons/labels, last-row reachability, page-2 identity, and one dispatch per selection pass | Omit Delete/Forward, map a row to the wrong action, or render `_actionOrder` outside the popup -> TC-310-02 red | `flutter test test/shared/widgets/media/full_screen_typed_media_viewer_test.dart --plain-name 'compact video overflow lists and dispatches every authorized media action'`; AUTO (`host-all` glob), executed directly per plan |
| TC-310-03 | Conditional PiP is the seventh video popup row immediately before Delete, never a sibling AppBar icon, and selecting it starts the exact current video owner through the existing controller. | `test/shared/widgets/media/full_screen_typed_media_viewer_test.dart::compact video overflow nests conditional PiP and starts exact current owner` | Widget host / two compact videos, fake playback adapters, existing fake PiP gateway/path authority/resume store and current-item authorization | HEAD compile/assertion RED because compact video is absent and PiP is a standalone IconButton -> key absent before opening the popup, one popup-local row after opening, exact order/current owner, and one gateway start pass | Leave PiP in `AppBar.actions` or map its popup row to a media action/no-op -> TC-310-03 red | `flutter test test/shared/widgets/media/full_screen_typed_media_viewer_test.dart --plain-name 'compact video overflow nests conditional PiP and starts exact current owner'`; AUTO (`host-all` glob), executed directly per plan |
| TC-310-04 | Existing received-photo overflow labels/icons and bottom Forward/Delete geometry remain unchanged; the standard presentation remains default. | `test/shared/widgets/media/full_screen_typed_media_viewer_test.dart::compact overflow lists localized image actions in order and targets the current item`; `::compact image layout places overflow forward and delete on safe corners`; `::actions always target the currently visible typed item and owner` | `GREEN sentinel` / Plan-307/308 image fixtures plus standard direct/group fixture | GREEN on HEAD -> remains GREEN after adding a distinct enum branch | Reuse/replace the image branch with video all-menu behavior or change the enum default -> named sentinels red | `flutter test test/shared/widgets/media/full_screen_typed_media_viewer_test.dart --plain-name 'compact overflow lists localized image actions in order and targets the current item'`; same command for `'compact image layout places overflow forward and delete on safe corners'` and `'actions always target the currently visible typed item and owner'`; AUTO (`host-all` glob), executed directly |
| TC-310-05 | Real direct video access paths keep their exact current attachment/effects: Share and Info after image-to-video swipe, all six capabilities from the direct caller, and conditional direct PiP composition. Kind-neutral Forward/Delete handlers remain preserved by their exact existing sentinels. | `test/features/conversation/presentation/screens/conversation_received_media_actions_test.dart::same message bubble and viewer parity follows selected attachment`; `::info follows selected attachment within one message without transport reads`; `::direct received-video route forwards exact PiP composition to the typed viewer`; `test/features/conversation/presentation/screens/conversation_received_media_forward_test.dart::compact viewer bottom forward launches existing picker with current attachment`; `test/features/conversation/presentation/screens/conversation_wired_test.dart::viewer delete invokes existing direct whole message cleanup` | Causal video access-path assertions plus `GREEN sentinel` effects / real direct callbacks, stored Info fake, direct PiP composition, existing Forward picker and wired Delete seam | Share/Info/PiP effects are GREEN on HEAD but strengthened video interactions RED because the video ellipsis is absent -> opening it retains exact attachment/effects and all six plus conditional PiP rows; Forward/Delete sentinels remain GREEN | Capture the initial item, omit one direct capability, or route a popup value to its sibling -> one of the exact identity/effect assertions red | Exact three direct-action `flutter test ... --plain-name` commands plus the exact Forward/Delete commands in Acceptance Gates; direct files are in existing 1:1 arrays and AUTO (`feature-host-all` glob), no registration edit |
| TC-310-06 | Direct Shared Media, group/default/private viewers, video controls/metadata/resume including standard PiP restore, and callback-only/redacted boundary remain unchanged. | `test/features/conversation/presentation/screens/conversation_shared_media_viewer_test.dart::in-viewer current item actions execute across parent messages`; `test/shared/widgets/media/full_screen_typed_media_viewer_test.dart::supported Android PiP control targets and restores the exact current video owner`; complete shared-viewer suite; `test/shared/widgets/media/media_viewer_boundary_test.dart::viewer remains callback-only transport-free and diagnostics are redacted` | `GREEN sentinel` / default library/shared viewer fixtures, standard PiP restore fixture, private/video fixtures, import allowlist and diagnostic sink | GREEN on HEAD -> unchanged default callers, standard PiP restore, and shared boundary stay GREEN | Infer compact video inside the shared viewer, alter the standard PiP path, or implement any effect in it -> sentinel/boundary red | Exact library/PiP/boundary commands and complete shared-viewer command in Acceptance Gates; shared tests AUTO (`host-all` glob), library file already in both 1:1 arrays |

### Test Notes

- TC-310-02 scopes all key/icon/label assertions beneath the open video
  `PopupMenuItem` tree. Before opening, only `media_action_more` may exist;
  Save/Share/Info/Reply/Forward/Delete must have zero standalone finders.
- The exact video order is Save, Share, Info, Reply, Forward, optional Picture
  in Picture, Delete. The first four intentionally match the photo popup;
  destructive Delete remains last.
- Use generic localized `media_viewer_action_save` for video and the existing
  `media_viewer_action_picture_in_picture`; never reuse photo-only `Save image`.
- TC-310-03 must first swipe to the second video, open its menu, and select the
  row. Before opening, `media_action_picture_in_picture` must be absent; after
  opening, require exactly one keyed `PopupMenuItem` descendant and no keyed
  `IconButton`. Assert only the second owner/attachment starts and the first
  adapter is not disposed by the current action. Restore remains owned by the
  unchanged standard-PiP sentinel in TC-310-06.
- Update only existing tests that reach a received video action directly:
  open `media_action_more` before Share/Info/PiP. Do not weaken their existing
  message/attachment/current-owner/effect assertions.

## Implementation Steps

1. Snapshot `git status --short` and preserve all overlapping Plan-303-309
   work. Add TC-310-01/02/03 before production edits and record their causal
   assertion/compile REDs; run TC-310-04/06 baseline sentinels GREEN.
2. Add `compactVideoOverflow` to `MediaViewerActionPresentation` without
   changing the `standardToolbar` default or `compactImageOverlay` semantics.
3. In `_buildDirectViewerItem`, select the new value only for
   `message.isIncoming && decision.isOrdinary && kind == video`; retain the
   existing image predicate and standard fallback.
4. In `FullScreenTypedMediaViewer`, add a video-only popup branch. Reuse the
   existing compact More visual and existing media icon/tooltip helpers; use a
   small private video-popup selection mapping only where necessary to
   distinguish PiP from `MediaViewerAction`. Route media values through
   `_dispatch` and PiP through `_requestPictureInPicture` exactly once.
5. Suppress standalone PiP/media AppBar actions and photo bottom controls only
   for `compactVideoOverflow`. Leave image result-chip positioning and all
   standard/private branches unchanged.
6. Update exact received-video test interactions, run focused/complete GREEN,
   representative action-census/PiP mutations, preservation gates, the curated
   1:1 lane, analyzer and diff hygiene. Refresh the app-owned graph once after
   the coherent code change.

## Risks And Blind Spots

- An incomplete list could silently drop Forward, Delete, or PiP ->
  TC-310-01/02/03 bind the real direct capability set and exact six/seven-row
  popup census.
- A visually correct row could dispatch the wrong action or stale page ->
  TC-310-02/03/05 assert exact enum/current attachment/current owner and effect.
- Refactoring the photo popup could regress its bottom layout or `Save image`
  label -> TC-310-04 keeps the existing branch as a distinct sentinel.
- PiP visibility and start readiness are asynchronous -> TC-310-03 uses the
  established gateway/playback fixture and waits for authorization before
  opening the menu; the production request method reauthorizes again.
- A shared MIME inference could leak into outgoing/group/library/private
  viewers -> TC-310-01/04/06 require explicit caller selection and defaults.
- Lifecycle / derived-state durability: action presentation is immutable per
  item and recomputed on every page; PiP visibility already refreshes on mount,
  widget update, page change, and playback change. TC-310-02/03 cover page and
  async visibility transitions.
- Sibling-surface consistency: photos intentionally retain their split layout;
  default/group/library/private siblings intentionally remain standard or
  minimized, locked by TC-310-04/06.
- Destructive-action side effects: Delete remains whole-message Delete for me;
  TC-310-02 proves it remains in the video menu and the existing wired Delete
  sentinel owns close/confirmation/cleanup handoff.
- Invariant re-verification under new transitions: `_dispatch` and
  `_requestPictureInPicture` both capture/revalidate the current item at action
  time; TC-310-02/03 swipe before selection.

## Gate Cadence

- Per-plan closure: focused causal tests, complete shared-viewer and direct
  actions files, exact photo/default/Shared-Media/boundary/Forward/Delete/PiP
  sentinels, and the affected curated `1to1` lane. No core/feature/performance,
  group, simulator, device, relay, native, or migration sweep is justified for
  this default-off presentation-only change.
- Do not run full `host-all` for this individual plan. Run
  `./scripts/run_host_test_gates.sh host-all` once after the 1:1 media
  presentation batch (Plans 303-310) is complete, and once at final
  rollout/release closure.
- Shared tests outside feature/core globs run by exact command during this plan;
  list mode verifies later `host-all` discovery.

## Acceptance Gates

```bash
# Dirty-tree snapshot; preserve unrelated and overlapping work.
git status --short

# First causal RED before production edits; expect non-zero because received
# video currently selects standardToolbar and has no three-dot menu.
flutter test test/features/conversation/presentation/screens/conversation_received_media_actions_test.dart \
  --plain-name 'received keep-in-chat video selects its all-action overflow without widening sibling media'

# Shared causal REDs; expect non-zero for the absent enum/menu and standalone PiP.
flutter test test/shared/widgets/media/full_screen_typed_media_viewer_test.dart \
  --plain-name 'compact video overflow lists and dispatches every authorized media action'
flutter test test/shared/widgets/media/full_screen_typed_media_viewer_test.dart \
  --plain-name 'compact video overflow nests conditional PiP and starts exact current owner'

# Focused and complete GREEN; expect exit 0 and zero failed tests.
flutter test test/shared/widgets/media/full_screen_typed_media_viewer_test.dart
flutter test test/features/conversation/presentation/screens/conversation_received_media_actions_test.dart

# Exact photo/default/PiP/library/boundary preservation; expect exit 0.
flutter test test/shared/widgets/media/full_screen_typed_media_viewer_test.dart \
  --plain-name 'compact image layout places overflow forward and delete on safe corners'
flutter test test/shared/widgets/media/full_screen_typed_media_viewer_test.dart \
  --plain-name 'compact overflow lists localized image actions in order and targets the current item'
flutter test test/shared/widgets/media/full_screen_typed_media_viewer_test.dart \
  --plain-name 'actions always target the currently visible typed item and owner'
flutter test test/shared/widgets/media/full_screen_typed_media_viewer_test.dart \
  --plain-name 'supported Android PiP control targets and restores the exact current video owner'
flutter test test/features/conversation/presentation/screens/conversation_shared_media_viewer_test.dart \
  --plain-name 'in-viewer current item actions execute across parent messages'
flutter test test/shared/widgets/media/media_viewer_boundary_test.dart \
  --plain-name 'viewer remains callback-only transport-free and diagnostics are redacted'

# Exact direct video access-path preservation; expect the popup route to retain
# page-current Share/Info and conditional PiP composition.
flutter test test/features/conversation/presentation/screens/conversation_received_media_actions_test.dart \
  --plain-name 'same message bubble and viewer parity follows selected attachment'
flutter test test/features/conversation/presentation/screens/conversation_received_media_actions_test.dart \
  --plain-name 'info follows selected attachment within one message without transport reads'
flutter test test/features/conversation/presentation/screens/conversation_received_media_actions_test.dart \
  --plain-name 'direct received-video route forwards exact PiP composition to the typed viewer'

# Exact Forward/Delete effects remain on their existing direct callback seams.
flutter test test/features/conversation/presentation/screens/conversation_received_media_forward_test.dart \
  --plain-name 'compact viewer bottom forward launches existing picker with current attachment'
flutter test test/features/conversation/presentation/screens/conversation_wired_test.dart \
  --plain-name 'viewer delete invokes existing direct whole message cleanup'

# Registration discovery only; expect exact targets selected.
./scripts/run_host_test_gates.sh 1to1 --list \
  --only test/features/conversation/presentation/screens/conversation_received_media_actions_test.dart
./scripts/run_host_test_gates.sh host-all --list \
  --only test/shared/widgets/media/full_screen_typed_media_viewer_test.dart

# Affected curated lane; expect exit 0 and zero failed Flutter/Go cases.
./scripts/run_test_gates.sh 1to1

# App-owned graph and hygiene; expect successful refresh, no new analyzer
# issues attributable to this plan, and no whitespace errors.
./graphify-arch/refresh_arch_graph.sh --incremental
flutter analyze
git diff --check
```

## Execution Interpretation And Done Criteria

- Expected RED: TC-310-01 fails because the direct video is standard;
  TC-310-02/03 fail because `compactVideoOverflow` and its unified menu are
  absent and PiP is standalone.
- Green sentinels: current photo layout/icons, standard default/current-item
  dispatch, direct Shared Media, callback-only boundary, video metadata/
  playback/resume, Forward, Delete, and existing PiP owner behavior.
- Pre-existing dirty tree / known failure: overlapping Plans 303-309 and their
  source/tests, index, Graphify output, generated l10n, native/evidence, and
  deployment result are baseline and must not be reverted or absorbed. The two
  planning probes passed; no TC-310 test has yet been written or run.
- Environment blocker: none; closure is host-only. No native PiP behavior is
  changed or newly claimed.
- Scope drift: any request to change photo layout, Shared Media/group/private
  video chrome, action authorization/effects, PiP policy/native behavior, or
  persistence/transport requires replanning.

- [x] Every video action available before consolidation is present exactly
      once in the popup and remains reachable.
- [x] Causal RED, focused GREEN, and representative media-census/PiP mutation
      re-reds are recorded.
- [x] Photo/default/library/private/boundary and real direct-effect sentinels pass.
- [x] Existing harness registration is verified; no unnecessary script edit lands.
- [x] The curated `1to1` lane, analyzer, Graphify refresh, and diff hygiene pass.
- [x] Scope Contract And Guard and dirty-tree preservation are respected.

## Handoff

- First causal RED command:
  `flutter test test/features/conversation/presentation/screens/conversation_received_media_actions_test.dart --plain-name 'received keep-in-chat video selects its all-action overflow without widening sibling media'`.
- Preservation command:
  `flutter test test/shared/widgets/media/full_screen_typed_media_viewer_test.dart --plain-name 'compact overflow lists localized image actions in order and targets the current item'`.
- Manual registration: none; direct actions is already in both 1:1 arrays and
  shared widget tests are `host-all` glob-discovered.
- Migration: none.
- Boundary closure: host-only widget/application proof; existing native PiP
  boundary is untouched.
- Unresolved evidence: none.

## Reviewer Findings

- Verdict: `ready`; plan classification `implementation-ready`; core bet
  `confirmed`; disposition `execute`. The initial `plan-fixes-required`
  findings below were patched in place and the five lenses were rerun.
- L1 evidence/classification: `clear`; current source confirms one direct
  selector, six conditional direct media capabilities, and conditional PiP as
  the only additional video AppBar action.
- L2 causality: `clear` after replacing the vague TC-310-05 proof reference,
  labeling its video access-path assertions causal while keeping Forward/Delete
  as GREEN sentinels, and requiring PiP absence-before/popup-local-after-open.
- L3 bypass/scope: `clear`; source search finds one production
  `actionPresentation:` selector and all other `MediaViewerItem` callers consume
  the default. No alternate in-chat typed-video builder bypasses the seam.
- L4 gates: `clear` after adding the omitted standard-presentation command and
  exact direct test names. Review list mode selected direct actions as 1:1 item
  82 and the shared viewer as host-all item 1239; full `host-all` remains owned
  by the named presentation wave/final closure.
- L5 boundary/reversibility: `N/A` for the change itself—host widget
  composition only. TC-310-03 now claims start, not restore; the untouched
  standard-PiP sentinel owns restore and native policy remains out of scope.
- Blind-spot sweep: B2/B3/B4/B7/B9 hits were checked and are clear after the
  deltas above; B1/B5/B6/B8/B10 are N/A because there is no data, schema,
  persistence, cross-version, or new OS-boundary change.
- User decisions required: none.

## Execution Progress

| Time | Phase | Files | Last command/result | Current evidence | Decision/blocker | Next |
|---|---|---|---|---|---|---|
| 2026-07-31 19:24 CEST | causal RED | direct/shared viewer tests | Three exact new tests exited non-zero: direct video remained `standardToolbar`; shared video enum/menu was absent; PiP remained standalone. | TC-310-01/02/03 failed for the requested missing behavior before production edits. | none | implement the reviewed seam |
| 2026-07-31 19:28 CEST | focused GREEN | `media_viewer_item.dart`, `full_screen_typed_media_viewer.dart`, `conversation_screen.dart`, and two focused test files | New exact tests green; complete shared viewer `20/20` and complete direct received-media actions `19/19` green. | Received ordinary video alone selects `compactVideoOverflow`; the menu has Save/Share/Info/Reply/Forward/Delete plus conditional PiP and dispatches the current item. | none | mutation and preservation proof |
| 2026-07-31 19:31 CEST | mutation / preservation | focused tests plus existing callback sentinels | Removing Delete, leaking standalone PiP, and reverting the route selector each made its causal test red; all edits restored. Exact Shared Media, boundary, Forward, and Delete sentinels then passed. | Tests discriminate incomplete census, duplicate PiP chrome, route bypass, and preserve existing effects/boundary. | none | curated lane |
| 2026-07-31 19:34 CEST | affected curated lane | registered 1:1 Flutter/Go gates | `./scripts/run_test_gates.sh 1to1` exited `0`: 2,525 Flutter tests passed; relay notification/toolchain Go gates passed. | Required affected lane is green; full `host-all` remains at wave/final cadence. | none | static and graph closure |
| 2026-07-31 19:35 CEST | closure | changed production/tests, plan/index, Graphify architecture outputs | `flutter analyze` no issues; format check `0 changed`; `git diff --check` clean; affected-context query succeeded; incremental Graphify refresh processed 5 changed code files and refreshed the TDD overlay. | All reviewed done criteria are satisfied with no migration, native/device, l10n, or gate-script change. | none | complete |
