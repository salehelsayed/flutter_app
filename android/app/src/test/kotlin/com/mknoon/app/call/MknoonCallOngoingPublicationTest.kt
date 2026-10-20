package com.mknoon.app.call

import android.app.Notification
import android.app.NotificationManager
import android.content.Context
import android.util.Log
import java.lang.reflect.InvocationTargetException
import java.util.UUID
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.Shadows.shadowOf
import org.robolectric.android.controller.ServiceController
import org.robolectric.annotation.Config
import org.robolectric.annotation.Implementation
import org.robolectric.annotation.Implements
import org.robolectric.annotation.LooperMode
import org.robolectric.shadows.ShadowLog
import org.robolectric.shadows.ShadowNotificationManager

/** Models the Android 13 NMS CallStyle eligibility rule absent from Robolectric. */
@Implements(NotificationManager::class)
class CallStyleEligibilityShadow : ShadowNotificationManager() {
    var forcedPostFailure: Throwable? = null

    @Implementation
    override fun notify(id: Int, notification: Notification) {
        if (id == 505) forcedPostFailure?.let { throw it }
        val callStyle = notification.extras.getString(Notification.EXTRA_TEMPLATE) ==
            Notification.CallStyle::class.java.name
        require(!callStyle || notification.flags and Notification.FLAG_FOREGROUND_SERVICE != 0 ||
            notification.fullScreenIntent != null) { "CallStyle requires FGS ownership or a full-screen intent" }
        super.notify(id, notification)
    }
}

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [33], shadows = [CallStyleEligibilityShadow::class])
@LooperMode(LooperMode.Mode.PAUSED)
class MknoonCallOngoingPublicationTest {
    private lateinit var manager: NotificationManager
    private lateinit var serviceController: ServiceController<MknoonCallForegroundService>
    private lateinit var service: MknoonCallForegroundService
    private lateinit var runtime: MknoonCallRuntime
    private lateinit var platform: MknoonCallPlatform
    private lateinit var factory: MknoonCallNotificationFactory
    private val callId = UUID.fromString("00000000-0000-4000-8000-000000000031")

    @Before
    fun setUp() {
        ShadowLog.clear()
        val context = RuntimeEnvironment.getApplication()
        manager = context.getSystemService(NotificationManager::class.java)
        serviceController = Robolectric.buildService(MknoonCallForegroundService::class.java).create()
        service = serviceController.get()
        runtime = MknoonCallRuntime::class.java.getDeclaredConstructor(Context::class.java)
            .also { it.isAccessible = true }.newInstance(context)
        platform = runtime.javaClass.getDeclaredField("androidPlatform")
            .also { it.isAccessible = true }.get(runtime) as MknoonCallPlatform
        factory = MknoonCallNotificationFactory(context)
    }

    @After
    fun tearDown() {
        if (::manager.isInitialized) manager.cancelAll()
        if (::serviceController.isInitialized) serviceController.destroy()
    }

    @Test
    fun `marked prepublication is legal before foreground ownership while foreground payload retains CallStyle`() {
        val foreground = factory.createOngoing(callId)
        assertEquals(Notification.CallStyle::class.java.name,
            foreground.extras.getString(Notification.EXTRA_TEMPLATE))
        assertNull(foreground.fullScreenIntent)
        val publication = factory.createOngoing(callId, UUID.randomUUID())
        assertEquals(0, publication.flags and Notification.FLAG_FOREGROUND_SERVICE)
        assertNull(publication.fullScreenIntent)
        assertFalse("side publication has neither FGS ownership nor a full-screen intent",
            publication.extras.getString(Notification.EXTRA_TEMPLATE) == Notification.CallStyle::class.java.name)
        assertEquals(MknoonCallNotificationFactory.ONGOING_CHANNEL_ID, publication.channelId)
        assertEquals(Notification.CATEGORY_CALL, publication.category)
        assertTrue(publication.flags and Notification.FLAG_ONGOING_EVENT != 0)
        assertEquals(1, publication.actions.size)
    }

