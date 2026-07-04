# 206 - Settings Entry Point Migration: Orbit Center Avatar Opens Settings, Feed Header Avatar Removed  (Feature Improvement)

Status: awaiting-review
Spec: Test-Flight-Improv/206-orbit-center-avatar-settings-entry.md (corrected in place 2026-07-04 after the verify→refute pass — see Root Cause)

## Planning Progress
| Time | Role | Files inspected | Decision/blocker | Next action |
|---|---|---|---|---|
| 2026-07-04 | Evidence Collector (wf_c22619f4-4c5: 1 scout + 4 ground + 6 verify + 6 refute, 17 agents 0 errors) | orbital_visualization.dart, inner_circle_interactive_surface.dart, orbit_screen.dart, orbit_wired.dart, feed_header.dart, feed_screen.dart, feed_wired.dart, settings_wired.dart, app_shell_controller.dart, user_avatar.dart, orbital_ring_painter.dart, run_test_gates.sh, 6 test files, 3 ARBs | 3 spec claims corrected (hit-opacity not arena; background pref propagates via controller; only 1 guaranteed breaking test), 2 confirmed narrowed, 1 confirmed | build matrix |
| 2026-07-04 | Planner | tier-matrix.md, sufficiency-checklist.md, plan-template.md | single-mechanism propagation via AppShellController change-kinds (no dual `.then`+listener — INV-203-1 masking lesson); conditional detector mount (TC-194-26 constraint) | emit plan |
| 2026-07-04 | Reviewer (sufficiency) | this plan | all checklist gates pass; zero empty matrix cells; blind-spot sweep 4/4 addressed | hand off |
| 2026-07-04 | Arbiter | | host-only closure; no migration; no device-proof; 1 rewrite + 2 new files + 5 extended | hand off to execution |

## Execution Progress
| Time | Phase | Files touched | Command/evidence | Decision/blocker | Next |
|---|---|---|---|---|---|
| | contract extraction (git status --short) | | | scope confirmed | |
| | RED tests added | | (cmd proving they FAIL) | RED for expected reason | |
| | implementation | | | scoped files only | |
| | direct GREEN | | (exact cmd) | reds now green | |
| | preservation GREEN | | (exact cmd) | sentinels green | |
| | named gates | | (exact cmd + counts) | gate green | |
| | QA (independent) | | (re-run cmds) | blocking: none/list | verdict |

## Source Of Truth
- Spec / intent: Test-Flight-Improv/206-orbit-center-avatar-settings-entry.md
- Gate definitions: scripts/run_test_gates.sh (script wins over prose)
- Discovery/registration: scripts/check_reliability_simulation_discovery.sh (N/A here — no sim rows)
- Numbering / index: Test-Flight-Improv/00-INDEX.md

## Session Classification
implementation-ready

## Exact Problem Statement

The Orbit screen renders the current user's avatar as a static, gesture-free, semantics-free 48×48 `UserAvatar` at the canvas center (`orbital_visualization.dart:171-180`). Tapping it does nothing — in ANY surface mode (idle, edit, find): the whole canvas is hit-opaque, so the tap dies on non-interactive render objects (see Root Cause). Settings is reachable via avatars only from the Feed header's top-right avatar (`feed_header.dart:51-57` → `feed_wired._onAvatarTap:1869-1898`). Product direction: the Orbit center avatar becomes the settings entry; the Feed header avatar is removed entirely.

What must improve: center avatar opens Settings (idle surface only; modal-dismiss during edit/find; long-press enters sculpt for uniformity); Feed header avatar removed; settings-driven changes (identity/avatar, image/video quality) still propagate to Feed AND Orbit without the dying `.then` continuation; Settings opened from Orbit is functionally equivalent (incl. `nearbyLocationService`).

What must stay unchanged (→ preserved-green sentinels): satellite node taps open chat/group (TC-198-67 lock); background long-press-to-edit / double-tap-labels on empty space (198 suite); TC-194-26's single-GestureDetector invariant in direct-viz trees; center avatar painted position/size (sculpt :809-824 + arcs :123 geometry locks); background-pref live propagation (`AppShellController` path); Posts-screen settings entry; doc-202 repaint isolation; username editing + `ConnectionStatusIndicator` in the Feed header.

## Root Cause (verify → refute confirmed)

Workflow `wf_c22619f4-4c5` (1 graphify scout → 4 ground workers ∥ 6 verify → 6 adversarial refute). Surviving mechanism:

- **Center-avatar inertness (CL-1 narrowed):** no gesture handler / no Semantics on the center `UserAvatar` (`orbital_visualization.dart:171-180`; `user_avatar.dart` has zero GestureDetector/InkWell/Semantics). The tap is absorbed by hit-opaque render objects ABOVE the background detector: `UserAvatar`'s circular `DecoratedBox` (`user_avatar.dart:186-220`; `BoxDecoration.hitTest` true inside the circle) and the canvas-filling ring `CustomPaint` (`orbital_ring_painter.dart:35` — no `hitTest` override; `RenderCustomPaint.hitTestSelf` defaults true). `RenderStack.defaultHitTestChildren` stops at the first hit child, so the `Positioned.fill` background detector (`inner_circle_interactive_surface.dart:573-581`) is **never hit-tested at canvas center** — `_onBackgroundTap` (:318-326) never runs there. Repo-encoded corroboration: `bgPoint` taps LEFT of the circle column "so the sibling background gesture layer receives it" (`orbit_sculpt_summon_wired_test.dart:128-135`).
- **Propagation seams (CL-3 corrected, CL-4 confirmed-narrowed):** background pref propagates live via the shared `AppShellController` (`settings_wired.dart:196/:230` → `app_shell_controller.dart:40-47` → `feed_wired.dart:387/:2508-2521` → live read `:1854-1855/:2706`); the embedded Orbit host receives the SAME shared controller (`feed_wired.dart:2573`). Identity/username/avatar-bytes and image/video quality prefs have NO passive channel: set only by `_loadIdentity:425-448` / `_loadQualityPreference:450-457` / `_loadVideoQualityPreference:459-466`, called only from `initState:393-396` and the dying `.then:1892-1897`. `OrbitWired._loadIdentity` runs once from `initState` (`orbit_wired.dart:444`); none of its nine subscriptions (:257-267) carries self-identity. Photo-change staleness mechanism: avatar upload DOES broadcast (`upload_profile_picture_use_case.dart:78-80` — file write + `IdentityAvatarResolver.invalidatePeer` + `UserAvatar.invalidatePeer`), but a non-null `avatarBytes` puts `UserAvatar` on the Priority-1 `MemoryImage` path (`user_avatar.dart:122-136`) which ignores the notifier; only the first-ever avatar (null bytes → Priority-2 listenable, `:141-168`) auto-refreshes.
- **Dependency gaps (CL-5 confirmed w/ corrections):** both `OrbitWired` ctor sites (`feed_wired.dart:2542`, `main.dart:4257`) pass statically non-null `appShellController` + `postsPrivacySettingsRepository` (fields `feed_wired.dart:171/:173`, `main.dart:3477/:3446`); `widget.nearbyLocationService` is in scope at both (nullable at the feed site `feed_wired.dart:176` — null on the `qr_scanner_wired.dart:386` path; non-null at `main.dart:3449`). `OrbitWired`'s own fields are nullable (`orbit_wired.dart:137/:148`) → null-guard needed. `OrbitWired` has NO `nearbyLocationService` field and imports neither `settings_wired.dart` nor `settings_route_transition.dart` (orbit_wired.dart:13-15).
- **Breaking-test set (CL-6 corrected in BOTH directions):** exactly ONE guaranteed breaker: `feed_wired_test.dart::'refreshes background preference after returning from Settings'` (testWidgets :408, tap :418). TC-198-67 (:319-347) and TC-194-01/34 (:405-424) **survive** a nullable-callback implementation (locks, not breakers). NEWLY DISCOVERED conditional breaker: **TC-194-26** (:464-486) — unscoped `find.byType(GestureDetector)` + `getSize` single-match; an always-mounted center detector throws "Too many elements".

