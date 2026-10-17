package com.mknoon.app.call

import android.media.AudioAttributes
import android.media.AudioManager
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Test

class AndroidMknoonCallRingtoneStarterTest {
    @Test
    fun `missing ringtone still vibrates and stop cancels the vibration`() {
        val vibrator = RecordingVibrator()
        val starter = starter(VIBRATE_MODE, sound = RecordingSound(session = null), vibrator = vibrator)

        val session = requireNotNull(starter.start())
        assertEquals(1, vibrator.startCalls)
        assertEquals(0, vibrator.cancelCalls)

        session.stop()
        assertEquals(1, vibrator.cancelCalls)
    }

    @Test
    fun `failing player still vibrates`() {
        val vibrator = RecordingVibrator()
        val starter = starter(VIBRATE_MODE, sound = RecordingSound(session = null, fail = true), vibrator = vibrator)

        assertNotNull(starter.start())
        assertEquals(1, vibrator.startCalls)
    }

    @Test
    fun `plan without vibration never starts the vibrator and stop releases the player only`() {
        val vibrator = RecordingVibrator()
        val playback = CountingSession()
        val starter = starter(SILENT_MODE, sound = RecordingSound(playback), vibrator = vibrator)

        val session = requireNotNull(starter.start())
        assertEquals(0, vibrator.startCalls)

        session.stop()
        assertEquals(1, playback.stopCalls)
        assertEquals(0, vibrator.cancelCalls)
    }

    @Test
    fun `no sound and no vibration returns no session`() {
        val vibrator = RecordingVibrator()
        val starter = starter(SILENT_MODE, sound = RecordingSound(session = null), vibrator = vibrator)

        assertNull(starter.start())
        assertEquals(0, vibrator.startCalls)
    }

    @Test
    fun `device without a vibrator keeps a sound-only session`() {
        val vibrator = RecordingVibrator(available = false)
        val playback = CountingSession()
        val starter = starter(VIBRATE_MODE, sound = RecordingSound(playback), vibrator = vibrator)

        val session = requireNotNull(starter.start())
        assertEquals(1, vibrator.startCalls)

        session.stop()
        assertEquals(1, playback.stopCalls)
        assertEquals(0, vibrator.cancelCalls)

        assertNull(starter(VIBRATE_MODE, sound = RecordingSound(session = null), vibrator = vibrator).start())
    }

    @Test
    fun `DND with channel bypass plays the ringtone as an alarm, without bypass as a ringtone`() {
        val bypassed = RecordingSound(CountingSession())
        starter(DND_BYPASS_NORMAL, sound = bypassed, vibrator = RecordingVibrator()).start()
        assertEquals(listOf(AudioAttributes.USAGE_ALARM), bypassed.usages)

        val blocked = RecordingSound(CountingSession())
        starter(DND_NO_BYPASS_NORMAL, sound = blocked, vibrator = RecordingVibrator()).start()
        assertEquals(listOf(AudioAttributes.USAGE_NOTIFICATION_RINGTONE), blocked.usages)
    }

    @Test
    fun `throwing vibrator cancel still releases the player`() {
        val vibrator = RecordingVibrator(failOnCancel = true)
        val playback = CountingSession()
        val starter = starter(VIBRATE_MODE, sound = RecordingSound(playback), vibrator = vibrator)

        val session = requireNotNull(starter.start())
        assertThrows(IllegalStateException::class.java) { session.stop() }
        assertEquals(1, vibrator.cancelCalls)
        assertEquals(1, playback.stopCalls)
    }

    @Test
    fun `unreadable alert state still rings as a plain ringtone`() {
        val sound = RecordingSound(CountingSession())
        val vibrator = RecordingVibrator()
        val starter = AndroidMknoonCallRingtoneStarter(
            alertState = { throw SecurityException("fixture failure") },
            sound = sound,
            vibrator = vibrator,
        )

        assertNotNull(starter.start())
        assertEquals(listOf(AudioAttributes.USAGE_NOTIFICATION_RINGTONE), sound.usages)
        assertEquals(0, vibrator.startCalls)
    }

    private fun starter(
        state: MknoonRingAlertState,
        sound: MknoonRingSoundStarter,
        vibrator: MknoonRingVibrator,
    ) = AndroidMknoonCallRingtoneStarter(
        alertState = { state },
        sound = sound,
        vibrator = vibrator,
    )

    private companion object {
        val VIBRATE_MODE = MknoonRingAlertState(
            ringerMode = AudioManager.RINGER_MODE_VIBRATE,
            vibrateWhenRinging = false,
            dndFilter = MknoonDndFilter.All,
            channelBypassesDnd = false,
        )
        val SILENT_MODE = VIBRATE_MODE.copy(ringerMode = AudioManager.RINGER_MODE_SILENT)
        val DND_BYPASS_NORMAL = MknoonRingAlertState(
            ringerMode = AudioManager.RINGER_MODE_NORMAL,
            vibrateWhenRinging = true,
            dndFilter = MknoonDndFilter.Priority,
            channelBypassesDnd = true,
        )
        val DND_NO_BYPASS_NORMAL = DND_BYPASS_NORMAL.copy(channelBypassesDnd = false)
    }
}

private class CountingSession : MknoonCallRingtoneSession {
    var stopCalls = 0

    override fun stop() {
        stopCalls++
    }
}

private class RecordingSound(
    private val session: MknoonCallRingtoneSession?,
    private val fail: Boolean = false,
) : MknoonRingSoundStarter {
    val usages = mutableListOf<Int>()

    override fun start(soundUsage: Int): MknoonCallRingtoneSession? {
        usages += soundUsage
        if (fail) throw IllegalStateException("fixture failure")
        return session
    }
}

private class RecordingVibrator(
    private val available: Boolean = true,
    private val failOnCancel: Boolean = false,
) : MknoonRingVibrator {
    var startCalls = 0
    var cancelCalls = 0

    override fun start(): Boolean {
        startCalls++
        return available
    }

    override fun cancel() {
        cancelCalls++
        if (failOnCancel) throw IllegalStateException("fixture failure")
    }
}
