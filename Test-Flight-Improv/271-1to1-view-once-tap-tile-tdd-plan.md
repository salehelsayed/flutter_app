# 271 - Direct received View once tap-tile extension

Status: implemented and host-green (2026-07-24)
Type: Modification
Spec: free-text intent — user request 2026-07-24 to extend the successful Plan 270 UI/UX to View once in 1:1 chats only
Classification: implemented
Closure tier: host

## Planning Progress

| Time | Role | Files inspected | Decision/blocker | Next action |
|---|---|---|---|---|
| 2026-07-24 | Evidence Collector | Plan 270; `direct_private_media_viewer.dart`; `conversation_screen.dart`; `conversation_wired.dart`; viewer controller/lifecycle engine; direct viewer/tile/continuity/action/card tests; group sentinel; `ONE_TO_ONE_TESTS`; Plan-234 device-local harness/criteria/runner | View once is the only received image/video mode excluded from the Plan-270 tap predicate. Its separate button is the sole initiation control; there is no second confirmation dialog. The existing tile helper, typed launcher, lifecycle, copy, and safety tests are reusable | Lock the accepted one-step tile UX and build one contract |
| 2026-07-24 | Planner | same + live device discovery | Keep the visible `View-once photo/video` title and `You can only view this once.` warning; remove only the separate button; use the 150px tile as the sole one-step control. Preserve null-open, legacy GIF, outgoing, failure/terminal, group, lifecycle, and native behavior | Emit host-first plan with the existing device-local harness replay |
| 2026-07-24 | `$tdd-review` counterexample verifier + main-agent synthesis | Plan 271; current viewer/tile/continuity/action/card/lifecycle tests; controller classifier; direct/group callers; 1:1 and host gate scripts; device harness/criteria/runner | Initial verdict `plan-fixes-required`, core bet confirmed. Required deltas: invoke the semantics action, prove View once gesture discrimination directly, make the pause/resume continuity leg enter download, tighten outgoing callback counts and lifecycle exit evidence, assign wave `host-all`, and close tile-only/no-pixel negative gaps | Apply only verified deltas in this plan, then rerun all five lenses |

## Problem And Evidence

- Behavior to improve: an openable received View once image/video in a direct 1:1 chat still renders an inert 88px visual plus a separate `View photo/video` button, while the adjacent protected/disappearing modes now use the clearer 150px visual tile as their open affordance.
- Impact: the three received private-media modes are visually inconsistent, and View once retains the redundant action row that the user explicitly asked to retire after accepting Plan 270's tap-tile design.
- Confirmed current gap: `DirectPrivateMediaOpenPlaceholder.build` at `lib/features/conversation/presentation/screens/direct_private_media_viewer.dart:758-764` requires image/video, non-null `onOpen`, and mode protected/disappearing. `PrivateMediaMode.viewOnce` is deliberately absent, so it falls through to the 88px/title/body/`private-media-open` button branch at `:765-816`.
- Confirmed reusable mechanism: `PrivateMediaVisualCard` already delegates only a non-null `onTap` to `_PrivateMediaTappableTile` (`:499-529`). That helper owns the 150px tile, 0.975/120ms press feedback, in-tile spinner/dim state, disabled opening behavior, and one explicit labeled semantics button (`:580-690`).
- Confirmed open path: `ConversationScreen._openPrivateMediaFromConversation` at `lib/features/conversation/presentation/screens/conversation_screen.dart:1610-1672` already provides exact-identity single-flight, download continuity revalidation, typed-launcher routing, and truthful failure projection. The wired launcher/controller requalifies authority and owns View once lease/protection/settlement; none of those seams need modification.
- Existing coverage: `direct_private_media_viewer_test.dart::view-once placeholder states single view` currently locks the old inert 88px tile and button; all four `direct_private_media_continuity_test.dart` cases exercise a real `ConversationScreen` View once fixture through the old button, and the first already sends two rapid taps while download is held. Plan 270's tile file proves press, gesture, opening, and structural semantics behavior for the protected helper.
- Missing coverage confirmed by review: no test allows View once through the tap-tile mode predicate; no image/video/legacy-GIF View once matrix exists; the semantics node advertises tap without any test invoking that independent action; title/body tap-inertness and View-once-specific long-press/swipe/cancel behavior are unproved; the pause/resume continuity leg can pass without starting download; outgoing preservation uses non-exact callback counts; the lifecycle row omits the actual exit classifier; the no-pixel helper misses a direct `DecoratedBox`; and the device-local support harness still probes the incoming View once `private-media-open` button.
- Refuted findings:
  - “View once already has a confirmation dialog.” Refuted: there is no dialog or two-step flow. The separate `FilledButton` is the sole activation control, and its callback opens immediately (`direct_private_media_viewer_test.dart:1365-1410`).
  - “Nothing irreversible can happen before first frame.” Refuted: only the controller's enumerated pre-frame rollback exits restore availability; other settlement paths fail closed. The existing lifecycle tests, not a new UI modal, remain authoritative.
  - “The device harness taps the incoming View once button.” Refuted: it only checks that incoming action is visible at `integration_test/direct_private_media_device_local_journey_harness.dart:381-406`; the actual tap at `:794-808` is an outgoing protected Plan-262 fixture.
- Unresolved findings: none. The user explicitly selected inclusion after Plan 270, and the accepted difference below locks the one-step behavior.
- Affected production, test, and gate files:
  - Production: `lib/features/conversation/presentation/screens/direct_private_media_viewer.dart` only.
  - Host tests: `direct_private_media_viewer_test.dart`, `direct_private_media_tile_tap_test.dart`, `direct_private_media_continuity_test.dart`, `conversation_received_media_actions_test.dart`, and only narrowly necessary card/sender sentinels.
  - Supporting device harness: `integration_test/direct_private_media_device_local_journey_harness.dart`; keep its schema, criteria, runner, and discovery registration unchanged.
  - No ARB/generated-l10n, composer, policy, controller/lifecycle, repository/DB, group production, Go, relay, Android, or iOS production edit.

