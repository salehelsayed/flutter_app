package com.mknoon.app.call

import android.app.Application
import android.app.Notification
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Person
import android.content.Context
import android.content.Intent
import com.mknoon.app.MainActivity
import java.util.UUID
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import org.robolectric.annotation.Implementation
import org.robolectric.annotation.Implements
import org.robolectric.shadows.ShadowNotificationManager

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [33])
class MknoonCallNotificationFactoryTest {
    private lateinit var context: Context
    private lateinit var pendingIntents: RecordingCallPendingIntentFactory
    private lateinit var factory: MknoonCallNotificationFactory

    @Before
    fun setUp() {
        context = RuntimeEnvironment.getApplication()
        pendingIntents = RecordingCallPendingIntentFactory(context)
        factory = MknoonCallNotificationFactory(
            context = context,
            pendingIntents = pendingIntents,
        )
    }

    @Test
    @Config(sdk = [28, 33, 34])
    fun `authenticated caller name appears in incoming and ongoing notifications`() {
        val callId = UUID.fromString(CALL_ID)
        val namedFactory = MknoonCallNotificationFactory(
            context = context,
            pendingIntents = pendingIntents,
            presentation = { id ->
                if (id == callId) MknoonIncomingCallDisplay("Beta iPhone", null, false).toRingingMetadata()
                else null
            },
        )

        for (notification in listOf(
            namedFactory.createIncoming(callId, fullScreenAllowed = false),
            namedFactory.createOngoing(callId),
        )) {
            assertEquals("Beta iPhone", notification.extras.getCharSequence(Notification.EXTRA_TITLE))
            if (android.os.Build.VERSION.SDK_INT >= 31) {
                @Suppress("DEPRECATION")
                val person = notification.extras.getParcelable<Person>(Notification.EXTRA_CALL_PERSON)
                assertEquals("Beta iPhone", person?.name?.toString())
            }
        }

        val unknown = namedFactory.createIncoming(
            UUID.fromString("ffffffff-ffff-4fff-8fff-ffffffffffff"),
            fullScreenAllowed = false,
        )
        assertEquals("MKnoon caller", unknown.extras.getCharSequence(Notification.EXTRA_TITLE))
    }

    @Test
    fun `incoming CallStyle retains the intent for the OS denied-access heads-up fallback`() {
        val callId = UUID.fromString(CALL_ID)

        val notification = factory.createIncoming(
            nativeCallId = callId,
            fullScreenAllowed = false,
        )

        assertEquals(Notification.CATEGORY_CALL, notification.category)
        assertTrue(notification.flags and Notification.FLAG_ONGOING_EVENT != 0)
        assertTrue(notification.flags and Notification.FLAG_AUTO_CANCEL == 0)
        assertNotNull(notification.fullScreenIntent)
        assertEquals(
            listOf(
                CallNotificationPendingIntentRequest(
                    callId,
                    MknoonCallActionReceiver.ACTION_DECLINE,
                ),
                CallNotificationPendingIntentRequest(
                    callId,
                    MknoonCallActionReceiver.ACTION_ANSWER,
                ),
            ),
            pendingIntents.actionRequests,
        )
        assertNotNull(notification.contentIntent)
        assertEquals(listOf(callId), pendingIntents.fullScreenRequests)
    }

