# 307 - 1:1 Keep-in-chat Received Image Viewer Action Layout

Status: implemented / host-green
Type: Modification
Spec: free-text intent with supplied Images #1-#3 — replace the received
`Keep in chat` static-image viewer's crowded top action row with a circular
overflow menu plus bottom-corner Forward and Delete controls
Classification: implemented
Closure tier: host

## Planning Progress

| Time | Role | Files inspected | Decision/blocker | Next action |
|---|---|---|---|---|
| 2026-07-31 14:18 CEST | Evidence Collector | `$tdd-plan` instructions and required tier/template/sufficiency references; `graphify-arch/tdd_context.py` | Classified the free-text request as Modification 307 and selected Graphify's anchored direct-media viewer seam. | Verify current source, callers, tests, and gates. |
| 2026-07-31 14:29 CEST | Evidence Collector | `media_viewer_item.dart`; `full_screen_typed_media_viewer.dart`; `conversation_screen.dart`; `direct_shared_media_library_screen.dart`; received-media action/forward/wired/shared-viewer tests; gate scripts; l10n ARBs | Confirmed that the shared viewer renders every authorized action in `AppBar.actions`, while the direct caller already owns the direction/kind/policy discriminator and every side effect is callback-only. Three focused baseline probes passed. | Build a host-widget contract around an additive, default-standard presentation input. |
| 2026-07-31 14:34 CEST | Planner | all seven production `MediaViewerItem` caller files; Plan 230/231/306 contracts; l10n integrity and shared-viewer boundary tests | Scope compact chrome only to incoming ordinary static images opened from the conversation. Preserve action authority and side effects, default layouts, whole-message Delete, and transport-free ownership. No unresolved evidence blocks execution. | Write causal tests before production edits, then implement and run proportional gates. |

## Problem And Evidence

- Behavior to improve: when the receiver opens one or multiple ordinary
  (`Keep in chat`) static images from a 1:1 conversation, keep Back and the
  current/total counter, replace the individual top action icons with one
  circular horizontal-ellipsis control, put Save image / Share / Info / Reply
  in its list, put Forward at the bottom end (right in LTR), and put Delete at
  the bottom start (left in LTR).
- Impact: the current six-action `AppBar` is visually crowded and does not match
  the supplied compact reference, especially beside the `1 / N` counter.
- Confirmed current gap: `_actionOrder` at
  `lib/shared/widgets/media/full_screen_typed_media_viewer.dart:109` contains
  Reply, Save, Share, Forward, Info, Delete and sibling actions;
  `FullScreenTypedMediaViewer.build` puts every allowed action into
  `AppBar.actions` at `:400-442`; `_buildActions` creates one top
  `IconButton` per capability at `:477-496`. `MediaViewerItem` has no action
  presentation/layout input at
  `lib/shared/widgets/media/media_viewer_item.dart:114-170`.
- Confirmed current mechanism: `_buildDirectViewerItem` already derives the
  exact current `MediaViewerKind`, evaluates the current ordinary/private
  decision, and grants Save, Share, Reply, Info, Forward, and Delete
  independently at
  `lib/features/conversation/presentation/screens/conversation_screen.dart:2064-2100`.
  It also has `message.isIncoming` and constructs every page in the tapped
  message at `:2022-2059`, so the presentation discriminator belongs there,
  not in path/MIME inference inside the shared viewer.
- Confirmed side-effect boundary: `_dispatch` captures and rechecks the exact
  current item before awaiting one callback at
  `full_screen_typed_media_viewer.dart:349-369`; the direct callback switch at
  `conversation_screen.dart:2147-2207` owns the existing Save destination
  chooser, native Share, quote Reply, persisted Info, whole-message Delete,
  and internal Forward launcher. Moving controls therefore requires no
  controller/service/transport change.
- Confirmed action semantics: the Delete branch closes the viewer and invokes
  `onDeleteMediaMessage(item.messageId)` at `conversation_screen.dart:2180-2191`.
  `conversation_wired_test.dart:11459-11579` proves that this closes the viewer,
  opens the existing media-labeled Delete-for-Me confirmation, and hands the
  exact owning message ID plus direct media repository to the existing local
  delete seam. Cleanup itself is independently covered by
  `delete_message_use_case_test.dart:536-590`, where `deleteMessageForMe`
  removes the direct attachment rows and app-owned files. This plan relocates
  that control; it does not redefine Delete as attachment-only removal.
- Existing coverage:
  `full_screen_typed_media_viewer_test.dart::actions always target the currently visible typed item and owner`
  proves page-current identity and owner dispatch;
  `::capabilities and ownership fail closed and action outcomes settle once`
  proves authorization/availability/in-flight fencing;
  `conversation_received_media_actions_test.dart` proves Save, Share, Info,
  Reply, metadata, and ordinary/private routing;
  `conversation_received_media_forward_test.dart` proves the existing Forward
  picker; and the two wired tests at `conversation_wired_test.dart:11459` and
  `:11582` prove real presentation-to-controller Delete/egress wiring.
- Planning probes actually run on 2026-07-31:
  the shared current-item action test, the direct
  `same message bubble and viewer parity follows selected attachment` test,
  and `media_viewer_boundary_test.dart::viewer remains callback-only transport-free and diagnostics are redacted`
  each exited `0` with one passed test. These confirm the present callback and
  top-icon mechanism; they are not evidence for the unimplemented layout.
