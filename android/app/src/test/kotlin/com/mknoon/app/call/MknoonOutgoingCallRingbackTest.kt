package com.mknoon.app.call

import java.util.ArrayDeque
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Ringback is the tone the caller hears while the far end rings. Dart drives
 * start and stop from the call state; this owner keeps exactly one tone
 * session, bound to the Dart call handle, and treats the platform tone as
 * best effort so call control never depends on it.
 */
class MknoonOutgoingCallRingbackTest {
    @Test
    fun `same handle starts once and only its exact stop releases the tone`() {
        val first = RecordingRingbackSession()
        val starter = QueueRingbackStarter(first)
        val ringback = MknoonOutgoingCallRingback(starter)

        assertTrue(ringback.start(CALL_HANDLE))
        assertTrue(ringback.start(CALL_HANDLE))
        assertFalse(ringback.stop(OTHER_CALL_HANDLE))
        assertEquals(1, starter.startCalls)
        assertEquals(0, first.stopCalls)
        assertEquals(CALL_HANDLE, ringback.activeCallHandle)

        assertTrue(ringback.stop(CALL_HANDLE))
        assertFalse(ringback.stop(CALL_HANDLE))
        assertEquals(1, first.stopCalls)
        assertNull(ringback.activeCallHandle)
    }

    @Test
    fun `a new handle replaces the tone and stopAll releases whatever plays`() {
        val first = RecordingRingbackSession()
        val replacement = RecordingRingbackSession()
        val starter = QueueRingbackStarter(first, replacement)
        val ringback = MknoonOutgoingCallRingback(starter)

        assertTrue(ringback.start(CALL_HANDLE))
        assertTrue(ringback.start(OTHER_CALL_HANDLE))
        assertEquals(1, first.stopCalls)
        assertEquals(OTHER_CALL_HANDLE, ringback.activeCallHandle)
        assertFalse(ringback.stop(CALL_HANDLE))

        assertTrue(ringback.stopAll())
        assertEquals(1, replacement.stopCalls)
        assertFalse(ringback.stopAll())
        assertNull(ringback.activeCallHandle)
    }

    @Test
    fun `starter and stop failures stay best effort and allow a clean retry`() {
        val failingStop = RecordingRingbackSession(failOnStop = true)
        val recovered = RecordingRingbackSession()
        val starter = QueueRingbackStarter(
            RingbackStartOutcome.Failure,
            failingStop,
            recovered,
        )
        val ringback = MknoonOutgoingCallRingback(starter)

        assertFalse(ringback.start(CALL_HANDLE))
        assertNull(ringback.activeCallHandle)

        assertTrue(ringback.start(CALL_HANDLE))
        assertTrue(ringback.stop(CALL_HANDLE))
        assertEquals(1, failingStop.stopCalls)
        assertNull(ringback.activeCallHandle)

        assertTrue(ringback.start(CALL_HANDLE))
        assertTrue(ringback.stop(CALL_HANDLE))
        assertEquals(1, recovered.stopCalls)
        assertEquals(3, starter.startCalls)
    }

    @Test
    fun `an unavailable tone player is not a session and starts nothing`() {
        val starter = QueueRingbackStarter(RingbackStartOutcome.Unavailable)
        val ringback = MknoonOutgoingCallRingback(starter)

        assertFalse(ringback.start(CALL_HANDLE))
        assertFalse(ringback.stop(CALL_HANDLE))
        assertFalse(ringback.stopAll())
        assertEquals(1, starter.startCalls)
    }

    private companion object {
        const val CALL_HANDLE = "123e4567-e89b-42d3-a456-426614174000"
        const val OTHER_CALL_HANDLE = "323e4567-e89b-42d3-a456-426614174002"
    }
}

private sealed interface RingbackStartOutcome {
    object Failure : RingbackStartOutcome
    object Unavailable : RingbackStartOutcome
}

private class RecordingRingbackSession(
    private val failOnStop: Boolean = false,
) : MknoonCallRingbackToneSession {
    var stopCalls = 0

    override fun stop() {
        stopCalls += 1
        if (failOnStop) throw IllegalStateException("tone release failed")
    }
}

private class QueueRingbackStarter(vararg outcomes: Any?) : MknoonCallRingbackToneStarter {
    private val queue = ArrayDeque<Any?>(outcomes.toList())
    var startCalls = 0

    override fun start(): MknoonCallRingbackToneSession? {
        startCalls += 1
        return when (val next = if (queue.isEmpty()) null else queue.removeFirst()) {
            is MknoonCallRingbackToneSession -> next
            RingbackStartOutcome.Failure -> throw IllegalStateException("tone generator unavailable")
            else -> null
        }
    }
}
