# 110 — Voice Recording Screen Wake-Lock (TDD Plan)

- **Date:** 2026-06-10
- **Status:** implemented 2026-06-10 (same day) — core Steps 1–7 plus both §5.5 follow-ups, all red-green; targeted suites green. §5.5 Follow-up 1 was additionally wired into `compose_post_sheet.dart` (third surface, same stale-overlay bug; the plan text only named the two wired screens). Auto-stop discards the recording on every surface (state reset only, no draft/send).
- **Post-implementation review (2026-06-10, 46-agent adversarial pass, 21 raw → 6 confirmed):** all 6 fixed same day. (1) `start()` now rolls back fully (lock, timers, plugin recording) if anything after plugin-start throws — a throwing wakelock driver (Android `NoActivityException`) would otherwise leak a counted hold with no auto-stop bound; (2) session-ownership gating (`recorder.onAutoStopped == _onRecorderAutoStopped` — tear-offs are `==`, never `identical`) on the group force-cancel and all three dispose paths, so a surface with stale recording state can never cancel another surface's live session; (3) the two non-`_group` `_canWrite` mutation sites (`_loadSecurityStatus`, `_refreshSendCapabilityAndCanWrite`) got the same write-loss → force-cancel transition; (4) Step-5 test strengthened (release/re-acquire pinned, second-start-throws case); (5) arming-branch force-cancel test added; (6) compose-sheet auto-stop FLOW event added.
- **Source:** graphify-explorer workflow run (3 graph-driven exploration agents + 1 synthesis agent); findings verified against source with file:line evidence
- **Feature:** keep the screen awake while the user records a voice message; acquire on start, release on stop/cancel/error/dispose/auto-stop; never leak a hold
- **2026-06-10 review:** this plan was verified claim-by-claim against source alongside a competing v2 draft (declarative `WakeLockHold` widget over the composer `recordingState`; draft since deleted) and selected for implementation — all checked claims held (feed inline reply confirmed inert; posts composer confirmed a live third surface this design covers; release-before-plugin-call ordering confirmed lock-safe on stop-throw). The review also surfaced gaps this plan does not fully address — see **§5 Verified caveats** before implementing.


## 1. Design decision

**Mechanism:** Reuse the existing `UploadWakeLockController` (ref-counted wrapper over `wakelock_plus 1.5.1`, already a dependency, already used for uploads and migration) — no new package; ref-counting means recording and a concurrent upload can't release each other's hold.

**Placement:** Inside `RecordAudioRecorderService` (the production `AudioRecorderService` impl), NOT in the three UI surfaces. One change covers 1:1 chat, group chat, and the post composer, and — critically — the **5-minute auto-stop timer** (`record_audio_recorder_service.dart:85-89`), which calls `stop()` internally without ever invoking a UI callback; UI-layer release would leak there. UI dispose paths already funnel into `recorder.cancel()` on all three surfaces, so service-level release covers UI disposal too.

**Injection seams (both follow established project patterns):**
- Wake lock: already seamed — `UploadWakeLockController.debugReset(driver: FakeUploadWakeLockDriver())` (the setUp/tearDown convention used in 8 existing test files; fake at `test/shared/fakes/fake_upload_wake_lock_driver.dart`).
- The `record` plugin: add a `@visibleForTesting`-style constructor to `RecordAudioRecorderService({AudioRecorder? recorder, Duration maxDuration = const Duration(minutes: 5)})` so tests inject an in-file `_FakeAudioRecorder implements AudioRecorder` (Dart lets you implement any concrete class; use `noSuchMethod` for unused members) and a short auto-stop duration. This mirrors the `CompressFileFn` injectable-plugin pattern in `image_processor.dart`. Verified feasible: `AudioRecorder` in record 5.2.1 (pubspec pins `^5.1.0`) is a plain class — no `final`/`sealed`/`interface` modifier, trivial constructor, lazy platform `create` — so `implements` compiles and never touches a channel. But see §5.1: it is a **15-public-member third-party surface**, and `implements` gives no default bodies.