## Graph Grounding Snapshot

- Graph fingerprint / freshness: `20e8a7d24a04e87f`; stale only at generated `ios/Flutter/flutter_export_environment.sh`, which is outside this presentation-only plan.
- Query / profile: `python3 graphify-arch/tdd_context.py query "Direct 1:1 View once tap-tile UI redesign: DirectPrivateMediaOpenPlaceholder PrivateMediaMode.viewOnce _PrivateMediaTappableTile private-media-open confirmation direct_private_media_viewer_test.dart ONE_TO_ONE_TESTS" --profile tdd --budget 700`.
- Review query / profile: `python3 graphify-arch/tdd_context.py query "Plan 271 counterexample audit direct 1:1 View once tap tile: DirectPrivateMediaOpenPlaceholder tapTileMode PrivateMediaMode.viewOnce _PrivateMediaTappableTile onOpen opening double tap semantics gesture ConversationScreen _openPrivateMediaFromConversation direct_private_media_continuity_test direct_private_media_device_local_journey_harness ONE_TO_ONE_TESTS" --profile review --budget 800`; same fingerprint and freshness result.
- Anchors: `DirectPrivateMediaOpenPlaceholder` → `lib/features/conversation/presentation/screens/direct_private_media_viewer.dart:738`; `ONE_TO_ONE_TESTS` → `scripts/run_test_gates.sh:21`; viewer proof candidate → `test/features/conversation/presentation/screens/direct_private_media_viewer_test.dart`.
- Surfaced proof/gate files: `direct_private_media_viewer.dart`, `conversation_screen.dart`, `direct_private_media_viewer_test.dart`, and `scripts/run_test_gates.sh`.
- Graph gaps requiring source search: the absence of a real confirmation dialog, exact View once continuity selectors, outgoing/group branch separation, first-frame settlement semantics, and the device-local incoming-action probe were verified in current source.
- Reuse rule: these anchors may be handed to review/execution; all conclusions still require current-source or command evidence.

## Scope Contract And Guard

In scope:

- Received, openable, direct 1:1 View once image/video only:
  - add `PrivateMediaMode.viewOnce` to the existing `tapTileMode` predicate;
  - retain the visible media-specific `View-once photo/video` title;
  - retain the exact `You can only view this once.` body and existing translations;
  - remove the separate `private-media-open` `FilledButton`;
  - make the existing no-pixel `private-media-card-visual` a 150px, one-step open control;
  - keep the retained visible title and one-view warning pointer-inert so taps outside the visual tile cannot start an irreversible open;
  - expose the title once as the tile's semantic button label while excluding the duplicate visible title from semantics;
  - reuse the existing in-tile opening spinner/dim/disabled state, press feedback, long-press coexistence, and swipe-to-quote behavior.
- Update the existing direct widget/continuity/action tests from the old button handle to the tile and migrate the device-local harness's incoming View once visibility probe to the scoped tile.

Must preserve:

- `onOpen == null` received View once → visible title/body, inert 88px tile, and present disabled `private-media-open` button (`TC-05`).
- Legacy direct private View once GIF → compatibility-only 88px/title/body/button branch; no tap tile (`TC-02`).
- Received protected/disappearing image/video → Plan-270 layout, copy, semantics, and gestures unchanged (`TC-09`).
- Direct outgoing View once one-more-look → sender card and `private-media-open` button unchanged (`TC-08`).
- Consumed/expired/corrupt/unsupported/open-failure rows → existing terminal/failure projections and truthful rollback copy (`TC-08`).
- View once authority, lease, native protection, first-frame, settlement, cleanup, and rollback availability → existing controller/lifecycle tests (`TC-13`).
- Group View once → independent whole-bubble open plus 88px title/action card unchanged (`TC-10`).
- No private pixels, `Image`, `RawImage`, `MediaGrid`, or decoration image enter the card (`TC-11`).

Hard `Do not`:

- Do not add a confirmation dialog, bottom sheet, second tap, or new copy.
- Do not remove or demote the visible View once title or one-view warning.
- Do not broaden to GIF, null-open/denied rows, outgoing 1:1, groups, terminal/failure states, or ordinary media.
- Do not change `ConversationScreen._openPrivateMediaFromConversation`, the wired launcher, viewer controller, lifecycle engine, policy/composer/send/retry code, DB/schema, native protection, or relay/Go code.
- Do not change the device-local artifact schema/criteria or its outgoing protected tap.

Deferred / accepted difference:

- Accepted UX difference: the old dedicated button was the only “confirmation guard.” Per the user's request to include View once in the successful Plan-270 design, the warned and semantically labeled tile becomes the equally explicit, one-step activation control. There is no new modal. The unchanged lifecycle remains fail-closed after activation.
- Device/relay expansion: none. The existing device-local support journey is replayed only because its incoming View once selector changes; it makes no real-relay, cross-device delivery, iOS, or new native-protection claim.

Dependencies:

- Plan 270 implementation commit `0813292de` supplies `_PrivateMediaTappableTile`, its tests, and the image/video/openability guards. Stop and replan if execution no longer starts from an equivalent landed helper contract.

## Test Contract