    @Test
    @Config(sdk = [28, 34])
    fun `denied full-screen notification body opens the app without answering or changing call authority`() {
        val callId = UUID.fromString(CALL_ID)
        val notification = MknoonCallNotificationFactory(context).createIncoming(
            nativeCallId = callId,
            fullScreenAllowed = false,
        )

        assertNotNull(notification.fullScreenIntent)
        assertNotNull(notification.contentIntent)
        // A notification body tap is an open action, never an implicit Answer.
        // Its immutable PendingIntent also rejects replacement call identity.
        notification.contentIntent.send(
            context,
            0,
            Intent(MknoonCallActionReceiver.ACTION_ANSWER)
                .putExtra(
                    MknoonCallActionReceiver.EXTRA_NATIVE_CALL_ID,
                    "ffffffff-ffff-4fff-8fff-ffffffffffff",
                ),
        )

        val opened = requireNotNull(shadowOf(context as Application).nextStartedActivity)
        assertEquals(MainActivity::class.java.name, opened.component?.className)
        assertEquals("com.mknoon.app.call.action.OPEN_INCOMING", opened.action)
        assertEquals("mknoon-call://local/$callId", opened.dataString)
        assertEquals(
            callId.toString(),
            opened.getStringExtra(MknoonCallActionReceiver.EXTRA_NATIVE_CALL_ID),
        )
        assertEquals(
            setOf(MknoonCallActionReceiver.EXTRA_NATIVE_CALL_ID),
            opened.extras?.keySet(),
        )
        assertTrue(opened.flags and Intent.FLAG_ACTIVITY_CLEAR_TOP != 0)
        assertTrue(opened.flags and Intent.FLAG_ACTIVITY_SINGLE_TOP != 0)
    }

    @Test
    fun `incoming full-screen intent is retained for OS permission enforcement`() {
        val callId = UUID.fromString(CALL_ID)

        val notification = factory.createIncoming(
            nativeCallId = callId,
            fullScreenAllowed = true,
        )

        assertNotNull(notification.fullScreenIntent)
        assertEquals(notification.fullScreenIntent, notification.contentIntent)
        assertEquals(listOf(callId), pendingIntents.fullScreenRequests)
    }

    @Test
    @Config(sdk = [28, 33])
    fun `ringing notification replacements retain full-screen intent without alerting again`() {
        val callId = UUID.fromString(CALL_ID)
        val productionFactory = MknoonCallNotificationFactory(context)
        repeat(3) {
            val notification = productionFactory.createIncoming(callId)
            assertNotNull(notification.fullScreenIntent)
            assertEquals(notification.contentIntent, notification.fullScreenIntent)
            assertTrue(notification.flags and Notification.FLAG_ONLY_ALERT_ONCE != 0)
        }
    }

    @Test
    @Config(sdk = [34], shadows = [IncomingNotificationPermissionShadow::class])
    fun `every ringing replacement retains the OS actionable fallback across permission changes`() {
        val callId = UUID.fromString(CALL_ID)
        val productionFactory = MknoonCallNotificationFactory(context)
        listOf(true, true, false, false, true).forEach { allowed ->
            IncomingNotificationPermissionShadow.allowed = allowed
            val notification = productionFactory.createIncoming(callId)
            assertNotNull(notification.fullScreenIntent)
            assertNotNull(notification.contentIntent)
            assertEquals(2, notification.actions.count { it.actionIntent != null })
            assertTrue(notification.flags and Notification.FLAG_ONLY_ALERT_ONCE != 0)
        }
    }

    @Test
    @Config(sdk = [34], shadows = [IncomingNotificationPermissionShadow::class])
    fun `a ringing call without full-screen access is recorded for the in-app prompt`() {
        // O4 (beta 2026-10-08): the app asks for the access only after a call
        // was affected; allowed calls leave no record.
        context.getSharedPreferences("mknoon_full_screen_call_access", Context.MODE_PRIVATE).edit().clear().commit()
        val callId = UUID.fromString(CALL_ID)
        val productionFactory = MknoonCallNotificationFactory(context)
        IncomingNotificationPermissionShadow.allowed = true
        productionFactory.createIncoming(callId)
        var state = FullScreenCallAccess.read(context)
        assertEquals(true, state["supported"])
        assertEquals(true, state["allowed"])
        assertNull(state["deniedCallAtMs"])

        IncomingNotificationPermissionShadow.allowed = false
        productionFactory.createIncoming(callId)
        state = FullScreenCallAccess.read(context)
        assertEquals(false, state["allowed"])
        assertNotNull(state["deniedCallAtMs"])
        assertNull(state["dismissedAtMs"])
        assertTrue(FullScreenCallAccess.dismiss(context, nowMs = 42L))
        assertEquals(42L, FullScreenCallAccess.read(context)["dismissedAtMs"])
    }