**Refuted / do-NOT-re-introduce:**
- "Center taps fall through to the background detector / `_onBackgroundTap`" — FALSE (hit-opacity, above). Do not design or test against arena fall-through; do not claim modal-dismiss on center tap is "preserving" anything.
- "A tap-only wrapper changes long-press/double-tap routing to the background" — FALSE; those pointers never reached the background and never will. (Side-effect to handle instead: with a tap-only detector, a long hold fires `onTap` on release and a double-tap fires `onTap` twice → explicit long-press handler + single-flight route latch required.)
- "The `.then` continuation is the only background-pref refresh" — FALSE (shared-controller path). Do not add a redundant background reload mechanism.
- "TC-198-67 / TC-194-01/34 must be rewritten" — FALSE under conditional mounting; leave them untouched as live locks.
- "Feature already implemented" — checked and dead: zero hits for `SettingsWired|buildSettingsSlideUpRoute|onSelfAvatarTap` under `lib/features/orbit/`.

## Real Scope

In scope: E1-E10 below (orbit tap wiring + gated modal semantics + long-press sculpt-entry uniformity; `AppShellChangeKind.identity`/`.mediaQuality` propagation; Feed header avatar removal + dead plumbing; `nearbyLocationService` threading; 1 l10n key).
Out of scope (owners named): Posts-screen settings entry (unchanged); `ConnectionStatusIndicator`/username editing (unchanged); 196's known double-push follow-up on OTHER routes (this plan guards only the new settings push); orbit2/orbit3 prototype cleanup (plan 205); tap-away 300ms + decode quantization (202's Accepted Differences).

## Files To Inspect Next
Production: `lib/features/orbit/presentation/widgets/orbital_visualization.dart`, `.../widgets/inner_circle_interactive_surface.dart`, `.../screens/orbit_screen.dart`, `.../screens/orbit_wired.dart`, `lib/features/feed/presentation/widgets/feed_header.dart`, `.../screens/feed_screen.dart`, `.../screens/feed_wired.dart`, `lib/features/feed/application/app_shell_controller.dart`, `lib/features/settings/presentation/screens/settings_wired.dart`, `lib/main.dart`, `lib/l10n/app_{en,ar,de}.arb`.
Direct tests: `test/features/orbit/presentation/widgets/orbital_visualization_test.dart`, `test/features/orbit/presentation/screens/orbit_wired_test.dart` (fixture donor), `orbit_sculpt_summon_wired_test.dart` (helpers donor + geometry sentinel), `test/features/feed/presentation/screens/feed_wired_test.dart`, `test/features/settings/presentation/screens/settings_wired_test.dart` + `settings_wired_posts_nearby_test.dart` (nearby-fake donor), `test/features/feed/application/app_shell_controller_test.dart`, `test/l10n/orbit_strings_parity_test.dart`.
Dependency-only context: `lib/features/settings/presentation/navigation/settings_route_transition.dart`, `lib/features/home/presentation/widgets/user_avatar.dart`, `lib/features/orbit/presentation/widgets/orbital_avatar.dart` (:155-165 conditional-mount precedent), `upload_profile_picture_use_case.dart`.

## Existing Tests Covering This Area
- `feed_wired_test.dart:408-441` — the ONLY Feed-avatar→Settings test (real SettingsWired from fakes; back via `chevron_left`; asserts `CosmicBackground` after return). GUARANTEED BREAKER → rewritten in place. In **FEED_TESTS** (run_test_gates.sh:182).
- `orbital_visualization_test.dart` — :192-198 center renders; :319-347 TC-198-67 (`friendTaps==0 && badgeTaps==1`, `warnIfMissed:false`); :405-424 TC-194-01/34; :464-486 TC-194-26 (unscoped single-GestureDetector `getSize`). All survive under conditional mounting; NOT in any curated array (feature-host-all glob + orbit cluster only).
- `orbit_wired_test.dart` (GROUP_TESTS:227) — `buildOrbitWired` fixture (:254-369) with all 8 required SettingsWired dep fakes; `wrapInNavigator: true` (:266) enables route-push observation; `appShellController` param defaults null — tests pass a real one (:942, :1034).
- `orbit_sculpt_summon_wired_test.dart` (GROUP_TESTS:254) — `bgPoint`/`longPressBg` helpers (:128-152); geometry lock on center avatar (:234, :809-824).
- `settings_wired_posts_nearby_test.dart` — local `NearbyLocationService` fake (donor).
- `app_shell_controller_test.dart` — exists (extend for new kinds).
- Missing coverage gaps: no test that the center avatar opens Settings (the RED surface); no `FeedHeader` test at all; no surface-level modal-gating test for a center tap.
- Curated arrays: FEED_TESTS:182 (feed_wired_test), GROUP_TESTS:227/:254 (orbit wired suites). Last-known counts (202/203 closure): orbit cluster 472, groups 1041, feed 285.

## Design (named seams — E1..E10)

