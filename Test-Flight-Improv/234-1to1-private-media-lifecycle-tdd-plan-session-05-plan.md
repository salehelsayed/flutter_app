# Plan 234 Session 05 — Private-route UX and native Android/iOS protection truth

Status: accepted
Source: `Test-Flight-Improv/234-1to1-private-media-lifecycle-tdd-plan-session-breakdown.md` Session 05
Run mode: implementation + availability-bounded native/device proof
Dependencies: Plan 234 Sessions 02, 03, and 04 are accepted; Sessions 01-04 remain closed absent concrete regression evidence
Migration owner: none; Plan 234 v100 is already landed and Plan 238 retains sequential v101

## Planning Progress

| Time | Role | Files inspected since prior update | Decision / blocker | Next action |
|---|---|---|---|---|
| 2026-07-11 | Evidence Collector | `AGENTS.md`; Graphify skill; accepted Plan-234 source/breakdown and Sessions 01-04 closures; `MediaViewerProtection`; `FullScreenTypedMediaViewer`; `PrivateMediaLifecycleEngine`; direct conversation viewer adapters; Android/iOS entry files; tests/gates; live devices | Graphify returned current, anchored context for the shared viewer, lifecycle engine, and direct lifecycle repository. Current direct UI intentionally rejects private media from both ordinary viewers; no dedicated private route, first-frame renderer callback, Dart/native protection coordinator, Android `FLAG_SECURE`, iOS capture observer/cover, platform proof, or Session-05 test exists. | Freeze the route/lifecycle/native ownership contract and exact RED/GREEN gates. |
| 2026-07-11 | Planner | Session-03 reveal/cleanup engine; Session-04 current-parent decision; current playback adapter and viewer rendering; `MainActivity.kt`; `AppDelegate.swift`; Xcode project/native-test precedent; l10n assets | Use one dedicated single-item direct private route. Await native protection before any byte-rendering widget is built; View Once alone owns the Session-03 opening lease; protected/disappearing remain repeat-view/non-consume modes. Keep generic safe actions in the dedicated wrapper and do not weaken shared action eligibility. | Produce an execution-ready owner/test/device contract. |
| 2026-07-11 | Reviewer / Arbiter | Counterexamples for pre-existing secure flags, nested/late exits, first-frame timing, pre-frame rollback, background/capture, metadata leakage, ordinary-viewer preservation, and unavailable targets | No structural blocker. Platform guarantees remain deliberately asymmetric: Android prevention through route-scoped `FLAG_SECURE`; iOS detection/obscuring/dismissal with no screenshot-prevention claim. Unavailable targets are N/A under repository policy, not a reason to widen scope or wait for a model/OS band. | Stop planning; fresh Execution+QA begins with causal Dart/native/platform REDs. |

## Execution Preflight

- Take a fresh `git status --short` plus individual hashes and one aggregate hash over every owner/test/gate file listed below before creating a test. Preserve the shared dirty worktree; do not reset, stash, checkout, revert, or reformat unrelated hunks.
- Re-run `flutter devices --machine`, `adb devices -l`, `xcrun simctl list devices available`, and `flutter emulators` immediately before device work. Pin every device command to an explicit ID discovered in that execution.
- Planning snapshot only, captured 2026-07-11:
  - USB Android: Pixel 6 `21071FDF600CSC`, Android 16 / API 36.
  - Available but not running Android AVD: `mknoon_play_35`; it is not a Session-05 requirement.
  - Booted iOS simulator: iPhone 16e `DBE8C32E-9F19-4593-860A-B41113791D79`, iOS 26.5.
  - Historical iOS simulator `674DFFF6-5F38-4235-93F6-AF7FBF86AE65` is available but was shut down at planning time.
  - Available USB iPhones are optional confidence only; the iOS-specific selected proof may use an available simulator.
- These IDs are not immutable acceptance inputs. If an ID disappears, choose another currently available same-platform target. If no target for a platform exists, record that device leg exactly as `N/A (target unavailable by project policy)` and retain its host/native proof; do not wait for unavailable hardware.
- Confirm no private-protection process, Flutter test, Gradle test, `xcodebuild`, integration runner, or Graphify refresh is active before execution. Do not terminate an unrelated process.
- Record the initial output of the literal scope guard. Non-empty output may be authorized pre-existing work; acceptance compares the final output against this baseline and forbids any new Session-05-attributable path outside the allowlist.
- Acceptance requires every Done Criterion, every literal focused/named/native/device/static/scope gate, final Graphify `affected` over the actual production delta, fresh independent QA, and exactly one incremental architecture refresh after QA accepts.

## Validated Execution Contract

- **Source of truth:** this plan under `AGENTS.md`, the accepted D-234-01..08 contract, the accepted Session-03 lifecycle APIs, the accepted Session-04 current-parent capability decision, and the executable gate arrays.
- **Owned outcome:** a direct-only, single-item private viewer route with truthful lifecycle UX and route-scoped native protection. It may consume existing v100 state and Session-03 callbacks; it adds no schema, policy mode, receipt, transport authority, or actual Picture in Picture.
- **RED first:** create the dedicated Dart route/coordinator tests, Kotlin native test, Swift native test, and platform integration proof before their production implementations. Capture non-zero output caused by the missing route/coordinator/native contract, not a file-not-found intake run or malformed fixture.
- **Protection-before-bytes:** native `enter` must complete successfully before a widget receives a private local path or builds an image/video surface. After `enter` succeeds, mandatory post-enter/pre-widget revalidation must still prove the exact current parent/attachment/path and lifecycle authority before any route widget is built. A channel failure, missing activity/window, stale/terminal parent, denied current decision, lost lease, expired deadline, or route-push failure exposes no bytes and fails closed.
- **View Once lifecycle:** call `PrivateMediaLifecycleEngine.openViewOnce` before byte exposure. Record `markFirstFrame` exactly once from an actual rendered image/video frame. Only a proven renderer/decode failure before that frame may call `rollbackPreFirstFrame`. Back, explicit close, route-push failure, background/inactive/detach, capture handling, post-frame error, or dispose terminalizes through `terminalizeViewOnce`; none may restore `available`.
- **Protected/disappearing lifecycle:** revalidate the current parent/attachment before opening and on relevant lifecycle/capture events. These modes do not mint an opening lease or consume on ordinary exit. Protected stays repeat-viewable. Disappearing remains governed by the persisted deadline/high-water scheduler; an expired/currently terminal parent is covered/dismissed and cleaned by the application lifecycle authority.
- **Native ownership:** the Dart/native coordinator uses opaque route-owner tokens with idempotent enter/exit. Duplicate, nested, late, error, and dispose sequences settle once. Android preserves a pre-existing secure flag and clears only the flag ownership it added after the last private owner exits. iOS installs/removes observers exactly once, covers private pixels before app-switcher snapshots, covers/pauses during active capture, reports screenshot/capture signals, and restores ordinary routes.
- **Privacy:** the private route never renders caption, MIME, kind label, path, size, dimensions, duration metadata, key, nonce, thumbnail, sender display metadata, or lifecycle internals. Diagnostics/logs contain only bounded event/outcome information; no path, token, policy mode, duration, expiry, lifecycle state, key, nonce, or media bytes.
- **Safe actions:** the dedicated private wrapper may expose only freshly revalidated generic Reply, privacy-minimized Info, and Delete-for-me. It must not relax `MediaViewerItem.isActionEligible`, ordinary/shared viewer capability logic, or Session-04 Save/Files/Share/Forward/bookmark/library/PiP denial. The private render item has no shared-viewer action capabilities and no resume store.
- **Named gates:** focused causal and exact preservation suites, native unit commands, the available-platform proof, curated `1to1`, the 1:1 host inventory, completeness, formatter/analyzer, native project/build checks, diff/scope guards, Graphify `affected`, and independent QA. No `core-host-all`, `feature-host-all`, or full `host-all` is a Session-05 gate.
- **QA/Graphify cadence:** run `affected` after the final attributable production delta and before independent QA. Bounded fix passes must add a causal regression before changing behavior and rerun every affected gate. Do not refresh Graphify during implementation or rejected QA. After fresh QA returns `accepted` with no blocking finding, run exactly one `./graphify-arch/refresh_arch_graph.sh --incremental`.
- **Dependency release:** Plan 247 Session 03 remains serialization-blocked while Session 05 is planned, executing, in QA, or awaiting closure. Release it only after this plan has an accepted Execution Result, final QA, exactly one post-QA refresh, and a persisted Closure Audit. Plan 247 must then refresh against the landed shared-viewer/protection contract and make only additive action changes.

