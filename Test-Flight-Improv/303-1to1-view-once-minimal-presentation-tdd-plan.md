# 303 - 1:1 Image View-Once Minimal Presentation and Back Cleanup

Status: completed
Type: Modification
Spec: free-text product intent — user clarification 2026-07-30
Classification: implementation-ready
Closure tier: host causal tests plus availability-bounded single-Android device sentinels

## Planning Progress

| Time | Role | Evidence inspected | Decision | Next action |
|---|---|---|---|---|
| 2026-07-30 | Evidence collector | Direct viewer/placeholders, composer policy/picker, lifecycle/controller, owning tests and gates | Presentation is spread across a small direct-only surface; lifecycle already terminalizes a view-once lease on close | Draft initial contract |
| 2026-07-30 | First TDD review | Terminal hydration and cleanup projection | Exact terminal media kind is unavailable after secure cleanup; a widget-injected kind would be a false proof | Block exact-kind terminal design |
| 2026-07-30 | Product clarification | Current request | New view-once composition is image-only; Back must consume and delete the media; existing screenshot blocker must not change | Re-scope |
| 2026-07-30 | TDD planner | `private_media_policy.dart`, picker/composer call sites, viewer `_close`, controller `settle`, lifecycle cleanup, host/device proofs | Resolve the blocker by dropping terminal-kind presentation, not by adding storage or a protocol version. Add the missing UI-Back causal proof and a narrow mode-aware composer rule | Run critical TDD review |
| 2026-07-30 | TDD review (factual + destructive-boundary verifiers) | Composer final-send behavior, placeholder-body lane member, cleanup ordering, outgoing transport custody, SQLite/SQLCipher proofs, device harness fixture | Tighten stale-send rejection and Back ordering; add the missing lane test; state the unhanded-off sender custody exception; reuse exact cleanup tests; do not repair or use the synthetic sender device fixture | Apply only these material deltas |

## Execution Progress

| Stage | State | Required evidence |
|---|---|---|
| RED | complete | TC-01 through TC-06 failed for the documented mode/picker/minimal-presentation/viewer-chrome mechanisms. TC-07 additionally exposed that the shared AppBar used bare `Navigator.pop`, bypassing the direct owner's `PopScope`. Preservation rows stayed green. |
| GREEN | complete | The exact 13-file focused/preservation command passed 247 tests. TC-07 now proves one consume, one cleanup, zero rollback, cleanup-before-route-removal, and route-removal-before-native-release. |
| Refactor | complete | No storage, lifecycle, controller, capture-protection, group, terminal, schema, migration, wire, secure-storage, or l10n production file changed. The shared viewer gained one optional Back coordinator whose null/default behavior is preserved. |
| Closure | complete | `completeness-check` passed 1366/1366, `1to1` passed 2516 Flutter tests plus the relay Go gate, affected shared/ordinary/group sentinels passed, hygiene passed, and both unchanged device sentinels passed on USB Pixel 6 `21071FDF600CSC`. |

## Problem And Evidence

