# Session N+1 — Android-side regression test for `MainActivity.onNewIntent`

Spawned 2026-05-05 from
[`lock-window-fix-followups-tdd-plan-2026-05-04.md`](./lock-window-fix-followups-tdd-plan-2026-05-04.md)
follow-up #3 (Robolectric / instrumentation test infrastructure).

The parent session (Session N) landed the
`MainActivity.onNewIntent → super.onNewIntent + setIntent` override and
verified it on hardware. The only Android-side regression catcher today is
a **text-level static pin** in
`test/core/notifications/main_activity_onnewintent_pin_test.dart` that
greps the Kotlin source for the literal strings `override fun onNewIntent`,
`super.onNewIntent`, and `setIntent`. It is *shape-only*, not behaviour.

This session adds a narrow, PR-safe **behaviour-level** Android-side test
for the Activity contract that Session N fixed. It must catch the most
likely source regression: a future commit keeps or edits
`onNewIntent(...)` but drops `setIntent(intent)`, leaving the warm-resume
notification tap intent unavailable through `activity.intent`.

This is **not** the Android equivalent of the iOS `simctl push` +
Springboard tap smoke. A Robolectric unit test does not exercise the
Android notification shade, the real `PendingIntent`, the
`flutter_local_notifications` plugin callback, Dart `NOTIFICATION_TAPPED`
markers, or route navigation. It is a cheap Activity-contract guard that
keeps Standing Rule 2.1's hardware soak from being the only catcher.

---

## Pre-flight: pick the test surface (mandatory; do this before any code)

The project today has **no** Android JVM unit-test infrastructure:

- No `android/app/src/test/` directory.
- No `testImplementation` dependencies in `android/app/build.gradle.kts`
  (only `coreLibraryDesugaring` + `implementation` for the Go AAR).
- No `androidTest/` directory either.
- No `./gradlew test` invocation in `scripts/run_test_gates.sh`.

So this session must first decide which surface to introduce. The two
realistic options:

### Option A — Robolectric (`android/app/src/test/`)

JVM-only, no device/emulator needed, runs under `./gradlew test`.

- Pros: fast (sub-second per test once warmed), no device dependency,
  shadows the Android framework so `MainActivity` (extending
  `FlutterActivity`) can be instantiated and `onNewIntent` invoked
  programmatically.
- Cons: Robolectric is a sizable transitive dep (~tens of MB of AAR
  shadows in the build cache); occasional Android-Gradle-plugin / JVM
  target compat friction; one more test runner the project must keep
  green. Limited Flutter-embedding fidelity — the test verifies Android
  Activity contract, not the full PendingIntent → plugin → Dart pipeline.
- Decisive scope: catches "someone removes `setIntent` in `onNewIntent`"
  and "someone makes onNewIntent silently swallow the intent". The
  existing Dart pin remains the belt-and-braces catcher for the literal
  `super.onNewIntent(intent)` call, because this Robolectric test should
  avoid depending on a fully attached Flutter engine. Does NOT catch "the
  AndroidManifest launchMode changed in a way that bypasses onNewIntent"
  (no real launcher / notification tap is in play in a Robolectric unit
  test).

### Option B — Instrumentation (`android/app/src/androidTest/`)

Real device or emulator, runs under `./gradlew connectedAndroidTest`.

- Pros: full PendingIntent → MainActivity → flutter_local_notifications
  plugin → Dart pipeline is exercised. Catches AndroidManifest /
  launchMode regressions too. This is the **gold-standard** for the
  exact runtime path and the closest Android parity with the iOS
  simulator smoke.
- Cons: needs an emulator or device available at test time (CI cost);
  much slower; more infra to keep green; introducing it pulls in a
  AndroidJUnitRunner / espresso footprint the project has so far avoided.

### Decision rule for this session

**Default: Option A (Robolectric).** Reasons:

1. The runtime end-to-end catcher already exists in this repo — Standing
   Rule 2.1's hardware soak does the Option-B job by hand on every
   notification-touching change. Adding Option B as automation is
   valuable only if the project wants Android runtime parity with the iOS
   smoke; it is not required for this Session N+1 Activity-contract guard.
2. The most likely future regression mode is *source-level* (someone
   refactors `MainActivity.kt` and breaks the contract); Robolectric
   catches that at PR time without a device.
3. Robolectric is the cheapest path from zero-Android-test-infra to
   one-real-Android-test, which is also a foundation if the project later
   wants more.

**Do not position Option A as proof of full notification-open runtime
health.** If the acceptance question is "does a real Android OS
notification tap reach Dart and route to the thread?", this plan is
incomplete by design and should spawn a separate instrumentation /
UiAutomator runtime smoke plan instead.

**Override only if:** during the pre-flight, you discover that adding
Robolectric requires resolving an Android-Gradle / JVM target compat
chain that takes more than ~1 hour to land cleanly. In that case stop,
record the friction in this artifact under "Findings", and either
(a) escalate to the user for an Option-B / status-quo decision, or
(b) propose a third path (e.g., a `MethodChannel`-based behaviour test
on the Dart side that drives MainActivity through a fake intent — only
viable if `flutter_local_notifications` exposes a test seam, which at
v18.0.1 it does not).

Do not attempt to install both Option A and Option B in the same session
— scope creep. Pick one.

---

## Scope (this session, after the pre-flight decision lands on Option A)

In scope:

- Add `testImplementation` deps for Robolectric + JUnit4 in
  `android/app/build.gradle.kts`.
- Add the minimal `testOptions { unitTests { isIncludeAndroidResources =
  true } }` Android-Gradle config required by Robolectric.
- Create `android/app/src/test/kotlin/com/mknoon/app/MainActivityOnNewIntentTest.kt`
  with **one** test that asserts the override behaviour (see RED/GREEN
  below).
- Verify the Gradle task graph for `./gradlew :app:testDebugUnitTest`
  before wiring it into `scripts/run_test_gates.sh`. If the task runs
  without triggering Go AAR rebuild / gomobile-only prerequisites, add it
  to the gate. If it does trigger Android toolchain friction unrelated to
  this unit test, keep the Gradle invocation as a documented manual or
  named Android gate for this session and record the blocker in
  "Findings" instead of making every default test gate depend on it.
- Update the existing pin test
  (`test/core/notifications/main_activity_onnewintent_pin_test.dart`) to
  cross-reference the new Robolectric test in its preamble (so future
  readers know there is a behaviour catcher too, and the pin is now
  belt-and-braces rather than the only line of defence).

Out of scope:

- Any Espresso / instrumented test infrastructure (Option B).
- Adding Robolectric tests for any other Activity / Application class —
  this session is one test, one file, one regression scope.
