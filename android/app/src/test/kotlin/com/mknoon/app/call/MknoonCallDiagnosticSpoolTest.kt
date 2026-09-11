package com.mknoon.app.call

import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import java.util.UUID

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class MknoonCallDiagnosticSpoolTest {
    private class Memory : MknoonCallDiagnosticBackend {
        var bytes: ByteArray? = null
        var fail = false
        var writes = 0
        override fun read() = bytes
        override fun replace(bytes: ByteArray) { check(!fail); this.bytes = bytes.copyOf(); writes++ }
    }
    private val handle = "123e4567-e89b-42d3-a456-426614174000"
    private val trace = "223e4567-e89b-42d3-a456-426614174001"
    @Suppress("UNCHECKED_CAST")
    private fun events(store: MknoonCallDiagnosticSpool) = store.drain(64)["events"] as List<Map<String, Any>>

    @Test fun queuedCallObservationsShareWriteAndPreserveTerminalAndBinding() {
        val memory = Memory(); val store = MknoonCallDiagnosticSpool(memory)
        assertTrue(store.configure(true)); assertTrue(store.bind(handle, trace))
        val writes = memory.writes
        repeat(63) { assertTrue(store.append(handle, "audio", "snapshot", "ok", deferPersistence = true)) }
        assertTrue(store.append(handle, "terminal", "commit", "ok", deferPersistence = true))
        assertEquals(writes, memory.writes); assertTrue(store.persistPending()); assertEquals(writes + 1, memory.writes)
        val rows = events(store); assertEquals(64, rows.size); assertEquals("terminal", rows.last()["stage"])
        assertTrue(rows.all { it["traceId"] == trace })
    }
    @Test fun deferredSinkFailureDropsOnlyUncommittedObservations() {
        val memory = Memory(); val store = MknoonCallDiagnosticSpool(memory); store.configure(true)
        store.append(handle, "answer", "commit", "ok")
        repeat(64) { store.append(handle, "audio", "snapshot", "ok", deferPersistence = true) }
        memory.fail = true; assertFalse(store.persistPending())
        assertEquals(1, events(store).size); assertEquals(64L, store.drain(64)["droppedEvents"])
    }
    @Test fun optOutBeforeQueuedFlushCannotResurrectCallEvidence() {
        val memory = Memory(); val store = MknoonCallDiagnosticSpool(memory); store.configure(true, 10)
        store.append(handle, "answer", "commit", "ok", deferPersistence = true); store.recordDropped(20)
        assertTrue(store.configure(false, 11)); assertTrue(store.persistPending())
        assertTrue(events(MknoonCallDiagnosticSpool(memory)).isEmpty()); assertEquals(0L, store.drain(64)["droppedEvents"])
    }
    @Test fun deferredAppendReplacesExpiredBindingBeforeRecordingFreshCall() {
        var now = 1_900_000_000_000L
        val store = MknoonCallDiagnosticSpool(Memory(), { now }, { 1 })
        store.configure(true); store.bind(handle, trace)
        now += MknoonCallDiagnosticSpool.RETENTION_MS + 1
        store.append(handle, "answer", "commit", "ok", deferPersistence = true)
        assertTrue(store.persistPending())
        val fresh = events(store).single()["traceId"]
        assertNotEquals(trace, fresh); assertEquals(fresh, store.lookup(handle)["traceId"])
        store.append(handle, "audio", "activate", "ok", deferPersistence = true)
        assertTrue(store.persistPending()); assertTrue(events(store).all { it["traceId"] == fresh })
    }

    @Test fun buildIsStampedAtCreationAndNeverRewrittenOnRestart() {
        val memory = Memory()
        val original = MknoonCallDiagnosticSpool(memory, installedBuild = "1.2.3+100")
        original.configure(true); original.append(handle, "push", "receive", "ok")
        val first = events(original).single()
        assertEquals("1.2.3+100", first["build"])
        val upgraded = MknoonCallDiagnosticSpool(memory, installedBuild = "1.2.4+101")
        assertEquals("1.2.3+100", events(upgraded).first()["build"])
        upgraded.append(handle, "admission", "start", "started")
        assertEquals("1.2.4+101", events(upgraded).last()["build"])
        val legacyMemory = Memory(); val legacy = MknoonCallDiagnosticSpool(legacyMemory)
        legacy.configure(true); legacy.append(handle, "push", "receive", "ok")
        assertFalse(events(MknoonCallDiagnosticSpool(legacyMemory, installedBuild = "1.2.4+101")).first().containsKey("build"))
        val invalid = MknoonCallDiagnosticSpool(Memory(), installedBuild = "private error / token")
        invalid.configure(true); invalid.append(handle, "push", "receive", "ok")
        assertFalse(events(invalid).single().containsKey("build"))
    }
    @Test fun terminalCommandReasonNeverInventsAUserAction() {
        assertEquals("no_answer", MknoonCallDiagnosticSpool.journalReason(PendingNativeCallEventType.END_REQUESTED, mapOf("cause" to "no_answer")))
        assertEquals("local_user", MknoonCallDiagnosticSpool.journalReason(PendingNativeCallEventType.END_REQUESTED, mapOf("cause" to "local_user")))
        for (input in listOf(emptyMap(), mapOf("cause" to "none"), mapOf("cause" to "private error"))) {
            assertEquals("unknown", MknoonCallDiagnosticSpool.journalReason(PendingNativeCallEventType.END_REQUESTED, input))
        }
    }
    @Test fun disabledByDefaultAndOptOutErasesBindingsAndEvents() {
        val memory = Memory(); val store = MknoonCallDiagnosticSpool(memory)
        store.append(handle, "push", "receive", "ok")
        assertTrue(events(store).isEmpty())
        assertFalse(store.bind(handle, trace))
        assertTrue(store.configure(true)); assertTrue(store.bind(handle, trace))
        store.append(handle, "answer", "commit", "ok")
        assertEquals(trace, events(store).single()["traceId"])
        assertTrue(store.configure(false)); assertTrue(events(MknoonCallDiagnosticSpool(memory)).isEmpty())
        assertFalse(String(memory.bytes!!).contains(handle))
    }
    @Test fun restartRetainsUnackedEvidenceAndReportsUnknownInterruption() {
        val memory = Memory(); val store = MknoonCallDiagnosticSpool(memory)
        store.configure(true); store.bind(handle, trace)
        store.append(handle, "answer", "commit", "ok")
        val original = events(store).single()
        val recovered = MknoonCallDiagnosticSpool(memory)
        // JSON integral widths may decode as Int or Long; wire values are identical.
        assertEquals(org.json.JSONObject(original).toString(), org.json.JSONObject(events(recovered).first()).toString())
        assertEquals("interrupted_before_final_record", events(recovered).last()["reason"])
        assertTrue(recovered.ack(listOf(original["eventId"] as String)))
        assertTrue(events(recovered).none { it["eventId"] == original["eventId"] })
        recovered.append(handle, "audio", "activate", "ok")
        assertEquals(trace, events(recovered).last()["traceId"])
    }
    @Test fun diagnosticAckFailureKeepsTheBatchRetryable() {
        val memory = Memory(); val store = MknoonCallDiagnosticSpool(memory)
        store.configure(true); store.append(handle, "answer", "commit", "ok")
        val event = events(store).single(); memory.fail = true
        assertFalse(store.ack(listOf(event["eventId"] as String)))
        assertEquals(event, events(store).single())
    }
    @Test fun storageFailureCannotEscapeAnObservation() {
        val memory = Memory(); val store = MknoonCallDiagnosticSpool(memory)
        store.configure(true); memory.fail = true
        store.append(handle, "answer", "commit", "ok")
        assertTrue(events(store).isEmpty())
    }
    @Test fun outputDropsPrivateFieldsAndCanonicalIdentityCannotBecomeTrace() {
        val store = MknoonCallDiagnosticSpool(Memory()); store.configure(true)
        assertFalse(store.bind(handle, handle))
        store.append(handle, "secret-token", "arbitrary-error", "contact-name", "10.1.2.3",
            values = mapOf("token" to "private-token", "durationMs" to 12L, "connected" to true, "route" to "private-device", "count" to -1),
            context = mapOf("traceId" to handle, "operationId" to handle))
        val output = events(store).single().toString()
        for (secret in listOf(handle, "private-token", "private-device", "10.1.2.3", "contact-name", "arbitrary-error", "secret-token")) assertFalse(output.contains(secret))
        assertTrue(output.contains("durationMs=12")); assertTrue(output.contains("connected=true"))
    }
    @Test fun perAttemptQuotaIsBoundedAndDrainNeverExceedsSixtyFour() {
        val store = MknoonCallDiagnosticSpool(Memory()); store.configure(true); store.bind(handle, trace)
        repeat(300) { store.append(handle, "audio", "snapshot", "ok") }
        assertEquals(64, events(store).size)
        assertTrue((store.drain(1000)["droppedEvents"] as Long) > 0)
        var count = 0
        while (events(store).isNotEmpty()) { val batch = events(store); count += batch.size; store.ack(batch.map { it["eventId"] as String }) }
        assertTrue(count <= 256)
    }
    @Test fun oldEventsExpireAndTraceBindingSurvivesDiagnosticAck() {
        var now = 1_900_000_000_000L
        val store = MknoonCallDiagnosticSpool(Memory(), now = { now }, elapsed = { 1L })
        store.configure(true); store.bind(handle, trace); store.append(handle, "answer", "commit", "ok")
        val event = events(store).single(); store.ack(listOf(event["eventId"] as String))
        store.append(handle, "audio", "activate", "ok"); assertEquals(trace, events(store).single()["traceId"])
        now += MknoonCallDiagnosticSpool.RETENTION_MS + 1
        assertTrue(events(store).isEmpty())
    }
    @Test fun laterSharedBindingRetagsOnlyTheSamePrivateCall() {
        val store = MknoonCallDiagnosticSpool(Memory()); store.configure(true)
        store.append(handle, "push", "receive", "ok")
        store.append(UUID.randomUUID().toString(), "push", "receive", "ok")
        assertTrue(store.bind(handle, trace))
        assertEquals(trace, events(store)[0]["traceId"])
        assertNotEquals(trace, events(store)[1]["traceId"])
    }
    @Test fun staleOrConflictingConsentCannotReenableAfterDisableClearOrRestart() {
        val memory = Memory(); val store = MknoonCallDiagnosticSpool(memory)
        assertTrue(store.configure(true, 10)); store.append(handle, "answer", "commit", "ok")
        assertTrue(store.configure(false, 11)); assertTrue(store.clear())
        val restarted = MknoonCallDiagnosticSpool(memory)
        assertFalse(restarted.configure(true, 10)); assertFalse(restarted.configure(true, 11))
        assertFalse(restarted.configure(true)); assertTrue(restarted.configure(false, 11))
        restarted.append(handle, "audio", "activate", "ok"); assertTrue(events(restarted).isEmpty())
        assertTrue(restarted.configure(true, 12))
    }
    @Test fun canonicalJournalAckCannotDeleteDiagnosticEvidence() {
        val spool = MknoonCallDiagnosticSpool(Memory()); spool.configure(true)
        val rig = LifecycleRig(journalDiagnostic = { handle, _ -> spool.append(handle, "answer", "commit", "ok") })
        assertEquals(MknoonCallPresentationResult.PRESENTED, rig.controller.present(rig.payload))
        rig.controller.attach()
        assertTrue(rig.controller.markAdopted(rig.payload.nativeCallId))
        val sequence = requireNotNull(rig.controller.snapshot()).highestSequence
        val diagnosticIds = events(spool).map { it["eventId"] }
        assertTrue(rig.controller.acknowledge(rig.payload.nativeCallId, sequence, PendingNativeCallAcknowledgement.ADOPTED))
        assertEquals(diagnosticIds, events(spool).map { it["eventId"] })
    }
    @Test fun compactAuthorityHandlesKeepPrivateTraceBindingAfterCanonicalizationAndRestart() {
        val memory = Memory(); val store = MknoonCallDiagnosticSpool(memory); store.configure(true)
        val compact = "00112233445566778899aabbccddeeff"
        val canonical = "00112233-4455-6677-8899-aabbccddeeff"
        assertTrue(store.bind(compact, trace))
        store.append(canonical, "push", "receive", "ok")
        assertEquals(trace, events(store).single()["traceId"])
        val recovered = MknoonCallDiagnosticSpool(memory)
        recovered.append(canonical, "answer", "commit", "ok")
        assertEquals(trace, events(recovered).last()["traceId"])
    }
    @Test fun failedConsentWriteDisablesCaptureButSameRequestCanRetry() {
        val memory = Memory(); val store = MknoonCallDiagnosticSpool(memory)
        memory.fail = true
        assertFalse(store.configure(true, 10))
        store.append(handle, "answer", "commit", "ok"); assertTrue(events(store).isEmpty())
        memory.fail = false
        assertTrue(store.configure(true, 10))
        memory.fail = true
        assertFalse(store.configure(false, 11))
        store.append(handle, "audio", "activate", "ok"); assertTrue(events(store).isEmpty())
        assertFalse(store.configure(true, 10)); assertFalse(store.configure(true, 11))
        memory.fail = false
        assertTrue(store.configure(false, 11))
        assertTrue(events(MknoonCallDiagnosticSpool(memory)).isEmpty())
    }
    @Test fun lookupRetainsOnlyPrivateBindingAcrossAckRestartAndExpires() {
        var now = 1_900_000_000_000L
        val memory = Memory(); val compact = "00112233445566778899aabbccddeeff"
        val initial = MknoonCallDiagnosticSpool(memory, now = { now })
        assertNull(initial.lookup(compact)["traceId"])
        assertTrue(initial.configure(true, 10)); assertTrue(initial.bind(compact, trace))
        initial.append(compact, "push", "receive", "ok")
        assertTrue(initial.ack(events(initial).map { it["eventId"] as String }))
        val recovered = MknoonCallDiagnosticSpool(memory, now = { now })
        assertEquals(mapOf("version" to 1, "traceId" to trace), recovered.lookup("00112233-4455-6677-8899-aabbccddeeff"))
        assertNull(recovered.lookup(handle)["traceId"])
        now += MknoonCallDiagnosticSpool.RETENTION_MS + 1
        assertNull(recovered.lookup(compact)["traceId"])
        assertTrue(recovered.configure(false, 11)); assertNull(recovered.lookup(compact)["traceId"])
    }
    @Test fun wireCausePreservesClosedNativeReasonAndIgnoresPrivateInput() {
        for (wire in nativeDiagnosticWireContexts().values) {
            val expected = wire - "cause" + ("reason" to requireNotNull(wire["cause"]))
            assertEquals(expected, MknoonCallDiagnosticSpool.context(wire + ("private" to "secret")))
        }
        assertEquals(mapOf("reason" to "resume_refresh"), MknoonCallDiagnosticSpool.context(mapOf("reason" to "resume_refresh")))
        assertTrue(MknoonCallDiagnosticSpool.context(mapOf("cause" to "private-token")).isEmpty())
    }
}

internal fun nativeDiagnosticWireContexts(): Map<String, Map<String, Any>> {
    val fixture = generateSequence(java.io.File(System.getProperty("user.dir"))) { it.parentFile }
        .map { java.io.File(it, "tool/call_diagnostics/wire_fixtures_v1.json") }.first { it.isFile }
    val contexts = org.json.JSONObject(fixture.readText()).getJSONObject("contexts")
    return contexts.keys().asSequence().associateWith { MknoonCallDiagnosticSpool.jsonMap(contexts.getJSONObject(it)) }
}
