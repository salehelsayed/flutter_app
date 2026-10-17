package com.mknoon.app.call

import android.content.Context
import android.os.Build
import android.os.Vibrator
import android.os.VibratorManager
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [30, 33])
class AndroidMknoonRingVibratorTest {
    @Test
    fun `start plays one bounded 60 s ring pattern, never a repeating one, until cancel`() {
        val context: Context = RuntimeEnvironment.getApplication()
        val vibrator = AndroidMknoonRingVibrator(context)
        val system = shadowOf(systemVibrator(context))

        assertTrue(vibrator.start())
        assertTrue(system.isVibrating)
        assertArrayEquals(longArrayOf(0) + LongArray(60) { 1000 }, system.pattern)
        assertEquals(-1, system.repeat)

        vibrator.cancel()
        assertFalse(system.isVibrating)
        assertTrue(system.isCancelled)
    }

    private fun systemVibrator(context: Context): Vibrator =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            context.getSystemService(VibratorManager::class.java).defaultVibrator
        } else {
            context.getSystemService(Vibrator::class.java)
        }
}