## Problem And Current Evidence

- `ConversationScreen._openOrdinaryMediaViewer` explicitly rejects every non-ordinary decision. This correctly closes Session-04 bypasses but leaves available private media without its dedicated Session-05 route.
- `FullScreenTypedMediaViewer` renders ordinary metadata, has no native protection owner, has no first-rendered-frame/pre-frame-failure callbacks, and does not coordinate route exit with private lifecycle state.
- `MediaViewerProtection` currently describes byte availability/action protection only. It must not be repurposed so a private path enters an ordinary viewer or protected items gain ordinary actions.
- `PrivateMediaLifecycleEngine` already supplies the authoritative View Once operations: `openViewOnce`, `markFirstFrame`, `rollbackPreFirstFrame`, and `terminalizeViewOnce`. Session 05 adapts those methods; it does not duplicate their CAS/cleanup logic.
- `DirectPrivateMediaActionEligibility` and the wired action-decision loader already distinguish ordinary, available private, terminal, unsupported, hidden, deleted, corrupt, and stale identities. That fresh decision remains the route/action authority.
- Current Android source has no `FLAG_SECURE` coordinator. Current iOS source has no capture/screenshot observer or app-switcher privacy cover. The existing received-media egress handlers are unrelated and must remain unchanged.
- Existing private l10n covers composer mode/duration, generic `Private media`, device-local expiry, and View Once meaning. Session 05 still needs route state, unsupported/update-delete guidance, and platform-limit disclosure without leaking media metadata.

## Scope Contract And Guard

### Dedicated direct private route

Add a direct-only route controller, for example `DirectPrivateMediaViewerController`, and a dedicated `DirectPrivateMediaViewer` wrapper. The controller must accept only stable direct `messageId`/`attachmentId`, fresh loaders/decision authority, the existing direct lifecycle engine, and the native protection coordinator. It must not accept a caller path, MIME-derived policy, stale `ConversationMessage`, or an `isPrivate` boolean as authority.

Opening order is binding:

1. Reload the exact current direct parent and attachment and evaluate the Session-04 decision.
2. Deny unsupported/terminal/hidden/deleted/corrupt/missing/stale/wrong-owner rows before reading or exposing a local path.
3. For View Once, obtain the Session-03 opening lease under the attachment lock. For protected/disappearing, verify the exact canonical app-owned path and current availability without changing lifecycle state.
4. Await native protection `enter` for a new opaque route owner.
5. Re-read the exact parent/attachment immediately after `enter` and before any path is handed to a widget. View Once must retain the same active opening lease; disappearing must atomically advance/check persisted high-water and deny at expiry; protected must still be exact-current `available` with the canonical app-owned path. A loss here builds no route, terminalizes View Once rather than rolling it back, and releases protection in `finally`.
6. Only after successful post-enter revalidation, build and push one single-item private route. Never include ordinary/private siblings or library paging.
7. Report one real first rendered frame or one proven pre-frame renderer failure. Recheck current state before safe actions.
8. Cover private pixels synchronously before terminalization/dismissal/ordinary restoration. Settle lifecycle, remove the route, then release the native owner in completion-safe `finally` logic.

The route must handle double tap/open, concurrent route attempts, a parent becoming terminal between tap and push, navigation failure, initialization failure, image decode error, video initialize error, page/widget disposal, app inactive/paused/hidden/detached, screenshot signal, active-capture begin/end, and native enter/exit errors without duplicate callbacks or byte exposure.

Video first-frame truth is frozen as the first Flutter raster that contains the initialized video surface. Playback-adapter initialization completion and `buildSurface()` alone are not a rendered frame. The route schedules/observes the post-raster frame only after the initialized surface is mounted, reports exactly one first-frame callback then, reports zero callbacks if initialization succeeds but no raster occurs, and reports one pre-frame failure for initialization/render failure. If implementation requires a bounded callback seam in `media_playback_adapter.dart`, that file and its fake become conditional owners and must be included in focused format/analyze/tests; no native video callback or timer approximation is accepted.

`ConversationWired` must construct the route only after runtime-qualifying the current repositories as the accepted lifecycle capabilities: `MessageRepository` as `DirectPrivateMediaLifecycleRepository`; the attachment repository as both `DirectPrivateMediaCleanupRepository` and `DirectPrivateMediaCleanupRuntime`; and the repository's existing `directPrivateMediaLifecycleLock`. Missing capability hides/denies the private route without throwing. One retained engine/controller instance owns the same opening lease and lock from open through post-enter revalidation, first frame, rollback/terminalization, and cleanup; no new lock or engine recreation between callbacks is allowed.

### Render and state truth

- Available unopened private media renders a generic private placeholder and explicit in-app open affordance. If bytes are not present, reuse the accepted explicit app-local manual-download path; never auto-download from the viewer.
- Opening renders a generic progress state with no thumbnail or metadata.
- Viewing renders only the media surface plus generic safe controls/copy. The route never enables PiP and never supplies durable video resume storage.
- Consumed and expired states remain visible as generic terminal parent state even after cleanup removed the attachment row; they do not open a viewer or offer download. Conversation rendering must project this placeholder from the durable parent alone, with no synthetic attachment/attachment ID, path, thumbnail, download affordance, or ordinary media grid. Parent-level generic Reply/Info/Delete remains available through fresh current-parent authority.
- Unsupported/corrupt state gives update/delete guidance, remains redacted, and does not open or download.
- Protected exits normally and remains available. Disappearing exits normally unless the authoritative scheduler/current read says expired. View Once follows the binding lease rules above.
- Private quote text remains exactly the localized meaning `Private media`; privacy-minimized Info remains Session-04 authority. No Session-05 widget reconstructs metadata from a path or attachment snapshot.

Add localized keys with these exact English meanings and semantically equivalent reviewed German/Arabic values:

| State / disclosure | Required English meaning | Forbidden implication |
|---|---|---|
| open | `Open private media` | no same-thread/share/download claim |
| opening | `Opening private media…` | no thumbnail/type/mode disclosure |
| consumed | `Already viewed on this device` | no account-wide consumption claim |
| expired | `Expired on this device` | no sender-synchronized expiry claim |
| unsupported | `Update Mknoon to view this private media, or delete it` | no ordinary fallback |
| Android capture | screenshots and screen recording are blocked only while this private route is open | no protection after exit or against another camera |
| iOS capture | iOS cannot reliably prevent screenshots; capture is detected and private media is covered/dismissed | no screenshot-prevention claim |
| general limit | another device or camera can still photograph the screen | no impossible software guarantee |

Tests must assert absence of forbidden metadata and false claims in EN/DE/AR on a small viewport and RTL Arabic. Generated localization files are outputs of the normal Flutter l10n process, not hand-maintained alternate truth.

### Dart/native protection coordinator

Use bounded channels such as `mknoon/private_media_protection` and `mknoon/private_media_protection/events`. Exact method/result maps must be frozen by the RED tests before implementation. Only `enter` and `exit` command payloads may carry the opaque owner token needed for reference ownership. Event payloads, results, outcomes, errors, diagnostics, logs, and UI must never expose that token. Private mode, duration, expiry, message/attachment ID, path, MIME, key, nonce, caption, or bytes must never cross any channel.

The Dart coordinator must:

- make `enter`, `exit`, capture-event subscription, and disposal injectable/testable;
- coalesce duplicate operations and settle each Future exactly once;
- keep a private cover active while native enter/exit is unresolved;
- fail closed on `MissingPluginException`, malformed results, event-channel error/done, activity/window absence, or disposal;
- never own lifecycle CAS, expiry, cleanup, download, or message persistence; and
- expose no actual PiP API.

Android must:

- add `WindowManager.LayoutParams.FLAG_SECURE` on the current activity window before enter success;
- track opaque active owners and remove only Session-05-owned secure state after the last exit;
- preserve a flag that was already set by another owner;
- handle activity recreation/detach, duplicate/unknown tokens, late calls, and completion once;
- register through `MainActivity` without changing received-media egress, Bridge, notification, or Go wiring; and
- expose only the frozen `debugGetState` / `debugInjectEvent` proof methods when `BuildConfig.DEBUG` is true; and
- emit no raw token/path/media/policy diagnostic.

iOS must:

