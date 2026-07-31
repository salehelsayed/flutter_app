# 308 - 1:1 Keep-in-chat Image Viewer Overflow Action Icons

Status: implemented / host-green
Type: Modification
Spec: free-text intent — add an icon beside each Save image, Share, Info, and
Reply label in Plan 307's compact received-image overflow menu
Classification: implemented
Closure tier: host

## Planning Progress

| Time | Role | Files inspected | Decision/blocker | Next action |
|---|---|---|---|---|
| 2026-07-31 18:18 CEST | Evidence Collector | `$tdd-plan` instructions/references; Graphify compact context; `full_screen_typed_media_viewer.dart`; focused shared/direct tests; host gate discovery; Plan 307 and index | Confirmed one Text-only popup seam and an existing canonical icon mapping; no l10n, callback, route, native, or device change is needed. | Write the smallest causal widget contract. |
| 2026-07-31 18:20 CEST | Planner | tier matrix; plan template; sufficiency checklist; current dirty-tree snapshot | Selected one strengthened host-widget test plus three adjacent GREEN sentinels. No unresolved evidence blocks execution. | Run `$tdd-review`, apply only material deltas, then execute tests-first. |
| 2026-07-31 18:27 CEST | Reviewer | `$tdd-review` instructions/references; review-profile Graphify context; exact compact callers, Icon semantics, tests, and gate arrays | Verdict `ready`; core bet confirmed. Corrected one non-blocking Graph snapshot overstatement; no test, scope, tier, or gate delta is required. | Execute the reviewed plan tests-first. |

## Problem And Evidence

- Behavior to improve: when a receiver opens Plan 307's three-dot menu for an
  incoming ordinary 1:1 image, each Save image, Share, Info, and Reply label
  should have its familiar icon beside it.
- Impact: the menu is functional but its Text-only rows are slower to scan and
  do not match the icon-plus-label treatment requested by the user.
- Confirmed current gap: `_buildCompactTopActions` builds each
  `PopupMenuItem<MediaViewerAction>` with only a `Text` child at
  `lib/shared/widgets/media/full_screen_typed_media_viewer.dart:552-561`.
  `_actionIcon` already maps Save, Share, Info, and Reply to
  `Icons.download_rounded`, `Icons.ios_share_rounded`,
  `Icons.info_outline_rounded`, and `Icons.reply_rounded` at `:713-730`.
- Existing coverage: the shared test
  `compact overflow lists localized image actions in order and targets the current item`
  opens the real popup in en/de/ar, verifies exact row keys/labels/order, swipes
  to page 2, and dispatches Info for the current item. The direct-route test
  `compact image overflow preserves save share info and reply routes` proves
  the established Save destination, Share, Info sheet, and Reply effects.
  Both planning probes exited `0` before icon assertions were added.
- Missing coverage: no assertion requires any icon inside a compact popup row,
  binds the four exact icons to the corresponding actions, or proves that the
  icon remains on the directional leading side of its label in LTR and RTL.
- Refuted findings:
  - New localization is unnecessary: Plan 307's en/de/ar labels already exist
    and the current popup test verifies them.
  - A new action enum, callback, or direct-conversation edit is unnecessary:
    the existing popup values already dispatch the exact four actions through
    `_dispatch`.
  - A simulator/device proof is unnecessary: this is deterministic Flutter
    widget composition with no OS, native, persistence, crypto, or relay boundary.
- Unresolved findings: N/A — source fixes the menu, icon mapping, direction,
  test tier, and gate ownership.
- Affected production, test, and gate files:
  `lib/shared/widgets/media/full_screen_typed_media_viewer.dart` and
  `test/shared/widgets/media/full_screen_typed_media_viewer_test.dart`.
  `Test-Flight-Improv/00-INDEX.md` indexes this follow-up. No gate-script edit
  is planned.

## Graph Grounding Snapshot

- Graph fingerprint / freshness: `f94343fe15953a7c`;
  `stale:lib/shared/widgets/media/full_screen_typed_media_viewer.dart`.
  Current source was therefore used for every load-bearing line claim.
