package com.mknoon.app.call

import org.junit.Assert.*
import org.junit.Test
import java.util.UUID

class DebugCallLifecycleObservationTest {
    private val nonce = "1234567890abcdef1234567890abcdef"
    private var wall = 10000L
    private var elapsed = 300L
    private fun active(): MknoonCallJournalObservation {
        val rig = LifecycleRig()
        rig.controller.present(rig.payload)
        return rig.controller.observeJournal()
    }
    @Test fun synchronousOrderRetainsAuthenticatedExpiryAndAnswerAcrossJournalDeletion() {
        val source = active()
        val recorder = DebugCallLifecycleRecorder({ wall }, { elapsed })
        val armed = recorder.arm(nonce, source)
        assertEquals(source.descriptor!!.expiresAtMs, armed["authenticatedExpiresAtMs"])
        wall += 5; elapsed += 5
        recorder.record(source.descriptor.nativeCallId.toString(), "journal", "ANSWER_REQUESTED")
        wall += 2; elapsed += 2
        recorder.record(source.descriptor.nativeCallId.toString(), "answer", "rejected")
        val result = recorder.snapshot(nonce, MknoonCallJournalObservation(null, false, false))
        val events = result["events"] as List<*>
        assertEquals(2, events.size)
        assertEquals(10005L, (events[0] as Map<*, *>)["wallMs"])
        assertEquals(307L, (events[1] as Map<*, *>)["elapsedMs"])
        assertFalse(result.toString().contains(source.descriptor.nativeCallId.toString()))
        assertEquals(false, result["currentOwnerMatches"])
        assertEquals(false, result["successorPresent"])
    }
    @Test fun anotherOwnerCannotAppendOrReplaceArmedOwner() {
        val source = active(); val r = DebugCallLifecycleRecorder({ wall }, { elapsed })
        r.arm(nonce, source)
        val other = source.copy(descriptor = source.descriptor!!.copy(nativeCallId = UUID.randomUUID()))
        r.record(other.descriptor!!.nativeCallId.toString(), "answer", "ok")
        assertEquals(emptyList<Any>(), r.snapshot(nonce, other)["events"])
        assertEquals(true, r.snapshot(nonce, other)["successorPresent"])
        assertThrows(IllegalArgumentException::class.java) { r.arm(nonce, other) }
    }
    @Test fun overflowAndTtlAreExplicitAndNoLateArmCanResetBudget() {
        val source = active(); val r = DebugCallLifecycleRecorder({ wall }, { elapsed })
        r.arm(nonce, source)
        repeat(20) { r.record(source.descriptor!!.nativeCallId.toString(), "answer", "ok") }
        assertEquals(16, (r.snapshot(nonce, source)["events"] as List<*>).size)
        assertEquals(true, r.snapshot(nonce, source)["overflow"])
        elapsed += 1000; r.arm(nonce, source)
        assertEquals(300L, r.snapshot(nonce, source)["armedElapsedMs"])
        elapsed += 90001
        assertThrows(IllegalArgumentException::class.java) { r.snapshot(nonce, source) }
    }
    @Test fun readFailureWrongNonceAndCleanupCannotProduceCurrentProof() {
        val source = active(); val r = DebugCallLifecycleRecorder({ wall }, { elapsed })
        assertThrows(IllegalArgumentException::class.java) { r.arm("bad", source) }
        assertThrows(IllegalArgumentException::class.java) { r.arm(nonce, source.copy(cleanupPending = true)) }
        r.arm(nonce, source)
        assertEquals(false, r.snapshot(nonce, null)["journalReadable"])
        assertThrows(IllegalArgumentException::class.java) { r.snapshot("abcdef1234567890", source) }
    }
    @Test fun unrecognizedValuesAndRegressedClockDoNotAppendEvidence() {
        val source = active(); val r = DebugCallLifecycleRecorder({ wall }, { elapsed })
        r.arm(nonce, source)
        r.record(source.descriptor!!.nativeCallId.toString(), "raw", "private")
        r.record(source.descriptor.nativeCallId.toString(), "answer", "secret exception")
        elapsed--
        r.record(source.descriptor.nativeCallId.toString(), "answer", "ok")
        elapsed++
        assertEquals(emptyList<Any>(), r.snapshot(nonce, source)["events"])
    }
    @Test fun receiverAuthenticatedExpiryObservationDoesNotClaimOutgoingPolicyExpiry() {
        val source = active()
        val outgoing = source.copy(descriptor = source.descriptor!!.copy(direction = PendingNativeCallDirection.OUTGOING))
        val r = DebugCallLifecycleRecorder({ wall }, { elapsed })
        assertThrows(IllegalArgumentException::class.java) { r.arm(nonce, outgoing) }
    }

}