| Case | Behavior | Named test/proof | Tier / fixture | HEAD -> GREEN | Mutation | Gate / registration |
|---|---|---|---|---|---|---|
| TC-01 | Openable received View once photo uses the warned tile as its sole control; retained copy is not an activation surface | `test/features/conversation/presentation/screens/direct_private_media_viewer_test.dart::view-once placeholder uses warned tap tile as its sole open control` | Widget / localized `DirectPrivateMediaOpenPlaceholder`, callback spy | Causal RED on HEAD: visible title/body, inert 88px tile, and `View photo` button; visual tap count 0 → GREEN: title/body retained, button absent, tile 150px; tapping title then warning leaves count 0, and one visual-tile tap makes it exactly 1 | remove View once from `tapTileMode`, or wrap the whole card/title/body in an open handler → TC-01 red | `flutter test test/features/conversation/presentation/screens/direct_private_media_viewer_test.dart --plain-name 'view-once placeholder uses warned tap tile as its sole open control'`; existing `ONE_TO_ONE_TESTS` |
| TC-02 | View once tap-tile kind boundary is image/video only; legacy GIF stays compatible | `test/features/conversation/presentation/screens/direct_private_media_tile_tap_test.dart::view-once tap tile covers image and video while legacy GIF keeps the old branch` | Widget / image, video, and defensive legacy-GIF table | Causal RED on HEAD: image/video remain 88px/button and inert → GREEN: image/video are 150px semantic tiles with `View-once photo/video`, no old button, and one open; GIF remains 88px/title/body/button and tile-inert | remove video or the `tapTileKind` guard → TC-02 red | `flutter test test/features/conversation/presentation/screens/direct_private_media_tile_tap_test.dart --plain-name 'view-once tap tile covers image and video while legacy GIF keeps the old branch'`; existing `ONE_TO_ONE_TESTS` |
| TC-03 | Enabled/opening View once tile has one truthful, executable accessible action and no duplicate title/spinner action | `test/features/conversation/presentation/screens/direct_private_media_tile_tap_test.dart::view-once tile is one warned semantic button and opening is disabled in tile` | Widget / semantics handle and `WidgetTester.semantics.performAction`, normal then `opening:true` | Causal RED on HEAD: action lives on the separate button; visual is not an actionable button → GREEN: exactly one enabled `View-once photo` tile node has tap, performing its `SemanticsAction.tap` invokes `onOpen` exactly once, and the visible title is announced once; the opening node is disabled with localized value and no `SemanticsAction.tap`, opacity is below 1, spinner descendants are excluded, and a pointer tap leaves the count at 1 | replace `Semantics.onTap` with a no-op/wrong/double callback, remove title exclusion, or restore an opening callback → TC-03 red | `flutter test test/features/conversation/presentation/screens/direct_private_media_tile_tap_test.dart --plain-name 'view-once tile is one warned semantic button and opening is disabled in tile'`; existing `ONE_TO_ONE_TESTS` |
| TC-04 | View once directly inherits press/cancel feedback and event-discriminated ancestor long-press/swipe behavior | extend existing `direct_private_media_tile_tap_test.dart::tap feedback scales to 0.975 and resets on up and cancel` and `::tile tap preserves ancestor long press and swipe to quote` with explicit `PrivateMediaPolicy.viewOnce()` cases | Widget / View once gesture arena with open, long-press, and quote spies | Causal RED after adding View once cases on HEAD: its inert 88px visual has no tile scale/open path while protected passes → GREEN: View once pointer-down scales to 0.975, up/cancel returns to 1, tap adds exactly one open, long-press adds only one ancestor long-press and no open, and swipe adds only one quote and no open | route View once through a sibling wrapper, omit cancel reset, or add a competing long-press/swipe recognizer → TC-04 red | `flutter test test/features/conversation/presentation/screens/direct_private_media_tile_tap_test.dart`; existing `ONE_TO_ONE_TESTS` |
| TC-05 | Non-openable View once retains the disabled legacy layout | extend and rename `direct_private_media_tile_tap_test.dart::not-openable protected card keeps title 88px tile and disabled button` to `::not-openable protected and view-once cards keep title 88px tile and disabled button` | GREEN sentinel / null `onOpen`, protected + View once | GREEN sentinel after adding the View once row on HEAD → remains visible-title/body, 88px non-button tile, and disabled old button | remove the `onOpen != null` gate or hide the disabled fallback → TC-05 red | `flutter test test/features/conversation/presentation/screens/direct_private_media_tile_tap_test.dart --plain-name 'not-openable protected and view-once cards keep title 88px tile and disabled button'`; existing `ONE_TO_ONE_TESTS` |
| TC-06 | Real direct screen tile reaches the exact typed private launcher, never an ordinary viewer | `test/features/conversation/presentation/screens/conversation_received_media_actions_test.dart::received view-once tile reaches typed private launcher and never enters ordinary viewers` | Widget/host integration / real `ConversationScreen`, current-row action decision, typed identity spy | Causal RED on HEAD: tile tap invokes nothing → GREEN: exact message/attachment identity and valid continuity reach typed launcher once; ordinary viewer builders remain unused | drop View once mode wiring or route through ordinary viewer → TC-06 red | `flutter test test/features/conversation/presentation/screens/conversation_received_media_actions_test.dart --plain-name 'received view-once tile reaches typed private launcher and never enters ordinary viewers'`; existing `ONE_TO_ONE_TESTS` |
| TC-07 | Two rapid tile taps preserve one download/open single-flight, route/app continuity, rollback, and retry truth | rename and migrate `direct_private_media_continuity_test.dart::one tap downloads then auto-continues under one single-flight` to `::rapid double tap downloads then auto-continues under one single-flight`; migrate `::download-held route cover invalidates auto-open and a later tap requalifies`; strengthen/migrate `::pause-resume during download cannot auto-open`; migrate `::typed pre-frame failure renders truthful retry and clears it` | Widget/host integration / `ConversationScreen`, held download gates, typed results, route/lifecycle generation | Causal RED after selector migration on HEAD: the inert tile cannot start download; the rapid-double and pause/resume legs each assert one download plus the in-tile spinner before invalidation, while the route-cover leg retains its exact download/retry counts → GREEN: two rapid tile taps produce exactly one download and one launch, route/app invalidation cannot auto-open, later retry requalifies, and typed failure/retry counts remain exact | bypass `_privateOpenInFlight`, remove the pre-invalidation download/spinner discriminator, skip continuity recheck, or misproject the typed result → TC-07 red | `flutter test test/features/conversation/presentation/screens/direct_private_media_continuity_test.dart`; exact per-plan, AUTO later `feature-host-all`, intentionally not added to `ONE_TO_ONE_TESTS` |
| TC-08 | Outgoing View once and failure/terminal presentation stay unchanged | existing `direct_private_media_viewer_test.dart::sender protected and view-once expose one-more-look while disappearing and missing local media do not`, tightened to exact cumulative callback counts; `::typed open failure copy claims safety only for exact rollback`; `::sender-consumed terminal is generic after attachment cleanup`; `::attachmentless consumed and expired parents render generic terminal actions without synthetic media`; `::private open opening viewing terminal unsupported and capture copy are localized small and RTL safe` | GREEN sentinel / outgoing, rollback, consumed/expired/unsupported fixtures | GREEN sentinel on HEAD → protected tap makes count 1, View once tap makes it 2, disappearing/missing rows expose no button and leave it 2; sender body, failure retry copy, and terminal generic states remain exact | make either outgoing callback a no-op/double invocation, expose an excluded button, or broaden the incoming predicate into outgoing/failure branches → TC-08 red | `flutter test test/features/conversation/presentation/screens/direct_private_media_viewer_test.dart`; existing `ONE_TO_ONE_TESTS` |
| TC-09 | Plan-270 protected/disappearing tile behavior is preserved | existing `direct_private_media_tile_tap_test.dart::protected and disappearing tap tile covers image and video while legacy GIF keeps the old branch`; `::opening tile is dimmed busy disabled and has no tap or child spinner semantics`; `::enabled protected tile is one labeled semantic button with a tap action` | GREEN sentinel / protected/disappearing × image/video | GREEN sentinel on HEAD → remains green byte-for-byte in behavior | replace rather than extend `tapTileMode`, or alter title/body logic → TC-09 red | `flutter test test/features/conversation/presentation/screens/direct_private_media_tile_tap_test.dart`; existing `ONE_TO_ONE_TESTS` |
| TC-10 | Group View once stays on its independent 88px title/action and whole-bubble open paths | existing `test/features/groups/presentation/group_private_media_capabilities_test.dart::GPL-09 active private bubble exposes only the dedicated open path` | GREEN sentinel / group widget | GREEN sentinel on HEAD → title/body, 88px visual, inner action, and whole-bubble title tap remain | modify shared card behavior without the direct `onTap` gate or edit group production → TC-10 red | `flutter test test/features/groups/presentation/group_private_media_capabilities_test.dart --plain-name 'GPL-09 active private bubble exposes only the dedicated open path'`; existing `GROUP_TESTS`, exact only for this plan |
| TC-11 | No-pixel cohesive card structure and existing View once warning copy remain | extend existing `test/features/conversation/presentation/screens/direct_private_media_card_test.dart::card shows no-pixel visual header and media-kind title` so its scoped helper inspects direct `DecoratedBox` as well as `Container` decorations; Plan-271 `TC-01::view-once placeholder uses warned tap tile as its sole open control`; `TC-02::view-once tap tile covers image and video while legacy GIF keeps the old branch`; `test/l10n/l10n_integrity_test.dart::ARB files have identical non-empty key and placeholder sets` | GREEN sentinel / widget + ARB parity plus zero-diff l10n scope guard | GREEN sentinel on HEAD → no scoped `Image`, `RawImage`, `MediaGrid`, `Container` decoration image, or direct `DecoratedBox` decoration image; visible warning/title and ARB key/placeholder parity remain; all en/ar/de ARB/generated values stay byte-unchanged | inject a specified pixel-bearing child/decoration or remove title/body → card/TC-01/02 red; add/drop an ARB key/placeholder → integrity test red; value-only l10n edits are blocked by the `lib/l10n` zero-diff guard | `flutter test test/features/conversation/presentation/screens/direct_private_media_card_test.dart test/l10n/l10n_integrity_test.dart` plus `git diff --quiet HEAD -- lib/l10n`; card is in `ONE_TO_ONE_TESTS`, l10n exact |
| TC-12 | Existing device-local production fixture recognizes the incoming View once tile and rejects the retired button | `integration_test/direct_private_media_device_local_journey_harness.dart::instrumented Plan 234 device-local journey` production-card phase; unchanged strict criteria test | Conditional device-only supporting proof / availability-bounded USB physical Android + Android emulator, fully automated | Supporting maintenance on HEAD: the current harness is GREEN for the old button and becomes stale when production changes → after the coordinated scoped-selector update, GREEN proves the incoming 150px tile is mounted, the old button is absent, and `incomingActionVisible` remains truthfully derived; outgoing protected tap and artifact schema remain unchanged | remove View once from the predicate or restore the old button after the coordinated harness update → device phase red | Re-resolve and pin the pair, then run `dart run integration_test/scripts/run_direct_private_media_device_local_journey.dart --sender 21071FDF600CSC --recipient emulator-5554 --artifact-dir "$PLAN271_ARTIFACT_DIR"` while those IDs remain live; existing discovery support/runner + criteria already in `ONE_TO_ONE_TESTS`; missing target class is `N/A (target unavailable by project policy)` |
| TC-13 | View once durable opening lease, exactly-one first frame, enumerated pre-frame rollback, close/lifecycle fail-closed settlement, and cleanup remain unchanged | existing `direct_private_media_viewer_test.dart::pre-frame route and decode exits roll back while background fails closed`; rename `::view once protects before bytes records one first frame and terminalizes on every non-decode exit` to `::view once protects before bytes records one first frame and close terminalizes before or after first frame`; rename `::only proven pre-first-frame decode failure rolls view once back to available` to `::proven pre-first-frame decode failure rolls view once back to available` | GREEN sentinel / controller + lifecycle spies across prepare, first frame, five rollback reasons, close, four lifecycle fail-closed reasons, and cleanup | GREEN sentinel on HEAD → lease acquisition precedes bytes, first frame records once, pre-frame decode/route-push/route-continuity/protection-enter/revalidation exits roll back, close/background/capture/dispose/app-lifecycle exits terminalize, terminal cleanup occurs, and the rolled-back row is available | allow duplicate first-frame recording, alter the five-reason rollback classifier, make close/lifecycle exits roll back, make proven pre-frame decode failure consume, or skip terminal cleanup → TC-13 red | `flutter test test/features/conversation/presentation/screens/direct_private_media_viewer_test.dart --plain-name 'pre-frame route and decode exits roll back while background fails closed' && flutter test test/features/conversation/presentation/screens/direct_private_media_viewer_test.dart --plain-name 'view once protects before bytes records one first frame and close terminalizes before or after first frame' && flutter test test/features/conversation/presentation/screens/direct_private_media_viewer_test.dart --plain-name 'proven pre-first-frame decode failure rolls view once back to available'`; existing `ONE_TO_ONE_TESTS` |

