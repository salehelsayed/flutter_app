package com.mknoon.app.call

import android.content.Context
import android.media.AudioManager
import android.os.Looper
import com.cloudwebrtc.webrtc.audio.AudioSwitchManager
import com.mknoon.app.BuildConfig
import com.mknoon.app.MknoonApplication
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config

/**
 * Drives flutter_webrtc 1.6.0's real AudioSwitchManager against Robolectric's
 * AudioManager the way a Telecom call does: Telecom owns mode and route,
 * getUserMedia starts the plugin's AudioSwitch, Telecom ends the call, and the
 * plugin stops after the last peer disposal.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [33])
class MknoonCallAudioSessionOwnershipTest {
    private lateinit var audioManager: AudioManager
    private lateinit var plugin: AudioSwitchManager

    @Before
    fun setUp() {
        val context: Context = RuntimeEnvironment.getApplication()
        audioManager = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
        plugin = AudioSwitchManager(context)
        // flutter_webrtc_call_engine.dart:39-40 sets exactly this on Android.
        plugin.setManageAudioFocus(false)
    }

    @After
    fun tearDown() {
        plugin.stop()
        drainMainLooper()
        AudioSwitchManager.setAudioSessionManagementEnabled(true)
    }

    @Test
    fun `control - plugin default restores Telecom's in-call state after Telecom ended the call`() {
        AudioSwitchManager.setAudioSessionManagementEnabled(true)
        telecomActivatesCall()

        plugin.start()
        drainMainLooper()
        assertFalse(
            "AudioSwitch activate unmutes the microphone globally",
            audioManager.isMicrophoneMute,
        )

        telecomEndsCall()
        plugin.stop()
        drainMainLooper()

        assertEquals(
            "plugin deactivate restores the cached MODE_IN_COMMUNICATION",
            AudioManager.MODE_IN_COMMUNICATION,
            audioManager.mode,
        )
        assertTrue(
            "plugin deactivate restores the cached speakerphone state",
            audioManager.isSpeakerphoneOn,
        )
    }

    @Test
    fun `Telecom lane policy leaves Telecom's end-of-call state alone`() {
        MknoonCallAudioSessionOwnership.applyProcessPolicy(telecomLaneCompiledIn = true)
        telecomActivatesCall()

        plugin.start()
        drainMainLooper()
        assertTrue("no global unmute during the call", audioManager.isMicrophoneMute)
        assertEquals(AudioManager.MODE_IN_COMMUNICATION, audioManager.mode)

        telecomEndsCall()
        plugin.stop()
        drainMainLooper()

        assertEquals(AudioManager.MODE_NORMAL, audioManager.mode)
        assertFalse(audioManager.isSpeakerphoneOn)
        assertTrue("mute state is Telecom's, not restored by the plugin", audioManager.isMicrophoneMute)
    }

    @Test
    fun `without a Telecom lane the plugin stays the audio session owner`() {
        AudioSwitchManager.setAudioSessionManagementEnabled(false)

        MknoonCallAudioSessionOwnership.applyProcessPolicy(telecomLaneCompiledIn = false)

        assertTrue(pluginManagesAudioSession())
    }

    @Test
    fun `the manifest Application's onCreate sets the build's audio session policy`() {
        val application = RuntimeEnvironment.getApplication()
        assertTrue(
            "merged manifest must start ${MknoonApplication::class.java.name}, " +
                "Robolectric started ${application.javaClass.name}",
            application is MknoonApplication,
        )
        val expected = !BuildConfig.ENABLE_ANDROID_NATIVE_CALLS
        AudioSwitchManager.setAudioSessionManagementEnabled(!expected)

        application.onCreate()

        assertEquals(
            "ENABLE_ANDROID_NATIVE_CALLS=${BuildConfig.ENABLE_ANDROID_NATIVE_CALLS} " +
                "must leave audioSessionManagementEnabled=$expected",
            expected,
            pluginManagesAudioSession(),
        )
    }

    private fun telecomActivatesCall() {
        audioManager.mode = AudioManager.MODE_IN_COMMUNICATION
        audioManager.isSpeakerphoneOn = true
        audioManager.isMicrophoneMute = true
    }

    private fun telecomEndsCall() {
        audioManager.mode = AudioManager.MODE_NORMAL
        audioManager.isSpeakerphoneOn = false
    }

    private fun drainMainLooper() {
        shadowOf(Looper.getMainLooper()).idle()
    }

    private fun pluginManagesAudioSession(): Boolean =
        AudioSwitchManager::class.java
            .getDeclaredField("audioSessionManagementEnabled")
            .apply { isAccessible = true }
            .getBoolean(null)
}