    @Test
    fun `ringtone player is the only incoming call sound owner`() {
        factory.createIncoming(
            nativeCallId = UUID.fromString(CALL_ID),
            fullScreenAllowed = false,
        )

        val channel = requireNotNull(
            context.getSystemService(NotificationManager::class.java)
                .getNotificationChannel(MknoonCallNotificationFactory.CHANNEL_ID),
        )
        assertFalse(channel.id == "mknoon_calls")
        assertNull(channel.sound)
        assertFalse(channel.shouldVibrate())
    }

    @Test
    @Config(sdk = [24, 28, 34])
    fun `ongoing notification user tap reopens exact call without automatic launch or answer`() {
        val callId = UUID.fromString(CALL_ID)
        val notification = MknoonCallNotificationFactory(context).createOngoing(callId)
        assertNull(notification.fullScreenIntent)
        assertNotNull(notification.contentIntent)
        notification.contentIntent.send(context, 0,
            Intent(MknoonCallActionReceiver.ACTION_ANSWER)
                .putExtra(MknoonCallActionReceiver.EXTRA_NATIVE_CALL_ID, "ffffffff-ffff-4fff-8fff-ffffffffffff"))
        val opened = requireNotNull(shadowOf(context as Application).nextStartedActivity)
        assertEquals(AndroidMknoonCallPendingIntentFactory.ACTION_OPEN_INCOMING_CALL, opened.action)
        assertEquals(callId.toString(), opened.getStringExtra(MknoonCallActionReceiver.EXTRA_NATIVE_CALL_ID))
        assertEquals("mknoon-call://local/$callId", opened.dataString)
        assertEquals(setOf(MknoonCallActionReceiver.EXTRA_NATIVE_CALL_ID), opened.extras?.keySet())
    }

    @Test
    fun `ongoing CallStyle exposes one end action and remains non-dismissible`() {
        val callId = UUID.fromString(CALL_ID)

        val notification = factory.createOngoing(callId)

        assertEquals(Notification.CATEGORY_CALL, notification.category)
        assertTrue(notification.flags and Notification.FLAG_ONGOING_EVENT != 0)
        assertTrue(notification.flags and Notification.FLAG_AUTO_CANCEL == 0)
        assertEquals(
            listOf(
                CallNotificationPendingIntentRequest(
                    callId,
                    MknoonCallActionReceiver.ACTION_END,
                ),
            ),
            pendingIntents.actionRequests,
        )
        assertEquals(listOf(callId), pendingIntents.fullScreenRequests)
        assertNotNull(notification.contentIntent)
        assertNull(notification.fullScreenIntent)
    }
}

@Implements(NotificationManager::class)
class IncomingNotificationPermissionShadow : ShadowNotificationManager() {
    @Implementation(minSdk = 34)
    protected fun canUseFullScreenIntent(): Boolean = allowed

    companion object {
        var allowed = false
    }
}

private class RecordingCallPendingIntentFactory(
    private val context: Context,
) : MknoonCallPendingIntentFactory {
    val actionRequests = mutableListOf<CallNotificationPendingIntentRequest>()
    val fullScreenRequests = mutableListOf<UUID>()
    private var requestCode = 1

    override fun action(nativeCallId: UUID, action: String): PendingIntent {
        actionRequests += CallNotificationPendingIntentRequest(nativeCallId, action)
        return PendingIntent.getBroadcast(
            context,
            requestCode++,
            Intent(context, MknoonCallActionReceiver::class.java)
                .setAction(action)
                .putExtra(MknoonCallActionReceiver.EXTRA_NATIVE_CALL_ID, nativeCallId.toString()),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
    }

    override fun fullScreen(nativeCallId: UUID): PendingIntent {
        fullScreenRequests += nativeCallId
        return PendingIntent.getBroadcast(
            context,
            requestCode++,
            Intent(context, MknoonCallActionReceiver::class.java)
                .setAction(MknoonCallActionReceiver.ACTION_ANSWER)
                .putExtra(MknoonCallActionReceiver.EXTRA_NATIVE_CALL_ID, nativeCallId.toString()),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
    }
}

private data class CallNotificationPendingIntentRequest(
    val nativeCallId: UUID,
    val action: String,
)