- Missing coverage: no test selects a compact per-item layout, opens an exact
  four-item overflow list, checks the requested corner geometry/safe areas,
  distinguishes static received images from outgoing/GIF/video/library/group
  pages, verifies compact controls after a page swipe, or prevents the existing
  result chip from covering a new bottom control or legacy top actions from
  remaining visible beside the overflow control.
- Refuted findings:
  - `direct_received_media_action_sheet.dart` is not the crowded toolbar. It
    contains only the existing Save destination and Info bottom sheets at
    `:17-108` and `:114-337`; changing it cannot relocate viewer actions.
  - The controller/egress/forward/delete implementations do not need redesign.
    The shared viewer is already callback-only and the three planning probes
    confirm exact identity dispatch.
  - A global shared-viewer rewrite is unsafe. Static images also enter through
    direct Shared Media, group/announcement conversations and libraries, and
    private routes; all seven production `MediaViewerItem` caller files rely on
    today's default layout or stronger `privacyMinimized` behavior.
  - The new Delete icon must not delete only the visible attachment. Current
    source and the wired sentinel prove whole-message Delete-for-Me semantics.
- Unresolved findings: N/A — the requested surface, role, media-policy/kind
  discriminator, visual hierarchy, callback seams, test tier, and gate
  ownership are source-confirmed. Exact bitmap pixel reproduction is not
  claimed; the reference is translated into the concrete geometry below.
- Affected production, test, localization, and gate files:
  `lib/shared/widgets/media/media_viewer_item.dart`,
  `lib/shared/widgets/media/full_screen_typed_media_viewer.dart`,
  `lib/features/conversation/presentation/screens/conversation_screen.dart`,
  `lib/l10n/app_en.arb`, `app_de.arb`, `app_ar.arb`, generated
  `app_localizations*.dart`,
  `test/shared/widgets/media/full_screen_typed_media_viewer_test.dart`,
  `test/features/conversation/presentation/screens/conversation_received_media_actions_test.dart`,
  `conversation_received_media_forward_test.dart`, and the two exact affected
  blocks in `conversation_wired_test.dart`. The direct Shared Media, private,
  boundary, and l10n tests are preservation sentinels. No gate-script edit is
  planned.

## Graph Grounding Snapshot

- Graph fingerprint / freshness:
  `a59270646d5f859b`; `stale:ios/Flutter/flutter_export_environment.sh`. The
  stale generated iOS export file is unrelated to this host presentation seam
  and did not block current-source verification.
- Query / profile:
  `python3 graphify-arch/tdd_context.py query "1:1 chat Keep in chat received image fullscreen media viewer current top actions image count reply download save share forward info delete and desired overflow menu plus bottom forward/delete controls" --profile tdd --budget 700`
  returned `confidence=broad`; the permitted exact-anchor refinement was
  `python3 graphify-arch/tdd_context.py query "direct_received_media_action_sheet.dart DirectReceivedMediaActionSheet ReceivedMediaActionController received image viewer action toolbar overlay save share info reply forward delete" --profile tdd --budget 700`
  and returned `confidence=anchored`.
- Anchors:
  `direct_received_media_action_sheet.dart` ->
  `lib/features/conversation/presentation/widgets/direct_received_media_action_sheet.dart`;
  `receivedMediaActionController` ->
  `lib/features/conversation/presentation/screens/conversation_wired.dart:418`;
  typed viewer caller ->
  `lib/features/conversation/presentation/screens/conversation_screen.dart:2050`;
  shared viewer ->
  `lib/shared/widgets/media/full_screen_typed_media_viewer.dart:35`.
- Surfaced proof/gate files: `conversation_wired.dart`,
  `conversation_screen.dart`, `direct_received_media_action_sheet.dart`,
  `direct_shared_media_library_screen.dart`,
  `full_screen_typed_media_viewer.dart`, `media_viewer_item.dart`, and the
  direct policy/egress files. Source verification then found the focused
  shared/direct/forward/wired tests and both 1:1 gate arrays.
- Graph gaps requiring source search: the compact result did not surface
  `_actionOrder`, `_buildActions`, the current direct test selectors, the
  Forward UI test, the wired whole-message Delete sentinel, l10n integrity, or
  all seven `MediaViewerItem` callers. Each was verified in current source.
- Reuse rule: anchors may be handed to review/execution; all conclusions still
  require current-source or command evidence.

## Scope Contract And Guard

In scope:

- Add a presentation-only enum such as
  `MediaViewerActionPresentation.standardToolbar` /
  `compactImageOverlay` to `MediaViewerItem`, defaulting to
  `standardToolbar`. The shared viewer must honor the supplied value without
  inferring direction, lane, policy, or authorization.
- In `_buildDirectViewerItem`, select `compactImageOverlay` only when the
  current parent is incoming, the revalidated decision is ordinary
  (`Keep in chat`), and `kind == MediaViewerKind.image`. Every static image in
  the same message receives the policy so `1 / N` page changes stay compact.
- Compact chrome uses one 48dp accessible tap target around a centered 36dp
  `0xCC1C1C1E` circular visual with a subtle light border and a 20dp white icon.
  The top-end control uses `Icons.more_horiz_rounded`; bottom-end Forward reuses
  `Icons.forward_rounded`; bottom-start Delete reuses
  `Icons.delete_outline_rounded`. Controls sit inside `SafeArea` with at least
  12dp edge spacing. End/start means right/left in LTR and mirrors with the app
  in RTL.
- The overflow list contains only authorized actions, in the exact order
  Save image, Share, Info, Reply. Add localized `media_viewer_action_save_image`
  and `media_viewer_more_actions` strings for en/de/ar; reuse existing localized
  Share/Info/Reply/Forward/Delete strings. Save image continues into the
  existing Photos/Files destination chooser.
