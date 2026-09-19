package com.mknoon.app.call

import java.security.MessageDigest
import java.util.UUID
import org.junit.Assert.*
import org.junit.Test

class DebugCallJournalSnapshotTest {
    private val nonce = "1234567890abcdef1234567890abcdef"

    private fun terminal(): MknoonCallJournalObservation {
        val rig = LifecycleRig()
        rig.controller.present(rig.payload)
        rig.controller.attach()
        rig.controller.markAdopted(rig.payload.nativeCallId)
        rig.controller.acknowledge(rig.payload.nativeCallId, rig.controller.snapshot()!!.highestSequence,
            PendingNativeCallAcknowledgement.ADOPTED)
        rig.controller.terminate(rig.payload.nativeCallId, PendingNativeCallEventType.PROVIDER_REMOVED)
        return rig.controller.observeJournal()
    }

    @Test fun exactTerminalRecordIsNonceBoundWithoutExportingNativeIdentity() {
        val observed = terminal()
        var reads = 0
        val result = debugCallJournalSnapshot(nonce) { reads++; observed }
        assertEquals(1, reads)
        assertEquals("snapshot", result["status"])
        assertEquals("mknoon.debug-call-journal.v1", result["schema"])
        assertEquals(nonce, result["nonce"])
        assertEquals("terminal", result["recordState"])
        assertEquals("journal", result["phase"])
        assertEquals("adopted", result["handoff"])
        assertEquals("provider_removed", result["terminalType"])
        assertEquals(observed.descriptor!!.highestSequence, result["terminalSequence"])
        assertEquals(false, result["liveOwnerPresent"])
        assertEquals(false, result["cleanupPending"])
        val expected = MessageDigest.getInstance("SHA-256")
            .digest("$nonce:${observed.descriptor.nativeCallId}".toByteArray())
            .joinToString("") { "%02x".format(it) }
        assertEquals(expected, result["callBindingSha256"])
        assertFalse(result.toString().contains(observed.descriptor.nativeCallId.toString()))
        assertFalse(result.toString().contains(observed.descriptor.callHandle))
        assertEquals(64, (result["recordBindingSha256"] as String).length)
    }

    @Test fun nonceAndSuccessorAndTerminalSequenceChangeProtectedRecordIdentity() {
        val observed = terminal()
        val first = debugCallJournalSnapshot(nonce) { observed }
        val otherNonce = debugCallJournalSnapshot("abcdef1234567890") { observed }
        assertNotEquals(first["callBindingSha256"], otherNonce["callBindingSha256"])
        val descriptor = observed.descriptor!!
        val nextId = UUID.randomUUID()
        val nextEvent = descriptor.terminalEvent!!.copy(nativeCallId = nextId)
        val successor = observed.copy(descriptor = descriptor.copy(nativeCallId = nextId,
            terminalEvent = nextEvent, events = listOf(nextEvent)))
        val next = debugCallJournalSnapshot(nonce) { successor }
        assertNotEquals(first["callBindingSha256"], next["callBindingSha256"])
        val advancedEvent = descriptor.terminalEvent.copy(sequence = descriptor.highestSequence + 1)
        val advanced = observed.copy(descriptor = descriptor.copy(highestSequence = advancedEvent.sequence,
            terminalEvent = advancedEvent, events = listOf(advancedEvent)))
        assertNotEquals(first["recordBindingSha256"],
            debugCallJournalSnapshot(nonce) { advanced }["recordBindingSha256"])
    }

    @Test fun invalidNonceNeverReadsOrInitializesAnything() {
        for (invalid in listOf("", "a".repeat(15), "a".repeat(65), "ABCDEF1234567890", "../../private")) {
            val result = debugCallJournalSnapshot(invalid) { error("must not observe") }
            assertEquals(mapOf("status" to "rejected", "reason" to "invalid_nonce"), result)
        }
    }

    @Test fun missingRuntimeAndFailedProtectedReadCannotBeConfusedWithEmptyRecord() {
        assertEquals("runtime_unavailable", debugCallJournalSnapshot(nonce) { null }["reason"])
        val failed = debugCallJournalSnapshot(nonce) { error("secret exception / private handle") }
        assertEquals("read_failed", failed["reason"])
        assertFalse(failed.toString().contains("secret"))
        val empty = debugCallJournalSnapshot(nonce) { MknoonCallJournalObservation(null, false, false) }
        assertEquals("empty", empty["recordState"])
        assertFalse(empty.containsKey("callBindingSha256"))
    }

    @Test fun liveOwnerCleanupAndActiveRecordRemainDistinctFromIdleTerminal() {
        val terminal = terminal()
        assertEquals(true, debugCallJournalSnapshot(nonce) { terminal.copy(liveOwnerPresent = true) }["liveOwnerPresent"])
        assertEquals(true, debugCallJournalSnapshot(nonce) { terminal.copy(cleanupPending = true) }["cleanupPending"])
        val active = terminal.copy(descriptor = terminal.descriptor!!.copy(terminalEvent = null, events = emptyList()))
        assertEquals("active", debugCallJournalSnapshot(nonce) { active }["recordState"])
        assertFalse(debugCallJournalSnapshot(nonce) { active }.containsKey("terminalType"))
    }

    @Test fun ambiguousTerminalIdentityAndSequenceFailClosed() {
        val observed = terminal()
        val descriptor = observed.descriptor!!
        for (bad in listOf(
            descriptor.copy(highestSequence = descriptor.highestSequence + 1),
            descriptor.copy(terminalEvent = descriptor.terminalEvent!!.copy(nativeCallId = UUID.randomUUID())),
            descriptor.copy(events = emptyList()),
        )) {
            assertEquals("invalid_record", debugCallJournalSnapshot(nonce) { observed.copy(descriptor = bad) }["reason"])
        }
    }

    @Test fun readFailureDoesNotAcknowledgeOrDeleteTheJournal() {
        val rig = LifecycleRig()
        rig.controller.present(rig.payload)
        val before = rig.store.lastDescriptor
        val operations = rig.operations.toList()
        rig.store.snapshotFailuresRemaining = 1
        assertEquals("read_failed", debugCallJournalSnapshot(nonce, rig.controller::observeJournal)["reason"])
        assertEquals(before, rig.store.lastDescriptor)
        assertEquals(operations, rig.operations)
        assertEquals(0, rig.store.deleteCalls)
        assertTrue(rig.store.acknowledgementCalls.isEmpty())
    }
}
