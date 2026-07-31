# 306 - 1:1 Keep-in-chat Image Viewer Metadata Removal

Status: implemented / host-green
Type: Modification
Spec: free-text intent — remove the automatic sender/date/type/size information
from sender and receiver views of a direct `Keep in chat` image
Classification: implemented
Closure tier: host

## Planning Progress

| Time | Role | Files inspected | Decision/blocker | Next action |
|---|---|---|---|---|
| 2026-07-30 18:24 CEST | Evidence Collector | `graphify-arch/tdd_context.py`; `230-shared-typed-media-viewer-tdd-plan.md`; `full_screen_typed_media_viewer.dart`; `media_viewer_item.dart`; `conversation_screen.dart` | Confirmed that one unconditional ordinary-viewer metadata widget explains the reported sender/receiver difference. | Verify tests and gate ownership. |
| 2026-07-30 18:26 CEST | Planner | `full_screen_typed_media_viewer_test.dart`; `conversation_received_media_actions_test.dart`; `run_test_gates.sh`; `run_host_test_gates.sh`; `tier-matrix.md`; `plan-template.md` | Host widget closure is causal; no persistence, native, relay, crypto, or device boundary is involved. Existing metadata and explicit-Info sentinels passed as planning probes. | Complete sufficiency check, then run the requested independent review. |
| 2026-07-30 18:41 CEST | Reviewer | Plan 306; `direct_shared_media_library_screen.dart`; `conversation_shared_media_viewer_test.dart`; direct/shared viewer tests and gate arrays; review references | The audit found required plan fixes: direct Shared Media bypassed the inline caller, key-only negatives were gameable, direct video/GIF and captionless behavior were under-proved, and Info could not prove typed-item data retention. | Apply the verified deltas in place and rerun the five lenses. |
| 2026-07-30 18:57 CEST | Final Verifier | Updated Plan 306; both direct production entrypoints; all three planned test files; gate discovery | Both-direction caption and Shared Media counterexamples are now explicit; all prior findings are closed and the final independent verdict is `ready`. | Hand off the reviewed execution contract. |

## Problem And Evidence

- Behavior to improve: when either participant opens a direct 1:1 static image
  sent with `Keep in chat`, whether from the conversation bubble or that
  conversation's direct Shared Media library, the full-screen image should not
  automatically place sender, date/time, MIME/type, byte size, or dimensions
  over the top-left of the image.
- Impact: the overlay obscures the image and exposes technical details without
  an explicit user action. Captions and existing viewer actions are separate
  behavior and remain available.
- Confirmed policy mapping: `PrivateMediaPickerMode.ordinary` maps to
  `PrivateMediaPolicy.ordinary()` at
  `lib/features/conversation/presentation/widgets/compose_area.dart:405`, and
  its localized label is `Keep in chat` at `lib/l10n/app_en.arb:1729`.
- Confirmed root cause: `FullScreenTypedMediaViewer.build` mounts
  `_MediaViewerMetadata(item: current)` for every non-`privacyMinimized` route
  at `lib/shared/widgets/media/full_screen_typed_media_viewer.dart:459-465`.
  `_MediaViewerMetadata` renders sender, timestamp, caption, required MIME,
  optional size, and dimensions/duration at `:590-665`.
- Confirmed sender/receiver discriminator: `_buildDirectViewerItem` always
  supplies MIME, size, and timestamp, but supplies `senderLabel` only when
  `message.isIncoming` at
  `lib/features/conversation/presentation/screens/conversation_screen.dart:2101-2123`.
  The viewer does not have separate sender and receiver overlay branches; this
  input difference exactly explains why the receiver sees the sender name while
  the sender does not.
- Confirmed second direct entrypoint: direct Shared Media revalidates every
  loaded parent as ordinary before viewer entry at
  `lib/features/conversation/presentation/screens/direct_shared_media_library_screen.dart:246-278`
  and `:713-756`, then `_viewerItem` supplies the same sender/timestamp/type/
  size/dimension inputs at `:845-895` and opens the same typed viewer at
  `:919-929`.
- Existing coverage: planning probes on 2026-07-30 ran
  `full_screen_typed_media_viewer_test.dart::metadata and action semantics follow current item in LTR and RTL`
  and
  `conversation_received_media_actions_test.dart::info follows selected attachment within one message without transport reads`;
  both exited `0`. They confirm that automatic metadata is currently visible
  and that the explicit Info action independently loads current persisted
  metadata.
- Missing coverage: no test distinguishes automatic metadata visibility from
  caption/action visibility; no direct conversation test covers both incoming
  and outgoing ordinary-image presentation; and the Shared Media viewer test
  proves cross-message identity/actions without constraining automatic
  metadata visibility.