- Forward and Delete are absent from the overflow list and appear only as
  authorized bottom controls. If a callback/capability is unavailable, its
  menu/control is absent; if an authorized item is ownerless, unavailable, or
  an action is in flight, the rendered compact control remains fail-closed and
  cannot double-dispatch.
- Position the action-result chip above the compact bottom controls so Share,
  Save, or Forward outcome feedback cannot cover either requested control.
  Standard-layout result positioning remains unchanged.

Must preserve:

- Back, `1 / N`, initial index, swipe direction, current-item identity, image
  zoom/rendering, Plan-306 caption/metadata policy, diagnostics, and action
  result truthfulness -> `TC-307-01`, `TC-307-02`, `TC-307-04`, `TC-307-09`,
  and `TC-307-12`.
- Save/Share current-row revalidation and native egress, persisted Info, quote
  Reply, internal Forward picker, and whole-message Delete-for-Me confirmation
  and handoff -> `TC-307-05` through `TC-307-08`. The untouched cleanup use case
  remains covered by
  `delete_message_use_case_test.dart::deleteMessageForMe hard-deletes the row after local cleanup`.
- Unauthorized actions remain absent; authorized-but-ineligible and in-flight
  actions stay disabled and dispatch zero extra callbacks -> `TC-307-03`.
- Outgoing static images, incoming GIF/video, direct Shared Media, group and
  announcement viewers/libraries, and every default `MediaViewerItem` keep the
  existing top-toolbar layout -> `TC-307-04`, `TC-307-09`, and `TC-307-10`.
- Private `privacyMinimized` viewers suppress the new compact actions/bottom
  chrome through the explicit compact fixture in `TC-307-03`; their existing
  metadata/resume minimization remains locked by `TC-307-11`. Private route
  policy and PiP authorization are otherwise untouched.
- The shared viewer remains transport/repository/controller-free and logs no
  path, caption, sender, or full attachment ID -> `TC-307-12`.
- Preserve the pre-existing dirty worktree, especially Plan-303-306 changes in
  the same viewer/item/conversation tests, `onBackRequested`, metadata policy,
  terminal receipt/bubble work, and unrelated `conversation_wired_test.dart`
  edits.

Hard `Do not`:

- Do not infer compact layout from MIME/path, `owner == direct`, sender label,
  or capabilities inside the shared viewer; only the lane owner selects it.
- Do not change action authorization, current-row revalidation, callback
  result types, Save destinations, native share, Forward draft/delivery,
  Delete scope/confirmation, or quote/Info behavior.
- Do not apply compact chrome to direct Shared Media, outgoing, GIF/video,
  group/announcement, private, protected, view-once, disappearing, unsupported,
  or legacy path-only routes.
- Do not hide Back/page count, alter Plan-306 metadata/caption behavior, put
  Forward/Delete in the overflow list, or leave duplicate top icons visible.
- Do not change message/attachment persistence, DB schema, wire payloads,
  crypto, relay/Go, native platform code, media bytes, playback/PiP, or send
  policy.
- Do not overwrite, revert, or absorb unrelated dirty-tree work.

Deferred / accepted difference:

- Direct Shared Media intentionally retains its current toolbar because the
  request names the receiver's in-chat viewer. A future product request owns
  compact library chrome; `TC-307-10` locks today's accepted difference.
- Incoming GIF/video and outgoing images retain the standard layout. This plan
  implements the supplied static received-image reference, not a global media
  viewer redesign.
- RTL mirrors start/end positions according to Flutter navigation conventions;
  the supplied LTR placement remains top-right, Forward bottom-right, Delete
  bottom-left.
- The existing Delete action remains whole-message Delete for me, including all
  attachments. Attachment-only deletion requires a separately designed data
  and UX contract.
- A reporting-device visual sanity pass is optional confidence, not closure;
  deterministic widget geometry/interaction is the causal boundary and no OS
  service is involved.

Dependencies:

- Builds on Plan 230's typed callback-only viewer, Plan 231's direct received
  action policy/side effects, Plan 232's Forward flow, and Plan 306's current
  static-image metadata presentation.
- The current worktree contains the implemented-but-uncommitted Plan-306 seam
  and other Plan-303-305 edits. Execution may proceed on this baseline but must
  stop and rebase the contract if those edits disappear or change
  `MediaViewerItem`, `FullScreenTypedMediaViewer`, `_buildDirectViewerItem`, or
  the named test interactions.

## Test Contract