- register one bounded coordinator from `AppDelegate` and add it to the Runner/RunnerTests project sources;
- observe `UIApplication.userDidTakeScreenshotNotification`, `UIScreen.capturedDidChangeNotification`, and applicable app/scene inactive/background/foreground transitions;
- place an opaque cover above private content before app-switcher snapshots and while capture is active, signal Dart, and restore only when current ownership/state permits;
- resolve the foreground `UIWindowScene`/window rather than assuming a process-global window, observe active capture through availability-correct `UIScreen.isCaptured` handling, and expose only the frozen proof methods under `#if DEBUG`;
- retain/remove observers and covers exactly once across nested/late/dispose sequences;
- make screenshot handling truthful detection after the event, never prevention; and
- emit no raw token/path/media/policy diagnostic.

### Exact production owner allowlist

Expected new Dart files:

- `lib/core/media/private_media_protection_coordinator.dart`
- `lib/features/conversation/application/direct_private_media_viewer_controller.dart`
- `lib/features/conversation/presentation/screens/direct_private_media_viewer.dart`

Expected existing Dart owners:

- `lib/core/media/private_media_lifecycle_engine.dart` only if a causal route adapter test proves a minimal callback/accessor is missing; its accepted CAS semantics must not change
- `lib/features/conversation/application/direct_private_media_lifecycle.dart` only for the minimal route adapter seam proven missing
- `lib/features/conversation/presentation/screens/conversation_screen.dart`
- `lib/features/conversation/presentation/screens/conversation_wired.dart`
- `lib/shared/widgets/media/media_viewer_item.dart`
- `lib/shared/widgets/media/full_screen_typed_media_viewer.dart`
- `lib/shared/widgets/media/media_playback_adapter.dart` and `test/shared/widgets/media/fake_media_playback_adapter.dart` only if the causal video first-raster test proves a minimal post-raster callback seam is required
- `lib/l10n/app_en.arb`, `lib/l10n/app_de.arb`, `lib/l10n/app_ar.arb`, and generated localization outputs

Expected native owners:

- `android/app/build.gradle.kts` for the causal debug-only `BuildConfig.DEBUG` proof boundary
- `android/app/src/main/kotlin/com/mknoon/app/MainActivity.kt`
- new `android/app/src/main/kotlin/com/mknoon/app/PrivateMediaProtectionHandler.kt`
- `ios/Runner/AppDelegate.swift`
- new `ios/Runner/PrivateMediaProtectionCoordinator.swift`
- `ios/Runner.xcodeproj/project.pbxproj`

Expected gate/doc owners during execution:

- `scripts/run_test_gates.sh` — only the exact `ONE_TO_ONE_TESTS` registration hunk
- `scripts/run_host_test_gates.sh` — only the exact `ONE_TO_ONE_HOST_TESTS` registration hunk
- `Test-Flight-Improv/test-gate-definitions.md` — exact host/native/device classifications
- this plan, the Plan-234 breakdown, and the Plan-234 source plan at closure

If another production file is compile-required, stop and record the causal missing seam before expanding the allowlist. Do not silently thread the coordinator through Feed, Orbit, group, announcement, or app-wide service locators. `ConversationWired` already owns the repository/media dependencies needed to construct a route-scoped adapter; `main.dart` is not an expected owner unless a focused wiring RED proves that using the existing single engine is mandatory.

## Strict Non-Goals

- No migration, schema, database version, registry, v101, or Plan-238 work.
- No new policy mode, duration, receipt, account-wide consumption, sender revocation, relay revocation, recovery-after-uninstall, or Go/libp2p/relay change.
- No group, announcement, Plan-247 implementation, or cross-lane private lifecycle behavior.
- No actual PiP API, native PiP, Plan-243 edit, playback window, or floating player. Session-04 `canEnterPictureInPicture == false` remains the only private PiP output.
- No Session-06 paired-device lifecycle journey, aggregate closure, index/reference synchronization, or final Plan-234 verdict.
- No native-owned cleanup, DB mutation, download, lifecycle transition, key deletion, or expiry timer.
- No change to ordinary direct/group viewers, received-media egress, shared-library paging, Forward, bookmark, notification, Bridge, P2P, or native egress behavior except exact preservation-compatible optional viewer callbacks.

## Tests To Add Before Production

### Dart causal tests

Create `test/features/conversation/presentation/screens/direct_private_media_viewer_test.dart` first with at least these named tests:

- `view once protects before bytes records one first frame and terminalizes on every non-decode exit`
- `only proven pre-first-frame decode failure rolls view once back to available`
- `protected and disappearing private routes revalidate without consume and expiry dismisses fail closed`
- `private route states copy safe actions metadata and typed PiP remain privacy minimized`
- `ordinary direct and group viewers remain unchanged when private callbacks are absent`
- `post-enter terminal delete expiry or lease loss builds no route and view once terminalizes`
- `attachmentless consumed and expired parents render generic terminal actions without synthetic media`
- `wired route reuses one lifecycle lock and engine and denies missing runtime capabilities`

Create `test/core/media/private_media_protection_coordinator_test.dart` first with at least:

- `private route protection enter exit and capture events settle exactly once`
- `nested duplicate late and dispose ownership restores ordinary routes fail closed`
- `channel payloads diagnostics and failures expose no private metadata`

Extend `test/shared/widgets/media/full_screen_typed_media_viewer_test.dart` before production with:

- `private render lifecycle reports one real first frame or one pre-frame failure`
- `video initialization reports zero frames until one mounted post-raster surface and then settles once`
- `private presentation suppresses metadata resume actions and PiP without changing ordinary pages`

The first focused runs must fail because the dedicated route/coordinator/render-lifecycle APIs are absent or behavior is missing. A failure caused only by a bad matcher, missing fixture, or nonexistent test file is intake evidence, not causal RED.

### Native causal tests

Add `android/app/src/test/kotlin/com/mknoon/app/PrivateMediaProtectionNativeTest.kt` before the Kotlin production handler. It must cover actual window-flag mutation through injected activity/window seams, pre-existing flag preservation, multiple owners, duplicate/unknown/late exits, activity detach/rebind, malformed calls, completion once, and redacted diagnostics.

Add `ios/RunnerTests/PrivateMediaProtectionCoordinatorTests.swift` before the Swift production coordinator. Register the test source in the RunnerTests target before the RED command while the production coordinator remains absent, so `xcodebuild` compiles the causal test and fails for the intended missing contract rather than silently selecting zero tests. Register the production source in the Runner target only during GREEN. The suite must cover owner reference semantics, screenshot notification, active-capture begin/end, inactive/background cover before restoration, ordinary-route restoration, observer teardown, malformed calls, completion once, and redacted diagnostics. It must include a mutation that would call screenshot handling “prevention” and fail the truthful-copy/source assertion.

### Platform causal proof

Add `integration_test/direct_private_media_platform_protection_proof_test.dart` before production. It must be fully automated and expose stable proof steps for:

- native protection acknowledged before the first private render;
- Android secure-window state on private enter and restoration on exit/error/background;
- iOS privacy cover/capture event/dismissal and ordinary restoration through a test-injected native capture signal;
- View Once first-frame/exit behavior, protected repeat entry, disappearing terminal denial, unsupported denial, and typed PiP false;
- no user tap dependency beyond the automated Flutter harness and no media/policy secret in output.

Freeze one debug/test-only native proof seam on the protection method channel so the automated Flutter proof can observe state without pretending to perform or inspect a real OS screenshot. In debug/test builds only:

- `debugGetState` accepts no arguments and returns bounded booleans/counts only: Android `secureApplied`/`activeOwnerCount`; iOS scene-aware `coverVisible`/`captureActive`/`activeOwnerCount`.
- `debugInjectEvent` accepts only one enumerated event (`screenshot`, `captureStarted`, `captureStopped`, `inactive`, `background`, or `foreground`) and returns a bounded acknowledgement.
- Neither method returns or accepts owner tokens, message/attachment IDs, paths, policy/lifecycle values, or media metadata. They are unavailable/not implemented in release builds and are excluded from production diagnostics.

Android integration proof claims live-window `FLAG_SECURE` application/restoration observed through `debugGetState`, supported by the native window-mutation unit test; it does not claim that the harness executed a real screenshot. iOS proof uses the selected simulator scene/window, injects the bounded capture/lifecycle events, and verifies cover/dismiss/restoration; production still observes availability-correct `UIScreen.isCaptured` changes and screenshot notifications.

Run one explicit available target for the initial platform compile/behavior RED. Final GREEN must run on each applicable available Android/iOS platform target selected after live re-resolution, using the debug-only proof seam rather than unobservable OS assumptions.