- Query / profile:
  `python3 graphify-arch/tdd_context.py query "Plan 307 FullScreenTypedMediaViewer _buildCompactTopActions PopupMenuItem compact overflow Save image Share Info Reply add action icons beside labels _actionIcon" --profile tdd --budget 700`.
- Anchors: `_buildCompactTopActions` ->
  `lib/shared/widgets/media/full_screen_typed_media_viewer.dart:525`;
  `FullScreenTypedMediaViewer` -> graph node reported `unknown`; current source
  resolves the class in the same shared viewer file.
- Surfaced proof/gate files:
  `full_screen_typed_media_viewer.dart`, `media_viewer_item.dart`, generated
  l10n API, and `full_screen_typed_media_viewer_test.dart`.
- Graph gaps requiring source search: exact current popup child, canonical icon
  switch, direct-route preservation test, and host-all discovery were verified
  from current source/scripts because the compact output did not include them.
- Reuse rule: anchors may be handed to review/execution; all conclusions still
  require current-source or command evidence.

## Scope Contract And Guard

In scope:

- Replace only the compact popup item's Text-only child with an icon-plus-label
  row. Reuse `_actionIcon(action)` for the four already-authorized actions.
- Render one 20dp white icon, a 12dp horizontal gap, and the unchanged localized
  label. The icon is directionally leading: left of the label in LTR and right
  of it in RTL.
- Strengthen the existing en/de/ar compact-overflow test to bind each row to
  its exact icon, size/color, and leading adjacency.

Must preserve:

- Exact menu order, localized labels, capability filtering, current-page
  identity, and one callback dispatch -> `TC-308-01` and `TC-308-02`.
- Save/Share/Info/Reply direct-route effects -> `TC-308-03`.
- Ellipsis/top and Forward/Delete bottom geometry, standard-toolbar callers,
  pending fencing, and private suppression -> `TC-308-02` and `TC-308-04`.

Hard `Do not`:

- Do not change `_compactMenuOrder`, `_actionIcon`, `_compactActionLabel`,
  capabilities, keys, popup values, `_dispatch`, or action side effects.
- Do not add Forward/Delete to the popup or apply this menu to outgoing,
  GIF/video, Shared Media, group/announcement, or private/default viewers.
- Do not change l10n strings/generated files, persistence, wire/native code,
  media bytes, or the Plan 307 top/bottom layout.

Deferred / accepted difference:

- Standard toolbars already render icon-only buttons and remain unchanged;
  this request concerns only Plan 307's compact overflow rows.

Dependencies:

- Builds on implemented Plan 307's compact presentation, stable action keys,
  exact menu order, and existing `_actionIcon` mapping.

## Test Contract

