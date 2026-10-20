package com.mknoon.app.call

import android.app.Notification
import android.app.NotificationManager
import android.content.Context
import android.service.notification.StatusBarNotification
import java.util.UUID
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config
import org.robolectric.annotation.Implementation
import org.robolectric.annotation.Implements
import org.robolectric.annotation.LooperMode
import org.robolectric.shadows.ShadowNotificationManager

/** The notify request exists before Android's worker exposes its app record. */
@Implements(NotificationManager::class)
class MknoonCallDeferredAppRecordShadow : ShadowNotificationManager() {
    companion object { var hideRequested505 = false }

    @Implementation
    override fun getActiveNotifications(): Array<StatusBarNotification> =
        super.getActiveNotifications().filterNot { hideRequested505 && it.id == 505 }.toTypedArray()
}

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [33], shadows = [MknoonCallDeferredAppRecordShadow::class])
@LooperMode(LooperMode.Mode.PAUSED)
class MknoonCallHandoverCleanupTest {
    @Test
    fun `terminal cleanup before deferred promotion removes both call cards`() = checkCleanup(accept = false)

    @Test
    fun `terminal cleanup after promotion removes both call cards`() = checkCleanup(accept = true)

    @Test
    fun `terminal before OS record registration cannot leave a late ongoing card`() =
        checkCleanup(accept = false, hidden = true)

    @Test
    fun `terminal cleanup preserves a successor owned ongoing card`() = checkCleanup(
        accept = false,
        successor = UUID.fromString("00000000-0000-4000-8000-000000000012"),
    )

    private fun checkCleanup(accept: Boolean, successor: UUID? = null, hidden: Boolean = false) {
        MknoonCallDeferredAppRecordShadow.hideRequested505 = hidden
        val context = RuntimeEnvironment.getApplication()
        val manager = context.getSystemService(NotificationManager::class.java)
        val serviceController = Robolectric.buildService(MknoonCallForegroundService::class.java).create()
        val service = serviceController.get()
        // Robolectric replaces Application services per case; the process singleton survives.
        val runtime = MknoonCallRuntime::class.java.getDeclaredConstructor(Context::class.java)
            .also { it.isAccessible = true }.newInstance(context)
        val field = runtime.javaClass.getDeclaredField("androidPlatform").also { it.isAccessible = true }
        val platform = field.get(runtime) as MknoonCallPlatform
        val publish = platform.javaClass.getDeclaredMethod(
            "postOngoingNotification", UUID::class.java, Notification::class.java,
        ).also { it.isAccessible = true }
        val foreground = runtime.foregroundRuntime(service)
        val id = UUID.fromString("00000000-0000-4000-8000-000000000011")
        val notifications = MknoonCallNotificationFactory(context)
        val ongoing = notifications.createOngoing(id, UUID.randomUUID())
        val pendingChecks = mutableListOf<() -> Unit>()
        var owner = true
        try {
            assertTrue(handOverToOngoingCallNotification(
                foregroundNotificationId = 504,
                startForeground = { notificationId -> service.startForeground(notificationId, ongoing) },
                cancel = manager::cancel,
                postOngoing = { publish.invoke(platform, id, ongoing) },
                isOngoingAccepted = { accept },
                withCurrent = { effect -> if (!owner) false else { effect(); true } },
                scheduleCheck = { _, effect -> pendingChecks += effect },
                nowMs = { 0L },
            ))
            assertEquals(
                if (hidden) setOf(504) else if (accept) setOf(505) else setOf(504, 505),
                manager.activeNotifications.map { it.id }.toSet(),
            )
            if (successor != null) {
                publish.invoke(platform, successor, notifications.createOngoing(successor, UUID.randomUUID()))
            }
            // The controller owns the lifecycle lock across these terminal effects.
            owner = false
            platform.cancelNotification(id)
            foreground.stop(id)
            pendingChecks.toList().forEach { it() }
            // Reveal the same requested record after cleanup, as Android's worker would.
            MknoonCallDeferredAppRecordShadow.hideRequested505 = false
            assertEquals(
                "only the terminating call's notifications may be removed",
                if (successor == null) emptySet<Int>() else setOf(505),
                manager.activeNotifications.map { it.id }.toSet(),
            )
            if (successor != null) {
                assertEquals(
                    successor.toString(),
                    manager.activeNotifications.single().notification.extras
                        .getString(MknoonCallActionReceiver.EXTRA_NATIVE_CALL_ID),
                )
            }
        } finally {
            MknoonCallDeferredAppRecordShadow.hideRequested505 = false
            manager.cancelAll()
            serviceController.destroy()
        }
    }
}