| Case | Behavior | Named test/proof | Tier / fixture | HEAD -> GREEN | Mutation | Gate / registration |
|---|---|---|---|---|---|---|
| TC-307-01 | A compact multi-image page keeps Back and `1 / N`, replaces every legacy top action with one circular ellipsis at top-end, shows Forward at bottom-end and Delete at bottom-start, respects safe insets/48dp hit targets, and keeps the result chip clear of both bottom controls in LTR and RTL. | `test/shared/widgets/media/full_screen_typed_media_viewer_test.dart::compact image layout places overflow forward and delete on safe corners` | Widget host / two compact image items with all six capabilities, 320x568 MediaQuery with top/bottom padding, en + ar, callback recorder | HEAD assertion RED because no overflow exists and Forward/Delete are top AppBar icons -> only the ellipsis remains in the AppBar; reference icons, circle shape/size, relative rectangles, counter, mirroring, safe bounds, and non-overlap all pass | Swap the Forward/Delete `AlignmentDirectional` anchors, leave any legacy action in the AppBar, or leave the result chip at the old compact bottom-end position -> TC-307-01 red | `flutter test test/shared/widgets/media/full_screen_typed_media_viewer_test.dart --plain-name 'compact image layout places overflow forward and delete on safe corners'`; AUTO (`host-all` glob), executed directly per plan |
| TC-307-02 | Opening ellipsis lists exactly Save image, Share, Info, Reply in that order, omits Forward/Delete, exposes localized menu/tooltip semantics, and dispatches the exact visible item after a swipe. | `test/shared/widgets/media/full_screen_typed_media_viewer_test.dart::compact overflow lists localized image actions in order and targets the current item` | Widget host / two compact images, en/de/ar delegates, semantics, callback recorder, distinct stable IDs | HEAD assertion RED because the ellipsis/list is absent -> four exact labels/order in every locale, zero bottom actions in the list, and page-2 selection records only page 2 | Build the compact list from global `_actionOrder` instead of the exact four-item order -> TC-307-02 red | `flutter test test/shared/widgets/media/full_screen_typed_media_viewer_test.dart --plain-name 'compact overflow lists localized image actions in order and targets the current item'`; AUTO (`host-all` glob), executed directly; `flutter test test/l10n/l10n_integrity_test.dart`; AUTO (`host-all` glob), executed directly |
| TC-307-03 | Compact actions preserve capability absence, owner/availability disablement, one in-flight dispatch across both the menu and bottom controls, and complete `privacyMinimized` suppression. | `test/shared/widgets/media/full_screen_typed_media_viewer_test.dart::compact actions remain capability gated and single dispatch while pending` | Widget host / allowed-subset, ownerless, unavailable, completer-backed items with tap counter, and an explicitly compact image with all six capabilities under `privacyMinimized: true` | HEAD compile RED because the compact presentation input does not exist -> unauthorized entries/controls are absent, authorized-ineligible controls are disabled, pending dispatch disables all compact controls, a second tap records zero calls, and the private fixture renders no ellipsis/menu/bottom actions | Remove `capabilities.allows(action)` from either compact builder or render compact chrome before the `privacyMinimized` guard -> TC-307-03 red | `flutter test test/shared/widgets/media/full_screen_typed_media_viewer_test.dart --plain-name 'compact actions remain capability gated and single dispatch while pending'`; AUTO (`host-all` glob), executed directly |
| TC-307-04 | The direct conversation selects compact presentation for every incoming ordinary static image in a one/multi-image message, while outgoing images and incoming GIF/video remain standard; page count and current layout update together. | `test/features/conversation/presentation/screens/conversation_received_media_actions_test.dart::incoming keep-in-chat images select compact actions while sibling media stays standard` | Widget host / synchronous temp files; incoming two-image + GIF + video pages, separate outgoing image, complete fake callbacks | HEAD assertion RED because the first received image exposes individual top icons and no ellipsis/bottom controls -> only incoming static-image items carry compact presentation; `1 / N` and swipes select the matching layout | Select compact on `kind == image` without the incoming/ordinary predicate -> the outgoing/default assertions in TC-307-04 red | `flutter test test/features/conversation/presentation/screens/conversation_received_media_actions_test.dart --plain-name 'incoming keep-in-chat images select compact actions while sibling media stays standard'`; existing `ONE_TO_ONE_TESTS` + `ONE_TO_ONE_HOST_TESTS`, AUTO (`feature-host-all` glob); no registration edit |
| TC-307-05 | From the real conversation route, compact Save image, Share, Info, and Reply retain their exact current attachment/message targets and established destination/sheet/quote effects. | `test/features/conversation/presentation/screens/conversation_received_media_actions_test.dart::compact image overflow preserves save share info and reply routes` | Widget host / two received image attachments, temp files, egress/info/quote recorders, existing Save destination and Info sheets | HEAD assertion RED because overflow is absent -> Save opens Photos/Files then targets the selected attachment, Share and Info target it once, Reply closes the viewer and quotes its owning message once | Map one popup value to the wrong `MediaViewerAction` (for example Info -> Share) -> TC-307-05 red | `flutter test test/features/conversation/presentation/screens/conversation_received_media_actions_test.dart --plain-name 'compact image overflow preserves save share info and reply routes'`; existing 1:1 arrays + AUTO (`feature-host-all` glob); no registration edit |
| TC-307-06 | After a swipe to the second compact image, bottom-end Forward launches the existing internal picker with that exact current attachment ID and keeps editable caption behavior. | `test/features/conversation/presentation/screens/conversation_received_media_forward_test.dart::compact viewer bottom forward launches existing picker with current attachment` | Widget host / two received images with distinct files, real `BuildReceivedMediaForward` over fake owner-aware repository, navigator/picker and caption controller | HEAD geometry RED because the keyed Forward control is in the AppBar -> the page-2 bottom-end control launches the picker once with the second `currentAttachmentId`, only the second source preview, and the editable parent caption | Dispatch `messageId` without `currentAttachmentId` or capture the initial page -> TC-307-06 red | `flutter test test/features/conversation/presentation/screens/conversation_received_media_forward_test.dart --plain-name 'compact viewer bottom forward launches existing picker with current attachment'`; existing `ONE_TO_ONE_TESTS` + `ONE_TO_ONE_HOST_TESTS`, AUTO (`feature-host-all` glob); no registration edit |
| TC-307-07 | Viewer Share still reaches the current-row `ReceivedMediaActionController` once with zero delivery calls after moving behind overflow. | `test/features/conversation/presentation/screens/conversation_wired_test.dart::bubble and viewer media egress use controller with zero delivery calls` | Widget host / existing wired fake repositories, real action controller, recording egress service and throwing delivery spies; interaction updated to open ellipsis before Share | GREEN on current HEAD before interaction update; the updated interaction is assertion RED because ellipsis is absent -> controller still receives the same exact attachment/destination once with zero delivery | Bypass `_dispatch(MediaViewerAction.share)` from the popup or call controller twice -> TC-307-07 red | `flutter test test/features/conversation/presentation/screens/conversation_wired_test.dart --plain-name 'bubble and viewer media egress use controller with zero delivery calls'`; existing 1:1 arrays + AUTO (`feature-host-all` glob); no registration edit |
| TC-307-08 | Bottom-start Delete preserves viewer-close, one media-labeled confirmation, and exact owning-message handoff to the existing whole-message Delete-for-Me seam. | `test/features/conversation/presentation/screens/conversation_wired_test.dart::viewer delete invokes existing direct whole message cleanup` | `GREEN sentinel` / existing wired fake message/media repositories and recording Delete-for-Me function | GREEN on HEAD -> the same keyed action remains GREEN after relocation, closes the viewer, shows one local confirmation, calls the recording seam once with the owning message/direct repository, and removes the owning message row | Wire the bottom Delete control to anything other than `_dispatch(MediaViewerAction.delete)` -> TC-307-08 red | `flutter test test/features/conversation/presentation/screens/conversation_wired_test.dart --plain-name 'viewer delete invokes existing direct whole message cleanup'`; existing 1:1 arrays + AUTO (`feature-host-all` glob); no registration edit |
| TC-307-09 | Standard toolbar remains the default, retains individual authorized top actions, and dispatches the exact current direct/group item after swiping. | `test/shared/widgets/media/full_screen_typed_media_viewer_test.dart::actions always target the currently visible typed item and owner` | `GREEN sentinel` / existing direct + group items, strengthened with standard-presentation/no-overflow and top-geometry assertions | GREEN on HEAD -> remains GREEN with the additive default and unchanged `_actionOrder` path | Default `MediaViewerActionPresentation` to compact or infer compact from direct/group owner -> TC-307-09 red | `flutter test test/shared/widgets/media/full_screen_typed_media_viewer_test.dart --plain-name 'actions always target the currently visible typed item and owner'`; AUTO (`host-all` glob), executed directly |
| TC-307-10 | Direct Shared Media static-image pages retain their standard bookmark/save/share/delete toolbar and cross-parent current-item actions. | `test/features/conversation/presentation/screens/conversation_shared_media_viewer_test.dart::in-viewer current item actions execute across parent messages` | `GREEN sentinel` / strict direct library repository with cross-parent entries and action recorders, strengthened with no-compact-overflow assertion | GREEN on HEAD -> remains GREEN because `_viewerItem` consumes the standard default | Set compact in direct Shared Media or infer it from direct owner + image inside the viewer -> TC-307-10 red | `flutter test test/features/conversation/presentation/screens/conversation_shared_media_viewer_test.dart --plain-name 'in-viewer current item actions execute across parent messages'`; existing 1:1 arrays + AUTO (`feature-host-all` glob); no registration edit |
| TC-307-11 | Private `privacyMinimized` routes retain existing metadata/resume minimization and ordinary pages stay unchanged; TC-307-03 supplies the explicit compact-capable privacy guard. | `test/shared/widgets/media/full_screen_typed_media_viewer_test.dart::private presentation suppresses metadata resume actions and PiP without changing ordinary pages` | `GREEN sentinel` / existing private video and ordinary page fixture | GREEN on HEAD -> remains GREEN after compact chrome lands | Remove the existing `privacyMinimized` metadata or resume guard -> TC-307-11 red | `flutter test test/shared/widgets/media/full_screen_typed_media_viewer_test.dart --plain-name 'private presentation suppresses metadata resume actions and PiP without changing ordinary pages'`; AUTO (`host-all` glob), executed directly |
| TC-307-12 | The viewer remains callback-only/transport-free and action diagnostics stay redacted on both the standard toolbar and the new menu path. | `test/shared/widgets/media/media_viewer_boundary_test.dart::viewer remains callback-only transport-free and diagnostics are redacted` | `GREEN sentinel` plus compact extension / source import allowlist, event sink, secret path/caption/sender fixture; retain the standard dispatch assertion and add an explicitly compact item whose ellipsis is opened before Save | Existing standard boundary assertions GREEN on HEAD; the compact interaction is RED until the presentation/menu exists -> both paths emit only the same redacted action event with no controller/repository/transport import | Implement Save/Share/Forward/Delete in the widget or log `item.toString()` from the new menu -> TC-307-12 red | `flutter test test/shared/widgets/media/media_viewer_boundary_test.dart --plain-name 'viewer remains callback-only transport-free and diagnostics are redacted'`; AUTO (`host-all` glob), executed directly |

