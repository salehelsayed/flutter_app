package com.mknoon.app

import android.Manifest
import android.app.Application
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Intent
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
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
class UpdateCheckNotificationPosterTest {
    private lateinit var application: Application
    private lateinit var manager: NotificationManager

    @Before
    fun setUp() {
        application = RuntimeEnvironment.getApplication()
        manager = application.getSystemService(NotificationManager::class.java)
    }

    private fun grant() = shadowOf(application).grantPermissions(Manifest.permission.POST_NOTIFICATIONS)

    @Test
    fun `posts on its own default-importance channel with the fixed tag and id`() {
        grant()

        assertTrue(UpdateCheckNotificationPoster.post(application, "hard", "Update Mknoon", "Tap to update."))

        val channel = manager.getNotificationChannel("mknoon_app_updates")
        assertEquals("App updates", channel.name)
        assertEquals(NotificationManager.IMPORTANCE_DEFAULT, channel.importance)
        for (other in listOf("mknoon_messages", "mknoon_messages_silent", "mknoon_calls")) {
            assertNotEquals(other, channel.id)
        }
        val posted = shadowOf(manager).allNotifications.single()
        assertEquals("mknoon_app_updates", posted.channelId)
        val active = manager.activeNotifications.single()
        assertEquals("mknoon_app_update", active.tag)
        assertEquals(UpdateCheckNotificationPoster.HARD_ID, active.id)
    }

    @Test
    fun `the tap opens the built-in Play page directly`() {
        grant()
        assertTrue(UpdateCheckNotificationPoster.post(application, "soft", "t", "b"))

        val notification = shadowOf(manager).allNotifications.single()
        val intent = shadowOf(notification.contentIntent).savedIntent
        assertEquals(Intent.ACTION_VIEW, intent.action)
        assertEquals(
            "https://play.google.com/store/apps/details?id=com.mknoon.app",
            intent.dataString,
        )
        assertTrue(shadowOf(notification.contentIntent).isActivityIntent)
    }

    @Test
    fun `a reminder of the same kind replaces the previous one`() {
        grant()
        repeat(3) { i ->
            assertTrue(UpdateCheckNotificationPoster.post(application, "hard", "t$i", "b$i"))
        }
        assertTrue(UpdateCheckNotificationPoster.post(application, "soft", "s", "s"))

        val ids = manager.activeNotifications.map { it.tag to it.id }.sortedBy { it.second }
        assertEquals(
            listOf(
                "mknoon_app_update" to UpdateCheckNotificationPoster.SOFT_ID,
                "mknoon_app_update" to UpdateCheckNotificationPoster.HARD_ID,
            ),
            ids,
        )
    }

    @Test
    fun `not granted skips silently and never prompts`() {
        // POST_NOTIFICATIONS not granted on API 33.
        assertFalse(UpdateCheckNotificationPoster.post(application, "hard", "t", "b"))
        assertTrue(manager.activeNotifications.isEmpty())
        assertEquals(null, shadowOf(application).nextStartedActivity)

        grant()
        shadowOf(manager).setNotificationsEnabled(false)
        assertFalse(UpdateCheckNotificationPoster.post(application, "hard", "t", "b"))
        assertTrue(manager.activeNotifications.isEmpty())
    }

    @Test
    fun `a channel the user blocked skips silently`() {
        grant()
        manager.createNotificationChannel(
            NotificationChannel("mknoon_app_updates", "App updates", NotificationManager.IMPORTANCE_NONE),
        )
        assertFalse(UpdateCheckNotificationPoster.post(application, "soft", "t", "b"))
        assertTrue(manager.activeNotifications.isEmpty())
    }

    @Test
    fun `unknown kinds and empty text post nothing`() {
        grant()
        assertFalse(UpdateCheckNotificationPoster.post(application, "url", "t", "b"))
        assertFalse(UpdateCheckNotificationPoster.post(application, "soft", "", "b"))
        assertFalse(postFromArguments(application, mapOf("kind" to "soft", "title" to "t")))
        assertTrue(manager.activeNotifications.isEmpty())
    }
}