- Refuted findings:
  - The difference is not caused by two role-specific viewer widgets; both
    directions use the same `FullScreenTypedMediaViewer`.
  - `privacyMinimized` is not a safe fix: it also suppresses actions, video
    resume, controls, and PiP at
    `lib/shared/widgets/media/full_screen_typed_media_viewer.dart:85-88`,
    `:422-440`, and `:498-516`.
  - Clearing metadata fields is not a presentation-only fix. Explicit Info
    independently reloads current persisted metadata by message/attachment ID
    at `conversation_screen.dart:2143-2175` and `:2292-2311`, so its existing
    sentinel cannot prove that the displayed `MediaViewerItem` retained its
    MIME, size, dimensions, timestamp, or sender input.
- Unresolved findings: N/A — the requested visual behavior, role mapping,
  production seam, and host proof boundary are source-confirmed.
- Affected production, test, and gate files:
  `lib/shared/widgets/media/media_viewer_item.dart`,
  `lib/shared/widgets/media/full_screen_typed_media_viewer.dart`,
  `lib/features/conversation/presentation/screens/conversation_screen.dart`,
  `lib/features/conversation/presentation/screens/direct_shared_media_library_screen.dart`,
  `test/shared/widgets/media/full_screen_typed_media_viewer_test.dart`,
  `test/features/conversation/presentation/screens/conversation_received_media_actions_test.dart`,
  and
  `test/features/conversation/presentation/screens/conversation_shared_media_viewer_test.dart`.
  No gate-script edit is planned.

## Graph Grounding Snapshot

- Graph fingerprint / freshness:
  `5504a402e4d6beec`; `stale:ios/Flutter/flutter_export_environment.sh`.
  The stale generated iOS export file is unrelated to this host presentation
  seam and did not block current-source verification.
- Query / profile:
  `python3 graphify-arch/tdd_context.py query "1:1 keep-in-chat image viewer top-left metadata overlay sender receiver sender name date size image type shared typed media viewer" --profile tdd --budget 700`
  returned `confidence=broad`; the permitted exact-anchor refinement was
  `python3 graphify-arch/tdd_context.py query "FullScreenTypedMediaViewer full_screen_typed_media_viewer.dart metadata sender timestamp MIME byte size image keep-in-chat direct sender receiver overlay removal" --profile tdd --budget 700`
  and returned `confidence=anchored`.
- Anchors:
  `FullScreenTypedMediaViewer` ->
  `lib/shared/widgets/media/full_screen_typed_media_viewer.dart:35`;
  direct caller -> `conversation_screen.dart:2050`;
  shared proof candidate ->
  `test/shared/widgets/media/full_screen_typed_media_viewer_test.dart:82`.
- Surfaced proof/gate files:
  `full_screen_typed_media_viewer_test.dart`,
  `conversation_screen.dart`, `direct_private_media_viewer.dart`,
  `direct_shared_media_library_screen.dart`, group viewer/library callers, and
  the legacy viewer.
- Graph gaps requiring source search: the compact result did not surface
  `_MediaViewerMetadata`, the direct input discriminator,
  `conversation_received_media_actions_test.dart`, or its existing
  `ONE_TO_ONE_TESTS` / `ONE_TO_ONE_HOST_TESTS` registrations. These were
  verified in current source and gate arrays.
- Reuse rule: anchors may be handed to review/execution; all conclusions still
  require current-source or command evidence.

## Scope Contract And Guard

In scope:

- Add an item-level, presentation-only metadata-detail visibility input to
  `MediaViewerItem`, defaulting to the current visible behavior.
- For a direct ordinary (`Keep in chat`) static image built by
  `_buildDirectViewerItem`, suppress automatic sender, timestamp, MIME/type,
  byte-size, and dimensions/duration rows.
- Apply the same static-image policy in direct Shared Media's `_viewerItem`
  after its existing ordinary-parent revalidation; the same direct attachment
  must not regain unsolicited metadata through a second entrypoint.
- Keep a non-empty message caption visible; if a hidden-detail item has no
  caption, render no keyed metadata-content container or semantic text.
- Make visibility follow the current item while swiping a mixed media set so a
  visible video/GIF page cannot leak stale details onto a hidden image page, or
  vice versa.

Must preserve:

- Captions and authorized viewer actions remain visible and interactive when
  automatic details are hidden ->
  `TC-306-01` and `TC-306-02`.
- The explicit received-media Info sheet continues to show current persisted
  sender/type/size/dimensions/duration on demand ->
  `TC-306-06`.