| Case | Behavior | Named test/proof | Tier / fixture | HEAD -> GREEN | Mutation | Gate / registration |
|---|---|---|---|---|---|---|
| TC-308-01 | Every compact popup row contains exactly one matching 20dp white icon on the directional leading side of its unchanged label: Download/Save image, iOS Share/Share, outlined Info/Info, and Reply/Reply, in en/de/ar. | `test/shared/widgets/media/full_screen_typed_media_viewer_test.dart::compact overflow lists localized image actions in order and targets the current item` | Widget host / existing two-page compact image fixture, en/de/ar delegates, real PopupMenu | HEAD assertion RED because each keyed PopupMenuItem has zero Icon descendants -> each row has exactly its action's icon, leading geometry, 20dp size, white color, unchanged text and order | Temporarily move the icon after the label -> LTR/RTL leading-geometry assertions re-red; restore exactly | `flutter test test/shared/widgets/media/full_screen_typed_media_viewer_test.dart --plain-name 'compact overflow lists localized image actions in order and targets the current item'`; AUTO (`host-all` glob), executed directly per plan |
| TC-308-02 | Capability filtering, current-page identity, exact action value, and one dispatch remain unchanged with icon rows. | Same strengthened compact-overflow test plus `::compact actions remain capability gated and single dispatch while pending` | `GREEN sentinel` / existing authorized-all and authorized-subset compact fixtures with callback recorders | GREEN on HEAD for labels/order/dispatch/filtering -> remains GREEN after the child-only composition edit | Replace one PopupMenuItem `value` with a sibling action or remove capability filtering -> the named tests red | Exact tests in the shared viewer file; AUTO (`host-all` glob), executed directly per plan |
| TC-308-03 | Save image, Share, Info, and Reply still execute their established real direct-conversation presentation routes. | `test/features/conversation/presentation/screens/conversation_received_media_actions_test.dart::compact image overflow preserves save share info and reply routes` | `GREEN sentinel` / existing two-image real conversation widget fixture with egress/info/quote recorders | GREEN on HEAD -> remains GREEN because keys, values, and callback route are unchanged | Map one popup value to the wrong action -> exact destination/sheet/quote assertions red | `flutter test test/features/conversation/presentation/screens/conversation_received_media_actions_test.dart --plain-name 'compact image overflow preserves save share info and reply routes'`; existing `ONE_TO_ONE_TESTS` and `ONE_TO_ONE_HOST_TESTS`; no registration edit |
| TC-308-04 | Plan 307's top ellipsis, bottom Forward/Delete, safe-area/result geometry, pending/privacy guards, and standard-toolbar default remain unchanged. | `test/shared/widgets/media/full_screen_typed_media_viewer_test.dart` complete suite | `GREEN sentinel` / existing compact LTR/RTL, capability/private, and standard direct/group fixtures | GREEN on HEAD -> complete suite remains GREEN after the PopupMenuItem child edit | Apply the Row outside the compact branch or alter the bottom controls -> existing layout/default/privacy tests red | `flutter test test/shared/widgets/media/full_screen_typed_media_viewer_test.dart`; AUTO (`host-all` glob), executed directly per plan |

### Test Notes

- TC-308-01 must scope icon lookups beneath each keyed
  `PopupMenuItem<MediaViewerAction>`, require exactly one Icon descendant, and
  compare that descendant with the row's own label rectangle. A global
  `find.byIcon` could pass on the viewer's unrelated chrome.
- In LTR the icon rectangle ends before the label begins; in RTL the label
  ends before the icon begins. The gap is 12dp in both directions.

## Implementation Steps

1. Snapshot `git status --short` and preserve all overlapping Plan 303-307
   work. Add the TC-308-01 icon assertions first and record their causal RED.
2. In `_buildCompactTopActions`, replace only the PopupMenuItem's `Text` child
   with a `Row(mainAxisSize: MainAxisSize.min)` containing
   `Icon(_actionIcon(action), size: 20, color: Colors.white)`, a 12dp gap, and
   the existing localized Text. Stop-if the implementation requires changing
   action mapping, capability logic, keys, or dispatch.
3. Run focused GREEN, the complete shared-viewer suite, direct-route sentinel,
   discovery, and the curated 1:1 lane. No registration or l10n generation is
   expected.
4. Run the representative child-order mutation, restore it exactly, rerun the
   causal test GREEN, refresh the app-owned graph once, then run analyzer and
   whitespace hygiene.

## Risks And Blind Spots

- A global icon finder could pass on unrelated Back/More/bottom icons ->
  TC-308-01 scopes one exact Icon beneath each PopupMenuItem.
- A visually correct icon could map to the wrong action -> TC-308-01 binds icon
  data to the keyed row, while TC-308-02/03 retain callback/effect assertions.
- RTL could put the icon on the trailing side -> TC-308-01 compares row-local
  rectangles in Arabic as well as LTR locales.
- Longer German or Arabic labels could overflow after adding the icon -> the
  existing en/de/ar popup fixture pumps the real menu and must remain exception-free.
- Lifecycle / derived-state durability: N/A — immutable popup children are
  rebuilt from the current MediaViewerItem and store no state.
- Sibling-surface consistency: standard/default viewers are deliberately
  unchanged and locked by TC-308-04.