### Required preservation suites

- `test/features/conversation/application/consume_private_media_use_case_test.dart`
- `test/features/conversation/application/private_media_cleanup_race_test.dart`
- `test/features/conversation/application/private_media_expiry_scheduler_test.dart`
- `test/features/conversation/integration/private_media_restart_replay_test.dart`
- `test/core/lifecycle/private_media_lifecycle_recovery_wiring_test.dart`
- `test/features/conversation/application/private_media_action_eligibility_test.dart`
- `test/features/conversation/application/direct_private_media_boundary_test.dart`
- `test/features/conversation/application/download_media_use_case_test.dart`
- `test/features/conversation/presentation/screens/conversation_received_media_actions_test.dart`
- `test/shared/widgets/media/media_viewer_boundary_test.dart`
- `test/l10n/l10n_integrity_test.dart`

## Mutation Re-RED Contract

After focused GREEN, apply and immediately revert one mutation at a time with `apply_patch`, recording the exact named test that fails:

1. Build the private image/video widget before native enter completes.
2. Treat video initialization as a rendered first frame or fire first-frame twice.
3. Roll back View Once on back/background/capture instead of only a proven pre-frame decode failure.
4. Skip fresh parent/attachment revalidation before opening or a safe action.
5. Clear Android `FLAG_SECURE` while another/pre-existing owner still requires it.
6. Leave Android secure state active after the last private route exits.
7. Remove the iOS background cover or describe screenshot handling as prevention.
8. Allow a path/MIME/caption/size/duration/key/nonce or policy state into UI, channel payload, or diagnostics.
9. Enable PiP/resume or an ordinary Save/Share/Forward/bookmark action for a private item.
10. Let an ordinary direct/group viewer invoke private protection/lifecycle callbacks.
11. Terminalize/delete/expire or replace the exact row after native enter but before route push.
12. Recreate the lifecycle engine/lock between opening and first-frame or accept a repository missing one required runtime capability.

No mutation may remain in the worktree.

## Registration Contract

- Add `test/features/conversation/presentation/screens/direct_private_media_viewer_test.dart` and `test/core/media/private_media_protection_coordinator_test.dart` to both `ONE_TO_ONE_TESTS` and `ONE_TO_ONE_HOST_TESTS`.
- Keep the shared typed-viewer and l10n files as exact focused commands; do not falsely reclassify the entire shared/l10n directories into the 1:1 arrays.
- Add one exact required device record for `integration_test/direct_private_media_platform_protection_proof_test.dart` to `Test-Flight-Improv/test-gate-definitions.md`, requiring direct execution on each applicable available Android/iOS platform and availability-bounded N/A wording.
- Record the Kotlin and Swift tests as manual exact native commands in the gate definition. No current named shell gate runs Gradle/XCTest automatically.
- Do not add native or integration files to host arrays. Do not widen frozen named gates.

## Device / Relay Proof Profile

- Classification: `availability-bounded Android/iOS platform proof`; relay-authoritative proof N/A.
- Android selected claim: while a private route owns the current window, standard screenshot/screen-recording/recents capture is prevented through `FLAG_SECURE`; the flag is route-scoped and restored on every exit/error. Native unit proof plus an explicit available Android integration run closes this selected boundary. Prefer a USB physical Android when present, but unavailable physical hardware is not required when another Android target is available.
- iOS selected claim: screenshot prevention is not promised. XCTest plus an explicit available simulator integration run proves screenshot/capture notification handling, privacy cover, pause/dismiss signaling, app-switcher obscuring, and restoration. A physical iPhone is optional confidence, not a required second endpoint.
- No two-peer topology is required in Session 05. The available Android emulator is not required here. Session 06 owns the fully automated physical-Android plus Android-emulator lifecycle journey.
- No unavailable Android/iOS model, OS, or API band is a closure condition. Version-specific branches stay covered by native unit/availability tests; absent hardware is N/A, never an `environment_blocker` or failed gate.
- No relay, server, Go, Bridge, P2P, network, cross-device consume, or screenshot-with-another-camera claim is tested here.

## Acceptance Gates

Run from the repository root in this order. No failure is pre-authorized. Before substituting planning-snapshot IDs, persist the fresh discovery output and selected IDs in Execution Progress.