- Refactoring `MainActivity.kt` itself. The override stays exactly as it
  is; the test is observation-only.
- CI / GitHub Actions wiring. If the project's gates already run
  `scripts/run_test_gates.sh` from CI and the Gradle task graph is clean,
  the new line in that script picks it up for free; otherwise CI changes
  are a separate concern.
- Mocking the `flutter_local_notifications` plugin internals. The
  Robolectric test asserts the **Activity-side stored-intent contract**.
  The existing static pin continues to guard the literal
  `super.onNewIntent(intent)` call. Plugin-side dispatch and Dart routing
  are what the hardware soak still catches.

---

## RED — failing test before any GREEN edit

Add `android/app/src/test/kotlin/com/mknoon/app/MainActivityOnNewIntentTest.kt`:

```kotlin
package com.mknoon.app

import android.content.Intent
import org.junit.Assert.assertEquals
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [33])
class MainActivityOnNewIntentTest {

    @Test
    fun onNewIntent_storesIntent_soWarmNotificationPayloadRemainsObservable() {
        val activity = Robolectric
            .buildActivity(MainActivity::class.java)
            .create()
            .get()

        val notificationIntent = Intent().apply {
            action = "SELECT_NOTIFICATION"
            putExtra(
                "flutter_local_notifications_payload",
                "12D3KooWTestPeerId",
            )
        }

        activity.onNewIntent(notificationIntent)

        // setIntent(intent) was called — the test surface for the bug.
        // Without this assertion, removing `setIntent(intent)` from
        // MainActivity.kt would silently pass.
        val current = requireNotNull(activity.intent) {
            "Activity.intent must be non-null after onNewIntent"
        }
        assertEquals(
            "MainActivity.onNewIntent must call setIntent(intent) so the " +
                "warm-resume notification PendingIntent extras remain " +
                "observable through Activity.intent (singleTask resume " +
                "scenario; Pixel hardware soak 2026-05-05).",
            "12D3KooWTestPeerId",
            current.getStringExtra("flutter_local_notifications_payload"),
        )
        assertEquals(
            "Activity.intent.action must reflect the new intent's action.",
            "SELECT_NOTIFICATION",
            current.action,
        )
    }
}
```

To make this fail in a clean way against a hypothetical broken override
(`super.onNewIntent` only, no `setIntent`), revert `MainActivity.kt`
locally in a scratch branch first and confirm the test goes RED. **Do
not commit the revert.**

Start with `Robolectric.buildActivity(...).create().get()` rather than
`ActivityScenario.launch(...)`; the test does not need a resumed UI, only
an Activity instance whose `onNewIntent(...)` method can be invoked. If
`create()` fails because `FlutterActivity` / `GoBridge` requires a fuller
engine environment, first try `buildActivity(...).get()` without running
the lifecycle, because `setIntent(intent)` itself does not depend on the
Activity being resumed. If that is still brittle, use a tiny test-only
subclass that inherits `MainActivity.onNewIntent(...)` unchanged and
overrides only engine configuration. Document whichever path lands in
the test file preamble.

---

## GREEN — gradle wiring

In `android/app/build.gradle.kts`:

```kotlin
android {
    // ...existing config...
    testOptions {
        unitTests {
            isIncludeAndroidResources = true
            // Robolectric needs to load AndroidManifest.xml + resources
            // even for an Activity that doesn't render UI in the test.
        }
    }
}

dependencies {
    implementation(fileTree(mapOf("dir" to "libs", "include" to listOf("*.aar"))))
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")

    testImplementation("junit:junit:4.13.2")
    testImplementation("org.robolectric:robolectric:4.13") // verify against AGP 8.9.x + JVM 11
}
```

Pick exact versions by checking the Robolectric compat matrix
(<https://github.com/robolectric/robolectric/blob/master/README.md>) for
the project's current Android stack (`com.android.application` 8.9.1,
Kotlin 2.1.0, JVM 11 at the time this plan was reviewed). The example
numbers above are a starting point only; verify before committing.

After proving `:app:testDebugUnitTest` does not trigger unrelated Go AAR
or gomobile prerequisites, add this to `scripts/run_test_gates.sh`
alongside the existing `flutter test` invocation:

```bash
( cd android && ./gradlew :app:testDebugUnitTest --warning-mode=summary )
```

Confirm the exact task name with `./gradlew :app:tasks --all | grep -i test`
inside `android/`; AGP versions occasionally rename it. If the task graph
does pull in unrelated native-build prerequisites, do not wire it into the
default gate in this session. Instead document the exact command as a
manual/named Android regression gate and leave default gate promotion for
a follow-up cleanup.

---

## REFACTOR — keep the static pin test as belt-and-braces

Edit `test/core/notifications/main_activity_onnewintent_pin_test.dart`'s
preamble to cross-reference the new Robolectric test:

```
// This is a text-level pin AND a belt-and-braces companion to the
// behaviour-level Robolectric test at
// android/app/src/test/kotlin/com/mknoon/app/MainActivityOnNewIntentTest.kt
// (added in Session N+1, 2026-05-05). Either test catching a regression
// is sufficient; both passing is the green-bar guarantee.
```

Do not delete the pin — it costs nothing and catches things Robolectric
would not (e.g., a commit that disables the Robolectric test directly).

---

## Findings / implementation notes

- Landed pinned Android JVM unit-test dependencies:
  `junit:junit:4.13.2` and `org.robolectric:robolectric:4.13`. The
  versions compile and run against the repo's AGP 8.9.1 / Kotlin 2.1.0 /
  JVM 11 stack in `:app:testDebugUnitTest`.
- `Robolectric.buildActivity(MainActivity::class.java).create().get()`
  was not viable: `create()` reached FlutterActivity / GoBridge native
  loading and failed under Robolectric with
  `com.getkeepsafe.relinker.MissingLibraryException`. The landed test
  uses the plan's no-lifecycle fallback,
  `Robolectric.buildActivity(MainActivity::class.java).get()`, and
  reflectively invokes MainActivity's real protected `onNewIntent`
  override. No test-only subclass was needed.
- `cd android && ./gradlew :app:tasks --all` confirmed the exact unit
  task name: `testDebugUnitTest - Run unit tests for the debug build`.
- `:app:testDebugUnitTest` is green, but its dry-run and real task graph
  include `:app:compileFlutterBuildDebug`, `:app:packJniLibsflutterBuildDebug`,
  `:app:buildGoAar`, `:app:preBuild`, and the broader Android debug
  prebuild/resource chain. Because that pulls unrelated Go AAR /
  Flutter-Android build prerequisites into a nominal JVM unit-test gate,
  this session did **not** promote the command into
  `scripts/run_test_gates.sh`.