### Test Notes

- Use stable keys `media_action_more`, `media_action_save`,
  `media_action_share`, `media_action_info`, `media_action_reply`,
  `media_action_forward`, and `media_action_delete`. The four menu action keys
  exist only while the popup is open on a compact page; Forward/Delete keep
  their established action keys at the bottom so existing side-effect tests do
  not bypass the real control.
- TC-307-01 must inspect widget rectangles, not only finders: top versus bottom
  half, start/end ordering, 48dp tap bounds, 36dp circular visual, MediaQuery
  safe padding, and no intersection between `media_action_result_*` and either
  bottom control. With the popup closed, Save/Share/Info/Reply must have no
  visible top controls and Forward/Delete must exist only in the bottom band.
  It must test LTR and RTL rather than hard-code only one text direction.
- TC-307-02 must open the popup before locating its four action keys, compare
  their vertical centers for exact order, and verify the generated en/de/ar
  strings (`Save image` / `Bild speichern` / `حفظ الصورة` and localized More
  actions). It must prove Forward/Delete are absent from the popup subtree, not
  absent from the whole viewer.
- TC-307-04/05 must use the real typed route opened from `MediaGridCell` with
  synchronous temporary files. A multi-image swipe must assert both the counter
  and the current item's layout/callback identity; no test may call
  `viewer.onAction` directly as a substitute for the new controls.