- Inline-conversation and direct Shared Media video/GIF pages keep their
  automatic metadata behavior -> `TC-306-01`, `TC-306-03`, and `TC-306-04`.
- Group, announcement, private, and other default callers keep the automatic
  metadata behavior -> `TC-306-05`.
- Direct viewer items retain their original sender/timestamp/MIME/size/
  dimensions values even while their automatic presentation is hidden ->
  `TC-306-02` and `TC-306-03`.
- Private `privacyMinimized` routes keep their stronger metadata/action/resume
  suppression; do not route ordinary images through that mode ->
  `TC-306-01`, `TC-306-02`, `TC-306-06`, and the existing
  `private presentation suppresses metadata resume actions and PiP without changing ordinary pages`
  sentinel.
- Existing page counter, zoom, Back behavior, media bytes, action capability
  decisions, resume/PiP state, and diagnostic redaction remain unchanged.
- Preserve the pre-existing dirty-tree work in the same production files,
  especially `FullScreenTypedMediaViewer.onBackRequested` and the current
  Plan-304/305 terminal/bubble presentation edits.

Hard `Do not`:

- Do not globally remove `_MediaViewerMetadata`, change its default visibility,
  clear typed metadata values, or weaken explicit Info.
- Do not suppress video/GIF details or alter group, announcement, private-media,
  or legacy path-only viewer behavior.
- Do not change direct Shared Media paging, filters, cross-message identity,
  continuation, bookmark, egress, delete, or action authority.
- Do not change send policy, message/attachment persistence, DB schema, wire
  payloads, encryption, relay/Go code, native code, localization, or transport.
- Do not overwrite, revert, or absorb unrelated dirty-tree changes.

Deferred / accepted difference:

- Explicit Info remains intentionally available for currently eligible received
  media; the request removes unsolicited overlay details, not on-demand Info.
- A direct image caption remains visible because it is user-authored content,
  not one of the requested sender/date/type/size details.
- Broad metadata removal for videos, GIFs, group/announcement viewers, or
  private routes is deferred to a future product-owned plan; TC-306-03/04/05
  lock the current accepted difference.

Dependencies:

- Builds additively on Plan 230's typed callback-only viewer and Plan 231's
  direct received-media Info/action contract, plus Plan 233's direct Shared
  Media cross-message viewer.
- The current worktree contains overlapping Plan 303-305 presentation work.
  Execution must rebase around those edits and stop if their final state changes
  the ordinary-viewer seam or the accepted caption/action preservation contract.

## Test Contract

