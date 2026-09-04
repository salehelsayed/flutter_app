package com.mknoon.app.call

import java.util.ArrayDeque
import java.util.UUID
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class MknoonIncomingCallRingerTest {
    @Test
    fun `same call starts once and only its exact stop releases playback`() {
        val first = RecordingRingtoneSession()
        val starter = QueueRingtoneStarter(first)
        val ringer = MknoonIncomingCallRinger(starter)
        val callId = UUID.fromString(CALL_ID)
        val otherCallId = UUID.fromString(OTHER_CALL_ID)

        assertTrue(ringer.start(callId))
        assertTrue(ringer.start(callId))
        assertFalse(ringer.stop(otherCallId))
        assertEquals(1, starter.startCalls)
        assertEquals(0, first.stopCalls)

        assertTrue(ringer.stop(callId))
        assertFalse(ringer.stop(callId))
        assertEquals(1, first.stopCalls)
    }

    @Test
    fun `replacement stops old playback and unavailable starts retain no owner`() {
        val first = RecordingRingtoneSession()
        val replacement = RecordingRingtoneSession()
        val starter = QueueRingtoneStarter(first, null, replacement)
        val ringer = MknoonIncomingCallRinger(starter)
        val firstCallId = UUID.fromString(CALL_ID)
        val nextCallId = UUID.fromString(OTHER_CALL_ID)

        assertTrue(ringer.start(firstCallId))
        assertFalse(ringer.start(nextCallId))
        assertEquals(1, first.stopCalls)
        assertFalse(ringer.stop(firstCallId))

        assertTrue(ringer.start(nextCallId))
        assertTrue(ringer.stop(nextCallId))
        assertEquals(1, replacement.stopCalls)
        assertEquals(3, starter.startCalls)
    }

    @Test
    fun `starter and stop failures stay best effort and allow a clean retry`() {
        val failingStop = RecordingRingtoneSession(failOnStop = true)
        val recovered = RecordingRingtoneSession()
        val starter = QueueRingtoneStarter(
            StartOutcome.Failure,
            failingStop,
            recovered,
        )
        val ringer = MknoonIncomingCallRinger(starter)
        val callId = UUID.fromString(CALL_ID)

        assertFalse(ringer.start(callId))
        assertTrue(ringer.start(callId))
        assertTrue(ringer.stop(callId))
        assertTrue(ringer.start(callId))
        assertTrue(ringer.stop(callId))
        assertEquals(1, recovered.stopCalls)
    }

    private companion object {
        const val CALL_ID = "11111111-1111-4111-8111-111111111111"
        const val OTHER_CALL_ID = "22222222-2222-4222-8222-222222222222"
    }
}

private sealed interface StartOutcome {
    data class Session(val value: MknoonCallRingtoneSession) : StartOutcome

    data object Unavailable : StartOutcome

    data object Failure : StartOutcome
}

private class QueueRingtoneStarter(vararg outcomes: Any?) : MknoonCallRingtoneStarter {
    private val queued = ArrayDeque<StartOutcome>().apply {
        outcomes.forEach { outcome ->
            add(
                when (outcome) {
                    is StartOutcome -> outcome
                    is MknoonCallRingtoneSession -> StartOutcome.Session(outcome)
                    null -> StartOutcome.Unavailable
                    else -> error("unsupported fixture")
                },
            )
        }
    }
    var startCalls = 0

    override fun start(): MknoonCallRingtoneSession? {
        startCalls++
        return when (val outcome = queued.removeFirst()) {
            is StartOutcome.Session -> outcome.value
            StartOutcome.Unavailable -> null
            StartOutcome.Failure -> throw IllegalStateException("fixture failure")
        }
    }
}

private class RecordingRingtoneSession(
    private val failOnStop: Boolean = false,
) : MknoonCallRingtoneSession {
    var stopCalls = 0

    override fun stop() {
        stopCalls++
        if (failOnStop) throw IllegalStateException("fixture failure")
    }
}