- New 1:1 view-once media currently accepts both images and videos. `PrivateMediaEligibility.allowsNewPrivateMedia` at `lib/core/media/private_media_policy.dart:84-93` is intentionally shared by protected/disappearing modes, so changing that getter to image-only would incorrectly remove private video from those modes.
- The narrow policy seam is `normalizePrivateMediaComposerPolicy` at `private_media_policy.dart:284-294`. It already owns selected-mode retention and is called during attachment restore/replacement. `_setPrivateMediaPolicy` and the final `_onSend` guard in `conversation_wired.dart:3118-3134,:5219-5225` must use the same mode-aware rule so a stale view-once video policy cannot bypass the picker.
- The private picker renders every mode from `PrivateMediaPickerMode.values` at `lib/shared/widgets/private_media_policy_picker_sheet.dart:259-275`. Its existing `PrivateMediaPickerKind` type is currently unused and is sufficient to hide only View once for a video while retaining Keep in chat, Protected, and Disappearing.
- `DirectPrivateMediaViewer._close` at `lib/features/conversation/presentation/screens/direct_private_media_viewer.dart:105-166` settles before removing the route and releases protection afterward. `DirectPrivateMediaViewerController.settle` terminalizes a view-once grant for normal close, and `DirectPrivateMediaLifecycle.cleanupTerminal` deletes the exact owned file, secure key, and attachment row.
- Existing controller coverage at `test/features/conversation/presentation/screens/direct_private_media_viewer_test.dart:794-837` calls `settle(close)` directly. It proves one consume/cleanup but does not drive the visible Back arrow through `Navigator.pop` and `PopScope`; that UI seam is the useful missing test.
- Existing durable proofs are complementary:
  - `test/features/conversation/application/private_media_cleanup_race_test.dart:112-274` proves exact view-once file/key/row cleanup, sibling preservation, and retry convergence on the production schema (host SQLite, not SQLCipher).
  - `test/features/conversation/integration/private_media_restart_replay_test.dart:26-172,:269-425,:600-643` proves terminal view-once cannot reopen, preserves unhanded-off outgoing transport custody, and deletes it after durable handoff.
  - The unchanged recipient leg of `integration_test/direct_private_media_device_local_journey_harness.dart:1091-1157` uses password-backed SQLCipher and proves a view-once file/row is gone and cannot reopen after database reopen.
  - The sender Back leg at `harness.dart:549-560,:846-895` is stale and synthetic: it seeds outgoing `protected` with `status: sent` plus `upload_pending`, yet expects a one-shot state sequence and immediate deletion. Do not modify or use that leg as plan-303 evidence.
- “Deleted on Back” is direction/custody precise:
  - incoming recipient and already-handed-off sender media become consumed and cleanup removes the file/key/attachment row;
  - an unhanded-off outgoing `sending`/`failed` item immediately loses its sole viewer authority and cannot reopen, but its encrypted/pending bytes remain only as transport custody until durable handoff/reconciliation, then existing cleanup deletes them;
  - the parent message row remains as the existing terminal receipt. Deleting that row would conflict with the post-view state, and deleting unhanded-off bytes immediately would cancel delivery.

### Blocker Resolution

- Remove the icon + exact media-kind terminal redesign from plan 303. Terminal hydration deliberately has no attachment kind after cleanup (`ConversationMessage.media` is transient and terminal projections clear it), so persisting a kind only for presentation would add schema/protocol/rollback work with no privacy value.
- Keep `DirectPrivateMediaTerminalPlaceholder` and its production call site unchanged. Do not hard-code “Photo”: legacy version-1 view-once videos can still arrive and must not be mislabeled after cleanup.
- No ARB or generated-localization change is needed.

## Graph Grounding Snapshot

- Architecture graph: `graphify-arch/graphify-out/`, fingerprint `1a2ac3b8d4a4215c`; the planning query reported `freshness=current`.
- Planning query: `python3 graphify-arch/tdd_context.py query "Plan 303 image-only view-once: DirectPrivateMediaViewer back navigation settle terminal cleanup deletes file key attachment exactly once; preserve screenshot protection and exclude video presentation. Exact anchors DirectPrivateMediaViewerGrant, _close, settle, DirectPrivateMediaLifecycle cleanup, PrivateMediaPolicy allowsNewPrivateMedia" --profile tdd --budget 700`.
- Result: `confidence=anchored`; primary anchor `DirectPrivateMediaViewer` at `direct_private_media_viewer.dart:19`, with controller, conversation screen, and owning viewer tests surfaced.
- Review queries re-anchored `normalizePrivateMediaComposerPolicy`, `DirectPrivateMediaViewerController`, `DirectPrivateMediaViewer`, and `cleanupTerminal` with `confidence=anchored`. Review-time freshness reported only `stale:ios/Flutter/flutter_export_environment.sh`; exact conclusions were rechecked in current source.
- Targeted source inspection was required for the mode-aware composer/picker seam and for distinguishing file-backed SQLite from the real SQLCipher device proof.

## Scope Contract And Guard

In scope:

- New direct 1:1 view-once selection accepts exactly one image under the existing no-caption/no-edit/no-forward shape.
- A video draft still exposes the private-media selector, but its sheet omits only View once. Protected and Disappearing video remain selectable.
- A stale/restored `viewOnce + video` selection normalizes to ordinary and the final send guard refuses to emit it.
- Sender and receiver active view-once **image** bubbles become the minimal 150px cover tile with the `looks_one` affordance. The existing open callback, opening spinner/disable behavior, semantics label, and local-missing explanatory state remain authoritative.
- The full-screen direct viewer hides its bottom copy/actions only when `grant.mode == viewOnce && grant.kind == image`. Its AppBar Back arrow remains visible.
- For an incoming image, tapping that Back arrow settles once as `consumed`, awaits cleanup before route removal, and leaves no second open budget. Normal Back before first frame retains the existing fail-closed consume behavior already covered at controller tier.
- Outgoing view-once Back always consumes the sole local viewing budget. Already-handed-off media cleans immediately; unhanded-off transport custody follows the existing retain-until-handoff rule above.

Must preserve:

- `PrivateMediaEligibility.allowsNewPrivateMedia` remains true for eligible image **and video** shapes because protected/disappearing use it.
- `allowsPrivateMedia` and `PrivateMediaPolicy.validatedFor` remain compatible with legacy wire-arrived image/GIF/video private media.
- Legacy wire-arrived view-once video rendering/open/settlement and GIF fallback/open-failure presentation remain unchanged. No new video UX is added.
- Protected and disappearing bubbles/viewer overlays/actions remain unchanged.
- `DirectPrivateMediaTerminalPlaceholder`, its action row, keys, copy, and call site remain unchanged.
- Unhanded-off outgoing transport custody remains non-viewable after Back and is deleted after handoff/reconciliation; its delivery-preserving lifecycle contract remains unchanged.
- Capture protection, cover ordering, capture-event handling, native platform calls, and all screenshot/recording tests remain byte-for-byte unchanged.
- Group private-media surfaces remain unchanged.

Hard `Do not`:

- Do not edit `private_media_lifecycle_engine.dart`, `DirectPrivateMediaViewerController`, `DirectPrivateMediaLifecycle`, database helpers/schema/migrations, wire policy version, ARBs/generated l10n, or secure-storage code.
- Do not edit `PrivateMediaProtectionCoordinator`, platform capture code, `capturePlatformOverride`, or `integration_test/direct_private_media_platform_protection_proof_test.dart`.
- Do not edit the device-local journey harness/criteria to manufacture a combined Back+SQLCipher proof; its unchanged recipient role is only one leg of the split proof.
- Do not change `GroupPrivateMediaViewer`, group composer/picker behavior, terminal widgets, or terminal action reachability.
- Do not rename `private-media-card-visual`, `direct-private-media-viewer`, `private-media-cover`, or `private-terminal-<state>`.

Affected implementation files:

- `lib/core/media/private_media_policy.dart`
- `lib/shared/widgets/private_media_policy_picker_sheet.dart`
- `lib/features/conversation/presentation/widgets/compose_area.dart`
- `lib/features/conversation/presentation/screens/conversation_wired.dart`
- `lib/features/conversation/presentation/screens/direct_private_media_viewer.dart`
- `lib/shared/widgets/media/full_screen_typed_media_viewer.dart` (execution-discovered AppBar Back seam; optional callback, default behavior unchanged)

## Test Contract

`HEAD state` is `causal RED`, `GREEN sentinel`, or `device proof`; no row depends on a new schema or terminal-kind decision.