**Deliberately NOT changing `AudioRecorderService` (the abstract interface):** adding a method breaks every `implements`-based fake in the suite (known project hazard). The internal `_wakeLockHeld` guard bool keeps the service from ever decrementing a hold it doesn't own.

## 2. Red-green-refactor steps

All new tests go in one new file: `/Users/I560101/Project-Sat/mknoon-2/flutter_app/test/core/media/record_audio_recorder_service_test.dart`

Shared scaffolding (write once in step 1):
- In-file `_FakeAudioRecorder implements AudioRecorder` with explicit `start`/`stop`/`dispose`/`onAmplitudeChanged` (return an empty broadcast stream) and `noSuchMethod` for the rest; flags `throwOnStart`/`throwOnStop`, counters `startCalls`/`stopCalls`, configurable `stopReturnsPath`.
- `setUp`: `fakeDriver = FakeUploadWakeLockDriver(); UploadWakeLockController.debugReset(driver: fakeDriver); service = RecordAudioRecorderService(recorder: fakeRecorder);`
- `tearDown`: `await service.dispose(); UploadWakeLockController.debugReset(driver: FakeUploadWakeLockDriver());` (controller is static — must not leak holds into other test files).
- **Every `service.start(...)` call in tests MUST pass an explicit non-empty output path** (e.g. `outputPath: '/tmp/wake_lock_test.m4a'`): with an empty path, `start()` falls through to `getTemporaryDirectory()` (`record_audio_recorder_service.dart:60-62`, `:168-172`), which hits the path_provider platform channel and fails in plain `flutter test` (§5.2).

### Step 1 — RED: acquire on start, release on stop
Tests:
- `start() acquires the wake lock after recorder start succeeds` → `debugActiveHolds == 1`, `fakeDriver.enableCalls == 1`.
- `stop() releases the wake lock` → start, stop → `debugActiveHolds == 0`, `disableCalls == 1`.
- `stop() when never started does not release anything` → acquire one *external* hold via `UploadWakeLockController.acquire()` (simulates a concurrent upload), call `service.stop()` → `debugActiveHolds` still `1`, `disableCalls == 0`. (Guards the shared ref-count.)

**GREEN** — modify `/Users/I560101/Project-Sat/mknoon-2/flutter_app/lib/core/media/record_audio_recorder_service.dart`:
- Constructor: `RecordAudioRecorderService({AudioRecorder? recorder, this.maxDuration = const Duration(minutes: 5)}) : _recorder = recorder ?? AudioRecorder();` (drop `static const _maxDuration`, make `_recorder` constructor-set).
- Add `bool _wakeLockHeld = false;` plus private helpers:
  - `_acquireWakeLock()`: if not held → set held, `await UploadWakeLockController.acquire()`.
  - `_releaseWakeLock()`: if held → clear held, `await UploadWakeLockController.release()`.
- `start()`: call `await _acquireWakeLock()` **after** `_recorder.start(...)` resolves (after line 72, next to `_isRecording = true`).
- `stop()`: call `await _releaseWakeLock()` immediately after `_isRecording = false` (line 98), i.e. *before* `await _recorder.stop()`.

### Step 2 — RED: cancel and dispose release
Tests:
- `cancel() releases the wake lock` → start, cancel → `debugActiveHolds == 0`.
- `dispose() while recording releases the wake lock` → start, dispose → `debugActiveHolds == 0`. (Covers UI-dispose→cancel path *and* MyApp shutdown at `main.dart:3294`.)
- `stop() then cancel() then dispose() releases exactly once` → `disableCalls == 1`, holds `0` (idempotent release; never double-decrements).

**GREEN** — same file:
- `cancel()`: `await _releaseWakeLock()` right after `_isRecording = false` (line 129), before `await _recorder.stop()`.
- `dispose()`: `await _releaseWakeLock()` at the top (before line 143).