- **E1 `orbital_visualization.dart`:** add `final VoidCallback? onSelfAvatarTap;` + `final VoidCallback? onSelfAvatarLongPress;` (ctor). In the center block (:171-180): when `onSelfAvatarTap != null`, wrap the `UserAvatar` in `Semantics(label: l10n.orbit_open_settings, button: true, child: GestureDetector(key: ValueKey('orbit-center-self-avatar'), behavior: HitTestBehavior.opaque, onTap: onSelfAvatarTap, onLongPressStart: onSelfAvatarLongPress == null ? null : (_) => onSelfAvatarLongPress!(), child: <avatar>))`. SAME `Positioned(left: cx-24, top: cy-24)`, same 48px box (geometry locks). Conditional mount is LOAD-BEARING (TC-194-26). Mirrors `orbital_avatar.dart:155-165`.
- **E2 `inner_circle_interactive_surface.dart`:** add `final VoidCallback? onSelfAvatarTap;` (ctor ~:70). Gated wrapper mirroring `_onNodeFriendTap:330-336` + the find-close branch of `_onBackgroundTap:318-326`:
  `void _onSelfAvatarTap() { if (_editing) { setState(() => _setEditing(false)); return; } if (_findOpen || _findActive) { setState(_closeFindInternal); return; } widget.onSelfAvatarTap?.call(); }`
  plus `void _onSelfAvatarLongPress() { if (!_editing) _enterEdit(); }`. Pass into `OrbitalVisualization` (~:593) null-preservingly: both `null` when `widget.onSelfAvatarTap == null`.