```bash
# 0. Shared dirty-tree and live-target preflight
git status --short
flutter devices --machine
adb devices -l
xcrun simctl list devices available
flutter emulators

# Set separately from the live discovery above; leave empty only when that
# platform/runner class is genuinely unavailable. Current planning snapshot:
# Android Flutter 21071FDF600CSC; iOS Flutter/XCTest DBE8C32E-9F19-4593-860A-B41113791D79.
# The Executor assigns these from the fresh discovery; never default to a stale ID.
export ANDROID_FLUTTER_DEVICE_ID="${ANDROID_FLUTTER_DEVICE_ID:-}"
export IOS_FLUTTER_DEVICE_ID="${IOS_FLUTTER_DEVICE_ID:-}"
export IOS_XCTEST_SIMULATOR_ID="${IOS_XCTEST_SIMULATOR_ID:-}"
if [[ -n "$ANDROID_FLUTTER_DEVICE_ID" ]]; then adb -s "$ANDROID_FLUTTER_DEVICE_ID" get-state; else printf '%s\n' 'N/A (target unavailable by project policy): Android Flutter proof'; fi
if [[ -n "$IOS_FLUTTER_DEVICE_ID" ]]; then xcrun simctl list devices available | rg "$IOS_FLUTTER_DEVICE_ID"; else printf '%s\n' 'N/A (target unavailable by project policy): iOS Flutter proof'; fi
if [[ -n "$IOS_XCTEST_SIMULATOR_ID" ]]; then xcrun simctl list devices available | rg "$IOS_XCTEST_SIMULATOR_ID"; else printf '%s\n' 'N/A (target unavailable by project policy): iOS XCTest'; fi

# 1. Causal Dart REDs, then focused GREEN after implementation
flutter test test/features/conversation/presentation/screens/direct_private_media_viewer_test.dart
flutter test test/core/media/private_media_protection_coordinator_test.dart
flutter test test/shared/widgets/media/full_screen_typed_media_viewer_test.dart test/shared/widgets/media/media_viewer_boundary_test.dart

# 2. Native causal REDs, then focused GREEN after implementation
./android/gradlew -p android app:testDebugUnitTest --tests 'com.mknoon.app.PrivateMediaProtectionNativeTest'
if [[ -n "$IOS_XCTEST_SIMULATOR_ID" ]]; then xcodebuild test -workspace ios/Runner.xcworkspace -scheme Runner -destination "platform=iOS Simulator,id=$IOS_XCTEST_SIMULATOR_ID" CODE_SIGNING_ALLOWED=NO -only-testing:RunnerTests/PrivateMediaProtectionCoordinatorTests; else printf '%s\n' 'N/A (target unavailable by project policy): iOS XCTest'; fi

# 3. Existing lifecycle/action/download/presentation preservation
flutter test test/features/conversation/application/consume_private_media_use_case_test.dart test/features/conversation/application/private_media_cleanup_race_test.dart
flutter test test/features/conversation/application/private_media_expiry_scheduler_test.dart test/features/conversation/integration/private_media_restart_replay_test.dart test/core/lifecycle/private_media_lifecycle_recovery_wiring_test.dart
flutter test test/features/conversation/application/private_media_action_eligibility_test.dart test/features/conversation/application/direct_private_media_boundary_test.dart
flutter test test/features/conversation/application/download_media_use_case_test.dart
flutter test test/features/conversation/presentation/screens/conversation_received_media_actions_test.dart

# 4. Generated localization and native project registration
flutter gen-l10n
flutter test test/l10n/l10n_integrity_test.dart
./android/gradlew -p android app:compileDebugKotlin
xcodebuild -list -workspace ios/Runner.xcworkspace
plutil -lint ios/Runner.xcodeproj/project.pbxproj

# 5. Availability-bounded real platform GREEN proof
if [[ -n "$ANDROID_FLUTTER_DEVICE_ID" ]]; then flutter test integration_test/direct_private_media_platform_protection_proof_test.dart -d "$ANDROID_FLUTTER_DEVICE_ID"; else printf '%s\n' 'N/A (target unavailable by project policy): Android Flutter proof'; fi
if [[ -n "$IOS_FLUTTER_DEVICE_ID" ]]; then flutter test integration_test/direct_private_media_platform_protection_proof_test.dart -d "$IOS_FLUTTER_DEVICE_ID"; else printf '%s\n' 'N/A (target unavailable by project policy): iOS Flutter proof'; fi

# 6. Curated registration/gates; no broad/full host-all
rg -n 'direct_private_media_viewer_test.dart|private_media_protection_coordinator_test.dart' scripts/run_test_gates.sh scripts/run_host_test_gates.sh Test-Flight-Improv/test-gate-definitions.md
rg -n 'direct_private_media_platform_protection_proof_test.dart|PrivateMediaProtectionNativeTest|PrivateMediaProtectionCoordinatorTests' Test-Flight-Improv/test-gate-definitions.md
./scripts/run_test_gates.sh 1to1
./scripts/run_host_test_gates.sh 1to1 --list
./scripts/run_test_gates.sh completeness-check

# 7. Scoped static/format/script/project hygiene
dart format --output=none --set-exit-if-changed \
  lib/core/media/private_media_protection_coordinator.dart \
  lib/features/conversation/application/direct_private_media_viewer_controller.dart \
  lib/features/conversation/presentation/screens/direct_private_media_viewer.dart \
  lib/core/media/private_media_lifecycle_engine.dart \
  lib/features/conversation/application/direct_private_media_lifecycle.dart \
  lib/features/conversation/presentation/screens/conversation_screen.dart \
  lib/features/conversation/presentation/screens/conversation_wired.dart \
  lib/shared/widgets/media/media_viewer_item.dart \
  lib/shared/widgets/media/full_screen_typed_media_viewer.dart \
  lib/shared/widgets/media/media_playback_adapter.dart \
  test/features/conversation/presentation/screens/direct_private_media_viewer_test.dart \
  test/core/media/private_media_protection_coordinator_test.dart \
  test/shared/widgets/media/full_screen_typed_media_viewer_test.dart \
  test/shared/widgets/media/fake_media_playback_adapter.dart \
  integration_test/direct_private_media_platform_protection_proof_test.dart
dart analyze \
  lib/core/media/private_media_protection_coordinator.dart \
  lib/features/conversation/application/direct_private_media_viewer_controller.dart \
  lib/features/conversation/presentation/screens/direct_private_media_viewer.dart \
  lib/core/media/private_media_lifecycle_engine.dart \
  lib/features/conversation/application/direct_private_media_lifecycle.dart \
  lib/features/conversation/presentation/screens/conversation_screen.dart \
  lib/features/conversation/presentation/screens/conversation_wired.dart \
  lib/shared/widgets/media/media_viewer_item.dart \
  lib/shared/widgets/media/full_screen_typed_media_viewer.dart \
  lib/shared/widgets/media/media_playback_adapter.dart \
  test/features/conversation/presentation/screens/direct_private_media_viewer_test.dart \
  test/core/media/private_media_protection_coordinator_test.dart \
  test/shared/widgets/media/full_screen_typed_media_viewer_test.dart \
  test/shared/widgets/media/fake_media_playback_adapter.dart \
  integration_test/direct_private_media_platform_protection_proof_test.dart
bash -n scripts/run_test_gates.sh scripts/run_host_test_gates.sh
git diff --check

# 8. Literal non-goal/scope guard; compare to the preflight output
git diff --name-only -- \
  lib/core/database/migrations \
  lib/core/database/app_database_version.dart \
  lib/core/database/production_migration_registry.dart \
  go-mknoon go-relay-server \
  lib/features/groups lib/features/announcements \
  lib/features/feed lib/features/orbit \
  Test-Flight-Improv/243-picture-in-picture-floating-media-player-tdd-plan.md \
  Test-Flight-Improv/241-* Test-Flight-Improv/242-* \
  Test-Flight-Improv/248-* Test-Flight-Improv/253-* Test-Flight-Improv/254-* \
  Test-Flight-Improv/247-announcement-media-private-reply-routing-tdd-plan.md \
  Test-Flight-Improv/247-announcement-media-private-reply-routing-tdd-plan-session-breakdown.md \
  Test-Flight-Improv/234-1to1-private-media-lifecycle-tdd-plan-session-06-plan.md

# Final attributable-file allowlist audit. Persist the Session-05-attributable
# path list and prove every path is one of the exact Dart/native/l10n/test/gate/
# plan owners named in `Exact production owner allowlist`; shared baseline paths
# outside that list remain unattributed and untouched.
git status --short -- \
  lib/core/media/private_media_protection_coordinator.dart \
  lib/features/conversation/application/direct_private_media_viewer_controller.dart \
  lib/features/conversation/presentation/screens/direct_private_media_viewer.dart \
  lib/core/media/private_media_lifecycle_engine.dart \
  lib/features/conversation/application/direct_private_media_lifecycle.dart \
  lib/features/conversation/presentation/screens/conversation_screen.dart \
  lib/features/conversation/presentation/screens/conversation_wired.dart \
  lib/shared/widgets/media/media_viewer_item.dart \
  lib/shared/widgets/media/full_screen_typed_media_viewer.dart \
  lib/shared/widgets/media/media_playback_adapter.dart \
  android/app/src/main/kotlin/com/mknoon/app/MainActivity.kt \
  android/app/src/main/kotlin/com/mknoon/app/PrivateMediaProtectionHandler.kt \
  android/app/src/test/kotlin/com/mknoon/app/PrivateMediaProtectionNativeTest.kt \
  ios/Runner/AppDelegate.swift ios/Runner/PrivateMediaProtectionCoordinator.swift \
  ios/RunnerTests/PrivateMediaProtectionCoordinatorTests.swift \
  ios/Runner.xcodeproj/project.pbxproj \
  lib/l10n/app_en.arb lib/l10n/app_de.arb lib/l10n/app_ar.arb \
  lib/l10n/app_localizations.dart lib/l10n/app_localizations_en.dart \
  lib/l10n/app_localizations_de.dart lib/l10n/app_localizations_ar.dart \
  test/features/conversation/presentation/screens/direct_private_media_viewer_test.dart \
  test/core/media/private_media_protection_coordinator_test.dart \
  test/shared/widgets/media/full_screen_typed_media_viewer_test.dart \
  test/shared/widgets/media/fake_media_playback_adapter.dart \
  integration_test/direct_private_media_platform_protection_proof_test.dart \
  scripts/run_test_gates.sh scripts/run_host_test_gates.sh \
  Test-Flight-Improv/test-gate-definitions.md \
  Test-Flight-Improv/234-1to1-private-media-lifecycle-tdd-plan-session-05-plan.md
```

If one platform has no available target after fresh discovery, do not run a command with a stale/implicit ID. Record that exact command leg as `N/A (target unavailable by project policy)`, retain the native host test and other available-platform proof, and continue. If the target exists but the causal assertion fails, it is a blocker, not N/A.

The formatter/analyzer command may remove `private_media_lifecycle_engine.dart`, `direct_private_media_lifecycle.dart`, `media_playback_adapter.dart`, or its fake only if execution records that the corresponding file did not change. It may add one compile-required direct-only adapter file only after recording its causal need. It may not replace these commands with a repository-wide analyzer or any host-all sweep.

## Graphify, Independent QA, And Fix-Pass Contract

After all production/test/device/static gates pass:

1. Compute the final attributable production-file list from the scoped baseline.
2. Run exactly one final pre-QA reverse-impact query:

   ```bash
   python3 graphify-arch/tdd_context.py affected <actual-attributable-production-files...> --budget 600
   ```

3. Verify surfaced direct callers and shared viewer/native entry points in current source; graph edges alone do not prove platform behavior.
4. Launch fresh independent QA with the plan, dirty baseline, RED/GREEN ledger, native/device outputs, final diffs, registrations, scope guard, and affected result.
5. Permit at most two bounded fix passes. Every behavior correction starts with a causal RED or demonstrated native/device counterexample, reruns all affected focused/native/device/static/named gates, and obtains a fresh QA verdict. A remaining blocker after the bounded passes stops the session as not accepted.
6. Only after QA returns `accepted` with no blocking finding, run exactly once:

   ```bash
   ./graphify-arch/refresh_arch_graph.sh --incremental
   ```

7. Do not run a second refresh for closure-document edits. Persist the Execution Result and closure audit after the accepted refresh.

## Known-Failure Interpretation