- TC-307-06 must swipe between two distinct image attachments before pressing
  Forward; a single-image fixture cannot re-red initial-page capture.
- Update existing direct static-image assertions and interactions that assume
  `media_action_save/share/info/reply` are immediately present in the AppBar.
  Open `media_action_more` before popup-key assertions/taps, including the
  metadata visibility, same-message parity, viewer-reopen, selected-attachment
  Info, viewer Reply, and wired viewer Share cases. Keep standard video/GIF/
  outgoing interactions, every identity/callback count, denial, and side-effect
  assertion unchanged; only the compact image access path changes.
- TC-307-08 proves that the relocated control still reaches the existing
  whole-message seam; it must not claim that its recording fake independently
  exercises attachment cleanup. That behavior remains owned by the unchanged
  `deleteMessageForMe` application test cited above.
- TC-307-12 must select Save through an opened compact popup at least once; a
  standard-only dispatch would not catch menu-local logging of private item
  fields.
- The result chip is feedback, not a new action. Its compact position must
  remain above the bottom safe-area control band in both directions.

## Implementation Steps

1. Snapshot `git status --short` and preserve the current dirty diffs in every
   overlapping Plan-303-306 source/test file. Run TC-307-09/10/11/12 and the
   unchanged TC-307-08 Delete sentinel GREEN. Add TC-307-04 first and record its
   user-visible assertion RED; then add the shared/forward causal tests and
   record their assertion/compile REDs before production edits.
2. Add `MediaViewerActionPresentation` and a default-standard field to
   `MediaViewerItem` in `media_viewer_item.dart`. This is presentation data
   only; do not add direction/policy inference or change action capability
   types. Stop-if a required action cannot remain expressed by the existing
   `MediaViewerAction` callback contract.
3. In `full_screen_typed_media_viewer.dart`, preserve the existing standard
   `_actionOrder`/`_buildActions` path byte-semantically. Add exact compact menu
   order, a reusable circular 48/36dp control, localized popup construction,
   bottom start/end SafeArea controls, and compact result-chip positioning.
   Derive all visible/disabled states from the current item on every rebuild
   and route every selection through `_dispatch` exactly once.
4. In `_buildDirectViewerItem` in `conversation_screen.dart`, set compact only
   for `message.isIncoming && decision.isOrdinary && kind == image`. Do not edit
   direct Shared Media or any group/private caller. Stop-if execution finds a
   second in-chat ordinary typed builder that bypasses this discriminator.
5. Add en/de/ar `media_viewer_action_save_image` and
   `media_viewer_more_actions` ARB entries, run `flutter gen-l10n`, and use only
   generated getters in UI/semantics. Do not rename or globally change the
   existing generic Save label.
6. Update the exact affected direct test interactions without weakening their
   side-effect assertions. No harness registration edit is expected; verify
   existing 1:1 array discovery and shared/l10n `host-all` glob discovery in
   list mode.
7. Run focused GREEN, complete touched suites, exact default/private/library/
   boundary sentinels, the curated 1:1 lane, analyzer and whitespace hygiene.
   After the coherent app-owned change, run
   `./graphify-arch/refresh_arch_graph.sh --incremental` once.

## Risks And Blind Spots

- A global layout predicate could silently change groups, announcements,
  Shared Media, or outgoing pages -> `TC-307-04`, `TC-307-09`, and
  `TC-307-10` enforce caller-selected/default-standard behavior.
- Popup construction could expose an unauthorized action or leave stale page-1
  identity after a swipe -> `TC-307-02/03/04/05` bind list contents and dispatch
  to the current item.
- Moving an icon could bypass existing effects -> `TC-307-05/06/07/08` exercise
  the real Save/Share/Info/Reply/Forward/Delete presentation paths.
- Bottom controls can collide with home indicators, localized direction, video
  controls, or result feedback -> compact is static-image-only and
  `TC-307-01` proves safe-area/mirroring/result non-overlap; videos retain the
  standard path in `TC-307-04`.
- A disabled popup could still dispatch through a stale selection or allow a
  second async tap -> `TC-307-03` uses owner/availability and a pending
  completer with exact call counts.
- Lifecycle / derived-state durability: N/A — action layout is recomputed from
  the immutable current `MediaViewerItem` on each mount/page change and stores
  no state beyond existing `_currentIndex`, `_dispatching`, and `_lastResult`;
  `TC-307-01/03/04` cover those transitions.
- Sibling-surface consistency: direct Shared Media and default shared callers
  are deliberately asymmetric and locked by `TC-307-09/10`; private routes are
  locked by `TC-307-11`.
- Destructive-action side effects: `TC-307-08` asserts viewer removal,
  confirmation, exact message ID, and handoff to the unchanged whole-message
  seam; the existing `deleteMessageForMe` application test owns attachment/file
  cleanup. This plan does not add attachment-only deletion.