| Case | Behavior | Named test/proof | Tier / fixture | HEAD state -> GREEN | Mutation that re-reds | Gate |
|---|---|---|---|---|---|---|
| TC-01 | Mode-aware policy permits view-once image, rejects view-once video, and retains protected/disappearing video | Extend `test/features/conversation/presentation/screens/conversation_private_media_composer_test.dart::every stale or ineligible composer shape resets private policy` with the mode/kind matrix | host unit | causal RED: current normalizer retains view-once video -> exact matrix passes | remove the `viewOnce => image` condition or make generic eligibility image-only | focused file; registered in `1to1` |
| TC-02 | Video sheet keeps selector plus Protected/Disappearing but has no View once; image sheet still commits View once | Split/update `conversation_private_media_composer_test.dart::view-once and exact disappearing durations emit typed policy` and add `video omits only view-once` | widget | causal RED: current sheet renders View once for video -> image/video option matrix passes | render all enum values or hide the whole video selector | same command |
| TC-03 | Attachment replacement/restore and final send cannot retain or emit view-once video, and cannot silently downgrade-send it as persistent media | Add `test/features/conversation/presentation/screens/conversation_wired_test.dart::video replacement blocks stale view-once send` using the existing composer/send fixture | widget + wired fake send/upload | causal RED: broad guards accept view-once video -> first Send produces zero send/upload/optimistic-message calls, resets selector to ordinary, and shows existing invalid-shape feedback; an ordinary send requires a second explicit tap | normalize to ordinary but continue the first send, or bypass the shared predicate in `_setPrivateMediaPolicy`/`_onSend` | focused file; registered in `1to1` |
| TC-04 | Sender view-once image is one tappable 150px cover tile; opening disables it; open-denied/local-missing states remain honest | Rewrite the view-once leg in `direct_private_media_sender_pending_button_test.dart::hydrated outgoing view_once upload_pending row offers exact one-more-look`; extend the image state matrix in `direct_private_media_viewer_test.dart`; update only the view-once-image expectation in `direct_private_media_placeholder_body_test.dart::direct private placeholders render localized bodies` | widget | causal RED: title/body/button render today -> tile shape, one semantics action, existing open intent and state guards pass; protected/local-missing body assertions stay GREEN | restore the button/card branch, duplicate the semantics node, or remove preserved sibling copy | focused files; placeholder-body is registered in `1to1`, sender-pending remains an explicit command |
| TC-05 | Receiver view-once image is the same minimal tile; legacy video/GIF and protected/disappearing retain current presentation | Rewrite image assertions in `direct_private_media_tile_tap_test.dart::view-once tile is one warned semantic button` and preserve the video/GIF legs in `::view-once tap tile covers image and video while legacy GIF keeps the old branch`; retain `direct_private_media_card_test.dart` video title sentinel | widget | causal RED for image copy; GREEN sentinels for video/GIF/sibling modes -> image copy absent and open semantics preserved | suppress copy for every kind or break the existing tap callback | focused files; registered in `1to1` |
| TC-06 | Only image view-once viewer hides bottom copy/actions; legacy view-once video and protected/disappearing keep them | Add `direct_private_media_viewer_test.dart::minimal viewer chrome is image view-once only` using an exact mode/kind matrix | widget | causal RED for image view-once; sibling legs GREEN -> only that leg finds no overlay copy/action | guard on mode alone or remove the guard | focused viewer file; registered in `1to1` |
| TC-07 | Actual incoming AppBar Back runs close settlement once, keeps the covered route mounted until cleanup finishes, then removes it before protection release | Add `direct_private_media_viewer_test.dart::view-once image Back consumes and cleans exactly once` using existing `_fixture`/`_Lane`, a real pushed route, valid 1x1 PNG, viewer-scoped Back, a test-only cleanup barrier, and `onNativeExit` | widget + fake lifecycle lane | causal RED found during execution: the shared AppBar's bare `Navigator.pop` bypassed the owner's `PopScope` -> after Back and cleanup entry, viewer/cover remain mounted and native calls are only `enter`; after releasing the barrier assert `terminalized/close`, consume=1, cleanup=1, rollback=0, attachments empty, route gone/underlying visible; inside `onNativeExit`, assert viewer absent and underlying visible | bare-pop early, release protection before route removal, bypass `_close`, or let dispose consume twice | focused viewer file |
| TC-08 | View-once cleanup is exact and retry-convergent; reopen never returns; unhanded-off outgoing bytes are retained only as transport custody and deleted after handoff | Existing `private_media_cleanup_race_test.dart::terminal cleanup removes every exact direct artifact and preserves siblings`, `::cleanup failure retains terminal row/key metadata and retry converges`; existing `private_media_restart_replay_test.dart::reopen terminalizes opening...`, `::restart terminalizes viewer state without destroying unhanded-off outbox custody`, and `::restart with durable envelope handoff cleans terminal outbox custody` | production-schema SQLite + fake secure store/file manager | GREEN sentinels -> file/key/row exactness, retry convergence, no second lease, custody retention, and post-handoff deletion all stay true | delete unhanded-off custody early, retain handed-off bytes, skip key/row cleanup, or remint a lease | both files registered in `1to1` |
| TC-09 | Real SQLCipher recipient cleanup removes view-once file/row and remains irreopenable after database reopen | Run the unchanged recipient role in `direct_private_media_device_local_journey_harness.dart` directly on one pinned Android target; do not use or edit its stale sender leg | Android integration / password-backed SQLCipher | unchanged device sentinel -> recipient observations report cleanup complete, attachment absent, and available-after-reopen false | retain the row/file or permit a new lease after reopen | availability-bounded pinned Android command |
| TC-10 | Screenshot/recording blocker and fail-closed cover are unchanged | Existing viewer protection cases at `direct_private_media_viewer_test.dart:981-1445` plus unchanged `integration_test/direct_private_media_platform_protection_proof_test.dart` | widget + device proof | GREEN sentinel before/after | any protection/cover/native change | focused viewer test; platform proof unchanged |
| TC-11 | Terminal, legacy video/GIF, protected/disappearing, and group surfaces do not drift | Existing `private_media_thumbnail_wipe_test.dart`, `conversation_received_media_actions_test.dart`, `direct_private_media_card_test.dart`, `direct_private_media_tile_tap_test.dart`, `group_private_media_capabilities_test.dart` | widget | GREEN sentinel before/after | hard-code Photo terminal, restyle all view-once kinds, or widen direct changes to groups | focused exact files |