- No product, test, native, or device failure is pre-accepted. Every required-command failure starts as `pending_triage` and is blocking until narrowed.
- A missing planning-snapshot device ID is target churn, not a code failure. Re-resolve another available target. Only complete same-platform unavailability earns the exact N/A classification.
- A device that is offline/unauthorized while another eligible target exists must be replaced or repaired; it is not N/A. A real assertion failure on an available target is blocking.
- Native test success cannot replace the applicable integration proof, and a Dart boolean cannot replace Android window/iOS observer/cover evidence.
- An iOS screenshot that occurs is not a failure of an unselected prevention claim. Failure to detect, cover/dismiss, restore, or disclose the limitation is blocking.
- A View Once rollback after back/background/capture/dispose, a secure flag cleared too early/left global, private metadata in UI/logs/channels, or any private PiP/resume/ordinary-action authorization is blocking.
- Preserve unrelated dirty native/project/l10n/gate changes. Attribute with the scoped hash snapshot and normal plus whitespace-ignored diffs; do not rewrite another owner's hunks.

## Done Criteria

- [x] Fresh causal Dart, Android, iOS, and platform tests are RED before their production behavior and GREEN afterward.
- [x] One exact current-parent/attachment route decision governs every private open; stale snapshots, caller paths, MIME, and booleans grant no authority.
- [x] Native protection completes before any private path reaches a render widget; enter failure or route-push failure exposes no bytes.
- [x] Post-enter/pre-widget revalidation retains the same View Once lease or exact protected/disappearing authority; terminal/delete/expiry/scope/path/kind loss builds no route, terminalizes View Once, and releases protection.
- [x] View Once claims opening before exposure, records exactly one real first frame, rolls back only a proven pre-frame decode failure, and terminalizes/cleans on every other exit/background/capture/error path.
- [x] Protected remains repeat-viewable; disappearing obeys persisted expiry/high-water authority; neither is accidentally consumed by ordinary route exit.
- [x] Available/opening/viewing/consumed/expired/unsupported UI is generic, truthful, localized in EN/DE/AR, small-viewport/RTL safe, and leaks no forbidden metadata.
- [x] Consumed/expired parents with zero attachment rows still render a parent-derived generic terminal placeholder and safe parent actions, with no synthetic attachment/open/download/path/thumbnail.
- [x] Generic Reply, privacy-minimized Info, and Delete-for-me remain available only through fresh central decisions; Save/Files/Share/Forward/bookmark/Shared Media/PiP stay denied.
- [x] Android route ownership applies and restores `FLAG_SECURE` correctly across pre-existing, nested, duplicate, late, error, background, and dispose sequences.
- [x] iOS screenshot/capture/app-switcher handling detects/obscures/pauses/dismisses/restores truthfully and makes no screenshot-prevention claim.
- [x] Only `enter`/`exit` command payloads carry the opaque owner token; UI, events, results, errors, diagnostics, and logs expose no token, path, media metadata, policy mode/duration/expiry/state, key, nonce, or bytes; completion settles once.
- [x] `ConversationWired` runtime-qualifies all lifecycle/cleanup/runtime interfaces, reuses the repository's existing lock, and retains one engine/controller from open through settlement; missing capabilities deny without throwing.
- [x] Video initialization/build alone reports no first frame; exactly one mounted post-raster video surface reports it, and initialization/render errors report one pre-frame failure.
- [x] Debug/test-only native state/capture proof methods are bounded, secret-free, scene/window truthful, and unavailable in release builds.
- [x] Ordinary direct and group viewers, metadata/actions/resume/playback, received-media egress, Session-03 lifecycle, Session-04 capability/PiP denial, and manual private download remain green.
- [x] Both new host tests are in both 1:1 arrays; native/device records are exact; curated `1to1`, host inventory, completeness, l10n, native projects, formatter/analyzer, diff, and scope guards pass.
- [x] Every applicable available Android/iOS proof runs on an explicit freshly discovered target; unavailable platform legs use only the repository-approved N/A wording.
- [x] No migration/schema/v101, actual PiP, Go/relay, group/announcement, Plan-247 implementation, Session-06, or excluded-plan scope lands.
- [x] Final Graphify `affected`, fresh independent QA, bounded fix-pass policy, and exactly one post-QA incremental refresh pass.
- [x] An accepted Execution Result, Closure Audit, and separate read-only Closure Reviewer acceptance are persisted before Plan 247 Session 03 is released.

## Source / Closure Docs To Update After Acceptance

- Add `## Execution Result`, final independent-QA verdict/fix-pass count, the exact live target record, native/device outputs, Graphify result, and a stable `## Closure Audit` to this plan; change its status to `accepted` only after every criterion passes.
- Update only Session 05 in `Test-Flight-Improv/234-1to1-private-media-lifecycle-tdd-plan-session-breakdown.md`: record accepted evidence, make Session 06 dependency-satisfied, and state that controller serialization runs Plan 247 Sessions 03-04 before Plan 234 Session 06 so final acceptance sees the additive shared-viewer action.
- Add the accepted Session-05 checkpoint and TC-234-11 evidence to `Test-Flight-Improv/234-1to1-private-media-lifecycle-tdd-plan.md` without checking program-wide closure criteria or claiming overall Plan-234 acceptance.
- Keep `Test-Flight-Improv/00-INDEX.md` and `Test-Flight-Improv/19-1to1-message-reliability-closure-reference.md` for Session 06.
- Do not edit Plan-247 documents during Session 05. Its fresh Session-03 planner records the released dependency only after this closure is stable.
- Keep gate arrays/definitions synchronized with the accepted test and device inventory.
- After closure writing, run a separate read-only Closure Reviewer over this plan, the Plan-234 source/breakdown, current evidence, dependency transition, and attributable allowlist. Plan 247 Session 03 remains blocked until that reviewer records `accepted` with no unresolved documentation/dependency finding.

## Reviewer Findings

- The ordinary-viewer denial is correct and must remain; Session 05 needs a dedicated private wrapper, not an exception that feeds a private path into legacy/ordinary viewer entry.
- Native protection must precede rendering. Setting secure/cover state from `build`, after navigation, or only on first frame leaves a privacy gap and is rejected.
- Video initialization is not by itself a rendered first frame. The shared render callback must settle from an actual post-render surface/frame and remain once-only.
- A generic `dispose => rollback` violates the accepted View Once state machine. Only a proven same-process pre-first-frame decode failure rolls back; all other exits fail closed and terminalize.
- Android must preserve pre-existing/window-shared secure ownership. iOS must detect/obscure rather than claim impossible prevention. These are native causal boundaries, not Dart-only flags.
- Keeping safe private actions in the dedicated wrapper avoids weakening shared `MediaViewerItem.isActionEligible` before Plan 247 adds its separate callback-only viewer action.
- No app-wide service locator or constructor sweep is justified. Direct `ConversationWired` has the repository/media dependencies needed for a narrow route adapter; expand only on a causal wiring RED.

## Arbiter Decision And Stop Rule

- Verdict: `execution-ready`.
- Structural blockers: none.
- Dependencies: Sessions 02-04 are accepted; Sessions 01-04 are not reopened by this plan.
- Current target availability is sufficient for the selected Android physical plus iOS simulator proof, but execution must re-resolve it and obey availability-bounded N/A policy.
- Exact owners, REDs, native/device commands, registrations, named/static/scope gates, QA/Graphify cadence, closure docs, and Plan-247 release guard are explicit.
- Stop planning. Fresh Execution+QA must implement only this Session-05 contract and must not enter Session 06 or Plan 247.

## Execution Progress