### Step 3 — RED: failure paths never leak
Tests:
- `start() failure does not acquire the wake lock` → `fakeRecorder.throwOnStart = true`, `expect(service.start(...), throwsA(...))` → `debugActiveHolds == 0`, `enableCalls == 0`. (Passes for free if Step 1 acquired strictly after `_recorder.start` — this test pins that ordering.)
- `stop() releases even when the plugin stop throws` → start, `throwOnStop = true`, `expect(service.stop(), throwsA(...))` → `debugActiveHolds == 0`.
- `cancel() releases even when the plugin stop throws` → same shape via `cancel()`.

**GREEN** — likely already green from release-before-plugin-call ordering in Steps 1–2; if not, wrap the `_recorder.stop()` awaits in `try/finally { await _releaseWakeLock(); }`.

### Step 4 — RED: 5-minute auto-stop releases (the silent path)
Test:
- `auto-stop at max duration releases the wake lock` → construct `RecordAudioRecorderService(recorder: fake, maxDuration: Duration(milliseconds: 50))`, start, `await Future<void>.delayed(Duration(milliseconds: 120))` → `service.isRecording == false`, `debugActiveHolds == 0`.

**GREEN** — no extra code if Step 1's release lives inside `stop()` (the auto-stop timer at lines 85-89 calls `stop()`); the injectable `maxDuration` from Step 1's constructor makes it testable.

### Step 5 — RED: rapid start/start (force-stop branch) holds exactly one
Tests:
- `start() while already recording keeps exactly one hold` → start, start → `debugActiveHolds == 1`; then stop → `0`. Assert `enableCalls - disableCalls == 1` after the second start (no orphaned hold from the force-stopped stale recording).
- `rapid start/stop/start/stop ends at zero holds` → two full cycles → holds `0`, `enableCalls == disableCalls`.

**GREEN** — in the force-stop branch of `start()` (lines 44-58), add `await _releaseWakeLock()` next to `_isRecording = false` (line 57); the fresh acquire after `_recorder.start` then restores the single hold.

### Step 6 — RED: UI dispose chain regression pin (only if not already covered)
First check `test/features/conversation/presentation/screens/conversation_wired_test.dart` for an existing "dispose while recording cancels the recorder" test; if absent, add one:
- `disposing the conversation while recording cancels the recorder` → pump `ConversationWired` with `FakeAudioRecorderService`, invoke `onRecordStart` via the rendered screen's props, `pumpWidget(SizedBox.shrink())` → `fakeRecorder.isRecording == false`. (Service-level release in Step 2 makes recorder-cancel ⇒ lock-release; this just pins the existing UI→cancel wiring at `conversation_wired.dart:3471-3474`. Group/composer surfaces have identical existing dispose code — one surface pin is enough.)

**GREEN** — no production change expected; existing dispose handlers already call `cancel()`.

### Step 7 — REFACTOR
- Sanity-check the new constructor doc comment marks `recorder`/`maxDuration` as test seams.
- Run the full affected suite: `flutter test test/core/media/ test/core/device/upload_wake_lock_test.dart test/features/conversation/presentation/screens/conversation_wired_test.dart`.
- Run `graphify update .` (project rule).
- Optional, only if cheap: a one-line rename/doc note that `UploadWakeLockController` is now a general screen-wake controller (used by uploads, migration, recording) — do **not** rename the class in this change.

## 3. Files to create vs modify

**Create**
- `test/core/media/record_audio_recorder_service_test.dart` (includes in-file `_FakeAudioRecorder`)

