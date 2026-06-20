# 126 — Cold-Start Boot Hardening (fail-visible, not dead-splash)

**Status:** PLAN ONLY (no code changed). TDD, host-green-gated, **no migration** (DB version unchanged).
**Date:** 2026-06-18
**Origin:** Live diagnosis of a fresh-install hang on iPhone 17 Pro Max (iOS 26.5.1).

---

## 1. Problem statement

A tester installed the TestFlight (release) build on a **brand-new iPhone 17 Pro Max (iOS 26.5.1)** and the app **opened only the splash screen and never advanced** — with **no permission prompt and no error**. The *same* build:

- runs fine on the tester's older **iPhone 11** (warm install), and
- **booted fully to onboarding** on a fresh **iPhone 17 Pro Max simulator** (debug, no E2E defines): the entire `onCreate` migration chain + all pre-`runApp` init completed in a few seconds.
- A **clean delete + reinstall from TestFlight fixed the device.**

**Conclusion:** the *trigger* was almost certainly a **bad/incomplete first install or a one-time first-launch stall** (Apple-side delivery glitch or transient init condition) — not a deterministic code bug. **But** the app's boot architecture turns *any* such transient first-launch problem into a **permanent, silent, unrecoverable dead splash**, and one we **cannot diagnose on-device** because all boot telemetry is compiled out of release.

This plan does **not** try to fix Apple's delivery (we can't). It hardens the boot path so that the *class* of "something went wrong during first launch" becomes **visible, recoverable, and diagnosable** instead of a dead splash that only delete-and-reinstall escapes — which most users will never think to do.

---

## 2. Root-cause architecture findings (this session, with evidence)

All line numbers verified against the current tree.

1. **Heavy, mostly un-timed init runs BEFORE `runApp`.** `main()` (`lib/main.dart:332`) awaits a long chain before `runApp()` (`:3005`): `captureInitialIntent` (`:341`), `Firebase.initializeApp` (`:381`), `getApplicationDocumentsDirectory` (`:386`), **`openEncryptedDatabase` + ~90 `onCreate` migrations** (`:419`, `:423-515`), secrets migrations (`:805/:808/:809`), per-group keychain mirror loops (`:1261/:1264`), then **`startLiveServices()`** → `bridge.initialize()` + `notificationService.initialize()` (`:2932-2944`), **awaited** for non-share launches at `:2996`. While these run, iOS shows the static `LaunchScreen` — a hang here is a frozen splash.

2. **No global error boundary.** `main()` has **no `runZonedGuarded`, no `FlutterError.onError`, no `PlatformDispatcher.onError`** (verified absent). The only pre-`runApp` `try/catch` is inside `ensureFirebaseReady` (`:355`). `openEncryptedDatabase` (`:419`) is awaited with **no guard** — a throw there aborts `main()` before `runApp`, leaving the native splash forever with no error UI.

3. **Boot telemetry is invisible in release.** `StartupTiming.mark()` only prints under `if (kDebugMode)` (`startup_timing.dart:14`, summary gated `:30`). **And** the structured FLOW channel is gated by `flowEventLoggingEnabled = kDebugMode` (`flow_event_emitter.dart:6`, early-return `:217`), set `true` *only* in tests/harnesses — so `emitAppBuildInfo()` (`main.dart:338`) and every FLOW event are **silent in TestFlight too**. Net: **a stuck first launch in release leaves no on-device trace.** (This is why we could not capture the failure live.)

4. **The iOS notification-permission request is on the pre-`runApp` path.** `FlutterNotificationService.initialize()` builds `DarwinInitializationSettings` with `requestAlert/Sound/Badge = true` and awaits `_plugin.initialize()` (`flutter_notification_service.dart:28-42`), which triggers the iOS authorization prompt; it's awaited via `startLiveServices()` at `main.dart:2944` → `:2996`, **before** `runApp`. A pre-frame authorization request that doesn't resolve fits the observed "no prompt + dead splash."

### Assets to REUSE (do not reinvent)

- **Deferred-startup seam already exists.** On share-launch, `startLiveServices` is **not** run before `runApp`; it's passed as `deferredRuntimeStartup` (`main.dart:3085`) and run after the first frame via `_ensureRuntimeServicesReady` (`:3452-3470`). Extend this to the normal launch.
- **Inline error/Retry screen already exists.** `_StartupRouterState` has `_hasError`/`_errorMessage` (`startup_router.dart:271-272`), a `try/catch` that sets them (`:585-598`), an inline error `Scaffold` (`error_outline` + title + message + Retry button) in `build()` (`:1111-1148`), and an idempotent `_retry()` that re-runs routing (`:877-884`). Funnel failures here.
- **`StartupLoadingGate`** (`widgets/startup_loading_gate.dart:14`) — opaque branded spinner keyed by a `stage` string.
- **`.timeout()` idiom in-file** — `…​.timeout(const Duration(seconds: 2))` inside `try/catch` with `kDebugMode` log (`main.dart:3093-3102`; pervasive in `bridge.dart`). Match this style.
- **Durable file-marker helper** — `persistAppGroupContainerPathForGate` / `readPersistedAppGroupContainerPath` (`recent_remote_gate_ios_wiring.dart:16-55`): writes one string to app-support, `flush:true`, fail-open `try/catch`, injectable dir provider, **not** `kDebugMode`-gated. Template for the boot breadcrumb.
- **Permission-request templates** — `PushRegistrationCoordinator.ensureStarted()` (idempotent post-frame starter) and `requestPushPermission()`; fired post-frame at `startup_router.dart:650-653`. Every other iOS permission (camera/mic/location/local-network) is requested on first use, **not** at boot — notification is the lone exception.

