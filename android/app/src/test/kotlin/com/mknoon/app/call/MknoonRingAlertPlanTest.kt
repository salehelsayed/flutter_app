package com.mknoon.app.call

import android.app.NotificationManager
import android.media.AudioAttributes
import android.media.AudioManager
import org.junit.Assert.assertEquals
import org.junit.Test

class MknoonRingAlertPlanTest {
    private data class Row(
        val label: String,
        val ringerMode: Int,
        val vibrateWhenRinging: Boolean,
        val dndFilter: MknoonDndFilter,
        val channelBypassesDnd: Boolean,
        val expected: MknoonRingAlertPlan,
    )

    @Test
    fun `ringer mode, vibrate setting, interruption filter and channel bypass decide sound usage and vibration`() {
        val rows = listOf(
            Row("no DND, silent", SILENT, true, ALL, false, plan(RINGTONE, vibrate = false)),
            Row("no DND, vibrate mode", VIBRATE, false, ALL, false, plan(RINGTONE, vibrate = true)),
            Row("no DND, normal, vibrate when ringing on", NORMAL, true, ALL, false, plan(RINGTONE, vibrate = true)),
            Row("no DND, normal, vibrate when ringing off", NORMAL, false, ALL, false, plan(RINGTONE, vibrate = false)),
            Row("no DND, bypass flag, silent", SILENT, true, ALL, true, plan(RINGTONE, vibrate = false)),
            Row("no DND, bypass flag, normal", NORMAL, true, ALL, true, plan(RINGTONE, vibrate = true)),
            Row("priority DND without bypass, normal", NORMAL, true, PRIORITY, false, plan(RINGTONE, vibrate = false)),
            Row("priority DND without bypass, vibrate mode", VIBRATE, true, PRIORITY, false, plan(RINGTONE, vibrate = false)),
            Row("priority DND with bypass, normal, vibrate on", NORMAL, true, PRIORITY, true, plan(ALARM, vibrate = true)),
            Row("priority DND with bypass, normal, vibrate off", NORMAL, false, PRIORITY, true, plan(ALARM, vibrate = false)),
            Row("priority DND with bypass, vibrate mode", VIBRATE, false, PRIORITY, true, plan(RINGTONE, vibrate = true)),
            Row("priority DND with bypass, silent", SILENT, true, PRIORITY, true, plan(RINGTONE, vibrate = false)),
            Row("alarms only with bypass, normal", NORMAL, true, ALARMS_ONLY, true, plan(RINGTONE, vibrate = false)),
            Row("alarms only with bypass, vibrate mode", VIBRATE, true, ALARMS_ONLY, true, plan(RINGTONE, vibrate = false)),
            Row("alarms only without bypass, normal", NORMAL, true, ALARMS_ONLY, false, plan(RINGTONE, vibrate = false)),
            Row("total silence with bypass, normal", NORMAL, true, NONE, true, plan(RINGTONE, vibrate = false)),
            Row("total silence without bypass, vibrate mode", VIBRATE, false, NONE, false, plan(RINGTONE, vibrate = false)),
            Row("unknown filter with bypass, normal", NORMAL, true, UNKNOWN, true, plan(RINGTONE, vibrate = false)),
            Row("unknown filter without bypass, normal", NORMAL, true, UNKNOWN, false, plan(RINGTONE, vibrate = false)),
        )

        val mismatches = rows.mapNotNull { row ->
            val actual = mknoonRingAlertPlan(
                ringerMode = row.ringerMode,
                vibrateWhenRinging = row.vibrateWhenRinging,
                dndFilter = row.dndFilter,
                channelBypassesDnd = row.channelBypassesDnd,
            )
            if (actual == row.expected) null else "${row.label}: expected ${row.expected}, got $actual"
        }
        assertEquals(emptyList<String>(), mismatches)
    }

    @Test
    fun `interruption filter values map to the ring filter and anything else is unknown`() {
        assertEquals(ALL, mknoonDndFilter(NotificationManager.INTERRUPTION_FILTER_ALL))
        assertEquals(PRIORITY, mknoonDndFilter(NotificationManager.INTERRUPTION_FILTER_PRIORITY))
        assertEquals(ALARMS_ONLY, mknoonDndFilter(NotificationManager.INTERRUPTION_FILTER_ALARMS))
        assertEquals(NONE, mknoonDndFilter(NotificationManager.INTERRUPTION_FILTER_NONE))
        assertEquals(UNKNOWN, mknoonDndFilter(NotificationManager.INTERRUPTION_FILTER_UNKNOWN))
        assertEquals(UNKNOWN, mknoonDndFilter(99))
    }

    private fun plan(soundUsage: Int, vibrate: Boolean) =
        MknoonRingAlertPlan(soundUsage = soundUsage, vibrate = vibrate)

    private companion object {
        const val SILENT = AudioManager.RINGER_MODE_SILENT
        const val VIBRATE = AudioManager.RINGER_MODE_VIBRATE
        const val NORMAL = AudioManager.RINGER_MODE_NORMAL
        const val RINGTONE = AudioAttributes.USAGE_NOTIFICATION_RINGTONE
        const val ALARM = AudioAttributes.USAGE_ALARM
        val ALL = MknoonDndFilter.All
        val PRIORITY = MknoonDndFilter.Priority
        val ALARMS_ONLY = MknoonDndFilter.AlarmsOnly
        val NONE = MknoonDndFilter.None
        val UNKNOWN = MknoonDndFilter.Unknown
    }
}