- Invariant re-verification under new transitions: every page change rebuilds
  compact/standard chrome from `_currentItem`, and `_dispatch` rechecks the
  exact current item/capability immediately before callback; `TC-307-02/03/04`
  exercise swipe and pending transitions.

## Gate Cadence

- Per-plan closure: focused causal rows, the complete shared-viewer/direct
  actions/direct forward test files, the two exact wired tests, exact
  Shared-Media/private/boundary/l10n sentinels, and the affected curated `1to1`
  lane. No `core-host-all`, `feature-host-all`, performance, simulator, device,
  relay, native, or group sweep is justified for this default-off
  presentation-only change.
- Do not run full `host-all` for this individual plan. Run
  `./scripts/run_host_test_gates.sh host-all` once after the 1:1 media
  presentation batch (Plans 303-307, including still-open Plan 305 and this
  plan) is complete, and once at final rollout/release closure.
- Shared/l10n tests outside feature/core globs run by the exact commands below;
  list mode verifies their later `host-all` discovery without executing full
  `host-all` during this plan.

## Acceptance Gates

```bash
# Snapshot before execution; preserve unrelated and overlapping edits.
git status --short

# First causal RED before production edits; expect non-zero because the
# received image still has individual top icons and no compact controls.
flutter test test/features/conversation/presentation/screens/conversation_received_media_actions_test.dart \
  --plain-name 'incoming keep-in-chat images select compact actions while sibling media stays standard'

# Shared layout/menu/capability REDs; expect non-zero (assertion or missing
# presentation API) for the documented compact-layout gap.
flutter test test/shared/widgets/media/full_screen_typed_media_viewer_test.dart \
  --plain-name 'compact image layout places overflow forward and delete on safe corners'
flutter test test/shared/widgets/media/full_screen_typed_media_viewer_test.dart \
  --plain-name 'compact overflow lists localized image actions in order and targets the current item'
flutter test test/shared/widgets/media/full_screen_typed_media_viewer_test.dart \
  --plain-name 'compact actions remain capability gated and single dispatch while pending'

# Direct behavior REDs; expect non-zero because overflow/bottom access paths do
# not exist on the planning baseline.
flutter test test/features/conversation/presentation/screens/conversation_received_media_actions_test.dart \
  --plain-name 'compact image overflow preserves save share info and reply routes'
flutter test test/features/conversation/presentation/screens/conversation_received_media_forward_test.dart \
  --plain-name 'compact viewer bottom forward launches existing picker with current attachment'

# Generate localization API after additive ARB edits; expect exit 0.
flutter gen-l10n

# Focused/complete GREEN; expect exit 0 and zero failed tests.
flutter test test/shared/widgets/media/full_screen_typed_media_viewer_test.dart
flutter test test/features/conversation/presentation/screens/conversation_received_media_actions_test.dart
flutter test test/features/conversation/presentation/screens/conversation_received_media_forward_test.dart

# Exact wired action preservation; expect exit 0 and unchanged controller,
# zero-delivery, confirmation, and cleanup assertions.
flutter test test/features/conversation/presentation/screens/conversation_wired_test.dart \
  --plain-name 'bubble and viewer media egress use controller with zero delivery calls'
flutter test test/features/conversation/presentation/screens/conversation_wired_test.dart \
  --plain-name 'viewer delete invokes existing direct whole message cleanup'

# Exact default/private/library/boundary/l10n preservation; expect exit 0.
flutter test test/features/conversation/presentation/screens/conversation_shared_media_viewer_test.dart \
  --plain-name 'in-viewer current item actions execute across parent messages'
flutter test test/shared/widgets/media/full_screen_typed_media_viewer_test.dart \
  --plain-name 'actions always target the currently visible typed item and owner'
flutter test test/shared/widgets/media/full_screen_typed_media_viewer_test.dart \
  --plain-name 'private presentation suppresses metadata resume actions and PiP without changing ordinary pages'
flutter test test/shared/widgets/media/media_viewer_boundary_test.dart \
  --plain-name 'viewer remains callback-only transport-free and diagnostics are redacted'
flutter test test/l10n/l10n_integrity_test.dart

# Registration discovery only; expect each exact target to be listed.
./scripts/run_host_test_gates.sh 1to1 --list \
  --only test/features/conversation/presentation/screens/conversation_received_media_actions_test.dart
./scripts/run_host_test_gates.sh 1to1 --list \
  --only test/features/conversation/presentation/screens/conversation_received_media_forward_test.dart
./scripts/run_host_test_gates.sh 1to1 --list \
  --only test/features/conversation/presentation/screens/conversation_wired_test.dart
./scripts/run_host_test_gates.sh host-all --list \
  --only test/shared/widgets/media/full_screen_typed_media_viewer_test.dart
./scripts/run_host_test_gates.sh host-all --list \
  --only test/l10n/l10n_integrity_test.dart

# Affected curated lane; expect exit 0 and zero failed Flutter/Go cases.
./scripts/run_test_gates.sh 1to1

# App-owned graph and hygiene; expect successful incremental refresh, no new
# analyzer issues attributable to this plan, and no whitespace errors.
./graphify-arch/refresh_arch_graph.sh --incremental
flutter analyze
git diff --check
```

## Execution Interpretation And Done Criteria

- Expected RED: TC-307-04 first fails because `media_action_more` and bottom
  placement are absent; TC-307-01/02/03 fail on the missing compact
  presentation API/behavior; TC-307-05/06 fail on the missing access paths.