### Test Notes

- TC-07 was planned as a GREEN characterization, but the real AppBar action produced a legitimate causal RED: the shared viewer performed a direct pop before the private owner could settle. The narrow fix adds an optional owner Back callback; ordinary/shared/group viewers retain the existing null/default direct-pop path.
- TC-07 and TC-08 are complementary: a barrier-controlled fake lane proves Back ordering and one invocation, while the real repositories prove cleanup convergence/artifact boundaries. “Exactly once” applies to consumption/open authority; cleanup is idempotent, retryable, and convergent.
- TC-09 is the real SQLCipher boundary. It needs one Android target, not two peers; resolve and pin that target at execution. The current full paired runner is not a plan-303 gate because its unrelated sender fixture is stale/synthetic.
- The platform protection proof is a preservation sentinel only. This plan must not “improve,” rewrite, or rebaseline screenshot blocking.

## Implementation Steps

1. Record `git status --short`; preserve all pre-existing user changes.
2. RED-first: update TC-01 through TC-06 assertions and run their focused files. Record the expected mechanism-specific failures; run TC-07/08/10/11 as green baselines.
3. In `private_media_policy.dart`, add the smallest reusable mode-aware composer predicate inside/alongside `normalizePrivateMediaComposerPolicy`: view-once requires `attachmentKind == image`; other private modes continue to use `allowsNewPrivateMedia`.
4. Route `_setPrivateMediaPolicy`, attachment restore/replacement, and `_onSend` through that same predicate. Do not duplicate divergent conditions.
5. Use the existing picker-kind concept to omit only `PrivateMediaPickerMode.viewOnce` for video. Normalize an impossible initial `viewOnce + video` selection to ordinary before showing the sheet.
6. In `direct_private_media_viewer.dart`, make `PrivateMediaVisualCard.body` nullable and omit it only for the image view-once branches; build the sender/receiver image tiles and image-only viewer guard. Keep legacy video/GIF and all other modes on their current branches.
7. Add the TC-07 barrier-controlled route-level Back characterization without changing controller/lifecycle production.
8. Run focused GREEN, graph affected tests, the curated `1to1` lane, unchanged device sentinels when a supported target is available, and hygiene.

## Risks And Blind Spots