### Test Notes

- TC-01: tap the visible `private-media-mode-label` and exact one-view warning before tapping the visual; both copy taps must leave the callback count at zero.
- TC-03: use `tester.semantics.performAction(<the one enabled View-once tile semantics node>, SemanticsAction.tap)` rather than merely inspecting `hasAction`; in the opening state assert that the action is absent, then pointer-tap the tile and prove the callback count is unchanged.
- TC-04: extend both existing gesture tests with an explicit View once fixture and exact per-event counts; a long-press or swipe must not increment the open count.
- TC-07: replace only the initial/open-retry handle with `private-media-card-visual`, preserve both rapid taps in the renamed first test, and add a download counter plus in-tile spinner assertion before the pause/resume invalidation. After open failure, `private-media-try-again` remains the recovery handle.
- TC-08: replace `opens > 0` with exact cumulative counts `1`, then `2`, and retain `2` after disappearing/missing rows.
- TC-11: the scoped no-pixel helper must inspect a directly inserted `DecoratedBox.decoration` in addition to the existing `Container` decoration fields; do not widen production.
- TC-12: keep the artifact field name `incomingActionVisible`; it means “the production incoming open affordance is visibly mounted,” not specifically a `FilledButton`. Derive it from the scoped tile, locally assert 150px and old-button absence, and do not alter schema or criteria.
- TC-13: rename only the two overclaiming test descriptions; include the existing five-reason rollback/four-reason fail-closed classifier without changing controller/lifecycle production.