- Green sentinels: TC-307-08 preserves whole-message Delete, TC-307-09 preserves
  default current-item top actions, TC-307-10 preserves direct Shared Media,
  TC-307-11 preserves private suppression, and TC-307-12 preserves the shared
  boundary/redaction contract.
- Pre-existing dirty tree / known failure: the planning snapshot is dirty with
  overlapping Plan-303-306 changes in `media_viewer_item.dart`,
  `full_screen_typed_media_viewer.dart`, `conversation_screen.dart`,
  `conversation_wired.dart`, their tests, the index, Graphify outputs, and
  unrelated native/evidence files. Those changes are baseline, not Plan-307
  evidence, and must not be reverted or absorbed. The three named planning
  probes passed; no new TC-307 test has been written or run.
- Environment blocker: none; closure is host-only and requires no device,
  simulator, relay, SQLCipher, OS callback, or native fixture.
- Scope drift: any requirement for attachment-only Delete, compact Shared
  Media/group/private/video/GIF/outgoing layouts, new controller/transport
  behavior, native menu/share implementation, or persistent layout state
  blocks completion and requires replanning.

- [x] Every behavior has its named causal test or preservation sentinel.
- [x] Causal RED, focused GREEN, and one representative mutation re-red per
      distinct compact-layout/action contract are recorded.
- [x] Save/Share/Info/Reply/Forward/Delete effects and current-item identity
      remain green through their real presentation paths.
- [x] Default, Shared Media, private, boundary, l10n, and curated 1:1 gates pass
      with the semantic outcomes above.
- [x] Existing gate discovery is verified; no unnecessary registration edit is
      introduced.
- [x] Incremental Graphify refresh succeeds; `flutter analyze` has no new
      issues and `git diff --check` is clean.
- [x] Scope Contract And Guard is respected, including dirty-tree preservation.

## Handoff

- First causal RED command:
  `flutter test test/features/conversation/presentation/screens/conversation_received_media_actions_test.dart --plain-name 'incoming keep-in-chat images select compact actions while sibling media stays standard'`.
- Preservation command:
  `flutter test test/shared/widgets/media/full_screen_typed_media_viewer_test.dart --plain-name 'actions always target the currently visible typed item and owner'`.
- Manual registration: none. The three conversation test files are already in
  `ONE_TO_ONE_TESTS` / `ONE_TO_ONE_HOST_TESTS`; direct Shared Media is already
  in both; shared viewer, boundary, and l10n tests are discovered by
  `host-all`. Planning list-mode probes selected the actions file as 1:1 item
  82, Forward as item 83, shared viewer as host-all item 1239, and l10n
  integrity as host-all item 1229.
- Migration: none.
- Boundary closure: host-only widget/application proof; no
  simulator/device/relay profile.
- Unresolved evidence: none.

## Execution Progress

| Time | Phase | Files | Last command/result | Current evidence | Decision/blocker | Next |
|---|---|---|---|---|---|---|
| 2026-07-31 15:44 CEST | Dirty-tree grounding and RED | Three production seams plus the planned shared/direct/forward tests | Graphify affected query completed; TC-307-04 compile-failed on the absent presentation API and TC-307-06 assertion-failed because Forward was still at `dy=28` | The existing standard toolbar and direct route reproduced the exact missing layout while overlapping Plans 303-306 remained in place. | Expected causal RED; no blocker. | Implement the additive seam. |
| 2026-07-31 15:57 CEST | Implementation and focused GREEN | `media_viewer_item.dart`; `full_screen_typed_media_viewer.dart`; `conversation_screen.dart`; en/de/ar ARBs and generated l10n; focused tests | All six new causal rows passed individually; complete shared-viewer, direct-actions, and direct-forward files then passed `18/18`, `18/18`, and `5/5` | Incoming ordinary static images alone receive compact chrome; exact menu order, safe directional corners, current-page dispatch, pending fencing, and result-chip clearance are proven. | No controller, persistence, transport, private-policy, or default-caller change was needed. | Run preservation and wired proofs. |
| 2026-07-31 15:59 CEST | Preservation and discovery | Wired Share/Delete blocks; Shared Media viewer; boundary; l10n; existing gate inventories | Both wired tests, the exact Shared Media sentinel, boundary suite, and l10n integrity passed; list mode selected the direct files at 1:1 items 82/83/90 and shared/l10n files at host-all items 1239/1229 | Whole-message Delete, current-row egress, standard Shared Media, private suppression, redacted diagnostics, and en/de/ar parity remain intact without registration edits. | Full `host-all` intentionally omitted by project cadence. | Run the affected curated lane. |
| 2026-07-31 16:00 CEST | Curated lane | Existing `1to1` Flutter and relay inventories | `./scripts/run_test_gates.sh 1to1` exited `0`: `2523/2523` Flutter tests, relay Go toolchain contract, and `github.com/mknoon/relay-server` all passed | The complete affected 1:1 dependency lane is green. | None. | Static, graph, and causality closure. |
| 2026-07-31 16:06 CEST | Mutation and closure | Compact layout/menu predicate and direct selector; graph/hygiene outputs | Swapped Forward/Delete anchors re-red TC-307-01, swapped Save/Share order re-red TC-307-02, and admitting outgoing images re-red TC-307-04; every mutation was restored and each named test returned GREEN. Incremental Graphify refresh exited `0` (`9 changed code`, `2908 unchanged`, `63420` nodes, `96797` edges); `flutter analyze` reported `No issues found`; `git diff --check` exited `0`. | Tests are causally attached to the requested geometry, exact menu order, and receiver-only scope; no residual mutation or blocker remains. | Implemented / host-green. |
