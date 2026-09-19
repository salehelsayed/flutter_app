package com.mknoon.app.call

import org.junit.Assert.assertEquals
import org.junit.Assert.assertSame
import org.junit.Assert.assertThrows
import org.junit.Test

class MknoonCallForegroundAudioActivationTest {
    @Test
    fun `log projection has only fixed applied outcomes without call authority`() {
        assertEquals("MknoonCallForegroundAudio", MKNOON_CALL_FOREGROUND_AUDIO_TAG)
        assertEquals(
            listOf(
                "CALL_ANDROID_FOREGROUND_AUDIO outcome=applied",
                "CALL_ANDROID_FOREGROUND_AUDIO outcome=failed",
            ),
            listOf(true, false).map(::formatMknoonCallForegroundAudioApplied),
        )
    }

    @Test
    fun `applied evidence follows actual foreground type application`() {
        val sequence = mutableListOf<String>()
        applyMknoonCallForegroundAudio(
            startForeground = { sequence += "phone_call_and_microphone_applied" },
            reportApplied = { applied -> sequence += "reported_$applied" },
        )
        assertEquals(
            listOf("phone_call_and_microphone_applied", "reported_true"),
            sequence,
        )
    }

    @Test
    fun `platform refusal never reports applied audio and retains its failure`() {
        val refusal = SecurityException("fixture permission refusal")
        val reports = mutableListOf<Boolean>()
        val observed = assertThrows(SecurityException::class.java) {
            applyMknoonCallForegroundAudio(
                startForeground = { throw refusal },
                reportApplied = { reports += it },
            )
        }
        assertSame(refusal, observed)
        assertEquals(listOf(false), reports)
    }

    @Test
    fun `diagnostic failure cannot change successful or failed audio activation`() {
        applyMknoonCallForegroundAudio(
            startForeground = {},
            reportApplied = { error("fixture diagnostic failure") },
        )
        val refusal = SecurityException("fixture permission refusal")
        val observed = assertThrows(SecurityException::class.java) {
            applyMknoonCallForegroundAudio(
                startForeground = { throw refusal },
                reportApplied = { error("fixture diagnostic failure") },
            )
        }
        assertSame(refusal, observed)
    }
}