| Case | Behavior | Named test/proof | Tier / fixture | HEAD -> GREEN | Mutation | Gate / registration |
|---|---|---|---|---|---|---|
| TC-306-01 | Metadata-detail visibility follows the exact current item: a captioned hidden image keeps its caption/action but no detail text or semantics; a visible video keeps its details; a captionless hidden image has no metadata-content container; reverse swipes do not retain stale rows. | `test/shared/widgets/media/full_screen_typed_media_viewer_test.dart::metadata detail visibility follows current item while captions and actions remain` | Widget host / captioned image + fake video + captionless image, unique metadata strings, `SemanticsTester`, action recorder | HEAD compile RED because `MediaViewerItem` has no item-level visibility input -> hidden pages contain none of their unique keyed/text/semantic details, visible video retains all applicable details, captions/actions remain, and the captionless page has no metadata-content key | Ignore the visibility input, leave hidden text under renamed keys, read the first item's value after swipe, or gate the whole overlay/actions -> TC-306-01 red | `flutter test test/shared/widgets/media/full_screen_typed_media_viewer_test.dart --plain-name 'metadata detail visibility follows current item while captions and actions remain'`; AUTO (`host-all` glob), executed directly per plan |
| TC-306-02 | Inline direct incoming and outgoing ordinary static images both suppress automatic details; each direction's non-empty caption remains, the incoming Info action remains, a separate captionless page has no metadata-content container, and every viewer item retains its original typed values. | `test/features/conversation/presentation/screens/conversation_received_media_actions_test.dart::ordinary keep-in-chat image viewer hides automatic metadata for incoming and outgoing messages` | Widget host / real temporary image files, distinct incoming-captioned + outgoing-captioned + captionless ordinary messages, unique sender/timestamp/caption/MIME/size/dimensions, persisted-Info fake | HEAD assertion RED because `_MediaViewerMetadata` renders the unique details -> no route contains its detail keys/text/semantics; both authored captions and the Info action remain; the captionless route has no metadata-content key; `viewer.items` still contains each original metadata/caption tuple | Omit the hidden-detail input in `_buildDirectViewerItem`, apply it to one direction only, clear item fields or one direction's caption, leave text under different keys, or use `privacyMinimized` -> TC-306-02 red | `flutter test test/features/conversation/presentation/screens/conversation_received_media_actions_test.dart --plain-name 'ordinary keep-in-chat image viewer hides automatic metadata for incoming and outgoing messages'`; existing `ONE_TO_ONE_TESTS` and `ONE_TO_ONE_HOST_TESTS`, plus AUTO (`feature-host-all` glob); no registration edit |
| TC-306-03 | Direct Shared Media applies the same policy to incoming and outgoing ordinary static-image pages while retaining video/GIF metadata, current cross-message identity, item data, and authorized actions. | `test/features/conversation/presentation/screens/conversation_shared_media_viewer_test.dart::direct Shared Media hides automatic metadata only for keep-in-chat image pages` | Widget host / strict direct-library repository, ordinary current-parent decision loader, distinct incoming image + outgoing image + video + GIF entries with unique metadata, fake egress recorder | HEAD assertion RED because both image pages render automatic details -> both directions' image details are absent by key/text/semantics, video/GIF details remain present after swipe, original item tuples are retained, and action callbacks still carry exact attachment/message IDs | Omit the flag in `_viewerItem`, key it to sender presence or one direction, set it false for every library item, clear item fields, or replace the typed cross-message route -> TC-306-03 red | `flutter test test/features/conversation/presentation/screens/conversation_shared_media_viewer_test.dart --plain-name 'direct Shared Media hides automatic metadata only for keep-in-chat image pages'`; existing `ONE_TO_ONE_TESTS` and `ONE_TO_ONE_HOST_TESTS`, plus AUTO (`feature-host-all` glob); no registration edit |
| TC-306-04 | Inline direct ordinary video and GIF pages retain their automatic sender/timestamp/MIME/size and duration/dimensions. | `test/features/conversation/presentation/screens/conversation_received_media_actions_test.dart::direct keep-in-chat video and GIF viewers retain automatic metadata` | `GREEN sentinel` / real temporary video+GIF files in one ordinary incoming message, unique visible metadata | GREEN on HEAD -> remains GREEN after static-image suppression lands | Set hidden details unconditionally in `_buildDirectViewerItem` or infer only from direct owner -> TC-306-04 red | `flutter test test/features/conversation/presentation/screens/conversation_received_media_actions_test.dart --plain-name 'direct keep-in-chat video and GIF viewers retain automatic metadata'`; existing `ONE_TO_ONE_TESTS` and `ONE_TO_ONE_HOST_TESTS`; no registration edit |
| TC-306-05 | Default typed-viewer callers retain sender, timestamp, MIME, size, and current image dimensions/video duration in LTR and RTL. | `test/shared/widgets/media/full_screen_typed_media_viewer_test.dart::metadata and action semantics follow current item in LTR and RTL` | `GREEN sentinel` / strengthened heterogeneous image+video fixture with timestamps and positive assertions for every applicable row | GREEN on HEAD after the sentinel is strengthened -> remains GREEN after the additive default lands | Default visibility to hidden, remove/rename any automatic field globally, or stop updating it on page change -> TC-306-05 red | `flutter test test/shared/widgets/media/full_screen_typed_media_viewer_test.dart --plain-name 'metadata and action semantics follow current item in LTR and RTL'`; AUTO (`host-all` glob), executed directly per plan |
| TC-306-06 | Eligible received-image Info remains an explicit, current-attachment action and still shows persisted sender/type/size/dimensions without a transport read. | `test/features/conversation/presentation/screens/conversation_received_media_actions_test.dart::info follows selected attachment within one message without transport reads` | `GREEN sentinel` / existing persisted metadata map and two-attachment fixture, strengthened with positive size key/value assertion | GREEN on HEAD after the size assertion is added -> automatic-overlay suppression leaves the Info action and complete sheet GREEN | Reuse `privacyMinimized`, hide actions with details, drop the size row, or stop reloading the exact attachment identity -> TC-306-06 red | `flutter test test/features/conversation/presentation/screens/conversation_received_media_actions_test.dart --plain-name 'info follows selected attachment within one message without transport reads'`; existing `ONE_TO_ONE_TESTS` and `ONE_TO_ONE_HOST_TESTS`; no registration edit |

### Test Notes

- TC-306-02 must open the real typed route by tapping actual `MediaGridCell`
  widgets backed by synchronous temporary files. It must test distinct
  incoming-captioned and outgoing-captioned ordinary messages plus a separate
  captionless ordinary message, close each viewer before opening the next, and
  inspect the route widget's `MediaViewerItem` fields as well as rendered
  output.