- Destructive-action side effects: N/A — Delete remains outside the popup and
  no action side effect changes.
- Invariant re-verification under new transitions: page swipe/current-item and
  pending rebuilds remain locked by TC-308-02/04.

## Gate Cadence

- Per-plan closure: focused causal test, complete shared-viewer suite, exact
  direct-route preservation test, host-all discovery for the shared file, and
  the affected curated `1to1` lane. No core/feature/performance family sweep is
  justified for a child-only shared-widget edit.
- Do not run full `host-all` for this individual plan. Run
  `./scripts/run_host_test_gates.sh host-all` once after the 1:1 media
  presentation batch (Plans 303-308, after still-open Plan 305) completes, and
  once at final rollout/release closure.
- Shared tests outside feature/core globs run directly through the exact
  commands below; registration is verified in list mode only.

## Acceptance Gates

```bash
# Snapshot before execution; preserve unrelated and overlapping dirty changes.
git status --short

# Causal RED before production edits; expect non-zero because every keyed
# compact PopupMenuItem currently has zero Icon descendants.
flutter test test/shared/widgets/media/full_screen_typed_media_viewer_test.dart \
  --plain-name 'compact overflow lists localized image actions in order and targets the current item'

# Focused and complete GREEN; expect exit 0 and zero failed tests.
flutter test test/shared/widgets/media/full_screen_typed_media_viewer_test.dart \
  --plain-name 'compact overflow lists localized image actions in order and targets the current item'
flutter test test/shared/widgets/media/full_screen_typed_media_viewer_test.dart

# Exact direct-route preservation; expect unchanged Save/Share/Info/Reply effects.
flutter test test/features/conversation/presentation/screens/conversation_received_media_actions_test.dart \
  --plain-name 'compact image overflow preserves save share info and reply routes'

# Registration discovery only; expect the shared test file to be selected.
./scripts/run_host_test_gates.sh host-all --list \
  --only test/shared/widgets/media/full_screen_typed_media_viewer_test.dart

# Affected curated lane; expect exit 0 and zero failed Flutter/Go cases.
./scripts/run_test_gates.sh 1to1

# App-owned graph and hygiene; expect successful incremental refresh, no
# analyzer issues attributable to this plan, and no whitespace errors.
./graphify-arch/refresh_arch_graph.sh --incremental
flutter analyze
git diff --check
```

## Execution Interpretation And Done Criteria

- Expected RED: TC-308-01 fails only on absent PopupMenuItem Icon descendants;
  its existing label/order/current-item assertions remain green.
- Green sentinels: capability/private/current dispatch, direct action effects,
  and the complete Plan 307 layout/default suite remain green.
- Pre-existing dirty tree / known failure: overlapping Plans 303-307, index,
  Graphify output, generated l10n, native/evidence, and test edits are baseline
  and must not be reverted. The two named planning probes passed.
- Environment blocker: none; closure is host-only.
- Scope drift: any requested icon redesign outside the four popup rows, action
  behavior change, l10n edit, or device/native requirement blocks execution.

- [x] Every behavior has a named test or justified proof.
- [x] Causal RED, focused GREEN, and representative mutation re-red are recorded.
- [x] Preservation and named gates pass with semantic outcomes.
- [x] Existing harness registration is verified without a script edit.
- [x] `flutter analyze` has no new issues; `git diff --check` is clean.
- [x] Scope Contract And Guard is respected.

## Handoff

- First causal RED command:
  `flutter test test/shared/widgets/media/full_screen_typed_media_viewer_test.dart --plain-name 'compact overflow lists localized image actions in order and targets the current item'`.
- Preservation command:
  `flutter test test/features/conversation/presentation/screens/conversation_received_media_actions_test.dart --plain-name 'compact image overflow preserves save share info and reply routes'`.
- Manual registration: none; the feature test is already in the 1:1 arrays and
  the shared test is host-all glob-discovered.