| Time | Phase | Files / commands | Result | Next |
|---|---|---|---|---|
| 2026-07-11 | execution-plan preparation | accepted source/breakdown/Session-01..04 closures; anchored Graphify TDD context; current direct/shared viewer and lifecycle seams; native entry files/tests; gate arrays/docs; live device/emulator discovery | Execution-ready plan created. No production/test/gate/native change, test run, analyzer, device proof, QA, or Graphify refresh occurred. Plan-247 Session 03 remains serialization-blocked. | Fresh Executor captures scoped baseline, re-resolves devices, authors causal Dart/native/platform tests, and records RED before production. |
| 2026-07-11 | Executor preflight | `git status --short`; SHA-256 over every scoped owner/test/gate file; literal non-goal guard; anchored Graphify TDD queries; `flutter devices --machine`; `adb devices -l`; `xcrun simctl list devices available`; `flutter emulators`; bounded executable-name process inventory | Shared dirty tree preserved. Scoped aggregate baseline `3258faf7dc7fd8238629f1e990732ae74383f0e447ccb3158c423bcc65713ef6`; all three new Dart owners, both native coordinators/tests, both new Dart host tests, and the integration proof were absent. Literal non-goal baseline: Plan-247 source, DB version/registry, and two group repository paths were pre-existing. No Gradle/XCTest/Graphify/test runner was active. Fresh targets selected: Android Pixel 6 `21071FDF600CSC` (API 36); iOS simulator iPhone 16e `DBE8C32E-9F19-4593-860A-B41113791D79` (iOS 26.5) for Flutter and XCTest. | Add every causal Dart/native/platform test before production and capture missing-contract REDs. |
| 2026-07-11 | Dart/platform RED | Added both required Dart causal suites, the three typed-viewer lifecycle/privacy tests, the controllable fake initialization gate, and the automated platform proof before production. Ran the three literal focused commands and the Android proof on `21071FDF600CSC`. | All four commands exited non-zero for the intended absent contract: missing `private_media_protection_coordinator.dart`, `direct_private_media_viewer_controller.dart`, and `direct_private_media_viewer.dart`; missing typed-viewer `privacyMinimized`/first-frame callbacks; Android device build failed at kernel compilation for the missing coordinator API. These were causal missing-API REDs, not intake/file-not-found test invocations. | Implement the bounded Dart coordinator, controller, dedicated route, typed first-raster callbacks, direct wiring, localization, and registrations without weakening ordinary viewers. |
| 2026-07-11 | Focused Dart GREEN + Executor refinement | Implemented route-scoped coordinator, retained direct lifecycle controller, protection-before-widget/post-enter revalidation, generic private route/terminal states, typed image/video post-raster callbacks, direct screen/wiring qualification, EN/DE/AR copy, and exact registrations. Ran coordinator, typed-viewer+boundary, and direct-viewer suites. | Coordinator `3/3`, typed-viewer+boundary `7/7`, direct-viewer `8/8`. One direct widget run initially stalled because the test used asynchronous filesystem creation inside `testWidgets` fake time; production was unchanged, the fixture switched to equivalent synchronous temp-file setup plus bounded pumps, and the same privacy/first-frame assertions passed. This is an Executor test-harness refinement, not a behavior fix or QA pass. | Complete mutation re-REDs, native final evidence, preservation/named/static/device gates, and final Graphify `affected`. |
| 2026-07-11 | Mutation re-RED | Applied and immediately reverted all twelve contract mutations. Dart exact named tests failed for: completing a byte-bearing grant before native enter; treating video initialization as a frame; rolling back a pre-frame close; skipping post-enter row/lease revalidation; rendering private metadata; publishing PiP; changing the ordinary-viewer default; accepting an after-enter path replacement; and dropping required runtime capability/retained-lock wiring. Android exact native tests failed when secure ownership cleared too early or remained after the last exit. iOS exact XCTest failed when screenshot handling was renamed from detection to prevention. Native/Dart redaction sentinels cover forbidden token/path/metadata diagnostics. | Every mutation produced the intended non-zero causal result, was reverted with `apply_patch`, and a literal residue search plus scoped `git diff --check` was clean. No mutation remains. | Re-run final focused GREEN, then every literal preservation/native/device/named/static/scope gate. |
| 2026-07-11 | Native RED/GREEN and project proof | Added the registered Kotlin and Swift causal tests before their production handlers. Android RED failed on the missing handler; iOS RED failed on the missing coordinator. Implemented route-scoped `FLAG_SECURE` ownership, scene-aware iOS cover/capture observation, bounded debug-only proof methods, and native entry-point registration. Ran the exact Gradle/XCTest commands plus Kotlin/Xcode project checks. | Android native `3/3`; iOS XCTest `3/3` on simulator `DBE8C32E-9F19-4593-860A-B41113791D79`; `app:compileDebugKotlin` succeeded; `xcodebuild -list` succeeded; Xcode project `plutil` lint returned `OK`. The iOS contract makes detection/obscuring claims only, never screenshot prevention. | Run preservation and availability-bounded device proof. |
| 2026-07-11 | Preservation, localization, and device GREEN | Ran every literal preservation command, regenerated localization, ran l10n integrity, re-resolved the selected targets, and executed the automated proof on explicit target IDs. The existing received-media-actions fixture was causally adjusted to assert the new private placeholder instead of tapping a now-forbidden ordinary media cell; production was unchanged by that refinement. | Consume+cleanup `23/23`; expiry+restart+recovery `16/16`; eligibility+boundary `16/16`; fresh complete download `68/68`; received-media actions `10/10`; l10n `2/2`. Android Pixel 6 `21071FDF600CSC` proof `1/1`; iOS 26.5 simulator `DBE8C32E-9F19-4593-860A-B41113791D79` proof `1/1`. No user tap, relay, two-peer, or unavailable-hardware claim was used. | Run registrations, curated lane, inventory, completeness, and static/scope gates. |
| 2026-07-11 | Named/static/scope acceptance | Verified both new host suites in both 1:1 arrays and native/device records only in gate definitions. Ran curated `1to1`, host inventory, completeness, literal formatter/analyzer, the causal preservation-fixture analyzer, script syntax, diff check, and the final allowlist/scope guards. | Curated `1to1` `1920/1920`; host inventory `83` exact commands with dry-run discovery only; completeness `1170/1170`; formatter changed `0`; analyzer reported no issues; `bash -n` and `git diff --check` passed. The final non-goal guard exactly matches preflight: the pre-existing Plan-247 source, DB version/registry, and two group repository files only. No full `host-all`, migration/v101, Go/relay, group/announcement, PiP implementation, or Session-06 work ran or landed. | Run the one final pre-QA Graphify reverse-impact query and hand off. |
| 2026-07-11 | Final Graphify affected / Executor handoff | Ran exactly one `python3 graphify-arch/tdd_context.py affected <19 attributable production files> --budget 600`, then verified the surfaced direct lifecycle caller, ordinary/shared typed-viewer callers, and Android/iOS registration points in current source. | Graphify surfaced `direct_private_media_lifecycle.dart`, direct/shared viewer callers, and adjacent application importers; targeted source verification confirmed the dedicated direct route plus unchanged ordinary direct/group call sites and both native entry points. No incremental refresh ran. Executor has no failed gate or pending triage. | Fresh independent QA receives this ledger and final dirty-tree evidence. Do not refresh or close before QA accepts. |
| 2026-07-11 | Independent QA rejection / fix pass 1 | QA audited the route, lifecycle, typed renderer, native owners, project registration, localization, tests, and scope against B1-B10. Every correction received a causal regression before production changed. | Initial QA rejected B1-B10. Fix pass 1 closed the first-frame/privacy presentation, deadline/reload, route-lifecycle, native release, exact revalidation, unsupported-content, ownership, platform-proof, activity-rebind, and debug-build attribution findings; all affected gates were rerun. | Fresh independent QA over the corrected state. |
| 2026-07-11 | Independent QA rejection / fix pass 2 | QA re-audited the corrected state and found two remaining counterexamples: B3 could construct the typed viewer before a pre-route critical latch rendered black, and B7 balanced an unpublished native owner against a later mutable Dart snapshot. Causal regressions preceded both changes. | Fix pass 2 made the pre-route latch a first-build black surface and captured the native-ownership expectation at the invocation boundary. A fresh complete download run encountered the known cleanup timing assertion; its exact-name rerun passed and the subsequent complete suite passed 68/68. | Fresh independent QA over fix pass 2. |
| 2026-07-11 | Independent QA rejection / fix pass 3 | QA produced the deeper B7 counterexample in which two overlapping enters could both be native-active but unpublished. The new exact test failed before production. | Fix pass 3 serialized native enter, normal exit, and unpublished balancing exit through one synchronous-start transaction queue; recoverable incidents remain sticky until all pending operations settle. Coordinator `9/9` and direct viewer `16/16` passed. This third pass is an explicit controller-authorized causal exception to the plan's original two-pass forecast/limit, not a hidden count adjustment. | Rerun the full affected acceptance surface and obtain final independent QA. |
| 2026-07-11 | Final GREEN and exact acceptance rerun | Every affected focused/native/device/named/static/scope command was rerun after fix pass 3. The ignored Xcode configuration was regenerated after a deleted temporary Flutter target path, and the selected simulator was rebooted after XCTest shut it down; both exact reruns then passed. | Direct viewer `16/16`; coordinator `9/9`; typed viewer+boundary `8/8`; consume+cleanup `23/23`; scheduler/restart/recovery `16/16`; eligibility/boundary `16/16`; fresh download `68/68`; received actions `11/11`; l10n `2/2`; Android native `5/5`; iOS native `4/4`; Android device `1/1`; iOS simulator `1/1`; curated `1to1` `1935/1935`; host inventory `83`; completeness `1170/1170`; formatter/analyzer/script/diff/scope guards green. | Final exact-current Graphify impact query and independent QA. |
| 2026-07-11 | Final impact / independent QA | Graphify `affected` was reconciled over 22 exact impact inputs: 21 Session-05-attributable production deltas, including EN/DE/AR localization and `android/app/build.gradle.kts`, plus unchanged Session-04 preservation dependency `media_viewer_item.dart`. Fresh read-only QA independently ran coordinator+direct viewer `25/25`, formatter, analyzer, and diff checks and reviewed every B1-B10 counterexample. | `ACCEPTED`; no blocking finding. Honest `fix_passes=3`. Nonblocking observations are the fail-covered head-of-line wait if native never completes, explicitly excluded late external `FLAG_SECURE` acquisition, and reconstructed root `info.plist` attribution. | Run exactly one post-QA incremental architecture refresh. |
| 2026-07-11 21:20 CEST | Post-QA Graphify refresh | `./graphify-arch/refresh_arch_graph.sh --incremental` | Exit 0; architecture graph wrote 47,683 nodes / 74,055 edges and refreshed the 1,263-file / 12,363-test / 956-target TDD overlay. Exactly one post-QA refresh ran. No production or test file is newer than the refreshed overlay. | Persist Execution Result and synchronized closure documents, then obtain separate read-only closure review. |
| 2026-07-11 | Separate Closure Reviewer | Read-only reconciliation of this plan, the Plan-234 source/breakdown, code/tests/gates, native artifacts, graph timestamps, attribution, and dependency transition. | `ACCEPTED`; all 21 criteria are truthful. No blocking or nonblocking documentation finding remains. The reviewer confirmed 21 attributable production deltas plus one unchanged impact dependency, honest `fix_passes=3`, the explicit third-pass exception, exactly one refresh, and release of only Plan 247 Session 03. | Close Session 05; keep Plan 234 open and Session 06 controller-serialized behind Plan 247 Sessions 03-04. |