- TC-306-03 must use the real direct Shared Media host with a current ordinary
  decision for every entry and distinct parents representing both conversation
  directions; omitting `loadActionDecision` would exercise only its test
  compatibility path rather than production entry authority.
- Automatic-detail absence is keyed by `media_meta_sender`,
  `media_meta_timestamp`, `media_meta_mime`, `media_meta_size`,
  `media_meta_dimensions`, and `media_meta_duration`. Caption preservation is
  keyed by `media_meta_caption`; action preservation uses
  `media_action_info` or the surface's existing action key. A non-empty
  metadata body uses `media_viewer_metadata_content`; it must be absent for a
  captionless hidden item.
- Negative assertions must also use unique fixture values and a
  `SemanticsTester` (or equivalent semantics inspection). Removing/renaming
  `ValueKey`s while leaving sender/date/type/size text visible must not make a
  causal test pass. Positive video/GIF/default assertions likewise name the
  exact visible text/semantics for every applicable field.
- TC-306-05 strengthens the existing fixture before production edits: give
  both image and video pages timestamps, then positively assert sender,
  timestamp, MIME, size, and dimensions/duration after each page transition.
  TC-306-06 adds the missing positive Info size key/value assertion.
- The tests must not treat the AppBar page counter as metadata. It is separate
  navigation state and remains unchanged.

## Implementation Steps

1. Snapshot `git status --short` and record the existing edits to
   `full_screen_typed_media_viewer.dart`, `conversation_screen.dart`, and the
   Plan 303-305 artifacts. Strengthen TC-306-05/06 and add the TC-306-04
   preservation sentinel while HEAD is GREEN. Add TC-306-02 and TC-306-03 and
   record their assertion REDs before introducing a new API; then add TC-306-01
   and record its compile RED.
2. Extend `MediaViewerItem` in
   `lib/shared/widgets/media/media_viewer_item.dart` with an additive
   presentation input such as `showMetadataDetails`, defaulting to `true`.
   Stop-if: if execution discovers a third ordinary direct static-image
   entrypoint outside the inline and Shared Media callers, or a requirement to
   hide captions/all media, stop and revise this contract instead of widening
   the default. Known private viewers and direct/group video-only PiP
   authorization-item builders are not such entrypoints and retain the
   default-visible input.
3. Update `_MediaViewerMetadata` in
   `lib/shared/widgets/media/full_screen_typed_media_viewer.dart` to omit only
   sender/timestamp/technical detail rows when the current item disables them,
   retain a non-empty caption, key the non-empty content container, and return
   an empty widget when no visible row remains. Do not use
   `privacyMinimized`.
4. In `_buildDirectViewerItem` at
   `lib/features/conversation/presentation/screens/conversation_screen.dart`,
   disable automatic details only when the item is both an ordinary direct
   `Keep in chat` item and `MediaViewerKind.image`. Preserve the metadata values
   themselves and every capability decision.
5. In direct Shared Media's `_viewerItem` at
   `lib/features/conversation/presentation/screens/direct_shared_media_library_screen.dart`,
   apply the same hidden-details input only to `MediaViewerKind.image`.
   Preserve the existing ordinary-parent revalidation, item values,
   cross-message identity, continuation, PiP, and action capabilities.
6. No harness registration edit is expected. Verify both touched feature test
   files appear in both 1:1 inventories and the shared test is discoverable by
   the `host-all` glob without executing full `host-all`.
7. Run focused GREEN, exact preservation sentinels, the affected curated 1:1
   lane, analyzer, and diff hygiene.

## Risks And Blind Spots

- A shared-widget deletion could remove metadata from group/library/video
  callers -> `TC-306-01` mixed page and `TC-306-05`.
- An inline-only edit could let the same direct image regain metadata through
  Shared Media -> `TC-306-03`.
- A sender-label-based library predicate could hide details for only one
  conversation direction -> TC-306-03's distinct incoming/outgoing image pages.
- An unconditional direct-builder edit could suppress video/GIF details in the
  inline or library route -> `TC-306-03` and `TC-306-04`.
- Reusing `privacyMinimized` could silently remove actions/resume/PiP ->
  `TC-306-01`, `TC-306-02`, `TC-306-06`, and the private-presentation
  preservation command.
- Clearing item metadata can make the overlay disappear while violating the
  presentation-only contract; explicit Info would still pass because it
  reloads by ID -> direct item-tuple assertions in `TC-306-02/03`, while
  `TC-306-06` independently preserves the Info sheet.
- Key-only negatives can pass after deleting keys while leaving visible or
  announced text -> unique text plus semantics assertions in `TC-306-01/02/03`.
- Caption loss could broaden the request from technical metadata into
  user-authored content, while a captionless path could accidentally retain
  details -> both-direction captioned and separate captionless legs in
  `TC-306-01/02`.