---

## 3. Invariants

- **BOOT-1 (render-first):** A Flutter frame (loading gate) renders shortly after launch; the native splash is never the long-lived surface.
- **BOOT-2 (fail-visible):** Any boot init failure or timeout surfaces the existing error/Retry screen — **never** a silent permanent splash or spinner.
- **BOOT-3 (bounded):** Every step on the critical path is time-bounded; on timeout it deterministically either fails-open (degraded) or routes to Retry.
- **BOOT-4 (diagnosable):** The last-reached boot milestone is persisted durably **in release** and surfaced on the next launch.
- **BOOT-5 (no boot-time prompt):** No iOS permission is requested before the first frame.
- **BOOT-6 (happy-path unchanged):** Warm launch behavior is byte-equivalent; deferral preserves documented ordering — `node:start` before `rejoinGroupTopics`/`drainGroupOfflineInbox` (`main.dart:2971-2973`), the account-migration network gate, `startLiveServices` idempotency (`liveServicesStarted` flag `:2933`), and cold-start notification-tap payload capture.

---

## 4. Scope

**IN**
- Render-first restructure (defer non-minimal init through the existing `deferredRuntimeStartup` seam).
- Time-bound the minimal blocking steps (DB open + `db_encryption_key` keychain read).
- Route deferred-init failures into the existing Retry screen (await it + `try/catch`; fix the `unawaited(...)` at `startup_router.dart:419`).
- Global error boundary (`runZonedGuarded` + `FlutterError.onError` + `PlatformDispatcher.onError`) as a backstop.
- Split notification init: prompt-free `initialize()` + deferred `requestPermissions()` fired post-frame.
- Durable boot-milestone breadcrumb + next-launch surfacing (release-safe).

**OUT**
- Rewriting/optimizing the migration chain.
- Any DB schema change (**no migration**).
- The TestFlight/App-Store first-download glitch itself (Apple-side).
- Broad refactor of `StartupRouter` routing logic.

---

## 5. Phases (TDD, tests-first)

Ordered so each phase is independently shippable and de-risks the next. **Phase 0 ships first** so that if the issue recurs before the rest lands, we can finally see it.

### Phase 0 — Release-safe boot breadcrumb (diagnosability)
- **New** `lib/core/diagnostics/boot_milestone_store.dart`: `Future<void> writeLastBootMilestone(String name, {Future<Directory> Function()? supportDirectory})` and `Future<String?> readLastBootMilestone(...)`, modeled on `recent_remote_gate_ios_wiring.dart:16-55` — one file under app-support (`mknoon_last_boot_milestone`), `flush:true`, fail-open `try/catch`, injectable dir. **Not** `kDebugMode`-gated.
- Sentinel semantics: write `boot_in_progress|<stage>|<utc>` as each milestone is reached; overwrite to `boot_complete|<utc>` at `run_app_called`/first frame.
- Wire the writer into `StartupTiming.mark()` (`startup_timing.dart:12`) as `unawaited(...)` with swallowed errors → all existing milestones record durably with **zero new call-site churn**. (Resolve app-support lazily + cache; earliest marks are best-effort.)
- Next launch: read the prior breadcrumb early in `main()`; if it isn't `boot_complete`, surface via `developer.log`/`print` (visible in Console.app) and optionally a Crashlytics custom key.
- **Tests:** write/read round-trip with injected dir; sentinel transitions; fail-open on IO error; mark() never throws/blocks. Mutation-verify the sentinel comparison.

### Phase 1 — Global error boundary (backstop)
- Wrap the `main()` body in `runZonedGuarded`; set `FlutterError.onError` and `PlatformDispatcher.instance.onError`. On a fatal pre-frame error, `runApp` a minimal error/Retry shell so even an early throw shows *something*.
- **Tests:** inject a throwing initializer → assert the error shell renders (widget test) and the error is logged + breadcrumbed.