## Implementation Steps

1. Snapshot `git status --short` and preserve the pre-existing unrelated modifications to `docker-ws/run_fresh_three_phones_result.txt` and `info.plist`. Author TC-01/02/03/04/06, migrate and strengthen TC-07, tighten the TC-08/11/13 sentinels, and migrate the TC-12 harness expectation before production.
2. Run every causal RED. Confirm failure is the current View once exclusion: 88px/inert visual, present button, no pointer/semantic tile callback, no View-once tile scale, and no download—not a fixture or localization failure. The strengthened TC-08/11/13 rows must stay GREEN on HEAD.
3. In `DirectPrivateMediaOpenPlaceholder.build`, extend only `tapTileMode` with `labeledPolicy?.mode == PrivateMediaMode.viewOnce`. Do not alter `tapTileKind`, `onOpen != null`, the protected-only title-null condition, body switch, `_PrivateMediaTappableTile`, or any call site/controller.
4. Update the device-local incoming visibility probe to use its scoped `private-media-card-visual`, assert 150px and no scoped `private-media-open`, and leave its outgoing protected tap, artifact field/schema, criteria, runner, and discovery registration unchanged.
5. Run focused GREEN, the exact group/outgoing/lifecycle/no-pixel sentinels, registration/discovery checks, `1to1`, and the conditional live device-local runner.
6. After the coherent app-owned source change, run `./graphify-arch/refresh_arch_graph.sh --incremental` exactly once and record the refreshed fingerprint/output.
7. Run analyzer, scope/diff hygiene, and record representative mutation re-red evidence. Stop if any production file other than `direct_private_media_viewer.dart` is needed.

## Risks And Blind Spots

- Enlarged one-shot activation target: the old button is intentionally replaced by the tile, and some settlement paths can terminalize without a rendered first frame → guarded by retained pointer-inert title/body and tile-only callback counts in TC-01, executable semantics in TC-03, and unchanged lifecycle TC-13.
- Duplicate/dead accessibility action: structural semantics can look correct while invoking a no-op or duplicate callback; visible title plus tile label can also announce twice, or an opening spinner can leak a second node → TC-03 invokes the semantic action and discriminates enabled/opening counts.
- Gesture regression: a View-once-specific wrapper could consume long-press/swipe or leave scale stuck after cancel while protected tests remain green → TC-04 runs every gesture leg directly with View once.
- Lifecycle / derived-state durability: no durable-state reconstruction or lifecycle transition changes; TC-13 reverifies prepare/first-frame/settlement/rollback state, while TC-07 keeps the existing ConversationScreen route/app requalification path.
- Sibling-surface consistency: protected/disappearing TC-09, outgoing/failure TC-08, null-open/GIF TC-02/05, and group TC-10.
- Destructive-action side effects: View once activation can consume by design; no delete/cleanup transition changes. TC-13 asserts terminal consumption/cleanup and the narrow rollback discriminator.
- Invariant re-verification under new transitions: N/A — this plan introduces no lifecycle state or transition; it reaches the same typed callback from a new gesture surface. TC-07 still exercises route/app requalification, and TC-13 owns settlement invariants.
- Harness drift: the accepted Plan-234 device-local proof currently names the retired button → TC-12 updates only the incoming probe and replays the same strict runner.

