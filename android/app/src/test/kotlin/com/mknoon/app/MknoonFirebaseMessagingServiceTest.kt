package com.mknoon.app

import android.Manifest
import android.app.Notification
import android.app.NotificationManager
import android.content.Context
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.os.Bundle
import android.os.LocaleList
import com.google.firebase.messaging.RemoteMessage
import com.google.firebase.messaging.remoteMessageFromBundleForTest
import java.util.Locale
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
        DroppedPushRecoveryStore(context).setCurrentBinding("installation-a/account-a")
        val manager = context.getSystemService(NotificationManager::class.java)
        manager.cancelAll()
    }

    @Test
    @Config(sdk = [33])
    fun testTC37501ExactFixedWakeInterceptsAndAllOtherShapesDelegateOnce() {
        shadowOf(context as android.app.Application)
            .grantPermissions(Manifest.permission.POST_NOTIFICATIONS)
        val store = DroppedPushRecoveryStore(context)
        store.setCurrentBinding("installation-a/account-a", recoveryWorkEnabled = true)
        val delegated = mutableListOf<RemoteMessage>()
        val fixedSchedules = mutableListOf<DroppedPushRecoveryStore.PendingRecovery>()
        val deletedSchedules = mutableListOf<DroppedPushRecoveryStore.PendingRecovery>()
        val service = classifierService(delegated, fixedSchedules, deletedSchedules)
        val manager = context.getSystemService(NotificationManager::class.java)

        // Exact data-only fixed wake: intercepted once, never delegated.
        service.onMessageReceived(dataMessage(mapOf("v" to "1", "w" to "1")))
        assertEquals(
            "exact fixed wake must never enter FlutterFire rich staging",
            0,
            delegated.size,
        )
        assertEquals(1L, store.pendingGeneration())
        assertEquals(
            listOf(store.pendingRecovery()),
            fixedSchedules.toList(),
        )
        assertTrue(deletedSchedules.isEmpty())
        val fixedCard = manager.activeNotifications.single()
        assertEquals(MknoonFirebaseMessagingService.RECOVERY_NOTIFICATION_TAG, fixedCard.tag)
        assertEquals(MknoonFirebaseMessagingService.RECOVERY_NOTIFICATION_ID, fixedCard.id)
        // The one generic card is visibly present but explicitly silent.
        assertNull(fixedCard.notification.sound)
        assertEquals(0, fixedCard.notification.defaults)
        assertEquals("silent", fixedCard.notification.group)
        assertEquals(
            Notification.GROUP_ALERT_SUMMARY,
            fixedCard.notification.groupAlertBehavior,
        )
        assertTrue(
            fixedCard.notification.flags and Notification.FLAG_ONLY_ALERT_ONCE != 0,
        )

        // Every other shape delegates to FlutterFire exactly once and does not
        // touch marker, card, or scheduling.
        val nonFixedShapes = listOf(
            dataMessage(mapOf("v" to "1")),
            dataMessage(mapOf("w" to "1")),
            dataMessage(mapOf("v" to "1", "w" to "2")),
            dataMessage(mapOf("v" to "2", "w" to "1")),
            dataMessage(mapOf("v" to " 1", "w" to "1")),
            dataMessage(mapOf("v" to "1", "w" to "1 ")),
            dataMessage(mapOf("v" to "true", "w" to "1")),
            dataMessage(mapOf("v" to "1", "w" to "1", "x" to "1")),
            dataMessage(emptyMap()),
            notificationBearingMessage(mapOf("v" to "1", "w" to "1")),
        )
        for ((index, message) in nonFixedShapes.withIndex()) {
            service.onMessageReceived(message)
            assertEquals(
                "nonfixed shape $index must delegate exactly once",
                index + 1,
                delegated.size,
            )
            assertTrue(message === delegated.last())
        }
        assertEquals(1L, store.pendingGeneration())
        assertEquals(1, fixedSchedules.size)
        assertTrue(deletedSchedules.isEmpty())

        // A missing current binding consumes an exact fixed wake fail-closed:
        // zero marker, zero card, zero schedule, and still zero delegation.
        store.setCurrentBinding(null)
        manager.cancelAll()
        service.onMessageReceived(dataMessage(mapOf("v" to "1", "w" to "1")))
        assertEquals(nonFixedShapes.size, delegated.size)
        assertNull(store.pendingGeneration())
        assertEquals(1, fixedSchedules.size)
        assertTrue(deletedSchedules.isEmpty())
        assertTrue(manager.activeNotifications.isEmpty())
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

    @Test
    @Config(sdk = [33])
    fun `denied notification permission still schedules after committed bound marker`() {
        shadowOf(context as android.app.Application).denyPermissions(Manifest.permission.POST_NOTIFICATIONS)
        DroppedPushRecoveryStore(context).setCurrentBinding(
            "installation-a/account-a",
            recoveryWorkEnabled = true,
        )
        val observed = mutableListOf<DroppedPushRecoveryStore.PendingRecovery>()
        val service = recordingService(observed)

        service.onDeletedMessages()

        assertEquals(listOf(DroppedPushRecoveryStore.PendingRecovery(1L, "installation-a/account-a")), observed)
        assertEquals(observed.single(), DroppedPushRecoveryStore(context).pendingRecovery())
    }

    @Test
    @Config(sdk = [33])
    fun `disabled recovery readiness records marker without scheduling work`() {
        shadowOf(context as android.app.Application).denyPermissions(Manifest.permission.POST_NOTIFICATIONS)
        val observed = mutableListOf<DroppedPushRecoveryStore.PendingRecovery>()
        val service = recordingService(observed)

        service.onDeletedMessages()

        assertEquals(1L, DroppedPushRecoveryStore(context).pendingGeneration())
        assertTrue(observed.isEmpty())
    }

    @Test
    @Config(sdk = [26])
    fun `recovery copy follows locale and refreshes existing channel`() {
        val service = service()
        service.onDeletedMessages()
        val manager = context.getSystemService(NotificationManager::class.java)
        val original = requireNotNull(manager.getNotificationChannel(MknoonFirebaseMessagingService.RECOVERY_CHANNEL_ID))
        assertEquals("Message recovery", original.name.toString())
        val originalImportance = original.importance

        val german = Configuration(context.resources.configuration).apply {
            setLocales(LocaleList(Locale.GERMAN))
        }
        @Suppress("DEPRECATION")
        context.resources.updateConfiguration(german, context.resources.displayMetrics)
        service.onDeletedMessages()

        val refreshed = requireNotNull(manager.getNotificationChannel(MknoonFirebaseMessagingService.RECOVERY_CHANNEL_ID))
        assertEquals("Nachrichtenwiederherstellung", refreshed.name.toString())
        assertEquals(
            "Benachrichtigt, wenn möglicherweise Nachrichten wiederhergestellt werden müssen",
            refreshed.description,
        )
        assertEquals(originalImportance, refreshed.importance)
        assertEquals(MknoonFirebaseMessagingService.RECOVERY_CHANNEL_ID, refreshed.id)
    }

    @Test
    @Config(sdk = [26], qualifiers = "ar")
    fun `recovery card uses Arabic resources`() {
        service().onDeletedMessages()

        val notification = context.getSystemService(NotificationManager::class.java)
            .activeNotifications.single().notification
        assertEquals("مكنون", shadowOf(notification).contentTitle)
        assertEquals("قد تكون هناك رسائل بانتظار الاسترداد", shadowOf(notification).contentText)
    }

    @Test
    @Config(sdk = [26], qualifiers = "fr")
    fun `unsupported locale falls back to complete default recovery resources`() {
        service().onDeletedMessages()

        val manager = context.getSystemService(NotificationManager::class.java)
        val notification = manager.activeNotifications.single().notification
        assertEquals("MKnoon", shadowOf(notification).contentTitle)
        assertEquals("Messages may be waiting", shadowOf(notification).contentText)
        val channel = requireNotNull(
            manager.getNotificationChannel(MknoonFirebaseMessagingService.RECOVERY_CHANNEL_ID),
        )
        assertEquals("Message recovery", channel.name.toString())
        assertEquals(
            "Alerts when messages may be waiting to be recovered",
            channel.description,
        )
    }

    private fun service(): MknoonFirebaseMessagingService = recordingService(mutableListOf())

    private fun recordingService(
        observed: MutableList<DroppedPushRecoveryStore.PendingRecovery>,
    ): MknoonFirebaseMessagingService =
        Robolectric.buildService(RecordingFirebaseMessagingService::class.java)
            .create()
            .get()
            .also { it.observed = observed }

    private fun classifierService(
        delegated: MutableList<RemoteMessage>,
        fixedSchedules: MutableList<DroppedPushRecoveryStore.PendingRecovery>,
        deletedSchedules: MutableList<DroppedPushRecoveryStore.PendingRecovery>,
    ): MknoonFirebaseMessagingService =
        Robolectric.buildService(RecordingFirebaseMessagingService::class.java)
            .create()
            .get()
            .also {
                it.observed = deletedSchedules
                it.delegated = delegated
                it.observedFixed = fixedSchedules
            }

    private fun dataMessage(data: Map<String, String>): RemoteMessage {
        val bundle = Bundle()
        for ((key, value) in data) bundle.putString(key, value)
        return remoteMessageFromBundleForTest(bundle)
    }

    private fun notificationBearingMessage(data: Map<String, String>): RemoteMessage {
        val bundle = Bundle()
        for ((key, value) in data) bundle.putString(key, value)
        bundle.putString("gcm.n.e", "1")
        bundle.putString("gcm.n.title", "rich")
        val message = remoteMessageFromBundleForTest(bundle)
        checkNotNull(message.notification) {
            "fixture must present a notification-bearing message"
        }
        return message
    }
}

private class RecordingFirebaseMessagingService : MknoonFirebaseMessagingService() {
    lateinit var observed: MutableList<DroppedPushRecoveryStore.PendingRecovery>
    var delegated: MutableList<RemoteMessage> = mutableListOf()
    var observedFixed: MutableList<DroppedPushRecoveryStore.PendingRecovery> =
        mutableListOf()

    override fun scheduleRecovery(snapshot: DroppedPushRecoveryStore.PendingRecovery) {
        check(snapshot == DroppedPushRecoveryStore(this).pendingRecovery())
        observed += snapshot
    }

    override fun scheduleFixedWakeRecovery(
        snapshot: DroppedPushRecoveryStore.PendingRecovery,
    ) {
        check(snapshot == DroppedPushRecoveryStore(this).pendingRecovery())
        observedFixed += snapshot
    }

    override fun delegateRichMessageToFlutterFire(message: RemoteMessage) {
        // Hermetic recorder: production's seam is the only super call site and
        // remains covered by the source contract plus the device rich canary.
        delegated += message
    }
}