- Lifecycle / derived-state durability: N/A — visibility is immutable per
  `MediaViewerItem` and current-page selection is already widget state; no
  persisted or lifecycle-derived state changes.
- Sibling-surface consistency: direct conversation images intentionally differ
  from group/announcement callers, while direct Shared Media intentionally
  matches the conversation route; `TC-306-03/04/05` lock both sides.
- Destructive-action side effects: N/A — no write/delete/send action or
  capability changes.
- Invariant re-verification under new transitions: TC-306-01 and TC-306-03
  swipe hidden image -> visible video/GIF -> hidden image and reject stale
  metadata.

## Gate Cadence

- Per-plan closure: the three focused causal tests, the three exact contract
  sentinels, the private-presentation sentinel, all three complete touched test
  files, and the affected curated `1to1` gate. No `core-host-all`,
  `feature-host-all`, performance, simulator, device, relay, or native sweep is
  justified by this presentation-only change.
- Do not run full `host-all` for this individual plan. Run
  `./scripts/run_host_test_gates.sh host-all` once after the current 1:1
  media-presentation batch (Plans 303-306, including still-open Plans 305 and
  306) is complete, and once at final rollout/release closure.
- Shared tests outside feature/core globs:
  `test/shared/widgets/media/full_screen_typed_media_viewer_test.dart` runs by
  the exact commands below; its `host-all` registration is verified by list
  mode only during this plan.

## Acceptance Gates

```bash
# Snapshot before execution; preserve unrelated and overlapping work
git status --short

# First causal RED before production edits; expect non-zero because automatic
# incoming/outgoing detail keys are present on HEAD.
flutter test test/features/conversation/presentation/screens/conversation_received_media_actions_test.dart \
  --plain-name 'ordinary keep-in-chat image viewer hides automatic metadata for incoming and outgoing messages'

# Second production-entry RED before production edits; expect non-zero because
# the ordinary static-image page still renders its automatic details.
flutter test test/features/conversation/presentation/screens/conversation_shared_media_viewer_test.dart \
  --plain-name 'direct Shared Media hides automatic metadata only for keep-in-chat image pages'

# Shared seam RED before production edits; expect non-zero compile status
# because the additive item-level visibility input is absent on HEAD.
flutter test test/shared/widgets/media/full_screen_typed_media_viewer_test.dart \
  --plain-name 'metadata detail visibility follows current item while captions and actions remain'

# Focused GREEN; expect exit 0 and zero failed tests.
flutter test test/features/conversation/presentation/screens/conversation_received_media_actions_test.dart \
  --plain-name 'ordinary keep-in-chat image viewer hides automatic metadata for incoming and outgoing messages'
flutter test test/features/conversation/presentation/screens/conversation_shared_media_viewer_test.dart \
  --plain-name 'direct Shared Media hides automatic metadata only for keep-in-chat image pages'
flutter test test/shared/widgets/media/full_screen_typed_media_viewer_test.dart \
  --plain-name 'metadata detail visibility follows current item while captions and actions remain'

# Complete touched test files; expect exit 0 and zero failed tests.
flutter test test/features/conversation/presentation/screens/conversation_received_media_actions_test.dart
flutter test test/features/conversation/presentation/screens/conversation_shared_media_viewer_test.dart
flutter test test/shared/widgets/media/full_screen_typed_media_viewer_test.dart

# Exact preservation sentinels; expect exit 0.
flutter test test/features/conversation/presentation/screens/conversation_received_media_actions_test.dart \
  --plain-name 'direct keep-in-chat video and GIF viewers retain automatic metadata'
flutter test test/shared/widgets/media/full_screen_typed_media_viewer_test.dart \
  --plain-name 'metadata and action semantics follow current item in LTR and RTL'
flutter test test/shared/widgets/media/full_screen_typed_media_viewer_test.dart \
  --plain-name 'private presentation suppresses metadata resume actions and PiP without changing ordinary pages'
flutter test test/features/conversation/presentation/screens/conversation_received_media_actions_test.dart \
  --plain-name 'info follows selected attachment within one message without transport reads'

# Registration discovery only; expect each exact path to be selected.
./scripts/run_host_test_gates.sh 1to1 --list \
  --only test/features/conversation/presentation/screens/conversation_received_media_actions_test.dart
./scripts/run_host_test_gates.sh 1to1 --list \
  --only test/features/conversation/presentation/screens/conversation_shared_media_viewer_test.dart
./scripts/run_host_test_gates.sh host-all --list \
  --only test/shared/widgets/media/full_screen_typed_media_viewer_test.dart

# Affected curated lane; expect exit 0 and zero failed Flutter/Go cases.
./scripts/run_test_gates.sh 1to1

# Hygiene; expect no analyzer issues attributable to this plan and no
# whitespace errors. Compare against the recorded dirty-tree snapshot.
flutter analyze
git diff --check
```