**Modify**
- `lib/core/media/record_audio_recorder_service.dart` (constructor seam + `_wakeLockHeld` guard + 5 acquire/release call sites: start-success, force-stop branch, stop, cancel, dispose)
- `test/features/conversation/presentation/screens/conversation_wired_test.dart` (one regression test, only if dispose-cancels-recording isn't already pinned)

**Explicitly untouched:** `lib/core/media/audio_recorder_service.dart` (interface), `lib/core/device/upload_wake_lock.dart`, all three wired widgets, `test/shared/fakes/fake_audio_recorder_service.dart`, `pubspec.yaml`, AndroidManifest/Info.plist (FLAG_KEEP_SCREEN_ON and isIdleTimerDisabled need no permissions).

## 4. Deliberately out of scope
- **Backgrounding/screen-off during recording**: wakelock_plus only suppresses the idle timer while foregrounded; keeping recording alive in background needs a foreground-service/bg-task mechanism (cf. `MigrationTransferKeepAlive`) — separate feature.
- **User pressing the power button**: no wake-lock can prevent explicit screen-off; OS behavior.
- **Feed `InlineReplyInput` voice button**: inert (no surface wires `onRecordStart`), so no wake-lock path exists there. (Verified 2026-06-10: `InlineReplyInput` supports the callbacks at `inline_reply_input.dart:23-45`, but both call sites — `open_mode_card_body.dart:196-205`, `collapsed_mode_card_body.dart:442-451` — omit them, so the mic button is hidden at `:145-158`.)
- **Voice playback** keeping the screen awake (different feature, same controller if ever needed).
- **Renaming `UploadWakeLockController`** to a neutral name — cosmetic, high churn across migration/upload tests.
- Permission-denied before `start()` is ever called (no lock is acquired; nothing to test beyond Step 3's start-failure case).

## 5. Verified caveats — what this plan does NOT fully address (2026-06-10 review)

Findings from the source-verified comparison against the v2 plan. None of these change the design decision; all of them change how the plan should be executed or what must follow it.

### 5.1 Fake maintenance burden: `implements` against a 15-member third-party class
The in-file `_FakeAudioRecorder implements AudioRecorder` fakes the **record package's** class (15 public members in 5.2.1: `start`, `startStream`, `stop`, `cancel`, `pause`, `resume`, `isRecording`, `isPaused`, `hasPermission`, `listInputDevices`, `getAmplitude`, `isEncoderSupported`, `dispose`, `onStateChanged`, `onAmplitudeChanged`). The known project hazard — `implements` has no default bodies — applies here against code we don't control: any record minor-version that adds a member breaks the fake at compile time. `noSuchMethod` softens this for *unused* members only; explicitly-overridden members can still break on signature changes. Mitigation: keep the fake's explicit surface minimal (the four members listed in §2 scaffolding) and lean on `noSuchMethod` for everything else; expect to touch this fake on record upgrades.

### 5.2 `start()` with empty `outputPath` hits path_provider
`record_audio_recorder_service.dart:60-62` (and `:168-172`) calls `getTemporaryDirectory()` when no output path is supplied — a platform channel that is unavailable in plain `flutter test`. Production callers pass `''` (UI handlers let the service pick the temp dir), so the *natural* test call shape fails. Addressed by the scaffolding rule added in §2 (explicit output path in every test); do not stub path_provider instead — the explicit path is simpler and keeps the test hermetic.

### 5.3 First-of-its-kind test pattern in this repo
There are currently **zero** unit tests that fake the inner `AudioRecorder`; the only existing coverage of `RecordAudioRecorderService` is a real-device smoke test (`test/core/media/audio_recorder_smoke_test.dart:16-20`). The v2 plan's tests reuse proven seams (`debugReset(driver:)` + wired-widget pumps); this plan's test file establishes a new pattern. Budget extra time in Step 1 for fake-plumbing surprises (e.g. `onStateChanged`/`onAmplitudeChanged` stream expectations inside the service), and treat the scaffolding as the riskiest part of the change — the production diff itself is small.

### 5.4 Layering departure: first core-layer wake-lock acquisition
Today 100% of `UploadWakeLockController.acquire/release` call sites live in presentation (`conversation_wired.dart:525/577`, `group_conversation_wired.dart:453/504`, `account_migration_journey_screen.dart:151-208`). This plan introduces the first acquisition from `lib/core/`. Verified: this violates no enforced test — `send_voice_message_no_bg_task_test.dart` (in `test/features/conversation/application/`) only pins that the `sendVoiceMessage` use case issues no `bg:begin`/`bg:end` bridge commands; wake-lock calls in the recorder service cannot fail it. It is a convention departure, not a correctness issue. Consequence to accept: wake-lock behavior becomes **invisible to wired-screen tests** (`FakeAudioRecorderService` never acquires), so the service unit tests in §2 are the *only* lock coverage — which is why Steps 1–5 must be thorough. Document the departure in the Step 7 doc-comment pass.

### 5.5 UX bugs this plan deliberately leaves in place (lock-safe, but broken UI) — follow-up work required
This plan makes the **lock** correct on every path; it does not fix the pre-existing recorder/UI desyncs the review confirmed:
- **Stale overlay after 5-min auto-stop**: the timer (`record_audio_recorder_service.dart:85-89`) stops the recorder and (after this change) releases the lock exactly — but the UI is never notified, so `recordingState` stays `recording` and the overlay sits on screen until the user taps stop/cancel (which then resolves cleanly via the null-return path).
- **Group `!_canWrite` no-op handlers** (`group_conversation_wired.dart:3451`, `:3926`) and the **`_tryBeginSendFlow` early-return** (`:3467`): the UI can strand a running recorder. Under this design the lock is bounded by min(5-min auto-stop, screen dispose) — tighter than the UI-level alternative — but the recorder UX bug remains.

**Follow-up commits to graft** (originated as Phases E1/E2 of the deleted v2 draft; design-independent, compose cleanly with service-level placement; each its own red-green commit):
- **Follow-up 1 — `AudioRecorderService.onAutoStopped` hook** (closes the stale-overlay bug): (a) add abstract member `void Function(AudioRecording? recording)? onAutoStopped;` to `lib/core/media/audio_recorder_service.dart`; (b) change the `_maxDurationTimer` body in `record_audio_recorder_service.dart` to `final recording = await stop(); onAutoStopped?.call(recording);`; (c) **same commit**, update every `implements AudioRecorderService` site — re-grep `grep -rn "implements AudioRecorderService"` (3 hits verified, incl. `RecordAudioRecorderService` and `FakeAudioRecorderService`) — this is the interface-growth hazard §1 avoids for the core change, accepted here deliberately; (d) in both wired screens' `_onRecordStart`, set `onAutoStopped` to a handler that cancels duration/amplitude subs and resets `recordingState` to idle (clear the handler on stop/cancel paths); (e) `FakeAudioRecorderService` gains an `onAutoStopped` field + `triggerAutoStop()` knob for wired tests. State reset only; auto-send UX out of scope.
- **Follow-up 2 — group `_forceCancelActiveRecording()`** (closes the `!_canWrite`/group-switch traps): cancel subs, `unawaited(widget.audioRecorderService?.cancel())`, reset composer to idle; call from (a) `didUpdateWidget` on the `oldCanWrite && !_canWrite` transition (next to the existing quote-clear at `group_conversation_wired.dart:626-628`), (b) the top of `_resetForGroupChange` (`:641`), and (c) the canWrite true→false transition inside `_refreshVisibleGroup` (after `_group` is replaced, `:4195-4196`). Call site (c) is mandatory: `_canWrite` is a getter over the internal `_group` (`:4179`), and `_group` is replaced *outside* `didUpdateWidget` by listener-driven paths (group removal/dissolve at `:1352`, `:2060`, `:3752`) — without (c), a removal arriving mid-recording nulls the record callbacks, the handlers early-return, and the recorder is stranded until auto-stop or dispose.

### 5.6 Pre-landing line-number re-check
Branch `121-improvements` carries heavy uncommitted churn. The line references in this plan were verified 2026-06-10 (`record_audio_recorder_service.dart` refs exact; `conversation_wired.dart` dispose at `:3471-3474`). Re-verify the five touch points in `record_audio_recorder_service.dart` (start-success, force-stop branch, stop, cancel, dispose) immediately before editing rather than trusting the cited lines.