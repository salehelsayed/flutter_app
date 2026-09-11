package com.mknoon.app.diagnostics

import java.io.File
import java.util.UUID
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [30])
class MknoonAppDiagnosticSpoolTest {
    private class Memory : MknoonAppDiagnosticBackend {
        var bytes: ByteArray? = null
        var fail = false
        var writes = 0
        override fun read() = bytes
        override fun replace(bytes: ByteArray) { check(!fail); this.bytes = bytes.copyOf(); writes++ }
    }
    private fun spool(memory: Memory, now: () -> Long = { 1_900_000_000_000L }, build: String = "1.0.1+112") = MknoonAppDiagnosticSpool(memory, now, { 500 }, build)
    @Suppress("UNCHECKED_CAST")
    private fun events(store: MknoonAppDiagnosticSpool) = store.drain(64)["events"] as List<Map<String, Any>>
    @Test fun slowWriterAdmissionIsBoundedAndRecoversWithoutBlockingControls() {
        val admission = MknoonAppDiagnosticAdmission()
        val queued = mutableListOf<() -> Unit>()
        var accepted = 0; var dropped = 0L; var control = false
        repeat(10_000) { admission.enqueue({ queued.add(it) }) { lost -> accepted++; dropped += lost } }
        assertEquals(64, queued.size)
        queued.add { control = true } // Consent/ACK bypass event admission.
        queued.toList().forEach { it() }; queued.clear()
        assertTrue(control); assertEquals(64, accepted); assertEquals(9_936L, dropped)
        admission.enqueue({ queued.add(it) }) { accepted++ }
        queued.single()(); assertEquals(65, accepted)
    }
    @Test fun rejectedWriterSubmissionNeverEscapesAndReleasesAdmission() {
        val admission = MknoonAppDiagnosticAdmission(1)
        admission.enqueue({ error("writer unavailable") }) { error("must not execute") }
        var dropped = 0L
        admission.enqueue({ it() }) { dropped = it; error("sink failed") }
        assertEquals(1L, dropped)
        var next = false; admission.enqueue({ it() }) { next = true }; assertTrue(next)
    }
    @Test fun queuedObservationsShareOneWriteAndControlPersistsCurrentState() {
        val memory = Memory(); val store = spool(memory); assertTrue(store.configure(true, 10))
        val initial = memory.writes
        repeat(64) { assertTrue(store.append("runtime", "bridge", "ok", deferPersistence = true)) }
        assertEquals(initial, memory.writes)
        assertTrue(store.persistPending()); assertEquals(initial + 1, memory.writes)
        assertEquals(64, events(store).size)
        store.recordDropped(100)
        assertTrue(store.append("push", "receive", "ok", deferPersistence = true))
        assertTrue(store.configure(false, 11))
        assertTrue(store.persistPending()); assertTrue(events(spool(memory)).isEmpty())
        assertEquals(0L, store.drain(64)["droppedEvents"])
    }
    @Test fun failedDeferredWriteRemainsRetryableAndCountsOverflow() {
        val memory = Memory(); val store = spool(memory); store.configure(true, 10)
        store.recordDropped(20)
        repeat(64) { store.append("push", "receive", "ok", deferPersistence = true) }
        memory.fail = true; assertFalse(store.persistPending())
        memory.fail = false; assertTrue(store.persistPending())
        assertEquals(64, events(store).size); assertEquals(20L, store.drain(64)["droppedEvents"])
    }
    @Test fun defaultOffAndExplicitOffSurviveRestart() {
        val memory = Memory(); val store = spool(memory)
        assertFalse(store.append("push", "receive", "ok")); assertTrue(events(store).isEmpty())
        assertTrue(store.configure(true, 10)); assertTrue(store.append("push", "receive", "ok"))
        assertTrue(store.configure(false, 11)); assertTrue(store.clear())
        val restarted = spool(memory)
        assertFalse(restarted.configure(true, 10)); assertFalse(restarted.configure(true, 11)); assertFalse(restarted.configure(true, null))
        assertTrue(events(restarted).isEmpty()); assertTrue(restarted.configure(false, 11))
        assertTrue(restarted.configure(true, 12))
    }
    @Test fun drainNeverDeletesAndAckIsDurableBeforeRemoval() {
        val memory = Memory(); val store = spool(memory); store.configure(true, 10)
        store.append("startup", "launch", "started")
        val original = events(store).first(); assertEquals(original, events(store).first())
        val id = original["eventId"] as String
        memory.fail = true; assertFalse(store.ack(listOf(id))); assertEquals(id, events(store).first()["eventId"])
        memory.fail = false; assertTrue(store.ack(listOf(id)))
        assertFalse(events(spool(memory)).any { it["eventId"] == id })
    }
    @Test fun unclosedRunIsOnlyUnknownInterruptionAndRetainsOriginalBuild() {
        val memory = Memory(); val original = spool(memory, build = "1.0.1+112"); original.configure(true, 10)
        original.append("startup", "launch", "started")
        val recovered = spool(memory, build = "1.0.2+113")
        assertEquals("1.0.1+112", events(recovered).first()["build"])
        assertEquals("interrupted_unknown", events(recovered).last()["outcome"])
        assertFalse(events(recovered).any { it["reason"] == "os_crash" })
    }
    @Test fun failedConsentWriteDisablesCaptureAndPermitsExactRetry() {
        val memory = Memory(); val store = spool(memory)
        memory.fail = true; assertFalse(store.configure(true, 10)); assertFalse(store.append("push", "receive", "ok"))
        memory.fail = false; assertTrue(store.configure(true, 10)); store.append("push", "receive", "ok")
        memory.fail = true; assertFalse(store.configure(false, 11)); assertFalse(store.append("push", "receive", "ok"))
        assertFalse(store.configure(true, 10)); assertFalse(store.configure(true, 11))
        memory.fail = false; assertTrue(store.configure(false, 11)); assertTrue(events(spool(memory)).isEmpty())
    }
    @Test fun unknownFieldsRawErrorsAndIdentifiersNeverExport() {
        val memory = Memory(); val store = spool(memory, build = "/private/device/file")
        store.configure(true, 10)
        assertTrue(store.append("runtime", "bridge", "failed", "unknown", mapOf("error" to "private-token", "path" to "/private/file", "count" to 2, "errorClass" to "platform", "fingerprint" to "secret"), "raw-peer-id"))
        val encoded = JSONObject(events(store).first()).toString()
        assertFalse(encoded.contains("private-token")); assertFalse(encoded.contains("/private")); assertFalse(encoded.contains("raw-peer"))
        assertFalse(encoded.contains("secret")); assertFalse(events(store).first().containsKey("traceId")); assertEquals("unknown", events(store).first()["build"])
        assertFalse(store.append("private-text", "bridge", "failed"))
        assertFalse(store.ack(listOf("raw-peer-id")))
    }
    @Test fun quotasAndRetentionAreBoundedWithDropAccounting() {
        var now = 1_900_000_000_000L; val memory = Memory(); val store = spool(memory, { now }); store.configure(true, 10)
        repeat(400) { store.append("runtime", "snapshot", "ok") }
        val count = JSONObject(String(memory.bytes!!)).getJSONArray("events").length()
        assertTrue(count <= 256); assertTrue((store.drain(1000)["events"] as List<*>).size <= 64)
        assertTrue((store.drain(64)["droppedEvents"] as Long) > 0); assertTrue(memory.bytes!!.size <= MknoonAppDiagnosticSpool.MAX_BYTES)
        now += MknoonAppDiagnosticSpool.RETENTION_MS + 1; assertTrue(events(store).isEmpty())
    }
    @Test fun osExitEvidenceIsTypedDeduplicatedAndNeverBackfilledBeforeConsent() {
        var now = 1_900_000_000_000L; val memory = Memory(); val store = spool(memory, { now }); store.configure(true, 10)
        assertFalse(store.importExit(4, now - 1)); now += 10
        assertTrue(store.importExit(4, now)); assertFalse(store.importExit(4, now))
        assertEquals("os_crash", events(store).last()["reason"]); assertEquals("unknown", events(store).last()["build"])
        assertFalse(spool(memory, { now }).importExit(4, now))
        assertEquals("hang" to "os_anr", MknoonAppDiagnosticSpool.exitReason(6))
        assertEquals("recovery" to "unknown", MknoonAppDiagnosticSpool.exitReason(10))
        store.configure(false, 11); now += 10; store.configure(true, 12); assertFalse(store.importExit(4, now - 1))
    }
    @Test fun failedOsWriteCannotConsumeReportOrLoseItAfterRestart() {
        var now = 1_900_000_000_000L; val memory = Memory(); val store = spool(memory, { now }); store.configure(true, 10); now += 1
        memory.fail = true; assertFalse(store.importExit(6, now))
        memory.fail = false; val restarted = spool(memory, { now }); assertTrue(restarted.importExit(6, now))
        assertEquals(1, events(restarted).count { it["reason"] == "os_anr" })
    }
    @Test fun fingerprintContainsOnlyAppFramesAndIgnoresPrivateText() {
        val frame = "    at com.mknoon.app.GoBridge.handle(GoBridge.kt:123)"
        val first = MknoonAppDiagnosticFingerprint.appFrames("token-secret\n$frame\n    at vendor.External.run(External.kt:999)")
        assertNotNull(first); assertTrue(Regex("^[0-9a-f]{64}$").matches(first!!))
        assertEquals(first, MknoonAppDiagnosticFingerprint.appFrames("different-private-path\n$frame"))
        assertNull(MknoonAppDiagnosticFingerprint.appFrames("token-secret\n    at vendor.External.run(External.kt:999)"))
        assertNull(MknoonAppDiagnosticFingerprint.appFrames("    at com.mknoon.app.X.run(/private/file:12)"))
    }
    @Test fun bridgeClassificationNeverUsesRawMessagesAndPreservesDelegateOnSinkFailure() {
        val received = mutableListOf<Any?>()
        val delegate = object : MethodChannel.Result {
            override fun success(result: Any?) { received.add(result) }
            override fun error(code: String, message: String?, details: Any?) { received.add(listOf(code, message, details)) }
            override fun notImplemented() { received.add("notImplemented") }
        }
        val wrapped = MknoonAppDiagnosticBridgeResult.wrap("blobDecrypt", null, delegate, { _, _, _, _ -> error("sink unavailable") }, { 1 })
        val response = "{\"ok\":false,\"errorCode\":\"DECRYPT_IO_ERROR\",\"errorMessage\":\"private-file\"}"
        assertEquals("failed" to "io_failed", MknoonAppDiagnosticBridgeResult.response(response))
        assertEquals("failed" to "auth_failed", MknoonAppDiagnosticBridgeResult.response("{\"ok\":false,\"errorCode\":\"DECRYPT_AUTH_ERROR\"}"))
        assertEquals("failed" to "unknown", MknoonAppDiagnosticBridgeResult.response("{\"ok\":false,\"errorCode\":\"private-secret\"}"))
        assertEquals("unknown" to "unknown", MknoonAppDiagnosticBridgeResult.response("x".repeat(16385)))
        wrapped.success(response); wrapped.error("PRIVATE", "private-message", 12); wrapped.notImplemented()
        assertEquals(listOf(response, listOf("PRIVATE", "private-message", 12), "notImplemented"), received)
    }
    @Test fun bridgeEmitsBoundedSharedTraceAndDoesNotInstrumentUploader() {
        val trace = UUID.randomUUID().toString(); val recorded = mutableListOf<List<Any>>()
        val delegate = object : MethodChannel.Result {
            override fun success(result: Any?) {}
            override fun error(code: String, message: String?, details: Any?) {}
            override fun notImplemented() {}
        }
        val wrapped = MknoonAppDiagnosticBridgeResult.wrap("startNode", "{\"diagnostics\":{\"traceId\":\"$trace\"}}", delegate,
            { outcome, reason, _, id -> recorded.add(listOf(outcome, reason, id)) }, { 10 })
        wrapped.success("{\"ok\":true}")
        assertEquals(listOf(listOf("started", "none", trace), listOf("ok", "none", trace)), recorded)
        assertSame(delegate, MknoonAppDiagnosticBridgeResult.wrap("appDiagnosticsV1", null, delegate, { _, _, _, _ -> error("must not instrument upload") }))
    }
    @Test fun corruptedOptionalUuidIsDroppedOnRecovery() {
        val memory = Memory(); val active = spool(memory); active.configure(true, 10); active.append("push", "receive", "ok")
        val stored = JSONObject(String(memory.bytes!!)); val old = stored.getJSONArray("events").getJSONObject(0)
        val id = old.getString("eventId"); old.put("reportingRunId", "raw-device-id")
        memory.bytes = stored.toString().toByteArray()
        assertFalse(events(spool(memory)).any { it["eventId"] == id })
    }
    @Test fun canonicalVocabularyMatchesNativeCopy() {
        val root = generateSequence(File(requireNotNull(System.getProperty("user.dir")))) { it.parentFile }.first { File(it, "tool/app_diagnostics/schema_v1.json").exists() }
        val schema = JSONObject(File(root, "tool/app_diagnostics/schema_v1.json").readText())
        val copies = mapOf("required" to MknoonAppDiagnosticSchema.required, "optional" to MknoonAppDiagnosticSchema.optional,
            "feature" to MknoonAppDiagnosticSchema.feature, "stage" to MknoonAppDiagnosticSchema.stage, "outcome" to MknoonAppDiagnosticSchema.outcome,
            "reason" to MknoonAppDiagnosticSchema.reason, "booleanValues" to MknoonAppDiagnosticSchema.booleanValues,
            "integerValues" to MknoonAppDiagnosticSchema.integerValues, "hashValues" to MknoonAppDiagnosticSchema.hashValues, "uuidFields" to MknoonAppDiagnosticSchema.uuidFields)
        for ((key, expected) in copies) { val rows = schema.getJSONArray(key); assertEquals(expected, (0 until rows.length()).map { rows.getString(it) }.toSet()) }
        val enums = schema.getJSONObject("enumValues")
        assertEquals(MknoonAppDiagnosticSchema.enumValues.keys, enums.keys().asSequence().toSet())
        for ((key, expected) in MknoonAppDiagnosticSchema.enumValues) { val rows = enums.getJSONArray(key); assertEquals(expected, (0 until rows.length()).map { rows.getString(it) }.toSet()) }
    }
}