## Execution Interpretation And Done Criteria

- Expected RED: TC-306-02 fails because automatic detail widgets are found for
  incoming/outgoing ordinary images; TC-306-03 fails because the direct Shared
  Media image page renders the same details; TC-306-01 then fails to compile
  because the item-level presentation input is absent.
- Green sentinels: TC-306-04 preserves inline video/GIF details, TC-306-05
  preserves default shared metadata and page updates, TC-306-06 preserves
  explicit Info, and the private-presentation sentinel preserves the stronger
  private route contract.
- Pre-existing dirty tree / known failure: the planning snapshot contains
  unrelated and overlapping Plan 303-305 edits, including
  `FullScreenTypedMediaViewer.onBackRequested` and direct terminal/bubble work.
  They are not Plan-306 evidence and must not be reverted. The two planning
  probes named above passed.
- Environment blocker: none; closure is host-only.
- Scope drift: any need to change metadata persistence, Info authorization,
  all-media/default viewer behavior, another production direct-image
  entrypoint, group/announcement surfaces, localization, schema, transport,
  native code, or private-media lifecycle blocks completion and requires
  replanning.

- [x] Every behavior has a named test or justified proof.
- [x] Causal RED, focused GREEN, and representative mutation re-red are
      recorded.
- [x] Preservation and the curated 1:1 gate pass with semantic outcomes.
- [x] Existing registration is verified without a gate edit.
- [x] `flutter analyze` has no new issues; `git diff --check` is clean relative
      to the recorded dirty baseline.
- [x] Scope Contract And Guard is respected.

## Handoff

- First causal RED command:
  `flutter test test/features/conversation/presentation/screens/conversation_received_media_actions_test.dart --plain-name 'ordinary keep-in-chat image viewer hides automatic metadata for incoming and outgoing messages'`.
- Preservation command:
  `flutter test test/shared/widgets/media/full_screen_typed_media_viewer_test.dart --plain-name 'metadata and action semantics follow current item in LTR and RTL'`.
- Manual registration: none; the direct file is already pinned in
  `ONE_TO_ONE_TESTS` and `ONE_TO_ONE_HOST_TESTS`, the direct Shared Media file
  is pinned in those same inventories, and the shared widget file is discovered
  by `host-all`.
- Migration: none.
- Boundary closure: host-only widget proof; no simulator/device/relay profile.
- Unresolved evidence: none.

## Reviewer Findings

- Review method: `$tdd-review` counterexample audit on 2026-07-30, grounded by
  `python3 graphify-arch/tdd_context.py query "counterexample audit Plan 306 MediaViewerItem item-level showMetadataDetails FullScreenTypedMediaViewer _MediaViewerMetadata _buildDirectViewerItem direct ordinary keep-in-chat image captions Info mixed page bypass callers" --profile review --budget 800`
  (`confidence=anchored`, fingerprint `5504a402e4d6beec`) and current-source
  verification.
- Required deltas applied:
  - Added the direct Shared Media production entrypoint, separate incoming and
    outgoing image legs, causal test, full-file gate, registration check, and
    cross-message/action preservation.
  - Replaced key-only absence checks with unique rendered-text and semantics
    negatives, both-direction caption preservation, and separate captionless
    no-content-container branches.
  - Added direct inline and library video/GIF preservation so an unconditional
    caller flag cannot satisfy the image requirement.
  - Added direct item-tuple assertions and strengthened the independent default
    viewer and Info sentinels; Info alone cannot prove typed-item retention.
- Core bet: confirmed. An immutable per-item presentation flag with a
  default-visible constructor value reaches the single current-item metadata
  renderer without changing stored metadata or caller authority. The stop-if
  above is the fallback if another ordinary direct static-image entrypoint is
  found; execution must not compensate by widening the default.
- Five-lens result:
  - L1 evidence truth and classification: `clear`; one unconditional metadata
    renderer plus caller-supplied sender differences explains both reported
    directions.
  - L2 Test Contract causality: `clear` after the six-row contract and
    mutations above.
  - L3 bypass sites and scope safety: `clear` for inline conversation, direct
    Shared Media, mixed pages, captions, actions, default callers, and private
    presentation; production has no injected legacy `mediaViewerBuilder`
    overlay path.
  - L4 execution and gate integrity: `clear`; both feature files are already
    in the 1:1 inventories and the shared widget file is covered by `host-all`.
  - L5 boundary, reversibility, and state transitions: `N/A`; this is an
    immutable host presentation input with no persistence, platform, transport,
    or lifecycle boundary.