- Overbroad “image-only” eligibility could disable protected/disappearing video. TC-01/02 and the unchanged generic eligibility test prevent it.
- Hiding the picker option alone could leave restore/send bypasses. TC-03 and one shared normalizer close those paths.
- Normalizing and continuing the same Send would silently publish persistent video. TC-03 requires a stopped first attempt and a second explicit ordinary send.
- A mode-only presentation guard would restyle legacy view-once video. TC-05/06 pin `mode + image`.
- A route can disappear before cleanup completes, protection can release too early, or dispose can settle twice. TC-07's barrier and `onNativeExit` assertions pin all three boundaries.
- Immediate deletion of unhanded-off outgoing bytes would cancel delivery. TC-08 pins immediate no-reopen plus retain-until-handoff cleanup.
- Host SQLite is not SQLCipher. TC-09 owns the platform database boundary without expanding production scope.
- Exact terminal kind remains unavailable after cleanup by design. Any attempt to reintroduce it is scope drift, not an implementation detail.

## Gate Cadence

- Per-plan: focused causal tests, exact preservation sentinels, Graphify affected tests, and `./scripts/run_test_gates.sh 1to1`.
- No `feature-host-all`, `core-host-all`, or full `host-all` is owed for this plan. Full `host-all` remains a dependency-wave and final-release gate.
- Shared/group sentinels run by exact command; their registration in broader lanes does not create a full group-lane obligation.
- No new test file is planned, so no registration edit is expected. Verify completeness after edits.

## Acceptance Gates (literal)

```bash
flutter --version
git status --short

# Focused RED/GREEN and preservation
flutter test test/features/conversation/domain/models/private_media_policy_test.dart
flutter test test/features/conversation/presentation/screens/conversation_private_media_composer_test.dart
flutter test test/features/conversation/presentation/screens/conversation_wired_test.dart
flutter test test/features/conversation/presentation/screens/direct_private_media_sender_pending_button_test.dart
flutter test test/features/conversation/presentation/screens/direct_private_media_placeholder_body_test.dart
flutter test test/features/conversation/presentation/screens/direct_private_media_tile_tap_test.dart
flutter test test/features/conversation/presentation/screens/direct_private_media_card_test.dart
flutter test test/features/conversation/presentation/screens/direct_private_media_viewer_test.dart
flutter test test/features/conversation/application/private_media_cleanup_race_test.dart
flutter test test/features/conversation/integration/private_media_restart_replay_test.dart
flutter test test/features/conversation/application/private_media_thumbnail_wipe_test.dart
flutter test test/features/conversation/presentation/screens/conversation_received_media_actions_test.dart
flutter test test/features/groups/presentation/group_private_media_capabilities_test.dart

# Registration and affected dependents
./scripts/run_test_gates.sh completeness-check
python3 graphify-arch/tdd_context.py affected \
  lib/core/media/private_media_policy.dart \
  lib/shared/widgets/private_media_policy_picker_sheet.dart \
  lib/features/conversation/presentation/widgets/compose_area.dart \
  lib/features/conversation/presentation/screens/conversation_wired.dart \
  lib/features/conversation/presentation/screens/direct_private_media_viewer.dart \
  --budget 600
# Run every test file named by the affected query before the lane.

./scripts/run_test_gates.sh 1to1

# Availability-bounded unchanged device sentinels; pin the exact Android ID.
flutter devices --machine
adb devices
flutter test integration_test/direct_private_media_platform_protection_proof_test.dart \
  -d <discovered-android-id>
flutter test integration_test/direct_private_media_device_local_journey_harness.dart \
  -d <same-discovered-android-id> \
  --dart-define=P234_ROLE=recipient \
  --dart-define=P234_DEVICE_ID=<same-discovered-android-id>
# If no supported target exists: N/A (target unavailable by project policy).

flutter analyze
git diff --check
./graphify-arch/refresh_arch_graph.sh --incremental
```

Semantic outcomes:

- Every focused command exits 0 at GREEN; TC-01 through TC-06 fail at RED for the documented mechanism, and TC-07 fails at the execution-discovered AppBar/`PopScope` seam.
- TC-07 reports one consume, one cleanup, zero rollback, consumed state, empty attachments, removed viewer route, and one protection enter/exit pair.
- TC-08 proves exact file/key/row cleanup, retry convergence, no second lease, and the retain-until-handoff sender exception.
- TC-09 reports recipient cleanup complete, attachment absent after cleanup, and unavailable after SQLCipher reopen.
- `completeness-check`, `1to1`, `flutter analyze`, and `git diff --check` pass with no new issues.

## Closure Evidence

- Focused causal and preservation suite: PASS, 247 tests across the 13 literal host files.
- Shared-viewer affected sentinels: PASS, 24 tests across `full_screen_typed_media_viewer_test.dart`, `media_viewer_boundary_test.dart`, `conversation_shared_media_viewer_test.dart`, and `group_private_media_viewer_test.dart`.
- Registration: PASS, `completeness-check` reports 1366/1366 tests registered.
- Curated lane: PASS, `./scripts/run_test_gates.sh 1to1` reports 2516 Flutter tests passed; relay Go toolchain contract and relay Go tests passed.
- Device matrix rediscovery: USB Pixel 6 `21071FDF600CSC`, Android 16/API 36, was available and pinned. No iPhone was used.
- Unchanged native protection proof: PASS on `21071FDF600CSC`.
- Unchanged recipient SQLCipher journey: PASS on `21071FDF600CSC`; its emitted artifact reports view-once cleanup complete, attachment absent after cleanup, and unavailable after reopen.
- Hygiene: PASS, Flutter 3.41.4 / Dart 3.11.1, `flutter analyze` reports no issues, and `git diff --check` is clean.
- Graphify: incremental architecture refresh completed; refreshed affected analysis included all six production files, including the execution-discovered shared AppBar seam.
- Scope audit: no prohibited lifecycle/controller/database/schema/migration/wire/secure-storage/l10n/group/capture/device-harness file changed.

## Execution Interpretation And Done Criteria

- [x] Newly composed view-once is image-only at picker, restore, normalization, and final-send boundaries.
- [x] Sender and receiver image bubbles are minimal and remain one accessible tap target.
- [x] Only the image view-once viewer loses bottom chrome; Back remains visible.
- [x] Incoming actual Back consumes once, awaits cleanup before route removal, deletes payload artifacts, and cannot reopen.
- [x] Outgoing actual Back consumes its sole viewing authority; handed-off artifacts clean immediately, while unhanded-off custody remains non-viewable and cleans after handoff.
- [x] Screenshot/recording protection code and proofs are unchanged.
- [x] Terminal presentation and legacy view-once video/GIF behavior are unchanged.
- [x] No schema, migration, wire-version, secure-storage, l10n, group, lifecycle, or controller production diff.
- [x] Focused tests, affected tests, `1to1`, and hygiene pass; device result is PASS or policy-valid N/A.

## Rollback

- Revert the plan-303 implementation commit as one unit. The change has no schema, migration, wire-format, stored-key, or data-conversion consequence.
- Existing view-once lifecycle data remains readable because compatibility validation and policy version are unchanged.

## Device/Relay Proof Profile

- Profile: single Android target, availability-bounded; these seams do not need two peers.
- Planning-time matrix (2026-07-30): USB Pixel 6 `21071FDF600CSC` is attached and Android AVD `Pixel_7` is available but not running. This is a snapshot only; rediscover and pin at execution. Do not substitute an iPhone.
- Automation: run the unchanged platform-protection proof and only the recipient role of the existing device-local journey; no user taps and no full paired-runner claim.
- Boundary split:
  - platform proof: actual viewer Back plus one consume while native screenshot protection remains unchanged;
  - host TC-07: cleanup/route/protection ordering and one cleanup invocation;
  - recipient journey role: password-backed SQLCipher file/row cleanup and no reopen;
  - host TC-08: exact secure-key deletion and retry/custody convergence.
- The stale synthetic sender role is neither edited nor used as evidence.
- Unavailable Android target: `N/A (target unavailable by project policy)`, never an execution blocker.
