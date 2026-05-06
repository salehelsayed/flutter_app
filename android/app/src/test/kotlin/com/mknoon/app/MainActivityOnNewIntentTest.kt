package com.mknoon.app

import android.content.Intent
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

// Behaviour-level companion to the Dart source pin at
// test/core/notifications/main_activity_onnewintent_pin_test.dart.
// The initial buildActivity(...).create().get() surface reached FlutterActivity
// engine setup and GoBridge native loading under Robolectric. This no-lifecycle
// buildActivity(...).get() fallback still invokes MainActivity's real
// onNewIntent override and avoids adding a production-only public seam.
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [33])
class MainActivityOnNewIntentTest {

    @Test
    fun onNewIntent_storesIntent_soWarmNotificationPayloadRemainsObservable() {
        val activity = Robolectric
            .buildActivity(MainActivity::class.java)
            .get()

        val notificationIntent = Intent().apply {
            action = "SELECT_NOTIFICATION"
            putExtra(
                "flutter_local_notifications_payload",
                "12D3KooWTestPeerId",
            )
        }

        MainActivity::class.java
            .getDeclaredMethod("onNewIntent", Intent::class.java)
            .apply { isAccessible = true }
            .invoke(activity, notificationIntent)

        val current = activity.intent
        assertNotNull(
            "MainActivity.onNewIntent must call setIntent(intent) so the " +
                "warm-resume notification PendingIntent remains observable " +
                "through Activity.intent.",
            current,
        )
        assertEquals(
            "MainActivity.onNewIntent must call setIntent(intent) so the " +
                "warm-resume notification PendingIntent extras remain " +
                "observable through Activity.intent; removing setIntent " +
                "is the stored-intent regression this test guards.",
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