- Manual/named Android regression gate for this session:
  `cd android && ./gradlew :app:testDebugUnitTest --warning-mode=summary`.
  Existing Flutter fallback evidence is `flutter test
  test/core/notifications/main_activity_onnewintent_pin_test.dart` plus
  `flutter test`; the latter is currently red on unrelated Dart/widget
  suites.

---

## Verification

- `flutter test test/core/notifications/main_activity_onnewintent_pin_test.dart`
  — PASS.
- `flutter test` — FAIL, exit 1 after six unrelated existing-suite
  Dart/widget failures. Visible failure text included
  `test/features/conversation/presentation/screens/conversation_wired_test.dart:1597`
  expecting `non-empty` but receiving `[]`.
- `cd android && ./gradlew :app:tasks --all` — PASS; confirmed exact
  task name `testDebugUnitTest - Run unit tests for the debug build`.
- `cd android && ./gradlew :app:testDebugUnitTest --warning-mode=summary`
  — PASS after landing the no-lifecycle Robolectric fallback.
- RED proof: temporarily removed `setIntent(intent)` from
  `MainActivity.kt`; `cd android && ./gradlew :app:testDebugUnitTest
  --warning-mode=summary` failed with a clear stored-intent assertion:
  `MainActivity.onNewIntent must call setIntent(intent) ... removing
  setIntent is the stored-intent regression this test guards.
  expected:<12D3KooWTestPeerId> but was:<null>`. Restored
  `MainActivity.kt` and reran the Android unit test successfully.
- `flutter analyze` — FAIL with existing analyzer backlog:
  `1717 issues found`.
- `scripts/run_test_gates.sh` — not edited and not run. The Android unit
  command is kept as a manual/named Android regression gate because the
  Gradle task graph pulls `:app:buildGoAar` / `:app:preBuild` and broad
  Flutter-Android debug build work.