- Evergreen-blindspot result: B2 bypassing caller, B4 semantic negative
  weakness, and B9 preservation incompleteness were genuine and are
  closed by TC-306-01 through TC-306-06. B3 evidence truth and B7 core-bet/
  fallback are clear after source verification; B1, B5, B6, B8, and B10 are
  N/A because there is no irreversible data, destructive/concurrent,
  durable-derived-state, production-boundary, or cross-platform/version change.
- User decisions required: none.
- Final verdict: `ready`.

## Execution Progress

| Time | Phase | Files | Last command/result | Current evidence | Decision/blocker | Next |
|---|---|---|---|---|---|---|
| 2026-07-30 20:41 CEST | Dirty-tree grounding and preservation baseline | `conversation_screen.dart`; `full_screen_typed_media_viewer.dart`; Plan 303-305 work; three planned test files | `git status --short`; TC-306-04/05/06 exact commands all exited `0` | Existing `onBackRequested`, view-once terminal/bubble changes, default metadata, direct video/GIF metadata, and explicit Info remained intact before production edits. | No conflicting seam change; preserve all unrelated work. | Establish causal REDs. |
| 2026-07-30 20:41 CEST | RED | Three planned test files | TC-306-02 and TC-306-03 failed on the visible `media_meta_sender`; TC-306-01 failed to compile because `showMetadataDetails` did not exist | Both real direct entrypoints reproduced the leak, and the shared seam could not be satisfied without an explicit policy input. | Expected causal REDs; no blocker. | Implement the additive presentation policy. |
| 2026-07-30 20:41 CEST | Implementation and focused GREEN | Four production files; three planned test files | TC-306-01/02/03 exact commands exited `0` | `MediaViewerItem.showMetadataDetails` defaults visible; only direct ordinary static-image callers disable detail rows. Captions, typed values, actions, and mixed-page state remain intact. | Scope contract satisfied without persistence, authorization, private-mode, or default-caller changes. | Re-red and preservation proof. |
| 2026-07-30 20:41 CEST | Mutation and sentinels | `conversation_screen.dart`; focused/sentinel tests | Temporarily forcing the inline caller to `showMetadataDetails: true` made TC-306-02 fail on the sender leak; restoring `kind != MediaViewerKind.image` returned it to GREEN. TC-306-04/05/06 and the private-presentation sentinel all exited `0` | The test is causally attached to the production policy, and video/GIF/default/private/Info behavior is preserved. | Mutation fully restored; no residual mutation diff. | Run complete touched suites and registrations. |
| 2026-07-30 20:41 CEST | Complete suites and discovery | Three planned test files; existing gate arrays | Full files passed: received actions `16/16`, Shared Media viewer `6/6`, typed viewer `15/15`. List mode selected received actions at 1:1 item 82, Shared Media at item 88, and the shared typed viewer at host-all item 1239. | All new and adjacent tests pass; existing registration covers the feature without script edits. | Full `host-all` intentionally not run per cadence. | Run affected curated lane. |
| 2026-07-30 20:41 CEST | Curated lane | Existing `1to1` inventory and relay checks | First concurrent lane output ended nonzero near `conversation_wired_sender_finalize_canonical_path_test.dart`; that complete file then passed `14/14` alone. A clean full retry passed `2520/2520`, the relay Go toolchain contract, and `github.com/mknoon/relay-server`. | Required affected lane is green on a clean retry; the initially named file is independently green. | No reproducible failure remains. | Analyze and audit hygiene. |
| 2026-07-30 20:41 CEST | Analysis and hygiene | Full Dart workspace; current diff | Initial analyzer reported one new `use_null_aware_elements` info in TC-306-02; after the mechanical correction, `flutter analyze` exited `0` with `No issues found`. The causal test rerun exited `0`; `git diff --check` exited `0`. | Production and proof code are analyzer-clean and whitespace-clean against the recorded dirty tree. | No blocker. | Refresh architecture graph and close. |
| 2026-07-30 20:41 CEST | Graph and closure | Four production files; `graphify-arch/graphify-out/graph.json`; `graphify-arch/tdd-overlay.json` | `./graphify-arch/refresh_arch_graph.sh --incremental` exited `0` (`7 changed code`, `2910 unchanged`, `0 deleted`; `63402` nodes, `96779` edges; `14261` named tests). Post-refresh affected query surfaced the expected shared/default/private/group import impact. | Host closure is complete; no device, native, schema, transport, localization, or migration leg applies. | None. | Implemented / host-green. |
