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
        val failingStop = RecordingRingtoneSession(failingStops = Int.MAX_VALUE)
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

    @Test
    fun `a stop that throws is retried when the next call starts and that call still rings`() {
        val flaky = RecordingRingtoneSession(failingStops = 1)
        val next = RecordingRingtoneSession()
        val starter = QueueRingtoneStarter(flaky, next)
        val ringer = MknoonIncomingCallRinger(starter)
        val callId = UUID.fromString(CALL_ID)
        val nextCallId = UUID.fromString(OTHER_CALL_ID)

        assertTrue(ringer.start(callId))
        assertTrue(ringer.stop(callId))
        assertEquals(1, flaky.stopCalls)

        assertTrue(ringer.start(nextCallId))
        assertEquals(2, flaky.stopCalls)
        assertEquals(2, starter.startCalls)

        assertTrue(ringer.stop(nextCallId))
        assertEquals(1, next.stopCalls)
        assertEquals(2, flaky.stopCalls)
    }

    @Test
    fun `a stop that throws is retried on later stops until it succeeds`() {
        val flaky = RecordingRingtoneSession(failingStops = 2)
        val ringer = MknoonIncomingCallRinger(QueueRingtoneStarter(flaky))
        val callId = UUID.fromString(CALL_ID)
        val otherCallId = UUID.fromString(OTHER_CALL_ID)

        assertTrue(ringer.start(callId))
        assertTrue(ringer.stop(callId))
        assertEquals(1, flaky.stopCalls)

        assertFalse(ringer.stop(callId))
        assertEquals(2, flaky.stopCalls)

        assertFalse(ringer.stop(otherCallId))
        assertEquals(3, flaky.stopCalls)

        assertFalse(ringer.stop(callId))
        assertEquals(3, flaky.stopCalls)
    }

    @Test
    fun `a retained failed stop is never retried while another call rings`() {
        val retained = RecordingRingtoneSession(failingStops = 2)
        val active = RecordingRingtoneSession()
        val ringer = MknoonIncomingCallRinger(QueueRingtoneStarter(retained, active))
        val callId = UUID.fromString(CALL_ID)
        val otherCallId = UUID.fromString(OTHER_CALL_ID)

        assertTrue(ringer.start(callId))
        assertTrue(ringer.stop(callId))
        assertTrue(ringer.start(otherCallId))
        assertEquals(2, retained.stopCalls)

        assertTrue(ringer.start(otherCallId))
        assertFalse(ringer.stop(callId))
        assertEquals(2, retained.stopCalls)
        assertEquals(0, active.stopCalls)

        assertTrue(ringer.stop(otherCallId))
        assertEquals(1, active.stopCalls)
        assertEquals(3, retained.stopCalls)
    }

    @Test
    fun `a second failed stop never drops the first one`() {
        val first = RecordingRingtoneSession(failingStops = 2)
        val second = RecordingRingtoneSession(failingStops = 1)
        val third = RecordingRingtoneSession()
        val ringer = MknoonIncomingCallRinger(QueueRingtoneStarter(first, second, third))
        val thirdCallId = UUID.fromString(THIRD_CALL_ID)

        assertTrue(ringer.start(UUID.fromString(CALL_ID)))
        assertTrue(ringer.start(UUID.fromString(OTHER_CALL_ID)))
        assertTrue(ringer.start(thirdCallId))
        assertTrue(ringer.stop(thirdCallId))

        assertEquals(3, first.stopCalls)
        assertEquals(2, second.stopCalls)
        assertEquals(1, third.stopCalls)
    }

    private companion object {
        const val CALL_ID = "11111111-1111-4111-8111-111111111111"
        const val OTHER_CALL_ID = "22222222-2222-4222-8222-222222222222"
        const val THIRD_CALL_ID = "33333333-3333-4333-8333-333333333333"
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

/** The first [failingStops] stop calls throw; later ones succeed. */
private class RecordingRingtoneSession(
    private val failingStops: Int = 0,
) : MknoonCallRingtoneSession {
    var stopCalls = 0

    override fun stop() {
        stopCalls++
        if (stopCalls <= failingStops) throw IllegalStateException("fixture failure")
    }
}