## Executor Handoff

Executor implementation and all pre-QA acceptance gates are complete. The worktree remains shared and dirty; unrelated baseline changes were preserved. The preflight scoped aggregate was `3258faf7dc7fd8238629f1e990732ae74383f0e447ccb3158c423bcc65713ef6`. Session-05-attributable production is limited to the dedicated Dart coordinator/controller/route, the Session-03 lifecycle engine extension, direct screen/wiring integration, typed first-raster/privacy support, Android/iOS protection owners and entry registration, and EN/DE/AR localization. Tests, exact gate registrations, gate definitions, this plan, and the causal received-media-actions fixture are the attributable non-production delta.

Fresh QA inputs:

- Causal GREEN: direct viewer `8/8`, Dart protection coordinator `3/3`, typed viewer plus ordinary boundary `7/7`; all twelve required mutation re-REDs failed causally and were reverted.
- Native/project GREEN: Android `3/3`, iOS `3/3`, Kotlin compile, Xcode workspace listing, and project lint.
- Preservation/device GREEN: `23/23`, `16/16`, `16/16`, download `68/68`, received-media actions `10/10`, l10n `2/2`, Android proof `1/1`, iOS proof `1/1` on the explicit IDs recorded above.
- Named/static GREEN: curated `1to1` `1920/1920`, host inventory `83`, completeness `1170/1170`, format/analyze/script/diff clean, and a scope guard identical to preflight.
- Graphify: one final pre-QA `affected` query ran over the 19 attributable production files and was source-verified. No graph refresh has run.

There is no `## Execution Result`, QA verdict, closure audit, source/breakdown release, or post-QA Graphify refresh yet. Status must remain `executor-complete-awaiting-independent-qa` until a fresh independent QA accepts. Plan 247 Session 03 remains serialization-blocked during this handoff.

The preceding Executor Handoff is the immutable pre-QA handoff snapshot. It is superseded by the accepted evidence below and is retained so the rejection/fix chronology remains auditable.

## Execution Result

Verdict: `accepted` / `closed`.

- Session-05 production is complete within the exact attributable allowlist: the dedicated direct private route/controller, route-scoped Dart/native protection ownership, exact post-enter lifecycle revalidation, real first-raster reporting, generic privacy-minimized UI, direct wiring, EN/DE/AR localization, Android debug attribution, Android `FLAG_SECURE`, and truthful iOS detection/obscuring.
- Causal history is preserved: initial QA rejected B1-B10; fix pass 1 closed those concrete findings; the next QA rejected B3/B7; fix pass 2 closed them; the next QA found the deeper two-unpublished-owner B7; fix pass 3 added a failing causal test and serialized every native ownership mutation. Final QA accepted every B1-B10 item. `fix_passes=3` is the honest count. The third pass exceeded the original two-pass forecast/limit as an explicitly recorded, causally bounded controller exception.
- Final focused evidence: direct viewer `16/16`, Dart coordinator `9/9`, typed viewer plus ordinary boundary `8/8`, consume/cleanup `23/23`, scheduler/restart/recovery `16/16`, eligibility/boundary `16/16`, fresh complete download `68/68`, received actions `11/11`, and l10n `2/2`.
- Native/project evidence: Android native `5/5`; iOS XCTest `4/4` on iPhone 16e simulator `DBE8C32E-9F19-4593-860A-B41113791D79`; Kotlin compile, Xcode list, and project lint passed. The final iOS result bundle is `Test-Runner-2026.07.11_21-05-02-+0200.xcresult` under the Runner DerivedData logs.
- Availability-bounded proof: Android Pixel 6 `21071FDF600CSC` `1/1`; iOS 26.5 simulator `DBE8C32E-9F19-4593-860A-B41113791D79` `1/1`. No unavailable model/version, manual tap, relay, or two-peer claim is used.
- Named/static evidence: curated `1to1` `1935/1935`; host inventory `83`; completeness `1170/1170`; formatter changed zero files; scoped analyzer reported no issues; script syntax, `git diff --check`, native project checks, and the baseline-safe non-goal guard passed. No full `host-all` ran.
- Final Graphify impact was reconciled over 22 exact inputs: 21 Session-05-attributable production deltas plus unchanged Session-04 preservation dependency `lib/shared/widgets/media/media_viewer_item.dart`. Final independent QA returned `ACCEPTED` with no blocking finding. Exactly one post-QA incremental refresh completed at 21:20 CEST; no production or test file is newer than its TDD overlay.
- The root `info.plist` had no exact Session-05-start hash. Xcode rewrote only `LastAccessedDate`; it is restored to the last-known pre-Session-05 value `2026-07-10T14:38:37Z`, SHA-256 `63bb7ec9414e232ff0dc358904c6a9ff519cb019a107df9ea5d48bb215828629`. This is explicitly reconstructed attribution, not falsely claimed exact-baseline proof.
- Environment recovery was non-behavioral: an ignored generated Xcode config referenced a deleted temporary Flutter target until regenerated; XCTest shut down the selected simulator and the same exact target was rebooted. The final exact native/device commands passed.
- No migration/schema/v101, actual PiP, Go/relay, group/announcement, Plan-247 implementation, Session-06 work, or excluded plan landed. DB v100 remains exclusively Plan 234; Plan 238 retains sequential v101.

## Closure Audit

- Current classification: `closed`.
- Blocking findings: none after `fix_passes=3`.
- In-scope residuals/follow-ups: none. QA's native-never-completes queue wait remains fail-covered; late external Android secure-flag acquisition is an explicit non-goal; the reconstructed `info.plist` baseline uncertainty is recorded above.
- Prior Sessions 01-04 remain accepted and closed; no regression evidence reopens them.
- The source plan and breakdown are synchronized through accepted Session 05. Overall Plan 234 remains `implementation-in-progress`; Plan 247 Session 03 alone is released. Session 06 is dependency-satisfied but controller-serialized behind Plan 247 Sessions 03-04 so final Plan-234 acceptance sees the additive shared-viewer action.
- Exactly one post-QA incremental Graphify refresh ran. Closure-document edits do not trigger another refresh.
- Separate read-only Closure Reviewer verdict: `ACCEPTED`. It verified all 21 criteria, evidence fidelity, the 21+1 impact attribution, the three-pass exception, reconstructed metadata record, exactly-one refresh, and the dependency transition. Plan 247 Session 03 is now released; no other downstream session is released by this closure.
