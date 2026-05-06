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

This session adds an actual **behaviour-level** Android-side test that
would catch the same bug if a future commit removed or weakened the
override (e.g., kept the override but dropped `setIntent`, or upgraded to
a flutter embedding version where `setIntent` alone is no longer
sufficient and the plugin's instance hook is required).

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
  and "someone makes onNewIntent silently swallow the intent". Does NOT
  catch "the AndroidManifest launchMode changed in a way that bypasses
  onNewIntent" (no manifest is in play in a Robolectric unit test).

### Option B — Instrumentation (`android/app/src/androidTest/`)

Real device or emulator, runs under `./gradlew connectedAndroidTest`.

- Pros: full PendingIntent → MainActivity → flutter_local_notifications
  plugin → Dart pipeline is exercised. Catches AndroidManifest /
  launchMode regressions too. This is the **gold-standard** for the
  exact bug class Session N fixed.
- Cons: needs an emulator or device available at test time (CI cost);
  much slower; more infra to keep green; introducing it pulls in a
  AndroidJUnitRunner / espresso footprint the project has so far avoided.

### Decision rule for this session

**Default: Option A (Robolectric).** Reasons:

1. The runtime end-to-end catcher already exists in this repo — Standing
   Rule 2.1's hardware soak does the Option-B job by hand on every
   notification-touching change. Adding Option B as automation is
   high-cost low-marginal-value while the soak rule is in force.
2. The most likely future regression mode is *source-level* (someone
   refactors `MainActivity.kt` and breaks the contract); Robolectric
   catches that at PR time without a device.
3. Robolectric is the cheapest path from zero-Android-test-infra to
   one-real-Android-test, which is also a foundation if the project later
   wants more.

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
- Wire `./gradlew :app:testDebugUnitTest` (or whichever exact task name
  your AGP version exposes) into `scripts/run_test_gates.sh` so the
  Flutter-side test gate also runs the Android-side test.
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
  `scripts/run_test_gates.sh` from CI, the new line in that script picks
  it up for free; otherwise CI changes are a separate concern.
- Mocking the `flutter_local_notifications` plugin internals. The
  Robolectric test asserts the **Activity-side contract** (super called,
  intent stored), not the plugin-side dispatch. Plugin-side dispatch is
  what the hardware soak still catches.

---

## RED — failing test before any GREEN edit

Add `android/app/src/test/kotlin/com/mknoon/app/MainActivityOnNewIntentTest.kt`:

```kotlin
package com.mknoon.app

import android.content.Intent
import androidx.test.core.app.ActivityScenario
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [33])
class MainActivityOnNewIntentTest {

    @Test
    fun onNewIntent_storesIntentAndCallsSuper_so_pluginPipelineCanObservePayload() {
        val scenario = ActivityScenario.launch(MainActivity::class.java)
        scenario.onActivity { activity ->
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
            val current = activity.intent
            assertNotNull(
                "Activity.intent must be non-null after onNewIntent",
                current,
            )
            assertEquals(
                "MainActivity.onNewIntent must call setIntent(intent) so the " +
                    "Flutter embedding plugin pipeline can observe the " +
                    "notification PendingIntent extras (singleTask resume " +
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
}
```

To make this fail in a clean way against a hypothetical broken override
(`super.onNewIntent` only, no `setIntent`), revert `MainActivity.kt`
locally in a scratch branch first and confirm the test goes RED. **Do
not commit the revert.**

If the pre-flight reveals that `ActivityScenario.launch(MainActivity)`
fails because `FlutterActivity` requires a real engine attach, fall back
to instantiating MainActivity via `Robolectric.buildActivity(...)` with
the `create()` lifecycle stop short of `start()` — `onNewIntent` does
not depend on the FlutterEngine being attached, only on the Activity
existing. Document the choice in the test file's preamble.

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
    testImplementation("org.robolectric:robolectric:4.13") // pin a version compat with AGP 8.x + JVM 11
    testImplementation("androidx.test:core:1.6.1")
    testImplementation("androidx.test.ext:junit:1.2.1")
}
```

Pick exact versions by checking the Robolectric compat matrix
(<https://github.com/robolectric/robolectric/blob/master/README.md>) for
the project's AGP. The example numbers above are a starting point as of
2026-05; verify before committing.

In `scripts/run_test_gates.sh`, add (alongside the existing
`flutter test` invocation):

```bash
( cd android && ./gradlew :app:testDebugUnitTest --warning-mode=summary )
```

Confirm the exact task name with `./gradlew :app:tasks --all | grep -i test`
inside `android/`; AGP versions occasionally rename it.

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

## Verification

- `flutter test test/core/notifications/main_activity_onnewintent_pin_test.dart` — GREEN.
- `flutter test` overall — GREEN, same number of suites as before plus zero new failures.
- `cd android && ./gradlew :app:testDebugUnitTest` — GREEN; the new
  `MainActivityOnNewIntentTest` runs and passes.
- Locally revert `MainActivity.kt`'s `onNewIntent` to a no-op stub (don't
  commit) and confirm the Robolectric test goes RED with a clear
  failure message naming `setIntent`. Restore `MainActivity.kt`.
- `flutter analyze` — same issue count as before this session
  (no new analyzer warnings introduced, since the new file is Kotlin and
  outside the Dart analyzer's scope).
- `scripts/run_test_gates.sh` — runs both Flutter and Gradle tests in
  one invocation, exits 0.

---

## Critical files

- `android/app/src/main/kotlin/com/mknoon/app/MainActivity.kt` — the
  override under test; **not modified** by this session.
- `android/app/src/test/kotlin/com/mknoon/app/MainActivityOnNewIntentTest.kt` —
  new file (Robolectric test).
- `android/app/build.gradle.kts` — add `testOptions` + `testImplementation`
  deps.
- `scripts/run_test_gates.sh` — add a `./gradlew :app:testDebugUnitTest`
  invocation alongside the Flutter test gate.
- `test/core/notifications/main_activity_onnewintent_pin_test.dart` —
  preamble cross-reference only.
- `android/app/src/main/AndroidManifest.xml` — read-only reference for
  the test (`launchMode="singleTask"` line 20 is what makes
  `onNewIntent` the relevant entry point).

---

## Risk register

1. **Robolectric / AGP version mismatch.** Most common failure mode for
   first-time Robolectric introduction in an AGP 8.x project. Mitigation:
   pin both Robolectric and AndroidX-test deps explicitly; do not let
   Gradle resolve via dynamic version ranges. If the build fails on
   first run with a `RuntimeEnvironment` or shadow-loading error, that
   is the version-matrix issue, not a real test failure.
2. **`FlutterActivity` requires engine attach.** If `ActivityScenario`
   launches the activity all the way to `onResume` and that path tries
   to instantiate the FlutterEngine, the test may crash before the
   `onNewIntent` assertion runs. Mitigation documented inline in the
   RED step (use `Robolectric.buildActivity` and stop at `create()`).
3. **CI runtime increase.** `./gradlew testDebugUnitTest` cold-warm with
   Robolectric is on the order of 30–60 s the first time. Mitigation:
   accept this for now (one Android-side test); if it grows, revisit
   how the gate is sequenced.
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