    @Test
    fun `platform eligible publication precedes foreground505 and retirement504`() {
        val token = UUID.randomUUID()
        val publication = factory.createOngoing(callId, token)
        val foreground = factory.createOngoing(callId)
        val trace = mutableListOf<String>()
        assertTrue(handOverToOngoingCallNotification(
            foregroundNotificationId = 504,
            startForeground = { id -> trace += "fg$id"; service.startForeground(id, foreground) },
            cancel = { id -> trace += "cancel$id"; manager.cancel(id) },
            postOngoing = { post(publication); trace += "posted505" },
            isOngoingAccepted = {
                manager.activeNotifications.any { factory.isOngoingPublication(it, callId, token) }
            },
            withCurrent = { effect -> effect(); true },
            scheduleCheck = { _, _ -> error("an accepted publication needs no retry") },
            nowMs = { 0L },
        ))
        assertEquals(listOf("fg504", "posted505", "fg505", "cancel504"), trace)
        assertEquals(setOf(505), manager.activeNotifications.map { it.id }.toSet())
        assertEquals(Notification.CallStyle::class.java.name,
            manager.activeNotifications.single().notification.extras.getString(Notification.EXTRA_TEMPLATE))
    }

    @Test
    fun `failed side publication is logged while current foreground and cleanup survive`() {
        (shadowOf(manager) as CallStyleEligibilityShadow).forcedPostFailure =
            IllegalArgumentException("fixture-post-error\nsecond line")
        val foreground = factory.createOngoing(callId)
        assertTrue(handOverToOngoingCallNotification(
            foregroundNotificationId = 504,
            startForeground = { id -> service.startForeground(id, foreground) },
            cancel = manager::cancel,
            postOngoing = { post(factory.createOngoing(callId, UUID.randomUUID())) },
            isOngoingAccepted = { error("a failed post cannot be accepted") },
            withCurrent = { effect -> effect(); true },
            scheduleCheck = { _, _ -> error("a failed post must not schedule a probe") },
            nowMs = { 0L },
            diagnostic = ::emitMknoonCallNotificationDiagnostic,
        ))
        assertEquals(setOf(504), manager.activeNotifications.map { it.id }.toSet())
        val failures = ShadowLog.getLogsForTag("MKNOON_CALL_NOTIFY")
        assertTrue("post failure must be observable", failures.any {
            it.type == Log.ERROR && it.msg.contains("post_failed") &&
                it.msg.contains("exception_class=java.lang.IllegalArgumentException") &&
                it.msg.contains("message=fixture-post-error second line")
        })
        assertTrue(failures.none { it.msg.contains('\n') || it.msg.contains(callId.toString()) })
        platform.cancelNotification(callId)
        runtime.foregroundRuntime(service).stop(callId)
        assertTrue(manager.activeNotifications.isEmpty())
    }

    @Test
    fun `skipped publication reports deadline and stale owner without invoking the post`() {
        for (staleOwner in listOf(false, true)) {
            var now = 0L
            var posted = false
            val events = mutableListOf<String>()
            val applied = handOverToOngoingCallNotification(
                foregroundNotificationId = 504,
                startForeground = { now = 1_001L },
                cancel = { error("no publication to retire") },
                postOngoing = { posted = true },
                isOngoingAccepted = { error("no publication to inspect") },
                withCurrent = { effect -> if (staleOwner) false else { effect(); true } },
                scheduleCheck = { _, _ -> error("no publication to probe") },
                nowMs = { now },
                diagnostic = { event, _ -> events += event },
            )
            assertEquals(!staleOwner, applied)
            assertFalse(posted)
            val reason = if (staleOwner) "owner_not_current" else "deadline_before_post"
            assertTrue("a skipped post must say why: $events",
                events.any { it.startsWith("post_skipped reason=$reason") })
        }
    }

    private fun post(notification: Notification) {
        try {
            platform.javaClass.getDeclaredMethod(
                "postOngoingNotification", UUID::class.java, Notification::class.java,
            ).also { it.isAccessible = true }.invoke(platform, callId, notification)
        } catch (error: InvocationTargetException) {
            throw error.targetException
        }
    }
}