## Gate Cadence

- Per-plan closure: focused TC-01..13 files, exact outgoing/group/lifecycle/no-pixel/l10n sentinels, curated `1to1`, and the conditional availability-bounded device-local support journey because its incoming selector changes.
- Do not run `groups`, `core-host-all`, `feature-host-all`, performance, or full `host-all` for this individual plan. Group production is untouched and its single exact sentinel is sufficient.
- Wave owner: immediately after Plan 271's individual closure, the Plan 271 executor runs the separate aggregate command below for the completed direct private-media presentation wave containing Plans 270–271. The wave cannot be declared closed until it passes. This is not a per-plan acceptance gate. Final rollout/release runs full `host-all` again.
- Shared tests outside the curated 1:1 list: run `direct_private_media_continuity_test.dart`, `group_private_media_capabilities_test.dart` by exact name, and `l10n_integrity_test.dart` directly; their later host-all registration does not widen this plan's cadence.

### Post-Plan Wave Closure

```bash
# Separate Plans 270–271 wave aggregate; run only after Plan 271 per-plan GREEN.
# Expect exit 0 and zero failed host tests. Record separately from Plan 271.
./scripts/run_host_test_gates.sh host-all
```

Final rollout/release owns one additional full `host-all` run; it may not reuse the wave result.

## Device/Relay Proof Profile

- Profile: paired-device supporting preservation.
- Boundary being proven: the already-required Plan-234 device-local harness still mounts the production `ConversationScreen` incoming View once affordance from device-local SQLCipher-produced fixture state after its selector migration. This is not a new OS callback, native-protection, cross-device delivery, or relay claim.
- Live availability check: `flutter devices --machine`, `adb devices`, and `xcrun simctl list devices available` on 2026-07-24 found USB Pixel 6 `21071FDF600CSC`, Android emulators `emulator-5554`/`emulator-5556`, three physical iPhones, and available iOS simulators.
- Required setup: re-run `flutter devices --machine` and `adb devices` immediately before execution, then explicitly pin one discovered USB physical Android as sender and one discovered Android emulator as recipient. Use `21071FDF600CSC` + `emulator-5554` only while both remain present; otherwise replace both literal runner IDs with the newly selected Android IDs in the execution record. Create a new artifact directory; the existing runner drives both roles with no user taps.
- Two-peer default: one pinned USB physical Android plus one pinned Android emulator. No iOS leg is justified because the changed affordance is Flutter presentation and makes no parity/native claim.
- Closure role: conditional supporting preservation while the required target classes are available, not the causal closure tier. If no USB physical Android or no Android emulator is available, record `N/A (target unavailable by project policy)` without blocking host closure. A missing previously pinned ID is not N/A when another target of the same class is available.
- `FLUTTER_DEVICE_ID`: insufficient; the runner requires explicit sender and recipient IDs.
- Registration: harness and criteria remain `support`, runner remains `1to1` in `scripts/check_reliability_simulation_discovery.sh`; criteria test remains exactly once in `ONE_TO_ONE_TESTS`.
- Discovery command: `./scripts/check_reliability_simulation_discovery.sh` → the Plan-234 harness/support and 1:1 runner remain classified without unknown/duplicate entries.
- Closure command: `PLAN271_ARTIFACT_DIR="$(mktemp -d "${TMPDIR:-/tmp}/plan271-view-once.XXXXXX")"; dart run integration_test/scripts/run_direct_private_media_device_local_journey.dart --sender 21071FDF600CSC --recipient emulator-5554 --artifact-dir "$PLAN271_ARTIFACT_DIR"` → both roles and strict combined artifact pass with no secret/pixel/relay overclaim.
- Deferred device work: none when the discovered pair remains available; unavailable targets are N/A under project policy.

## Acceptance Gates