- Fix-pass `flutter test --reporter expanded` from the current workspace
  — FAIL, exit 1, final status `04:45 +6409 -4`; log:
  `/tmp/session_n1_fixpass_flutter_test.log`. Full failure list:
  `test/features/groups/integration/group_resume_recovery_test.dart`
  "MS004 partition replay preserves quoted parent ids and deterministic
  order" expected `['ms004-partition-parent',
  'ms004-partition-a-reply']` but got `[]` at line 4837;
  `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`
  "drains mixed epoch encrypted replay out of order without rewriting
  epochs" expected non-null but got null at line 3969;
  `test/features/groups/presentation/group_conversation_wired_test.dart`
  "voice send blocks text send while the voice pipeline is active and
  releases after failure" timed out after 30s at line 1227; and
  `test/features/groups/presentation/group_conversation_wired_test.dart`
  "voice stop cleanup still runs after unmount when group lookup resolves
  to not found" timed out after 6s at line 5492 and then expected
  non-null at line 5497.
- Fix-pass no-session baseline: created a detached temporary worktree at
  `HEAD` with no Dart diffs, ran `flutter pub get`, then ran
  `flutter test --reporter expanded` — FAIL, exit 1, final status
  `04:36 +6409 -4`; log:
  `/tmp/session_n1_fixpass_flutter_test_no_session_baseline.log`.
  Three failures overlapped the current workspace without any session
  changes: the same `group_resume_recovery_test.dart` MS004 failure, the
  same `drain_group_offline_inbox_use_case_test.dart` mixed-epoch replay
  failure, and the same `group_conversation_wired_test.dart` voice-stop
  cleanup failure. The fourth baseline-only failure was
  `test/features/push/application/ios_push_project_config_test.dart`
  failing to open `ios/Runner/GoogleService-Info.plist`; that file is
  ignored/untracked and exists in the main working tree, so this is a
  temporary-worktree fixture caveat, not a session regression.
- Fix-pass `flutter analyze` from the current workspace — FAIL, exit 1,
  `1717 issues found`; log:
  `/tmp/session_n1_fixpass_flutter_analyze_current.log`. The only Dart
  file touched by this session is
  `test/core/notifications/main_activity_onnewintent_pin_test.dart`, and
  the diff is comment-only in the preamble. The analyzer log contains no
  issue for that file.
- Fix-pass no-session analyzer comparison: in the same detached temporary
  worktree at `HEAD` with no Dart diffs, `flutter analyze` also failed
  with exactly `1717 issues found`; log:
  `/tmp/session_n1_fixpass_flutter_analyze_no_session_dart.log`. This is
  the before/same-count proof for the analyzer blocker. The temporary
  worktree was removed after evidence collection.

---

## Critical files

- `android/app/src/main/kotlin/com/mknoon/app/MainActivity.kt` — the
  override under test; **not modified** by this session.
- `android/app/src/test/kotlin/com/mknoon/app/MainActivityOnNewIntentTest.kt` —
  new file (Robolectric test).
- `android/app/build.gradle.kts` — add `testOptions` + `testImplementation`
  deps.
- `scripts/run_test_gates.sh` — add a `./gradlew :app:testDebugUnitTest`
  invocation alongside the Flutter test gate only after confirming the
  task graph is clean for default use.
- `test/core/notifications/main_activity_onnewintent_pin_test.dart` —
  preamble cross-reference only.
- `android/app/src/main/AndroidManifest.xml` — read-only reference for
  the test (`launchMode="singleTask"` line 20 is what makes
  `onNewIntent` the relevant entry point).

---

## Risk register

1. **Robolectric / AGP version mismatch.** Most common failure mode for
   first-time Robolectric introduction in an AGP 8.9.x / Kotlin 2.1.0 /
   JVM 11 project. Mitigation: pin Robolectric explicitly; do not let
   Gradle resolve via dynamic version ranges. If the build fails on first
   run with a `RuntimeEnvironment`, unsupported SDK, or shadow-loading
   error, treat that as a version-matrix issue before changing
   `MainActivity.kt`.
2. **`FlutterActivity` requires engine attach.** If a full lifecycle
   launch reaches Flutter engine / GoBridge setup, the test may crash
   before the `onNewIntent` assertion runs.
   Mitigation documented inline in the RED step: avoid
   `ActivityScenario`, start with `Robolectric.buildActivity`, and fall
   back to no-lifecycle construction or a tiny test subclass only if
   direct `MainActivity` creation is brittle.
3. **Default gate friction.** `./gradlew testDebugUnitTest` may be fast
   once warm, but this repo also has Android pre-build Go AAR validation.
   Mitigation: inspect the task graph and run the command locally before
   wiring it into `scripts/run_test_gates.sh`. If it pulls in unrelated
   native prerequisites, keep it as a manual/named Android regression
   gate until that build wiring is cleaned up.
4. **Plugin version drift.** Future `flutter_local_notifications`
   versions could change the contract such that `setIntent(intent)` is
   not enough and a plugin-instance hook must also be called. The test
   here would still pass (it asserts setIntent only) — the regression
   would surface as a hardware-soak failure under Standing Rule 2.1.
   This is by design: the Robolectric test scope is the Activity
   contract; the plugin contract is the soak's job. Document this
   clearly in the test file's preamble.

---

## Standing-rule applicability

Standing Rule 2.1 (hardware soak for notification-related changes)
**still applies** after this session lands. The Robolectric test does
not replace the soak — it shrinks the surface the soak has to catch.

If the rule's hardware-soak step is ever discussed for retirement, the
question to ask is: "do we have an Option-B (instrumentation) test for
the full PendingIntent → plugin → Dart pipeline?" Until that is yes,
Standing Rule 2.1 stays.

---

## Execution Progress

- 2026-05-06 16:37:52 CEST — contract extracted. Scope is Option A
  Robolectric only: add one Activity stored-intent regression test,
  Gradle unit-test dependencies/config, conditional default-gate wiring,
  and the pin-test preamble cross-reference. Code-entry files inspected:
  `android/app/build.gradle.kts`,
  `android/app/src/main/kotlin/com/mknoon/app/MainActivity.kt`,
  `android/app/src/main/AndroidManifest.xml`,
  `scripts/run_test_gates.sh`, and
  `test/core/notifications/main_activity_onnewintent_pin_test.dart`.
  Required evidence: direct pin test, full `flutter test`, Gradle task
  discovery, `:app:testDebugUnitTest`, local RED proof by temporarily
  removing `setIntent(intent)`, `flutter analyze`, and either promoted
  `scripts/run_test_gates.sh` or documented manual Android-gate fallback
  if the Gradle task graph has unrelated toolchain friction. Next action:
  spawn the isolated Executor.
- 2026-05-06 16:39:07 CEST — Executor spawned (`Mill`,
  `gpt-5.5`, `xhigh`) with write ownership limited to the Android
  Robolectric test, Android Gradle unit-test config, pin-test preamble,
  conditional gate-script wiring, and this progress/findings artifact.
  Command currently running: spawned Executor pass. Next action: bounded
  wait for implementation evidence.
- 2026-05-06 16:41:22 CEST — first Executor attempt ended with a
  stream-disconnect tool failure before returning a result. Inspection of
  assigned files found no implementation delta in `android/app/build.gradle.kts`,
  `android/app/src/test/kotlin/com/mknoon/app/MainActivityOnNewIntentTest.kt`,
  `test/core/notifications/main_activity_onnewintent_pin_test.dart`, or
  `scripts/run_test_gates.sh`, so there is no partial code/test state to
  reconcile. Decision: spend the allowed retry on a fresh isolated
  Executor. Next action: spawn retry Executor.
- 2026-05-06 16:42:07 CEST — retry Executor spawned (`Pauli`,
  `gpt-5.5`, `xhigh`) with the same bounded write ownership and required
  evidence list. Command currently running: spawned Executor retry pass.
  Next action: bounded wait for implementation evidence.
- 2026-05-06 16:43:16 CEST — fresh isolated Executor retry resumed
  locally after the prior stream disconnect. Confirmed no implementation
  delta existed in the allowed write paths before this pass. Files
  inspected: `android/app/build.gradle.kts`,
  `android/app/src/main/kotlin/com/mknoon/app/MainActivity.kt`,
  `android/app/src/main/AndroidManifest.xml`, `scripts/run_test_gates.sh`,
  and `test/core/notifications/main_activity_onnewintent_pin_test.dart`.
  Next action: add the Option A Robolectric unit-test wiring and
  behaviour regression.
- 2026-05-06 16:44:10 CEST — implementation files touched:
  added `android/app/src/test/kotlin/com/mknoon/app/MainActivityOnNewIntentTest.kt`,
  added Android JVM unit-test options and pinned `junit:junit:4.13.2` /
  `org.robolectric:robolectric:4.13` dependencies in
  `android/app/build.gradle.kts`, and updated the Dart pin-test preamble
  to point at the Robolectric behaviour companion. Next action: run the
  required verification commands in order.
- 2026-05-06 16:49:30 CEST — verification progress: `flutter test
  test/core/notifications/main_activity_onnewintent_pin_test.dart`
  passed. `flutter test` completed with exit code 1 after six unrelated
  existing-suite Dart/widget failures; no production Dart code was
  changed by this session. Visible failure text included
  `test/features/conversation/presentation/screens/conversation_wired_test.dart:1597`
  expecting a non-empty upload-pending row list but receiving `[]`.
  Decision: continue the required Android Gradle task discovery and
  Robolectric evidence; do not widen scope into unrelated Dart fixes.
- 2026-05-06 16:47:37 CEST — controller bounded-wait inspection found
  real Executor progress in `android/app/build.gradle.kts`,
  `android/app/src/test/kotlin/com/mknoon/app/MainActivityOnNewIntentTest.kt`,
  `test/core/notifications/main_activity_onnewintent_pin_test.dart`, and
  this progress artifact. Decision: one additional bounded wait is
  permitted for the Executor to finish required test/gate evidence. Next
  action: continue waiting for Executor completion.
- 2026-05-06 16:54:49 CEST — Gradle task discovery and Android gate
  decision completed. `cd android && ./gradlew :app:tasks --all`
  passed and confirmed `testDebugUnitTest - Run unit tests for the debug
  build`. A dry run plus real execution showed `:app:testDebugUnitTest`
  pulls `:app:buildGoAar`, `:app:preBuild`, and Flutter/Android debug
  prebuild work, so `scripts/run_test_gates.sh` was not edited. Decision:
  keep the Robolectric command as a manual/named Android regression gate
  for now.
- 2026-05-06 16:54:49 CEST — Android unit-test implementation evidence:
  first direct compile failed because Kotlin treats
  `MainActivity.onNewIntent` as protected; the test now invokes the real
  override reflectively. The first lifecycle run failed at
  `Robolectric.buildActivity(...).create().get()` with
  `com.getkeepsafe.relinker.MissingLibraryException`, so the landed test
  documents and uses the no-lifecycle `buildActivity(...).get()` fallback.
  Restored-source command `cd android && ./gradlew :app:testDebugUnitTest
  --warning-mode=summary` passed.
- 2026-05-06 16:54:49 CEST — RED proof completed. Temporarily removed
  `setIntent(intent)` from `MainActivity.kt` and ran `cd android &&
  ./gradlew :app:testDebugUnitTest --warning-mode=summary`; the test
  failed with `MainActivity.onNewIntent must call setIntent(intent) so
  the warm-resume notification PendingIntent extras remain observable
  through Activity.intent; removing setIntent is the stored-intent
  regression this test guards. expected:<12D3KooWTestPeerId> but
  was:<null>`. Restored `MainActivity.kt` immediately and reran the
  Android unit test successfully.
- 2026-05-06 16:54:49 CEST — final verification completed.
  `flutter analyze` exited 1 with the existing analyzer backlog
  (`1717 issues found`); the only touched Dart file changed comments
  only. `MainActivity.kt` has no final diff after RED proof restore.
  Executor handoff ready with remaining blockers limited to unrelated
  full-suite Flutter/analyzer failures outside this session's write
  scope.
- 2026-05-06 16:57:44 CEST — Executor completed with a coherent
  implementation and handoff evidence. Changed files in this session's
  write scope: `android/app/build.gradle.kts`,
  `android/app/src/test/kotlin/com/mknoon/app/MainActivityOnNewIntentTest.kt`,
  `test/core/notifications/main_activity_onnewintent_pin_test.dart`, and
  this plan artifact. `scripts/run_test_gates.sh` was intentionally not
  edited after the Gradle task graph showed Android native/prebuild
  friction. Required Android direct test and RED proof passed; full
  `flutter test` and `flutter analyze` returned non-zero. Next action:
  spawn isolated QA Reviewer for sufficiency classification.
- 2026-05-06 16:58:23 CEST — QA Reviewer spawned (`Copernicus`,
  `gpt-5.5`, `xhigh`) with the Executor handoff and strict sufficiency
  checklist. Command currently running: spawned QA review pass. Next
  action: bounded wait for QA classification.
- 2026-05-06 17:01:10 CEST — QA Reviewer completed with blocking
  issues. Blocking issue 1: required `flutter test` evidence is red and
  not classified as an accepted known-red baseline by the plan/gate docs.
  Blocking issue 2: required `flutter analyze` evidence is red without
  before-count proof for "same issue count as before." Non-blocking
  follow-up: future cleanup to isolate `:app:testDebugUnitTest` from
  broad Android/Go prebuild work before default-gate promotion. Decision:
  spend the single allowed fix-pass on contract-valid `flutter test` and
  `flutter analyze` evidence only. Next action: spawn fresh fix-pass
  Executor.
- 2026-05-06 17:01:42 CEST — fix-pass Executor spawned (`Laplace`,
  `gpt-5.5`, `xhigh`) with instructions limited to resolving the
  `flutter test` and `flutter analyze` evidence blockers or proving them
  unrelated with contract-valid baseline evidence. Command currently
  running: spawned fix-pass Executor. Next action: bounded wait for
  fix-pass handoff.
- 2026-05-06 17:02:36 CEST — fix-pass Executor started in the fresh
  isolated context. Scope is limited to the two QA blockers:
  contract-valid full `flutter test` evidence and `flutter analyze`
  before/same-count evidence. Confirmed `MainActivity.kt` has no current
  diff before fix-pass work. Next action: rerun current full-suite and
  analyzer evidence, then compare analyzer output with the session's
  comment-only Dart edit excluded in a temporary non-destructive copy.
- 2026-05-06 17:07:14 CEST — controller bounded-wait inspection found
  real fix-pass progress and an active required evidence command:
  `flutter test --reporter expanded` writing to
  `/tmp/session_n1_fixpass_flutter_test.log`. Decision: one additional
  bounded wait is permitted for the fix-pass to finish test/analyzer
  evidence. Next action: continue waiting for fix-pass handoff.
- 2026-05-06 17:08:16 CEST — fix-pass current full-suite evidence
  completed. Command: `flutter test --reporter expanded` with output in
  `/tmp/session_n1_fixpass_flutter_test.log`; result: FAIL, exit 1,
  final status `04:45 +6409 -4`. Failures were limited to group Dart
  suites: `group_resume_recovery_test.dart` MS004 parent/reply order
  actual `[]`, `drain_group_offline_inbox_use_case_test.dart`
  mixed-epoch replay expected non-null actual null, and two
  `group_conversation_wired_test.dart` voice cleanup/send timeout
  failures. Decision: no narrow code fix is justified by this Android
  on-new-intent session because no group/conversation Dart code was
  touched. Next action: run analyzer evidence and no-session baselines.
- 2026-05-06 17:10:09 CEST — fix-pass current analyzer evidence
  completed. Command: `flutter analyze` with output in
  `/tmp/session_n1_fixpass_flutter_analyze_current.log`; result: FAIL,
  exit 1, `1717 issues found`. `git diff --name-only -- '*.dart'`
  listed only `test/core/notifications/main_activity_onnewintent_pin_test.dart`,
  whose diff is comment-only in the preamble, and the analyzer output has
  no issue for that file. Next action: establish no-session analyzer
  count in a detached temporary worktree.
- 2026-05-06 17:11:12 CEST — created detached temporary worktree at
  `/tmp/mknoon-fixpass-analyze-base.ZFn9wO` from `HEAD` for
  non-destructive baseline evidence. The temporary worktree had no Dart
  diffs. Ran `flutter pub get` there successfully to create
  `.dart_tool/package_config.json`. Next action: run analyzer and full
  test baselines without the session's Dart comment change.
- 2026-05-06 17:11:29 CEST — no-session analyzer baseline completed in
  the detached temporary worktree. Command: `flutter analyze` with output
  in `/tmp/session_n1_fixpass_flutter_analyze_no_session_dart.log`;
  result: FAIL, exit 1, exactly `1717 issues found`. Decision: analyzer
  red state is unchanged by the session's comment-only Dart edit and is
  valid same-count evidence for final QA. Next action: run no-session
  full-suite baseline.
- 2026-05-06 17:17:07 CEST — no-session full-suite baseline completed in
  the detached temporary worktree. Command: `flutter test --reporter
  expanded` with output in
  `/tmp/session_n1_fixpass_flutter_test_no_session_baseline.log`; result:
  FAIL, exit 1, final status `04:36 +6409 -4`. Three failures overlapped
  the current workspace without session changes: same group resume MS004
  replay-order failure, same group offline-inbox mixed-epoch null
  failure, and same group conversation voice-stop cleanup timeout/null
  failure. The fourth baseline-only failure was the ignored/untracked
  `ios/Runner/GoogleService-Info.plist` fixture missing from the temp
  worktree; the file exists in the main working tree. Decision: full
  `flutter test` remains red on pre-existing/unrelated Dart suite issues,
  not this Android regression-test implementation.
- 2026-05-06 17:18:40 CEST — fix-pass final handoff ready. No code was
  changed during the fix pass; only this plan artifact was updated with
  evidence. The temporary worktree was removed with `git worktree remove`.
  `MainActivity.kt` still has no final diff. Remaining blockers, if any,
  are final-QA classification only: `flutter test` is still red but now
  has no-session baseline evidence; `flutter analyze` is still red but
  now has exact same-count proof.
- 2026-05-06 17:21:47 CEST — final QA Reviewer spawned (`McClintock`,
  `gpt-5.5`, `xhigh`) with the implementation evidence, initial QA
  blockers, and fix-pass baseline evidence. Command currently running:
  spawned final QA pass. Next action: bounded wait for final QA verdict.
- 2026-05-06 17:26:12 CEST — final QA Reviewer completed with blocking
  issues. The Android-specific implementation remains scope-clean and
  verified: pin test passed, Gradle task discovery passed,
  `:app:testDebugUnitTest` passed, RED proof passed, and `MainActivity.kt`
  has no final diff. The analyzer blocker is resolved as same-count
  evidence (`1717 issues found` in both current workspace and detached
  no-session baseline, with no issue in the only touched Dart file).
  Final blocker: required broad `flutter test` remains red (`04:45
  +6409 -4`) with group-suite failures, and the governing plan/gate docs
  do not classify those full-suite failures as accepted known failures.
  Final verdict: blocked. Blocker class: test_or_gate_failure.
  Recommended next retry focus: make broad `flutter test` green, or
  formally revise the plan/gate definitions to accept these exact
  pre-existing full-suite failures before rerunning this session.

## Final Execution Verdict

- Verdict: `blocked`
- Blocker class: `test_or_gate_failure`
- Exact blocker: required broad `flutter test` evidence remains red
  (`flutter test --reporter expanded` failed with `04:45 +6409 -4`) and
  is not accepted as a known failure by this plan or the governing gate
  definitions. The remaining failures are group-suite failures outside
  this Android on-new-intent implementation, but the original execution
  contract required full `flutter test` GREEN.
- Spawned-agent isolation used: yes. Executor, QA Reviewer, fix-pass
  Executor, and final QA Reviewer were separate spawned agents; the first
  Executor stream-disconnect was retried once with a fresh spawned
  Executor before implementation landed.
- Local sequential fallback used: no.
- Files changed by the accepted implementation delta:
  `android/app/build.gradle.kts`,
  `android/app/src/test/kotlin/com/mknoon/app/MainActivityOnNewIntentTest.kt`,
  `test/core/notifications/main_activity_onnewintent_pin_test.dart`, and
  this plan artifact.
- Tests added or updated: added
  `MainActivityOnNewIntentTest.kt`; updated the Dart pin-test preamble
  only.
- Required evidence satisfied: pin test PASS, Gradle task discovery PASS
  with `testDebugUnitTest`, Android Robolectric unit test PASS, RED proof
  PASS, `git diff --check` PASS, analyzer same-count proof established.
- Required evidence not satisfied: broad `flutter test` GREEN.
- Non-blocking follow-ups deferred: isolate `:app:testDebugUnitTest` from
  Go AAR / Android prebuild work before default-gate promotion; add a
  separate Android instrumentation/UI smoke if full notification tap
  runtime proof is desired.
- Why unsafe to consider complete: the Android regression-test slice is
  implemented and verified, but the execution contract cannot be accepted
  while a required broad test command remains red without explicit
  known-failure handling.

## Post-Run Summary And Next Work

Updated 2026-05-06 17:28:25 CEST.

What was done:

- Landed the Option A Robolectric path from this plan, not Option B
  instrumentation.
- Added Android JVM unit-test wiring in `android/app/build.gradle.kts`:
  Robolectric/JUnit dependencies plus resource-inclusive unit-test
  configuration.
- Added
  `android/app/src/test/kotlin/com/mknoon/app/MainActivityOnNewIntentTest.kt`,
  a behavior-level stored-intent regression for
  `MainActivity.onNewIntent`.
- Updated
  `test/core/notifications/main_activity_onnewintent_pin_test.dart` so
  the static Dart pin now cross-references the Robolectric behavior
  companion.
- Kept `MainActivity.kt` unchanged in the final diff. It was temporarily
  edited only for the RED proof, then restored.
- Verified the Android-specific slice:
  `flutter test test/core/notifications/main_activity_onnewintent_pin_test.dart`
  passed, Gradle task discovery confirmed `testDebugUnitTest`,
  `cd android && ./gradlew :app:testDebugUnitTest --warning-mode=summary`
  passed, and the RED proof failed correctly when `setIntent(intent)` was
  temporarily removed.
- Did not promote `:app:testDebugUnitTest` into
  `scripts/run_test_gates.sh` because the Gradle path pulls
  `:app:buildGoAar`, `:app:preBuild`, and broad Flutter/Android debug
  prebuild work. For now the Android regression gate remains the manual
  command:
  `cd android && ./gradlew :app:testDebugUnitTest --warning-mode=summary`.
- Proved `flutter analyze` is unchanged by this session: current
  workspace and detached no-session baseline both reported exactly
  `1717 issues found`, and the only touched Dart file changed comments
  only.

What still needs to be done before this session can be accepted:

- Resolve the broad `flutter test` blocker. Current workspace
  `flutter test --reporter expanded` failed with `04:45 +6409 -4`.
  The remaining failures are group-suite failures outside this Android
  implementation, but the plan requires full `flutter test` GREEN and the
  governing gate docs do not currently accept those failures as known red.
- Either make those group-suite failures pass, or formally update the
  plan/gate definitions to classify the exact pre-existing full-suite
  failures as accepted known failures before rerunning this session.
- After the broad test blocker is resolved or explicitly accepted, rerun
  the required evidence set: pin test, `flutter test`, Android Gradle
  task discovery, `:app:testDebugUnitTest`, RED proof if the Activity
  test or `MainActivity.kt` changed, `flutter analyze`, and
  `git diff --check`.

Optional follow-ups after acceptance:

- Isolate `:app:testDebugUnitTest` from Go AAR / Android prebuild work so
  it can be safely promoted into `scripts/run_test_gates.sh`.
- Add a separate Android instrumentation or UI smoke if the project wants
  full real notification tap proof for the PendingIntent -> plugin ->
  Dart route, because this Robolectric test intentionally covers only the
  Activity stored-intent contract.

## Controller Resume Sanity Check

Updated 2026-05-06 17:42:14 CEST.

- `git diff --check -- android/app/build.gradle.kts android/app/src/test/kotlin/com/mknoon/app/MainActivityOnNewIntentTest.kt test/core/notifications/main_activity_onnewintent_pin_test.dart Test-Flight-Improv/Group-Chat-Feature/session-N+1-android-onnewintent-regression-test-plan-2026-05-05.md`
  — PASS.
- `flutter test test/core/notifications/main_activity_onnewintent_pin_test.dart`
  — PASS.
- `cd android && ./gradlew :app:testDebugUnitTest --warning-mode=summary`
  — PASS, `BUILD SUCCESSFUL in 11s`. The task graph still includes
  `:app:buildGoAar`, `:app:preBuild`, Flutter asset/resource work, and
  broad Android debug prebuild work, so the manual/named-gate decision
  remains correct.
- Final verdict remains `blocked` for the same reason recorded above:
  the required broad `flutter test` command is red and not formally
  accepted as a known failure by this plan or the governing gate
  definitions.

## Broad Flutter Test Resume Closure

Updated 2026-05-06 17:58:49 CEST.

- Root cause of the broad-suite blocker: two group offline-replay tests
  used fixed `2026-04-29` timestamps. On 2026-05-06 those replay
  messages fell outside the seven-day backlog retention window, so
  `drainGroupOfflineInbox` correctly decrypted then skipped them before
  persistence.
- Updated only test fixtures, not production retention behavior:
  `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`
  and
  `test/features/groups/integration/group_resume_recovery_test.dart`
  now use retained timestamps relative to the test run.
- Focused repros now pass:
  `flutter test test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --plain-name 'drains mixed epoch encrypted replay out of order without rewriting epochs' --reporter expanded`
  and
  `flutter test test/features/groups/integration/group_resume_recovery_test.dart --plain-name 'MS004 partition replay preserves quoted parent ids and deterministic order' --reporter expanded`.
- Full required broad gate now passes:
  `flutter test --reporter expanded` completed with
  `04:19 +6413: All tests passed!`.
- `git diff --check` passed for the newly touched group tests and this
  session plan.

Superseding final verdict: accepted for this session's implemented
Android `onNewIntent` regression slice. The prior broad `flutter test`
blocker is resolved.

## Execution Progress - Current Orchestrator Re-run

- 2026-05-06 18:11:22 CEST - contract extracted from the current plan
  state. Exact scope remains the Android Option A Robolectric
  behaviour-level stored-intent regression for `MainActivity.onNewIntent`,
  Android Gradle unit-test wiring, the Dart pin-test preamble
  cross-reference, and plan evidence. Source of truth is this plan plus
  `Test-Flight-Improv/test-gate-definitions.md`. Code-entry files:
  `android/app/build.gradle.kts`,
  `android/app/src/main/kotlin/com/mknoon/app/MainActivity.kt`,
  `android/app/src/main/AndroidManifest.xml`,
  `android/app/src/test/kotlin/com/mknoon/app/MainActivityOnNewIntentTest.kt`,
  `test/core/notifications/main_activity_onnewintent_pin_test.dart`,
  `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`,
  and
  `test/features/groups/integration/group_resume_recovery_test.dart`.
  Required evidence remains pin test, broad `flutter test`,
  Android Gradle task discovery, `:app:testDebugUnitTest`, RED proof when
  the Activity test or `MainActivity.kt` changes, `flutter analyze`,
  and `git diff --check`. Decision: run the requested skill sequence
  against the current workspace with fresh Executor then QA Reviewer
  agents. Next action: spawn isolated Executor.
- 2026-05-06 18:12:10 CEST - Executor spawned (`Gibbs`, `gpt-5.5`,
  `xhigh`) with ownership limited to the Android Robolectric regression,
  Gradle unit-test wiring, pin-test preamble, group replay fixture
  timestamp fixes if required by broad test evidence, and this progress
  artifact. Command currently running: spawned Executor pass. Next
  action: bounded wait for implementation and verification evidence.
- 2026-05-06 18:13:14 CEST - current Executor pass inspected workspace
  state and relevant diffs. Scoped implementation appears already landed:
  `android/app/build.gradle.kts` has only Robolectric/JUnit unit-test
  wiring, `android/app/src/test/kotlin/com/mknoon/app/MainActivityOnNewIntentTest.kt`
  exists as the stored-intent behavior test, the Dart static pin has only
  preamble cross-reference edits, and the two group replay fixtures already
  carry retained relative timestamps. `MainActivity.kt`,
  `AndroidManifest.xml`, and `scripts/run_test_gates.sh` have no diff, so
  the no-production-refactor and no-default-gate-promotion constraints are
  still satisfied. Unrelated existing workspace diffs were observed in intro
  plan docs, `info.plist`, and `pubspec.yaml` and were left untouched. Next
  action: run required direct evidence commands before deciding whether any
  further edits are needed.
- 2026-05-06 18:14:22 CEST - first required evidence completed. `git diff
  --check -- android/app/build.gradle.kts test/core/notifications/main_activity_onnewintent_pin_test.dart test/features/groups/application/drain_group_offline_inbox_use_case_test.dart test/features/groups/integration/group_resume_recovery_test.dart Test-Flight-Improv/Group-Chat-Feature/session-N+1-android-onnewintent-regression-test-plan-2026-05-05.md`
  passed; the untracked Kotlin Robolectric test was also checked with
  `git diff --check --no-index -- /dev/null android/app/src/test/kotlin/com/mknoon/app/MainActivityOnNewIntentTest.kt`
  and had no whitespace errors. `flutter test
  test/core/notifications/main_activity_onnewintent_pin_test.dart` passed
  with `00:00 +1: All tests passed!`. `cd android && ./gradlew
  :app:testDebugUnitTest --warning-mode=summary` passed with `BUILD
  SUCCESSFUL in 7s`; its task graph still included `:app:buildGoAar`,
  `:app:preBuild`, and broad Flutter/Android debug prebuild tasks, so the
  no-default-gate-promotion decision remains valid. Next action: run broad
  `flutter test --reporter expanded`.
- 2026-05-06 18:24:58 CEST - broad Flutter evidence completed with one
  transient red pass followed by one green full rerun. First command:
  `flutter test --reporter expanded` failed after `04:32 +6412 -1`; the
  streamed transcript was too large to retain the failing assertion, and no
  code fix was attempted. Narrow follow-up checks for the first visible
  failure-counter area both passed: `flutter test
  test/features/conversation/presentation/screens/conversation_screen_test.dart
  --plain-name 'ConversationScreen renders the selected cosmic background'
  --reporter expanded` passed, and the full
  `test/features/conversation/presentation/screens/conversation_screen_test.dart`
  file passed with `00:03 +58: All tests passed!`. The neighboring
  `ConversationWired optimistic send prefills shared text into the composer`
  targeted check also passed. Classification: the first broad-suite failure
  is non-reproducible in this Executor pass and is not attributable to the
  Android `onNewIntent`, Gradle, pin-test, or group replay timestamp fixture
  changes. Fresh full command with complete JSON capture:
  `flutter test --reporter json > /tmp/session_n1_current_flutter_test.jsonl`
  passed with `{"success":true,"type":"done","time":258595}` and no
  `"type":"error"` events. Next action: run analyzer evidence.
- 2026-05-06 18:26:40 CEST - analyzer evidence completed. `flutter analyze`
  failed with the existing analyzer backlog, exactly `1717 issues found`;
  this matches the prior plan evidence. Current touched Dart files are only
  `test/core/notifications/main_activity_onnewintent_pin_test.dart`,
  `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`,
  and `test/features/groups/integration/group_resume_recovery_test.dart`.
  Targeted analyzer check for those three files passed:
  `flutter analyze test/core/notifications/main_activity_onnewintent_pin_test.dart test/features/groups/application/drain_group_offline_inbox_use_case_test.dart test/features/groups/integration/group_resume_recovery_test.dart`
  returned `No issues found! (ran in 1.7s)`. Prior RED proof remains
  acceptable because neither `MainActivity.kt` nor the Robolectric test was
  changed in this Executor pass after the recorded RED proof; no temporary
  production edit was made. Next action: run final `git diff --check` and
  hand off to QA.
- 2026-05-06 18:27:21 CEST - final Executor handoff evidence recorded.
  Final scoped `git diff --check` passed for `android/app/build.gradle.kts`,
  the Dart pin test, the two group replay fixture tests, and this plan file;
  the untracked Kotlin Robolectric test was checked separately with
  `git diff --check --no-index -- /dev/null
  android/app/src/test/kotlin/com/mknoon/app/MainActivityOnNewIntentTest.kt`
  and had no whitespace errors. No code edits were required in this
  Executor pass beyond this progress update. Executor verdict: coherent and
  complete for QA review, with two caveats for QA to assess: the first broad
  Flutter run had one non-reproducible failure before the JSON-captured full
  rerun passed, and full `flutter analyze` remains red on the pre-existing
  1717-issue backlog while touched Dart files analyze cleanly.
- 2026-05-06 18:29:16 CEST - Executor completed after an interrupt prompt
  to stop further tool work and return the handoff. Files changed in the
  Executor pass: this plan artifact only. Exact evidence reported: scoped
  `git diff --check` PASS, untracked Kotlin test whitespace check PASS,
  pin test PASS, `:app:testDebugUnitTest` PASS, one broad
  `flutter test --reporter expanded` FAIL that did not reproduce in
  targeted conversation checks or the subsequent full
  `flutter test --reporter json` PASS, full `flutter analyze` FAIL with
  existing `1717 issues found`, and targeted analyzer on touched Dart
  files PASS. Next action: spawn isolated QA Reviewer for sufficiency
  review.
- 2026-05-06 18:29:50 CEST - QA Reviewer spawned (`Planck`,
  `gpt-5.5`, `xhigh`) with the current plan, gate docs, and Executor
  handoff evidence. Command currently running: spawned QA review pass.
  Next action: bounded wait for QA classification.
- 2026-05-06 18:32:58 CEST - QA Reviewer completed with no blocking
  issues and final recommendation `accepted_with_explicit_follow_up`.
  Required evidence accepted: Robolectric test guards the real protected
  `MainActivity.onNewIntent` override and `setIntent(intent)` behavior;
  prior RED proof remains valid because neither `MainActivity.kt` nor the
  Robolectric test changed after that proof; scope guard is preserved;
  broad `flutter test` evidence is accepted because the first expanded
  failure was non-reproducible and the later full JSON run ended with
  `{"success":true,"type":"done","time":258595}` and no error events;
  full `flutter analyze` red is accepted as pre-existing same-count
  backlog while touched Dart files analyze cleanly; group replay
  timestamp fixture fixes are in scope and do not change production
  retention behavior. Non-blocking follow-ups: keep
  `:app:testDebugUnitTest` manual/named until Go AAR / Android prebuild
  task graph friction is isolated, add a separate Android instrumentation
  or UI smoke only if full real notification-tap runtime proof is
  desired, and keep unrelated dirty files out of this session's final
  package unless intentionally included elsewhere. Final verdict:
  `accepted_with_explicit_follow_up`.

## Current Orchestrator Final Verdict

- Verdict: `accepted_with_explicit_follow_up`
- Blocker class: none
- Spawned-agent isolation used: yes. The current pass used a fresh
  Executor (`Gibbs`) followed by a separate QA Reviewer (`Planck`).
- Local sequential fallback used: no.
- Files changed by this current orchestrator pass: this plan artifact
  only. The already-landed implementation delta remains
  `android/app/build.gradle.kts`,
  `android/app/src/test/kotlin/com/mknoon/app/MainActivityOnNewIntentTest.kt`,
  `test/core/notifications/main_activity_onnewintent_pin_test.dart`,
  `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`,
  and
  `test/features/groups/integration/group_resume_recovery_test.dart`.
- Tests added or updated: Robolectric
  `MainActivityOnNewIntentTest.kt`; Dart static pin-test preamble;
  group replay fixture timestamps retained inside the seven-day backlog
  window.
- Exact tests and gates accepted for this re-run:
  `git diff --check` on scoped touched files PASS; untracked Kotlin test
  whitespace check PASS; `flutter test
  test/core/notifications/main_activity_onnewintent_pin_test.dart` PASS;
  `cd android && ./gradlew :app:testDebugUnitTest --warning-mode=summary`
  PASS; full `flutter test --reporter json` PASS with
  `{"success":true,"type":"done","time":258595}`; full
  `flutter analyze` FAIL with the existing `1717 issues found` backlog;
  targeted `flutter analyze` on the three touched Dart files PASS.
- Blocking issues remaining: none.
- Non-blocking follow-ups deferred: isolate the Android unit-test Gradle
  task graph before default-gate promotion; create a separate
  instrumentation/UIAutomator plan only if full real Android
  notification-tap runtime proof is desired; keep unrelated dirty files
  out of this session's final package.
- Why the session is safe to consider complete: the Android
  Activity stored-intent regression is covered by a behavior-level
  Robolectric test plus the existing source pin, the required broad
  Flutter test has green full-run evidence, analyzer red state is
  demonstrated as pre-existing and not introduced by touched Dart files,
  and QA found no blocking issues.
