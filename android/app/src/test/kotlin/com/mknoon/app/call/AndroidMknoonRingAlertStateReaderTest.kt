package com.mknoon.app.call

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.media.AudioManager
import android.provider.Settings
import org.junit.Assert.assertEquals
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [33])
class AndroidMknoonRingAlertStateReaderTest {
    private lateinit var context: Context
    private lateinit var audio: AudioManager
    private lateinit var notifications: NotificationManager

    @Before
    fun setUp() {
        context = RuntimeEnvironment.getApplication()
        audio = context.getSystemService(AudioManager::class.java)
        notifications = context.getSystemService(NotificationManager::class.java)
        shadowOf(notifications).setNotificationPolicyAccessGranted(true)
    }

    @Test
    @Suppress("DEPRECATION")
    fun `reads priority DND, ringtone channel bypass, ringer mode and vibrate setting`() {
        audio.ringerMode = AudioManager.RINGER_MODE_NORMAL
        Settings.System.putInt(context.contentResolver, Settings.System.VIBRATE_WHEN_RINGING, 1)
        notifications.setInterruptionFilter(NotificationManager.INTERRUPTION_FILTER_PRIORITY)
        notifications.createNotificationChannel(
            NotificationChannel(
                MknoonCallNotificationFactory.CHANNEL_ID,
                "calls",
                NotificationManager.IMPORTANCE_HIGH,
            ).apply { setBypassDnd(true) },
        )

        assertEquals(
            MknoonRingAlertState(
                ringerMode = AudioManager.RINGER_MODE_NORMAL,
                vibrateWhenRinging = true,
                dndFilter = MknoonDndFilter.Priority,
                channelBypassesDnd = true,
            ),
            AndroidMknoonRingAlertStateReader(context).read(),
        )
    }

    @Test
    fun `alarms-only and total-silence filters read as their own states`() {
        notifications.setInterruptionFilter(NotificationManager.INTERRUPTION_FILTER_ALARMS)
        assertEquals(MknoonDndFilter.AlarmsOnly, AndroidMknoonRingAlertStateReader(context).read().dndFilter)

        notifications.setInterruptionFilter(NotificationManager.INTERRUPTION_FILTER_NONE)
        assertEquals(MknoonDndFilter.None, AndroidMknoonRingAlertStateReader(context).read().dndFilter)
    }

    @Test
    fun `DND reporting silent keeps the user's own ringer mode`() {
        audio.ringerMode = AudioManager.RINGER_MODE_SILENT
        Settings.Global.putInt(context.contentResolver, Settings.Global.MODE_RINGER, AudioManager.RINGER_MODE_NORMAL)
        notifications.setInterruptionFilter(NotificationManager.INTERRUPTION_FILTER_PRIORITY)

        assertEquals(AudioManager.RINGER_MODE_NORMAL, AndroidMknoonRingAlertStateReader(context).read().ringerMode)
    }

    @Test
    fun `no DND, no channel and no vibrate setting read as plain vibrate mode`() {
        audio.ringerMode = AudioManager.RINGER_MODE_VIBRATE
        notifications.setInterruptionFilter(NotificationManager.INTERRUPTION_FILTER_ALL)

        assertEquals(
            MknoonRingAlertState(
                ringerMode = AudioManager.RINGER_MODE_VIBRATE,
                vibrateWhenRinging = false,
                dndFilter = MknoonDndFilter.All,
                channelBypassesDnd = false,
            ),
            AndroidMknoonRingAlertStateReader(context).read(),
        )
    }
}