- Migration: none.
- Boundary closure: host-only widget/application proof; no simulator/device/relay leg.
- Unresolved evidence: none.

## Reviewer Findings

- Verdict: `ready`; plan classification `implementation-ready`; core bet
  `confirmed`; disposition `execute`.
- L1 evidence/classification: `clear` after correcting the graph's unresolved
  class anchor; current source still confirms the Text-only gap and canonical
  four-action icon mapping.
- L2 causality: `clear`; TC-308-01 scopes exactly one Icon beneath each keyed
  PopupMenuItem and compares that row-local icon with its own label, so Back,
  More, or bottom icons cannot satisfy it. Exact data plus LTR/RTL geometry
  rejects a constant icon and trailing placement.
- L3 bypass/scope: `clear`; source search finds one production
  `_buildCompactTopActions`/`PopupMenuItem<MediaViewerAction>` builder and one
  production compact selector in the direct conversation. Standard/private
  siblings retain explicit sentinels.
- L4 gates: `clear`; the shared test is host-all glob-discovered and executed
  directly, the direct test is in both 1:1 arrays, full host-all is correctly
  deferred to the named presentation wave/final closure, and no registration
  edit is needed.
- L5 boundary/reversibility: `N/A` — immutable widget composition only; no
  persistence, destructive state, native callback, relay, crypto, or device
  claim.
- Blind-spot sweep: B2, B3, B4, and B9 were triggered and are clear under the
  source/test evidence above; B1, B5-B8, and B10 are N/A. Flutter's Icon with
  no semantic label is already wrapped in `ExcludeSemantics`, so decorative
  icons do not introduce duplicate menu labels.
- User decisions required: none.

## Execution Progress

| Time | Phase | Files | Last command/result | Current evidence | Decision/blocker | Next |
|---|---|---|---|---|---|---|
| 2026-07-31 18:23 CEST | Dirty-tree grounding and RED | Shared viewer and its existing compact-overflow test; overlapping Plans 303-307 preserved | Exact TC-308-01 command exited `1`: Save's keyed PopupMenuItem had zero Icon descendants | The existing popup opened and the failure landed solely on the requested missing icon. | Expected causal RED; no blocker. | Implement the reviewed child-only change. |
| 2026-07-31 18:24 CEST | Implementation and focused GREEN | `full_screen_typed_media_viewer.dart`; `full_screen_typed_media_viewer_test.dart` | Exact causal test, complete shared-viewer file (`18/18`), and exact direct Save/Share/Info/Reply route sentinel all exited `0` | Each authorized row now uses the canonical action icon at 20dp/white with a 12dp directional-leading gap; labels, order, current identity, effects, bottom controls, default/private behavior all remain green. | Scope contract satisfied with no l10n, callback, route, or gate edit. | Mutation and discovery. |
| 2026-07-31 18:25 CEST | Mutation and discovery | Same production/test files; existing host gate registry | Temporarily moving Text before Icon made TC-308-01 exit `1` on the leading-gap assertion (`actual -173` vs `12`); exact restoration returned it to GREEN. Host-all list mode selected the shared test as item 1239. | The causal test rejects trailing placement in the real popup and no mutation remains. | None. | Run affected curated lane. |
| 2026-07-31 18:27 CEST | Curated lane | Existing `1to1` Flutter and relay inventories | `./scripts/run_test_gates.sh 1to1` exited `0`: `2523/2523` Flutter tests, relay Go toolchain contract, and `github.com/mknoon/relay-server` passed | Complete affected 1:1 dependency lane is green. | Full host-all correctly deferred by cadence. | Graph and hygiene closure. |
| 2026-07-31 18:30 CEST | Graph, analysis, and closure | Two changed app/test files; architecture graph; current dirty diff | Incremental Graphify refresh exited `0` (`2 changed code`, `2915 unchanged`, `63421` nodes, `96792` edges); `flutter analyze` reported `No issues found`; targeted format check and `git diff --check` exited `0` | Host closure is complete with no device, migration, native, persistence, or transport obligation. | None. | Implemented / host-green. |
