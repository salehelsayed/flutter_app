package com.mknoon.app.call

import android.app.Application
import android.app.Notification
import android.app.NotificationManager
import android.app.PendingIntent
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
    fun `incoming CallStyle is ongoing actionable and degraded without full-screen intent`() {
        val callId = UUID.fromString(CALL_ID)

        val notification = factory.createIncoming(
            nativeCallId = callId,
            fullScreenAllowed = false,
        )

        assertEquals(Notification.CATEGORY_CALL, notification.category)
        assertTrue(notification.flags and Notification.FLAG_ONGOING_EVENT != 0)
        assertTrue(notification.flags and Notification.FLAG_AUTO_CANCEL == 0)
        assertNull(notification.fullScreenIntent)
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

        assertNull(notification.fullScreenIntent)
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
    fun `incoming full-screen intent is added only when explicitly allowed`() {
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
        assertTrue(pendingIntents.fullScreenRequests.isEmpty())
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
