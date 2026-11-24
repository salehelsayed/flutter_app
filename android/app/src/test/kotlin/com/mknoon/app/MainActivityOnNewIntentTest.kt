package com.mknoon.app

import android.content.Intent
import android.net.Uri
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
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
    fun onNewIntent_keepsInviteOnlyInTheInviteBridge() {
        val cases = listOf(
            "https://invite.mknoon.xyz/i/v1#c2lnbmVk" to mapOf(
                "kind" to "link",
                "url" to "https://invite.mknoon.xyz/i/v1#c2lnbmVk",
            ),
            "mknoon://invite" to mapOf("kind" to "paste"),
            "https://invite.mknoon.xyz/i/v1#invalid+" to null,
            "mknoon://invite#c2lnbmVk" to null,
        )
        val onNewIntent = MainActivity::class.java
            .getDeclaredMethod("onNewIntent", Intent::class.java)
            .apply { isAccessible = true }
        val bridgeField = MainActivity::class.java
            .getDeclaredField("contactInviteBridge")
            .apply { isAccessible = true }
        val pendingField = ContactInviteBridge::class.java
            .getDeclaredField("pending")
            .apply { isAccessible = true }

        for ((raw, expected) in cases) {
            val activity = Robolectric.buildActivity(MainActivity::class.java).get()
            val invite = Intent(Intent.ACTION_VIEW, Uri.parse(raw))
            onNewIntent.invoke(activity, invite)

            assertEquals(Intent.ACTION_MAIN, activity.intent.action)
            assertNull(activity.intent.dataString)
            assertEquals(expected, pendingField.get(bridgeField.get(activity)))
        }
    }

    @Test
    fun onNewIntent_leavesOrdinaryTextShareUnchanged() {
        val activity = Robolectric.buildActivity(MainActivity::class.java).get()
        val text = "https://invite.mknoon.xyz/i/v1#c2lnbmVk"
        val share = Intent(Intent.ACTION_SEND)
            .setType("text/plain")
            .putExtra(Intent.EXTRA_TEXT, text)
        MainActivity::class.java
            .getDeclaredMethod("onNewIntent", Intent::class.java)
            .apply { isAccessible = true }
            .invoke(activity, share)

        assertEquals(Intent.ACTION_SEND, activity.intent.action)
        assertEquals("text/plain", activity.intent.type)
        assertEquals(text, activity.intent.getStringExtra(Intent.EXTRA_TEXT))
    }

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

    @Test
    fun onNewIntent_recoveryTapAcceleratesFlutterWithoutConsumingMarker() {
        val activity = Robolectric
            .buildActivity(MainActivity::class.java)
            .get()
        activity.getSharedPreferences(
            DroppedPushRecoveryStore.PREFERENCES_NAME,
            android.content.Context.MODE_PRIVATE,
        ).edit().clear().commit()
        val store = DroppedPushRecoveryStore(activity)
        // Recovery markers are installation/account-bound. Establish the
        // production precondition so this test reaches onNewIntent instead of
        // failing closed while arranging an impossible unbound marker.
        assertEquals(
            "on-new-intent-test/account-a",
            store.setCurrentBinding("on-new-intent-test/account-a").currentBinding,
        )
        assertEquals(1L, store.recordDeletion())
        val signalled = mutableListOf<Long>()
        val bridge = DroppedPushRecoveryBridge(
            activity,
            messenger = null,
            recoverySignal = { generation -> signalled.add(generation) },
        )
        MainActivity::class.java
            .getDeclaredField("droppedPushRecoveryBridge")
            .apply { isAccessible = true }
            .set(activity, bridge)
        val recoveryIntent = Intent(
            MknoonFirebaseMessagingService.RECOVERY_INTENT_ACTION,
        ).putExtra(
            MknoonFirebaseMessagingService.RECOVERY_GENERATION_EXTRA,
            1L,
        )

        MainActivity::class.java
            .getDeclaredMethod("onNewIntent", Intent::class.java)
            .apply { isAccessible = true }
            .invoke(activity, recoveryIntent)

        assertEquals(listOf(1L), signalled)
        assertEquals(1L, store.pendingGeneration())
        assertEquals(recoveryIntent, activity.intent)
    }
}