```bash
# Snapshot before execution; record and preserve unrelated changes.
git status --short

# Causal REDs before production edits; each expects non-zero for the documented
# 88px/inert/button or missing View-once event path, not a fixture failure.
flutter test \
  test/features/conversation/presentation/screens/direct_private_media_viewer_test.dart \
  --plain-name 'view-once placeholder uses warned tap tile as its sole open control'
flutter test \
  test/features/conversation/presentation/screens/direct_private_media_tile_tap_test.dart \
  --plain-name 'view-once tap tile covers image and video while legacy GIF keeps the old branch'
flutter test \
  test/features/conversation/presentation/screens/direct_private_media_tile_tap_test.dart \
  --plain-name 'view-once tile is one warned semantic button and opening is disabled in tile'
flutter test \
  test/features/conversation/presentation/screens/direct_private_media_tile_tap_test.dart \
  --plain-name 'tile tap preserves ancestor long press and swipe to quote'
flutter test \
  test/features/conversation/presentation/screens/direct_private_media_tile_tap_test.dart \
  --plain-name 'tap feedback scales to 0.975 and resets on up and cancel'
flutter test \
  test/features/conversation/presentation/screens/conversation_received_media_actions_test.dart \
  --plain-name 'received view-once tile reaches typed private launcher and never enters ordinary viewers'
flutter test \
  test/features/conversation/presentation/screens/direct_private_media_continuity_test.dart \
  --plain-name 'rapid double tap downloads then auto-continues under one single-flight'
flutter test \
  test/features/conversation/presentation/screens/direct_private_media_continuity_test.dart \
  --plain-name 'pause-resume during download cannot auto-open'

# Focused GREEN; exit 0, zero failed tests.
flutter test \
  test/features/conversation/presentation/screens/direct_private_media_viewer_test.dart \
  test/features/conversation/presentation/screens/direct_private_media_tile_tap_test.dart \
  test/features/conversation/presentation/screens/direct_private_media_continuity_test.dart \
  test/features/conversation/presentation/screens/conversation_received_media_actions_test.dart \
  test/features/conversation/presentation/screens/direct_private_media_card_test.dart

# Exact preservation outside the direct curated lane.
flutter test \
  test/features/groups/presentation/group_private_media_capabilities_test.dart \
  --plain-name 'GPL-09 active private bubble exposes only the dedicated open path'
flutter test test/l10n/l10n_integrity_test.dart

# Existing registrations remain exact; no new family entry.
awk '/^readonly ONE_TO_ONE_TESTS=\(/,/^\)/' scripts/run_test_gates.sh |
  rg -Fxc '  "test/features/conversation/presentation/screens/direct_private_media_tile_tap_test.dart"' |
  rg -x '1'
awk '/^readonly ONE_TO_ONE_TESTS=\(/,/^\)/' scripts/run_test_gates.sh |
  rg -Fxc '  "test/features/conversation/presentation/screens/direct_private_media_viewer_test.dart"' |
  rg -x '1'

# Curated direct family; exit 0 and output selects the updated files.
./scripts/run_test_gates.sh 1to1

# Existing support/runner discovery remains valid.
./scripts/check_reliability_simulation_discovery.sh

# Availability-bounded device-local support replay. Re-resolve the matrix and
# retain these literal IDs only if both are still reported; otherwise pin and
# record the exact replacement physical-Android and emulator IDs.
flutter devices --machine
adb devices
adb devices | rg -x '21071FDF600CSC[[:space:]]+device'
adb devices | rg -x 'emulator-5554[[:space:]]+device'
PLAN271_ARTIFACT_DIR="$(mktemp -d "${TMPDIR:-/tmp}/plan271-view-once.XXXXXX")"
dart run integration_test/scripts/run_direct_private_media_device_local_journey.dart \
  --sender 21071FDF600CSC \
  --recipient emulator-5554 \
  --artifact-dir "$PLAN271_ARTIFACT_DIR"

# Refresh the app-owned architecture graph once after the coherent source edit.
./graphify-arch/refresh_arch_graph.sh --incremental

# Hygiene; no new analyzer issues or whitespace errors.
flutter analyze
git diff --check

# Scope: staged, unstaged, and untracked Flutter production changes consist of
# exactly the intended viewer file; localized values remain byte-unchanged.
PLAN271_CHANGED_LIB_FILES="$(
  {
    git diff --name-only HEAD -- lib
    git ls-files --others --exclude-standard -- lib
  } | sort -u
)"
test "$PLAN271_CHANGED_LIB_FILES" = \
  'lib/features/conversation/presentation/screens/direct_private_media_viewer.dart'
git diff --quiet HEAD -- lib/l10n

# No staged, unstaged, or untracked native, web, package, or Go production edit.
PLAN271_FORBIDDEN_PRODUCTION_CHANGES="$(
  {
    git diff --name-only HEAD -- \
      android ios linux macos web windows assets packages \
      go-mknoon go-relay-server native-p2p-go-libp2p pubspec.yaml
    git ls-files --others --exclude-standard -- \
      android ios linux macos web windows assets packages \
      go-mknoon go-relay-server native-p2p-go-libp2p
  } | sort -u
)"
test -z "$PLAN271_FORBIDDEN_PRODUCTION_CHANGES"

# Device support schema, criteria, runner, and registration stay unchanged.
git diff --quiet HEAD -- \
  integration_test/scripts/direct_private_media_device_local_journey_criteria.dart \
  integration_test/scripts/run_direct_private_media_device_local_journey.dart \
  test/integration/direct_private_media_device_local_journey_criteria_test.dart \
  scripts/run_test_gates.sh \
  scripts/check_reliability_simulation_discovery.sh
```

## Execution Interpretation And Done Criteria

- Expected RED: TC-01/02/03/04/06/07 fail because current View once keeps an inert 88px non-semantic visual and separate button; it has no pointer/semantic tile callback, View-once tile feedback, typed launch, or entered download window.
- Green sentinels: protected/disappearing, null-open, legacy GIF, exact outgoing/failure/terminal counts, group, expanded no-pixel scan, l10n, enumerated lifecycle/first-frame settlement, and the outgoing device-harness tap stay unchanged.
- Pre-existing dirty tree: `docker-ws/run_fresh_three_phones_result.txt` and `info.plist` were modified before this planning turn. Execution must preserve them and record any additional unrelated change.
- Environment blocker: none at planning time; the default Android pair is live. Execution must re-resolve and re-pin available IDs. Only absence of either required target class makes TC-12 `N/A (target unavailable by project policy)`, not a failed gate.
- Scope drift: any new modal/copy, title/body removal, GIF/null-open/outgoing/group expansion, controller/lifecycle/policy/DB/native/relay edit, artifact-schema change, or second production file blocks closure.