### Phase 2 — Render-first restructure (core fix)
- Reduce pre-`runApp` to the **minimal blocking set**: `WidgetsFlutterBinding.ensureInitialized()`, platform/FFI setup, `openEncryptedDatabase` (the `db` handle is a constructor arg to nearly every repository passed into `MyApp`), and the secrets migrations (`:805/:808/:809`).
- Defer `startLiveServices()` for the **normal** launch through the existing seam: make `deferredRuntimeStartup` always non-null and **remove the eager `await startLiveServices()` at `:2996`**. `bridge.initialize()` (cheap — just an EventChannel subscribe, `go_bridge_client.dart:158-184`), `notificationService.initialize()`, and the ~25 listener/retrier `.start()` calls run **after** the first frame.
- **Critical:** change `unawaited(widget.ensureRuntimeServicesReady?.call())` (`startup_router.dart:419`) to an **awaited** call inside `_routeBasedOnIdentity()`'s `try`, and add `try/catch` in `_ensureRuntimeServicesReady` (`main.dart:3463`) — so deferred-init failure hits the existing catch (`:585`) → Retry screen (**BOOT-2**), not a forever spinner.
- Add a `startupStagePreparing` constant + l10n so the moved init is legible in `StartupLoadingGate` (reuse `_setStartupStage`, `startup_router.dart:958`).
- **Tests:** loading gate renders before heavy init; a thrown deferred-init → Retry screen; Retry re-runs and succeeds on the 2nd attempt (idempotency); ordering invariants (`node:start` before rejoin/drain) preserved.

### Phase 3 — Time-bound the minimal blocking steps
- Bound `openEncryptedDatabase` (`:419`) and the `db_encryption_key` read (`encrypted_db_opener.dart:40`) with `.timeout()` + `try/catch` (in-file idiom). DB is in the blocking set → **BLOCKING-but-bounded**: on timeout/throw show the error/Retry screen, never an infinite splash. (Note the existing `PRAGMA busy_timeout=5000` at `:97` only covers a locked-file query — not the keychain read or migration bodies.)
- Bound `captureInitialIntent` (`:341`, fail-open → non-share) and `getApplicationDocumentsDirectory` (`:386`, fail-open → degraded avatars).
- **Tests:** inject slow/throwing fakes → assert bounded + correct fail-open-vs-retry routing per step.

### Phase 4 — Notification permission off the boot path (BOOT-5)
- Split `FlutterNotificationService.initialize()`: keep a **prompt-free** init (Darwin `requestAlert/Sound/Badge = false`, still `_plugin.initialize` + `ensureMknoonNotificationChannel` + **`getNotificationAppLaunchDetails`** for cold-start tap payload — must stay early, see `:44-46/:76-90`).
- Add `NotificationService.requestPermissions()` (iOS `resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()?.requestPermissions(alert/badge/sound)`), gated on `requestApplePermissions`/`kE2ETestMode`, with a flow event mirroring the push path. Fire it post-first-frame next to push (`startup_router.dart:650-653`) with an idempotent guard.
- **Tests:** `initialize()` does **not** prompt; `requestPermissions()` prompts once; cold-start payload still captured; update any test asserting prompt-during-init.

---

## 6. Gates
- Host suites green: notification-core, p2p, groups, **identity/startup**, integration startup/routing.
- `0` new `flutter analyze` issues.
- Mutation-verify: breadcrumb sentinel logic, deferred-init failure→Retry routing, prompt-free init.
- **No migration** — `currentIdentityDatabaseVersion` unchanged.

## 7. Device proof
- Fresh install on the **iPhone 17 Pro Max** (debug — requires adding the Apple ID to Xcode → Settings → Accounts so automatic signing can register the device; this was the blocker this session): loading gate → onboarding.
- Inject a forced failure in deferred init → **Retry screen appears and recovers** on retry.
- Kill mid-boot → next launch surfaces the prior `boot_in_progress|<stage>` breadcrumb in Console.app.

## 8. Open questions
- **OQ-1** Timeout budgets — propose DB open 10s, keychain read 5s; tune with device data.
- **OQ-2** DB-open timeout → explicit Retry (recommended) vs auto-retry "still preparing".
- **OQ-3** Surface the recovered breadcrumb via Crashlytics custom key? (Milestone name only — privacy-safe.)
- **OQ-4** `requestPermissions()` at first frame (minimal change, recommended) vs first chat/feed (higher grant rate).

## 9. Risk notes
- Deferral must preserve: `node:start`-before-rejoin/drain ordering (`main.dart:2971-2973`); account-migration network gate short-circuit in `startLiveServices` (`:2936`); `startLiveServices` idempotency (`liveServicesStarted`, `:2933`); cold-start notification-tap payload capture (keep `getNotificationAppLaunchDetails` in the early half).
- The breadcrumb writer must never block or throw on the boot path (fire-and-forget, fail-open).
- `wipeKeychainOnce` (`:393`) is `kDebugMode`-gated (no-op in release) — out of scope, but note it adds unbounded keychain I/O in debug/internal builds.