- **E3 `orbit_screen.dart`:** thread `VoidCallback? onSelfAvatarTap` through `OrbitScreen` (field ~:204, ctor ~:269) → `_OrbitScreenState.build` (~:336) → `_OrbitScreenView` (field ~:389, ctor ~:442) → `_buildInnerCircleSurface` (~:748).
- **E4 `orbit_wired.dart`:** new field `final NearbyLocationService? nearbyLocationService;` + imports (`settings_wired.dart`, `settings_route_transition.dart`). Handler with single-flight latch:
  `bool _settingsRouteActive = false;`
  `void _onSelfAvatarTap() { final shell = widget.appShellController; final privacy = widget.postsPrivacySettingsRepository; if (shell == null || privacy == null || _settingsRouteActive) return; _settingsRouteActive = true; Navigator.of(context).push(buildSettingsSlideUpRoute(builder: (_) => SettingsWired(identityRepo: widget.identityRepo, bridge: widget.bridge, contactRepo: widget.contactRepo, p2pService: widget.p2pService, secureKeyStore: widget.secureKeyStore, imageProcessor: widget.imageProcessor, appShellController: shell, postsPrivacySettingsRepository: privacy, introductionRepository: widget.introductionRepository, nearbyLocationService: widget.nearbyLocationService, transportMetrics: widget.transportMetrics, accountMigrationRunTransfer: widget.accountMigrationRunTransfer, accountMigrationSizeGate: widget.accountMigrationSizeGate))).whenComplete(() { _settingsRouteActive = false; }); }`
  (field names per orbit_wired's actual ctor params — executor verifies exact names at :101-113/:135/:152-155). Wire `onSelfAvatarTap: _onSelfAvatarTap` into the `OrbitScreen` instantiation (~:2365-2400). Extend `_onAppShellChanged` (:517-532) with an identity branch: `if (widget.appShellController?.lastChangeKind == AppShellChangeKind.identity) { unawaited(_loadIdentity()); return; }` — the SINGLE refresh mechanism for the center avatar (no `.then(_loadIdentity)` duplicate: dual mechanisms mask mutations — the INV-203-1 lesson).
- **E5 `app_shell_controller.dart`:** `enum AppShellChangeKind { tab, background, identity, mediaQuality }` (:9 — no switch on this enum exists anywhere, compile-safe) + `void notifyIdentityChanged()` / `void notifyMediaQualityChanged()` (set `_lastChangeKind`, `notifyListeners()`; mirror :40-47 minus payload).
- **E6 `settings_wired.dart`:** fire `widget.appShellController.notifyIdentityChanged()` after successful username save (`identityRepo.saveIdentity`, ~:414) AND after successful avatar upload + identity re-read (~:453-467, AFTER the use-case's invalidatePeer broadcasts so the resolver re-reads fresh bytes); fire `notifyMediaQualityChanged()` in `_onQualityChanged` (~:257-259) and `_onVideoQualityChanged` (~:274-276) after their saves.
- **E7 `feed_wired.dart` `_onShellChanged` (:2508-2531):** add branches — `identity` → `unawaited(_loadIdentity())`; `mediaQuality` → `unawaited(_loadQualityPreference()); unawaited(_loadVideoQualityPreference())`.
- **E8 Feed removal:** `feed_header.dart` — delete the `GestureDetector`+`UserAvatar` (:51-57) and the now-orphaned 8px spacer (:49); delete fields/ctor params `avatarBytes`/`peerId`/`onAvatarTap` (+ dead imports). `feed_screen.dart` — delete `userAvatarBytes` (:33/:93/:213) and `onAvatarTap` (:37/:109/:217). `feed_wired.dart` — delete `_onAvatarTap` (:1869-1898) incl. the whole `.then` block, `_avatarBytes` (:250, write :437, read :2680), the `IdentityAvatarResolver.resolve` call in `_loadIdentity` (:430; KEEP `_identity`/`_username`/`_peerId` sets and `_refreshOrbitBadgeCount`), args at :2680/:2694; prune imports flagged by analyze. KEEP the four `_load*` methods (initState + E7 use them).
- **E9 threading:** `feed_wired.dart:2542` block gains `nearbyLocationService: widget.nearbyLocationService`; `main.dart:4257` block gains `nearbyLocationService: widget.nearbyLocationService`.
- **E10 l10n (ORDERED FIRST):** add `orbit_open_settings` = "Open settings" (+ar/de) to the 3 ARBs; `flutter gen-l10n`; append to `newOrbitKeys` (`orbit_strings_parity_test.dart:18-48`) + exercise in the generated-API block (:116-152). A hardcoded `Semantics(label: '…')` literal is DENIED by the literal-scan (`l10n_integrity_test.dart:45-64` matches `label: '…'`) — the l10n key is mandatory, not optional. 198's two-step order applies: parity-list append REDs first; ARB+gen before E1 references the getter (else compile break).

## RED Test Catalog  (add BEFORE any production code — INV-RED-FIRST)

**NEW FILE A: `test/features/orbit/presentation/screens/orbit_settings_entry_test.dart`** — fixture cloned from `orbit_wired_test.dart` `buildOrbitWired` (:254-369) with `wrapInNavigator: true`, a real `AppShellController` passed, an `InMemoryPostsPrivacySettingsRepository`, and the `NearbyLocationService` fake pattern from `settings_wired_posts_nearby_test.dart`. NOTE: the whole file is compile-RED on HEAD (references `ValueKey('orbit-center-self-avatar')` targets + new `OrbitWired.nearbyLocationService` param) — each test below also documents its behavioral RED once compilable.

1. `A::TC-206-01 idle center tap opens Settings via slide-up`
   - Tier: widget/wired · Shape: pump OrbitWired w/ identity seeded; tap `byKey('orbit-center-self-avatar')`; settle.
   - RED on HEAD: no detector/key exists — tap finds nothing / Settings title absent.
   - GREEN: `find.text('Settings')` findsOneWidget AND `find.byType(SettingsWired)` findsOneWidget.
   - Mutation re-red: revert E4 push (or E3 threading, or E1 wrap) → red.
2. `A::TC-206-02 orbit-opened Settings is the full screen`
   - Tier: widget/wired · GREEN: settings title + posts-privacy section + recovery/mnemonic section + move-account affordance present (stable keys per settings tests).
   - RED on HEAD: Settings never opens. Mutation: revert E4 → red.
3. `A::TC-206-03 back returns to orbit intact`
   - Tier: widget/wired · Shape: open → `chevron_left` → settle. GREEN: orbit nodes visible, no edit banner, `SettingsWired` gone. RED on HEAD: can't open. Mutation: revert E4 → red.
4. `A::TC-206-04 identity without photo still opens Settings`
   - Tier: widget/wired · Shape: seed identity w/ null avatar bytes. GREEN: Settings opens. RED on HEAD: no detector. Mutation: revert E1 conditional wrap → red.
5. `A::TC-206-06 rapid taps push exactly one settings route`
   - Tier: widget/wired · Shape: two immediate taps (no settle between), then settle. GREEN: exactly one `SettingsWired`; one pop returns to orbit. RED on HEAD: no route at all (0 ≠ 1). Mutation: remove `_settingsRouteActive` latch → 2 routes → red. (Discriminator: assert `findsOneWidget`, not `findsWidgets`.)
6. `A::TC-206-07 long-press center enters edit, no Settings`
   - Tier: widget/wired · Shape: `tester.startGesture` hold ≥600ms on center key. GREEN: edit banner present AND `SettingsWired` findsNothing. RED on HEAD: no detector → no edit entry. Mutation: revert E2 `_onSelfAvatarLongPress` (or E1 onLongPressStart) → red.
7. `A::TC-206-08 mid-edit center tap ends edit, no Settings`
   - Tier: widget/wired · Shape: enter edit (longPressBg helper pattern at empty-space point, `orbit_sculpt_summon_wired_test.dart:128-152`), tap center key. GREEN: edit ended AND `SettingsWired` findsNothing. RED on HEAD: compile/no-detector. Mutation: make E2 wrapper call `widget.onSelfAvatarTap` unconditionally → Settings pushed mid-edit → red. (Also covers spec TC-206-12's no-push-while-editing half.)
8. `A::TC-206-09 find-open center tap closes find; next tap opens Settings`
   - Tier: widget/wired · Shape: open find pill, tap center → assert find closed + no Settings; tap center again → Settings opens. RED on HEAD: no detector. Mutation: drop the find branch in E2 → first tap opens Settings while find open → red. (Post-transition FULL state asserted: find closed, no route, then idle tap works.)
9. `A::TC-206-18 identity change-kind refreshes center avatar bytes`
   - Tier: widget/wired · Shape: seed avatar bytes A; pump; swap fake identityRepo avatar to B; `appShellController.notifyIdentityChanged()`; pump. GREEN: `tester.widget<UserAvatar>(center finder).avatarBytes` == B. RED on HEAD: `notifyIdentityChanged` doesn't exist (compile) / no reload branch. Mutation: revert E4 identity branch → stale A → red.
10. `A::TC-206-22 wiring-lock: SettingsWired receives orbit-threaded nearby service + SHARED controller`
    - Tier: widget/wired · GREEN: `tester.widget<SettingsWired>(...).nearbyLocationService` identical(fake) AND `.appShellController` identical(passed controller). RED on HEAD: `OrbitWired.nearbyLocationService` param absent (compile). Mutation: drop `nearbyLocationService:` from E4's SettingsWired call → red. (Pins spec TC-206-17's shared-instance requirement + TC-206-22.)
11. `A::TC-206-23 move-account reachable from orbit-opened Settings`
    - Tier: widget/wired · GREEN: tap move-account entry → move-account screen appears → back → Settings. RED on HEAD: Settings unreachable. Mutation: revert E4 → red.
12. `A::TC-206-29 reopen after pop`
    - Tier: widget/wired · Shape: open → pop → tap center again. GREEN: Settings opens again (latch released via `whenComplete`). RED on HEAD: unreachable. Mutation: remove `whenComplete` release → second open blocked → red. (Lifecycle/derived-state blind-spot row.)
13. `A::TC-206-27 reduce-motion open + return`
    - Tier: widget/wired · Shape: `MediaQuery(disableAnimations: true)` wrapper (donor `orbital_visualization_test.dart:97-111`). GREEN: opens + returns, `tester.takeException()` null. RED on HEAD: unreachable. Mutation: revert E4 → red.
14. `A::TC-206-24 source-guard: both OrbitWired ctor sites thread nearbyLocationService`
    - Tier: unit (plain `test()`, `File.readAsStringSync` — NOT testWidgets, per sync-IO rule). GREEN: regex finds `nearbyLocationService:` inside the `OrbitWired(` arg block in BOTH `feed_wired.dart` and `main.dart`. RED on HEAD: neither passes it. Mutation: remove either E9 arg → red. (House precedent: source-guard tests, e.g. orbit3 guard.)

**FILE B (REWRITE IN PLACE): `test/features/feed/presentation/screens/feed_wired_test.dart`**

15. `B::TC-206-17/01 'opens Settings from the orbit center avatar and reflects background change on Feed'` (replaces `'refreshes background preference after returning from Settings'` :408-441)
    - Tier: widget/wired (end-to-end host: FeedWired → embedded OrbitWired → SettingsWired) · Shape: pump FeedWired; `appShellController.switchTo('orbit')`; settle (orbit host mounts); tap center key; assert Settings; tap `ValueKey('background-choice-cosmic')`; assert keystore persisted; `chevron_left` back; `switchTo('feed')`; assert `CosmicBackground` findsOneWidget.
    - RED on HEAD: center key absent → Settings never opens.
    - Mutation re-red: revert E1/E3/E4 chain → red; ALSO revert E9 feed-site threading → wiring-lock (row 10) red. **PROD-CRITICAL leg** — the only full-chain proof of the migrated entry.
16. `B::TC-206-19 identity change-kind reloads Feed username`
    - Tier: widget/wired · Shape: pump; change username in fake identityRepo; `appShellController.notifyIdentityChanged()`; pump. GREEN: header shows new username. RED on HEAD: compile (`notifyIdentityChanged` absent) / stale username. Mutation: revert E7 identity branch → red.
17. `B::TC-206-20 mediaQuality change-kind reloads quality prefs`
    - Tier: widget/wired · Shape: persist new image+video quality into fake keystore; `notifyMediaQualityChanged()`; pump; open a 1:1 conversation from the feed. GREEN: `tester.widget<ConversationWired>(...)`'s image+video quality params equal the NEW values. RED on HEAD: compile / stale prefs. Mutation: revert E7 mediaQuality branch → red. (Discriminator: asserts the value CARRIED INTO the push at :1617-1618, not merely keystore state.)

**NEW FILE C: `test/features/feed/presentation/widgets/feed_header_test.dart`**

18. `C::TC-206-13 header renders username + connection dot, NO avatar`
    - Tier: widget · GREEN: `find.byType(UserAvatar)` findsNothing; `ConnectionStatusIndicator` findsOneWidget (fake p2p passed); `EditableUsernameWidget` findsOneWidget. RED on HEAD: `UserAvatar` findsOneWidget → red. Mutation: re-add the avatar block → red. (Destructive-action blind-spot row: asserts REMOVED + PRESERVED.)
19. `C::TC-206-15 username editing still works`
    - Tier: widget · GREEN: drive `EditableUsernameWidget` edit → `onUsernameChanged` fires with new value. RED on HEAD: passes (preservation-RED exemption: this row is a sentinel written alongside; acceptable GREEN-on-HEAD, kept for the removal's blast radius). Mutation: E8 accidentally dropping `onUsernameChanged` plumbing → red.
20. `C::TC-206-16 narrow width + long username, no overflow`
    - Tier: widget · Shape: 320px surface, 40-char username. GREEN: `tester.takeException()` null. RED on HEAD: passes (sentinel, same exemption as row 19 — guards the post-removal layout). Mutation: E8 leaving an unconstrained Row → red.

**FILE D (EXTEND): `test/features/orbit/presentation/widgets/orbital_visualization_test.dart`**

21. `D::TC-206-10 wired self-tap fires onSelfAvatarTap, never onFriendTap`
    - Tier: widget · Shape: 15 friends + `onSelfAvatarTap` counter + `onFriendTap` counter; tap center key. GREEN: `selfTaps == 1 && friendTaps == 0` (distinct-event discriminator). RED on HEAD: param doesn't exist (compile). Mutation: revert E1 → red.
22. `D::TC-206-25 semantics button + l10n label`
    - Tier: widget · GREEN: `find.bySemanticsLabel('Open settings')` findsOneWidget (house pattern `orbit_wired_test.dart:2730`). RED on HEAD: absent. Mutation: drop `Semantics` wrapper → red; ALSO reds if a hardcoded literal is used (l10n_integrity literal-scan).
23. `D::TC-206-26 hit target ≥48 and position unchanged`
    - Tier: widget · GREEN: `tester.getSize(byKey center) >= 48×48` AND `getRect(...).center` equals the pre-change canvas-center anchor (same expected values the sculpt/arcs locks use). RED on HEAD: key absent. Mutation: shrink the wrapper box or shift the Positioned → red.
24. `D::TC-206-05 null userPeerId → no center avatar, canvas tap no-op`
    - Tier: widget · GREEN: `UserAvatar` findsNothing; `tapAt(canvas center)` → no exception, selfTaps==0. RED on HEAD: `onSelfAvatarTap` param absent (compile). Mutation: E1 mounting the detector without the `userPeerId != null` guard → red.
25. `D::INV-206-1 no callback → no detector (TC-194-26 guard)`
    - Tier: widget · Shape: 1 friend, NO `onSelfAvatarTap`. GREEN: `find.byKey('orbit-center-self-avatar')` findsNothing AND unscoped `find.byType(GestureDetector)` still single-match (`tester.getSize` does not throw). RED on HEAD: key finder is dead code but the single-match half passes — the row's RED is the compile-RED of the new param elsewhere in the file; its GREEN half locks the conditional mount. Mutation: mount the detector unconditionally → "Too many elements" → red (and TC-194-26 itself reds).

**FILE E (EXTEND): `test/features/settings/presentation/screens/settings_wired_test.dart`**

26. `E::TC-206-19a username save fires AppShellChangeKind.identity`
    - Tier: widget · Shape: drive the username edit flow; listen on the passed controller. GREEN: listener fired with `lastChangeKind == identity`. RED on HEAD: compile (`identity` member absent). Mutation: revert E6 username notify → red.
27. `E::TC-206-18a avatar save fires AppShellChangeKind.identity`
    - Tier: widget · Shape: drive the profile-photo change with the fixture's fake `ImageProcessor` (donor: existing settings avatar flow tests; fallback seam if UI drive is impractical: assert at the post-upload block ~:453-467 via the same widget flow used in `profile_picture_flow_test.dart`). GREEN: `lastChangeKind == identity` after save. RED on HEAD: compile. Mutation: revert E6 avatar notify → red.
28. `E::TC-206-20a image+video quality saves fire AppShellChangeKind.mediaQuality`
    - Tier: widget · Shape: change each quality control. GREEN: two notifications, `lastChangeKind == mediaQuality`. RED on HEAD: compile. Mutation: revert E6 quality notifies → red.

**FILE F (EXTEND): `test/features/feed/application/app_shell_controller_test.dart`**

29. `F::notifyIdentityChanged sets kind + notifies` / `F::notifyMediaQualityChanged sets kind + notifies`
    - Tier: unit · GREEN: listener called once each; `lastChangeKind` correct; kinds distinct from `background`/`tab`. RED on HEAD: compile. Mutation: revert E5 → red.

**FILE G (EXTEND): `test/l10n/orbit_strings_parity_test.dart`**

30. `G::orbit_open_settings key parity + generated API`
    - Tier: unit · Shape: append `'orbit_open_settings'` to `newOrbitKeys` (:18-48) + generated-getter row (:116-152). RED on HEAD: key absent from ARBs → parity red. GREEN after E10. Mutation: remove the ARB key → red.

## Test Coverage Matrix  (ZERO empty cells in tier / mutation / gate / registration)

| Spec case | Behavior props | Tier | Test file::name | RED reason on HEAD | Mutation revert | Acceptance gate cmd | Harness registration |
|---|---|---|---|---|---|---|---|
| TC-206-01 | UI nav | widget/wired | A::TC-206-01 (+B row 15 full-chain) | no center detector/key | revert E1/E3/E4 | `flutter test test/features/orbit/presentation/screens/orbit_settings_entry_test.dart` | AUTO (glob) + **add to GROUP_TESTS** |
| TC-206-02 | UI content | widget/wired | A::TC-206-02 | Settings unreachable | revert E4 | same as -01 | AUTO + GROUP_TESTS |
| TC-206-03 | UI nav/state | widget/wired | A::TC-206-03 | Settings unreachable | revert E4 | same | AUTO + GROUP_TESTS |
| TC-206-04 | UI edge | widget/wired | A::TC-206-04 | no detector | revert E1 wrap | same | AUTO + GROUP_TESTS |
| TC-206-05 | UI null-guard | widget | D::TC-206-05 | compile (new param) | drop `userPeerId != null` guard | `flutter test test/features/orbit/presentation/widgets/orbital_visualization_test.dart` | AUTO (glob) |
| TC-206-06 | concurrency guard | widget/wired | A::TC-206-06 | no route pushed | remove latch | orbit_settings_entry cmd | AUTO + GROUP_TESTS |
| TC-206-07 | gesture (new) | widget/wired | A::TC-206-07 | no detector | revert E2 long-press | same | AUTO + GROUP_TESTS |
| TC-206-08 | modal gate | widget/wired | A::TC-206-08 | no detector | ungate E2 wrapper | same | AUTO + GROUP_TESTS |
| TC-206-09 | modal gate | widget/wired | A::TC-206-09 | no detector | drop find branch | same | AUTO + GROUP_TESTS |
| TC-206-10 | regression lock | widget | D::TC-206-10 + existing TC-198-67 (:319-347) stays green | compile (new param) | revert E1 | orbital_visualization cmd + orbit cluster | AUTO (glob) |
| TC-206-11 | preservation | widget/wired | existing 198 double-tap-labels suite (sentinel) | N/A — preserved-green sentinel | any E-edit breaking bg detector | `./scripts/run_test_gates.sh groups` | existing GROUP_TESTS |
| TC-206-12 | gesture safety | widget/wired | A::TC-206-08 (no-push-while-editing) + sculpt drag suite sentinel | covered by -08 | ungate E2 | groups gate | existing + A |
| TC-206-13 | removal | widget | C::TC-206-13 | avatar still present → findsNothing fails | re-add avatar block | `flutter test test/features/feed/presentation/widgets/feed_header_test.dart` | AUTO + **add to FEED_TESTS** |
| TC-206-14 | removal | widget | C::TC-206-13 (absence) + E8 deletes the only push site (`_onAvatarTap`) | avatar present | re-add `onAvatarTap` plumbing | feed_header cmd + `flutter analyze` (dead-param) | AUTO + FEED_TESTS |
| TC-206-15 | preservation | widget | C::TC-206-15 | GREEN-on-HEAD sentinel (documented) | E8 dropping username plumbing | feed_header cmd | AUTO + FEED_TESTS |
| TC-206-16 | layout | widget | C::TC-206-16 | GREEN-on-HEAD sentinel (documented) | E8 layout regression | feed_header cmd | AUTO + FEED_TESTS |
| TC-206-17 | propagation | widget/wired | B row 15 (rewrite) + A::TC-206-22 (shared-controller identity lock) | center key absent | revert E1/E3/E4/E9 | `./scripts/run_test_gates.sh feed` | existing FEED_TESTS:182 |
| TC-206-18 | propagation | widget/wired | A::TC-206-18 + E::TC-206-18a | `notifyIdentityChanged` absent (compile) | revert E4 branch / E6 notify | orbit_settings_entry + settings_wired cmds | AUTO + GROUP_TESTS / AUTO |
| TC-206-19 | propagation | widget/wired | B::TC-206-19 + E::TC-206-19a | compile / stale username | revert E7 / E6 | feed gate + settings cmd | FEED_TESTS / AUTO |
| TC-206-20 | propagation | widget/wired | B::TC-206-20 + E::TC-206-20a | compile / stale prefs into push | revert E7 / E6 | feed gate + settings cmd | FEED_TESTS / AUTO |
| TC-206-21 | preservation | widget | existing posts settings-entry coverage (sentinel) | N/A — preserved-green | any edit breaking posts entry | `./scripts/run_test_gates.sh posts` | existing POSTS_TESTS |
| TC-206-22 | dep parity | widget/wired | A::TC-206-22 | `nearbyLocationService` param absent (compile) | drop E4 arg | orbit_settings_entry cmd | AUTO + GROUP_TESTS |
| TC-206-23 | UI flow | widget/wired | A::TC-206-23 | Settings unreachable | revert E4 | same | AUTO + GROUP_TESTS |
| TC-206-24 | wiring both sites | unit (source-guard) + wired | A::TC-206-24 + B row 15 (feed path live) | args absent on HEAD | remove either E9 arg | orbit_settings_entry cmd | AUTO + GROUP_TESTS |
| TC-206-25 | a11y | widget | D::TC-206-25 | label absent | drop Semantics | orbital_visualization cmd | AUTO |
| TC-206-26 | a11y/geometry | widget | D::TC-206-26 + existing geometry locks (sculpt :809-824, arcs :123) | key absent | shrink/shift wrapper | orbital_visualization cmd + groups gate | AUTO / existing |
| TC-206-27 | a11y motion | widget/wired | A::TC-206-27 | Settings unreachable | revert E4 | orbit_settings_entry cmd | AUTO + GROUP_TESTS |
| TC-206-28 | lifecycle | N/A — justified | route-stack persistence across backgrounding is framework-guaranteed; NO new lifecycle-coupled state exists beyond the latch (covered by A::TC-206-29); a host test would be vacuous theater | — | — | — | — |
| TC-206-29 | lifecycle latch | widget/wired | A::TC-206-29 | Settings unreachable | remove `whenComplete` release | orbit_settings_entry cmd | AUTO + GROUP_TESTS |
| TC-206-30 | perf invariant | widget | 202's repaint/pulse suites + orbit cluster (sentinels; E1 adds a leaf outside the isolated boundaries) | N/A — preserved-green | E1 wrapping INSIDE the ring boundary | orbit cluster cmd | existing |
| INV-206-1 | conditional mount | widget | D::INV-206-1 + existing TC-194-26 stays green | compile (new param) | unconditional mount | orbital_visualization cmd | AUTO |
| l10n key | i18n | unit | G::orbit_open_settings | key absent from ARBs | remove ARB key | `flutter test test/l10n/orbit_strings_parity_test.dart` | existing explicit path (orbit cluster) |
| E5 kinds | pure logic | unit | F:: both notify tests | compile | revert E5 | `flutter test test/features/feed/application/app_shell_controller_test.dart` | AUTO (glob) |

## Blind-Spot Sweep
- **Lifecycle / derived-state durability:** the `_settingsRouteActive` latch reconstructs via `whenComplete` on ANY pop path → A::TC-206-29. The stale-avatar derived state (`_avatarBytes`) reconstructs via the identity change-kind → A::TC-206-18 / B::TC-206-19. App-restart identity load is the existing initState path (unchanged). Covered.
- **Sibling-surface consistency:** parallel entry points enumerated — Posts settings entry (TC-206-21 sentinel), satellite node taps (TC-206-10 + TC-198-67), background long-press/double-tap on empty space (198 suite sentinels), center long-press made uniform with background sculpt-entry (A::TC-206-07). The deliberate asymmetry — center double-tap is NOT labels-toggle (no `onDoubleTap` registered, avoiding the TC-54 tap-latency trap) — is test-locked by A::TC-206-06 (two rapid taps → one route, not a labels toggle). Covered.
- **Destructive-action side-effects:** the removal (E8) asserts what is REMOVED (avatar, its tap target) AND what is PRESERVED (username editing, connection dot, clean 320px layout) → C rows 18-20; dead-plumbing removal is compile-verified (`flutter analyze` 0 new + no orphaned params). Covered.
- **Invariant re-verification under new transitions:** the two NEW transitions (center-tap edit-exit; center-tap find-close) assert FULL post-transition state — edit ended + no route (A::TC-206-08); find closed + no route + subsequent idle tap opens (A::TC-206-09). The settings-pop transition re-verifies orbit surface state (A::TC-206-03). Covered.

## Invariants (locked by tests)
- INV-206-1: center detector/Semantics mount ONLY when the host wires the callback → D::INV-206-1 (+ TC-194-26 stays green).
- INV-206-2: a center tap NEVER fires `onFriendTap` → D::TC-206-10 discriminator + existing TC-198-67.
- INV-206-3: center avatar painted position/size unchanged → D::TC-206-26 + sculpt/arcs geometry locks.
- INV-206-4: Settings never opens from a non-idle surface → A::TC-206-08/-09.
- INV-206-5: single-flight settings route → A::TC-206-06/-29.
- INV-206-6: identity/mediaQuality propagation is controller-kind-driven, SINGLE mechanism (no `.then` duplicate that would mask mutations) → A::TC-206-18, B::TC-206-19/-20 red on branch reverts.
- INV-RED-FIRST and INV-MUTATION-VERIFIED apply to every row above.

## Step-By-Step Implementation Plan
1. `git status --short` snapshot (dirty tree expected — 205-era working-tree changes; do not revert).
2. **E10 first (l10n two-step):** append `orbit_open_settings` to `newOrbitKeys` + parity RED run; add the key to 3 ARBs; `flutter gen-l10n`; parity GREEN.
3. Add ALL RED tests (files A-G edits). Run the RED gate block below; confirm each fails for its documented reason (compile-RED where noted).
4. E5 (controller kinds) → F green. E1+E2+E3 (viz wrap, surface gating, threading) → D rows green. E4 (orbit push + latch + identity branch + nearby field) → A rows 1-13 green.
5. E6 (settings notifies) → E rows green. E7 (feed listener branches) → B rows 16-17 green.
6. E8 (feed removal) + rewrite B row 15 + C file → feed rows green. E9 (threading both sites) → A::TC-206-24 + A::TC-206-22 green.
7. Register: add `test/features/orbit/presentation/screens/orbit_settings_entry_test.dart` to **GROUP_TESTS** and `test/features/feed/presentation/widgets/feed_header_test.dart` to **FEED_TESTS** in `scripts/run_test_gates.sh`; verify both appear in their gate runs.
8. Stop-if: any surviving reference to `_avatarBytes`/`onAvatarTap` outside E8's list (scope drift — replan, don't hack); any orbit geometry lock red (position shifted — fix E1, never re-baseline the locks); TC-194-26 red (conditional mount violated).
9. Rerun direct → preservation → named gates. `graphify update .` + `./graphify-arch/refresh_arch_graph.sh` after code lands.

## Risks And Edge Cases
- Double-tap fires `onTap` twice (no double-tap recognizer) → latch → A::TC-206-06.
- Long hold fires `onTap` on release if no long-press handler → E1 registers `onLongPressStart` → A::TC-206-07.
- Unconditional detector breaks TC-194-26 ("Too many elements") → conditional mount → D::INV-206-1.
- Wrapper shifting the 48px box breaks sculpt/arcs geometry locks → same Positioned/box → D::TC-206-26.
- Notify-then-pop ordering: identity kind fires at SAVE time (Settings still open) — `_loadIdentity` re-runs beneath; safe because `upload_profile_picture_use_case:78-80` invalidates resolver caches BEFORE E6's notify → A::TC-206-18 exercises exactly this order.
- `AppShellChangeKind` enum growth: no switch statements exist on it (grep-verified) — compile-safe.
- Fallback-controller hazard (posts_wired :180-181 pattern): Orbit must pass the SHARED controller → locked by A::TC-206-22 identity check.
- Pre-existing l10n literal-scan debt (orbit3, noted at 203 closure; removed by 205 when it lands) may red `l10n_integrity_test` — known-failure, not this plan's scope; its 3-locale parity leg must stay green.
- 204/205 may execute before this plan → gate counts drift; recompute baselines, interpretation unchanged.

## Device/Relay Proof Profile
**host-only for closure** — pure Flutter UI/navigation + ChangeNotifier propagation; no OS boundary, no crypto, no relay, no DB schema (NO migration number). No `/sims` registration (nothing added to `integration_test/`). PROD-CRITICAL leg = B row 15 (full FeedWired→OrbitWired→SettingsWired host chain) — do NOT treat the A-file unit slices as sufficient without it. Optional manual smoke on a simulator after landing (launch, orbit tab, tap center, flip background) — evidence-only, not a closure gate.

## Acceptance Gates  (literal — copy/paste, with expected counts)
```bash
# RED (before production edits) — must FAIL for the documented reasons
flutter test test/l10n/orbit_strings_parity_test.dart                                    # RED: orbit_open_settings absent
flutter test test/features/orbit/presentation/screens/orbit_settings_entry_test.dart     # RED: compile (new params/keys)
flutter test test/features/feed/presentation/widgets/feed_header_test.dart               # RED: UserAvatar still present
flutter test test/features/feed/presentation/screens/feed_wired_test.dart --plain-name 'opens Settings from the orbit center avatar and reflects background change on Feed'   # RED: center key absent
flutter test test/features/orbit/presentation/widgets/orbital_visualization_test.dart    # RED: compile (new params)
flutter test test/features/settings/presentation/screens/settings_wired_test.dart        # RED: compile (notify methods absent)
flutter test test/features/feed/application/app_shell_controller_test.dart               # RED: compile (enum members absent)

# Direct GREEN (after fix) — all seven commands above pass; expected NEW test counts:
#   orbit_settings_entry_test: 14 · feed_header_test: 3 · feed_wired_test: +2 (and 1 rewritten)
#   orbital_visualization_test: +5 · settings_wired_test: +3 · app_shell_controller_test: +2 · parity: key in list

# Preservation sentinels + named gates (must stay green)
./scripts/run_test_gates.sh feed        # baseline 285 (post-203) + 5 new = 290; recompute if 204/205 landed
./scripts/run_test_gates.sh groups      # baseline 1041 (post-203) + 14 new (orbit_settings_entry pinned) = 1055
./scripts/run_test_gates.sh posts       # unchanged count — TC-206-21 sentinel
flutter test test/features/orbit/ test/l10n/orbit_strings_parity_test.dart   # orbit cluster: baseline 472 + 19 new ≈ 491
flutter test test/l10n/l10n_integrity_test.dart   # parity leg green; literal-scan may be red PRE-EXISTING (orbit3 debt, 203-documented)
./scripts/run_host_test_gates.sh feature-host-all # discovery: both new files listed

# Registration verification
grep -n "orbit_settings_entry_test" scripts/run_test_gates.sh   # in GROUP_TESTS
grep -n "feed_header_test" scripts/run_test_gates.sh            # in FEED_TESTS

# Hygiene
flutter analyze            # 0 new issues (also proves E8 dead-plumbing fully pruned)
git diff --check
```

## Known-Failure Interpretation
- Expected RED: the seven RED-block commands before implementation (compile-RED documented per file).
- Pre-existing dirty: 205-era working-tree modifications (orbit label styling, find pill, index/graph artifacts) — snapshot first, never revert.
- Pre-existing red: `l10n_integrity_test` literal-scan (orbit3 debt; owned by 205). Parity leg must be green.
- Environment blocker (NOT product): none expected — host-only.
- Scope drift (BLOCKING): any red in ONE_TO_ONE/TRANSPORT/INTRO gates, any orbit geometry-lock red, TC-194-26 red, TC-198-67 red.

## Done Criteria
- [ ] RED added first; each failed for its documented reason.
- [ ] Mutation-verified: every E1-E10 edit has a named re-red revert (see catalog/matrix).
- [ ] Direct GREEN + preservation sentinels + named gates pass at the stated counts.
- [ ] No DB schema change (no migration test needed — verified none).
- [ ] Host-only closure justified (no OS/multi-device/crypto boundary).
- [ ] GROUP_TESTS + FEED_TESTS registrations done and verified via gate runs.
- [ ] flutter analyze 0 new; git diff --check clean; no Scope Guard violations.
- [ ] `graphify update .` + `./graphify-arch/refresh_arch_graph.sh` run after landing.

## Scope Guard (hard "Do not")
- Do not add `onDoubleTap` to the center detector (re-introduces the TC-54 tap-latency trap the :556 comment exists to prevent).
- Do not mount the center GestureDetector/Semantics unconditionally (TC-194-26).
- Do not add a `.then(_loadIdentity)` on the orbit settings push IN ADDITION to the controller branch (dual mechanisms mask mutation reverts — INV-203-1 lesson).
- Do not re-baseline the sculpt/arcs geometry locks or TC-198-67; fix the code instead.
- Do not touch the background detector (:573-581), `_onBackgroundTap`, or the ring painter's hit-testing.
- Do not remove `ConnectionStatusIndicator` or username editing from the Feed header.
- Do not harden `OrbitWired.appShellController`/`postsPrivacySettingsRepository` to required non-null (ctor-site churn beyond scope; the null-guard suffices).
- Do not modify the Posts settings entry, `buildSettingsSlideUpRoute`, or `SettingsWired`'s public API.
- Do not register hardcoded semantics label literals (l10n literal-scan denies them).

## Accepted Differences / Intentionally Out Of Scope
- Center double-tap ≠ labels-toggle (deliberate; latency trap). Locked by A::TC-206-06.
- Username staleness on the Orbit screen itself: Orbit renders no self username (refuter-verified: `_identity` consumed only for `.peerId`) — the identity reload still runs for avatar correctness.
- `main.dart:4257` intro-orbit path proven by source-guard + compile only (no host test pumps `MyApp`); A::TC-206-24 is the guard. Full behavioral proof rides the feed-embedded path (B row 15).
- Backgrounding-while-open (TC-206-28): justified N/A (framework route stack; no new lifecycle state beyond the latch).
- The pre-existing double-push exposure on OTHER routes (196 finding) stays with its owner; this plan guards only the new settings push.

## Dependency Impact
- Plan 205 (find-UX/prototype cleanup): touches the same surface files (`inner_circle_interactive_surface.dart`, `orbit_screen.dart`) — if 205 lands first, re-anchor E2/E3 line numbers (mechanisms unaffected); if this lands first, 205's TC-198F-04 band re-baseline is unaffected (center avatar geometry unchanged here).
- Future settings entry points get identity/quality propagation FOR FREE via the controller kinds (E5-E7) — record in any follow-up spec.

## Reviewer Findings
Sufficiency self-check (Step 4, blocking checklist): all core conditions hold — every spec TC-206-01..30 has ≥1 named matrix row (28 test-bearing rows, 2 justified sentinels/N-A: TC-206-21 posts-gate sentinel, TC-206-28 justified N/A); every INV locked; every E1-E10 edit mutation-named; compile-REDs documented per file (198 two-step precedent); no migration (none needed); no OS-boundary rows (host-only justified); PROD-CRITICAL leg named (B row 15); preservation sentinels named with commands+counts; literal gates present; harness registration named per new test (2 manual pins: GROUP_TESTS + FEED_TESTS; rest AUTO); known-failure interpretation written; dirty-tree snapshot planned; refuted findings recorded. Blind-spot sweep: 4/4 with rows or justified N/A. Zero empty matrix cells in tier/mutation/gate/registration. Two rows (C::15/16) are GREEN-on-HEAD sentinels — documented exemption (they guard the E8 removal's blast radius, cannot be RED before the removal exists in the same file as the RED TC-206-13).

## Arbiter Decision
Structural blockers: none. Deferred details: exact ctor param names in E4 (executor verifies at orbit_wired.dart:101-155); stable finder keys for settings sections in A::TC-206-02 (executor picks from settings tests). Accepted differences: as listed. Verdict: implementation-ready.

## Final Execution Verdict
Verdict: **IMPLEMENTED + host-green** (commit `cb69371b`, 2026-07-04) | Files changed: 10 production (app_shell_controller, orbital_visualization, inner_circle_interactive_surface, orbit_screen, orbit_wired, settings_wired, feed_wired, feed_screen, feed_header, main) + 3 ARB + 4 generated l10n + 1 gate script + 7 test files (2 new: orbit_settings_entry_test, feed_header_test) + 2 docs | Tests run: orbit cluster 501 GREEN · feed 292 GREEN · group 1060 GREEN (1 pre-existing flake `group_membership_smoke_test::B6` — passes in isolation, unrelated to this change) · l10n_integrity GREEN · settings_wired 19 GREEN · new suites all GREEN (orbit_settings_entry 14, feed_header 3, +5 orbital-viz, feed_wired +2 & 1 rewritten full-chain, settings +3, controller +2, parity key) | Blocking: none | QA verdict: PASS | Non-blocking follow-ups: TC-206-18a landed as a source-guard (driving the full ImagePicker→upload→image-decode pipeline in a widget test never settles — the behavioral avatar propagation is proven by A::TC-206-18 + the identity change-kind mechanism); posts gate is device-only in this env but TC-206-21 holds by construction (zero posts files touched).

**Accepted difference vs plan (executor):** A::TC-206-08 enters edit via the center long-press (proven by TC-206-07) rather than a background long-press; the fixture wires `feedUnreadCountListenable` so it renders the real persistent-nav layout (no standalone close button overlapping the find pill). B row 15's final assertion is scoped to the Feed pane (`find.descendant(of: FeedScreen, ...)`) because the embedded orbit host stays mounted and also renders a `CosmicBackground`. TC-206-18a is a source-guard (see above).
