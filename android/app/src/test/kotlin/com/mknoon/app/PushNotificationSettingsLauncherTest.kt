package com.mknoon.app

import android.app.Application
import android.content.Intent
import android.provider.Settings
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.Shadows
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
class PushNotificationSettingsLauncherTest {
    @Test
    @Config(sdk = [33])
    fun `modern Android opens the app notification settings destination`() {
        val application: Application = RuntimeEnvironment.getApplication()

        assertTrue(PushNotificationSettingsLauncher.open(application))

        val intent = Shadows.shadowOf(application).nextStartedActivity
        assertEquals(Settings.ACTION_APP_NOTIFICATION_SETTINGS, intent.action)
        assertEquals(
            application.packageName,
            intent.getStringExtra(Settings.EXTRA_APP_PACKAGE),
        )
        assertTrue(intent.flags and Intent.FLAG_ACTIVITY_NEW_TASK != 0)
    }

    @Test
    @Config(sdk = [24])
    fun `API 24 uses the legacy app notification settings destination`() {
        val application: Application = RuntimeEnvironment.getApplication()

        assertTrue(PushNotificationSettingsLauncher.open(application))

        val intent = Shadows.shadowOf(application).nextStartedActivity
        assertEquals("android.settings.APP_NOTIFICATION_SETTINGS", intent.action)
        assertEquals(
            application.packageName,
            intent.getStringExtra("app_package"),
        )
        assertEquals(application.applicationInfo.uid, intent.getIntExtra("app_uid", -1))
    }
}