- [x] Every behavior has the named host test or justified supporting proof.
- [x] TC-01/02/03/04/06/07 record causal RED→GREEN and representative mutation re-red.
- [x] TC-05/08/09/10/11/13 remain green with the tightened exact-count/classifier/no-pixel assertions; conditional TC-12 passes on a re-resolved live Android pair or is recorded N/A under project policy.
- [x] Existing `ONE_TO_ONE_TESTS` and device-runner discovery remain exact; no new registration is added.
- [x] Focused tests, exact sentinels, `1to1`, and conditional TC-12 pass with zero failures.
- [x] Incremental Graphify refresh, `flutter analyze`, `git diff --check`, l10n/native/support zero-diff guards, and the one-production-file scope check pass.
- [x] Scope Contract And Guard is respected.
- [x] After individual closure, the Plan 271 executor runs the separately recorded Plans 270–271 wave `host-all`; the wave remains open until it passes. Final rollout/release runs it again.

## Reviewer Findings

- `$tdd-review` initial verdict: `plan-fixes-required`; classification remained `implementation-ready`, core bet confirmed, disposition `apply-plan-fixes`.
- Verified and applied: executable semantics callback proof (TC-03), View-once-specific gesture/cancel discrimination (TC-04), non-vacuous pause/resume entry plus explicit rapid-double-tap wording (TC-07), exact outgoing counts (TC-08), direct-`DecoratedBox` no-pixel coverage (TC-11), the actual rollback/fail-closed classifier with honest test names (TC-13), and a separately owned Plans 270–271 wave aggregate.
- Critical synthesis: TC-01 additionally proves the retained title and warning are pointer-inert; TC-03 treats the opening node's absent action as the invariant and separately proves pointer inertness; TC-07 requires the pre-invalidation download/spinner discriminator only in the rapid-double and pause/resume legs where it prevents a vacuous pass. No production scope was added.
- Independent post-revision subagent re-audit: L1–L5 clear, no required findings, no material overclaim or non-executable command; `host-all --list` discovery also succeeded. Blind-spot hits B-3/B-4/B-5/B-9 are closed; B-2/B-7/B-8 remain clear and B-1/B-6/B-10 are N/A. No user-owned decision remains.
- Final verdict: `ready`; classification `implementation-ready`; core bet confirmed; disposition `execute`.

## Handoff

- First causal RED command: `flutter test test/features/conversation/presentation/screens/direct_private_media_viewer_test.dart --plain-name 'view-once placeholder uses warned tap tile as its sole open control'`.
- Preservation command: `flutter test test/features/conversation/presentation/screens/direct_private_media_tile_tap_test.dart test/features/conversation/presentation/screens/direct_private_media_viewer_test.dart && flutter test test/features/groups/presentation/group_private_media_capabilities_test.dart --plain-name 'GPL-09 active private bubble exposes only the dedicated open path'`.
- Manual registration: none. The changed viewer/tile/action/card tests and criteria test are already exactly once in `ONE_TO_ONE_TESTS`; continuity is exact per-plan and AUTO in the later `feature-host-all`; the device support/runner is already classified.
- Migration: none.
- Boundary closure: host widget tests are causal; the existing device-local harness replay conditionally uses a re-resolved and pinned physical-Android + emulator pair only as supporting preservation, with no relay/iOS/new-native claim.
- Wave closure: after per-plan GREEN, the Plan 271 executor runs `./scripts/run_host_test_gates.sh host-all` once for the completed Plans 270–271 wave; final rollout/release runs it independently again.
- Unresolved evidence: none.

## Execution Progress

| Time | Phase | Files | Last command/result | Current evidence | Decision/blocker | Next |
|---|---|---|---|---|---|---|
| 2026-07-24 | causal RED | five host test surfaces plus device harness | TC-01/02/03/04/06/07 failed on the View-once exclusion seam; preservation sentinels remained GREEN | 88px/separate-button layout, missing tile action/typed launch, and absent download entry were each observed before production changed | RED was causal and bounded to the planned predicate | Extend only `tapTileMode` |
| 2026-07-24 | focused GREEN + mutation | `direct_private_media_viewer.dart` and planned tests/support | Five focused files passed 61 tests; exact group sentinel and two l10n tests passed; removing the View-once predicate re-reddened TC-01, then byte-identical restore returned it GREEN | TC-01–13 host contracts and preservation sentinels are GREEN | One production file changed; no scope drift | Run per-plan gates |
| 2026-07-24 | per-plan closure | registered 1:1 host surfaces | `./scripts/run_test_gates.sh 1to1` passed 2,440 Flutter tests plus relay Go; discovery, exact-once registration, analyzer, diff/l10n/native/support/scope guards passed | Required host tier is GREEN | No blocker | Run conditional device support and wave aggregate |
| 2026-07-24 | device support | existing device-local journey harness | Physical Android `21071FDF600CSC` + emulator `emulator-5554` passed; artifact SHA-256 `c3772ee7f6989a64631a5266a1cbe3a5e194861c5358c5228bd40f6d11ea0a11` | Re-resolved, pinned default Android pair proves the retained local journey without adding an iOS/relay claim | No blocker | Refresh graph once and run wave |
| 2026-07-24 | graph + Plans 270–271 wave closure | app-owned architecture graph and `host-all` | Incremental refresh ran exactly once, fingerprint `fc333c615c1b3e10`; `host-all --batch-flutter --concurrency 4 --reporter failures-only` passed 12,876 Flutter tests (one intentional skip) plus all eight Go tails | A post-refresh mutation probe advanced only the viewer mtime; restored MD5 `ca4cc226c9cba779f122b1f669bf8f2e` equals manifest `ast_hash`/`semantic_hash`, so the warning is timestamp-only and no contradictory second refresh ran | Wave closed; concurrency 8 exposed an unrelated Orbit timing flake that passed alone and in the clean 4-way aggregate | Complete |
