package com.mknoon.app

import android.Manifest
import android.app.NotificationManager
import android.content.Context
import android.content.pm.PackageManager
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
class MknoonFirebaseMessagingServiceTest {
    private lateinit var context: Context

    @Before
    fun setUp() {
        context = RuntimeEnvironment.getApplication()
        context.getSharedPreferences(
            DroppedPushRecoveryStore.PREFERENCES_NAME,
            Context.MODE_PRIVATE,
        ).edit().clear().commit()
        val manager = context.getSystemService(NotificationManager::class.java)
        manager.cancelAll()
    }

    @Test
    @Config(sdk = [24])
    fun `real deletion override persists before posting without creating a channel on API 24`() {
        service().onDeletedMessages()

        assertEquals(1L, DroppedPushRecoveryStore(context).pendingGeneration())
        val manager = context.getSystemService(NotificationManager::class.java)
        assertTrue(shadowOf(manager).notificationChannels.isEmpty())
        val posted = manager.activeNotifications.single()
        assertEquals(MknoonFirebaseMessagingService.RECOVERY_NOTIFICATION_TAG, posted.tag)
        assertEquals(MknoonFirebaseMessagingService.RECOVERY_NOTIFICATION_ID, posted.id)
        assertFalse(posted.notification.flags and android.app.Notification.FLAG_AUTO_CANCEL != 0)
        assertTrue(posted.notification.flags and android.app.Notification.FLAG_ONLY_ALERT_ONCE != 0)
    }

    @Test
    @Config(sdk = [26])
    fun `real deletion override creates reserved channel and coalesces reserved card on API 26`() {
        service().onDeletedMessages()
        service().onDeletedMessages()

        assertEquals(2L, DroppedPushRecoveryStore(context).pendingGeneration())
        val manager = context.getSystemService(NotificationManager::class.java)
        assertNotNull(manager.getNotificationChannel(MknoonFirebaseMessagingService.RECOVERY_CHANNEL_ID))
        assertEquals(1, manager.activeNotifications.size)
        assertEquals(MknoonFirebaseMessagingService.RECOVERY_NOTIFICATION_TAG, manager.activeNotifications.single().tag)
        assertTrue(
            manager.activeNotifications.single().notification.flags and
                android.app.Notification.FLAG_ONLY_ALERT_ONCE != 0,
        )
    }

    @Test
    @Config(sdk = [33])
    fun `API 33 denied notification permission still persists generation and creates channel`() {
        shadowOf(context as android.app.Application).denyPermissions(Manifest.permission.POST_NOTIFICATIONS)
        assertEquals(
            PackageManager.PERMISSION_DENIED,
            context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS),
        )

        service().onDeletedMessages()

        assertEquals(1L, DroppedPushRecoveryStore(context).pendingGeneration())
        val manager = context.getSystemService(NotificationManager::class.java)
        assertNotNull(manager.getNotificationChannel(MknoonFirebaseMessagingService.RECOVERY_CHANNEL_ID))
        assertTrue(manager.activeNotifications.isEmpty())
    }

    @Test
    @Config(sdk = [33])
    fun `matching acknowledgement alone clears marker and exact reserved card`() {
        shadowOf(context as android.app.Application).grantPermissions(Manifest.permission.POST_NOTIFICATIONS)
        service().onDeletedMessages()
        val bridge = DroppedPushRecoveryBridge(context, messenger = null)

        assertFalse(bridge.acknowledgeGeneration(999L))
        assertEquals(1, context.getSystemService(NotificationManager::class.java).activeNotifications.size)
        assertTrue(bridge.acknowledgeGeneration(1L))
        assertNull(DroppedPushRecoveryStore(context).pendingGeneration())
        assertTrue(context.getSystemService(NotificationManager::class.java).activeNotifications.isEmpty())
    }

    private fun service(): MknoonFirebaseMessagingService =
        Robolectric.buildService(MknoonFirebaseMessagingService::class.java)
            .create()
            .get()
}
