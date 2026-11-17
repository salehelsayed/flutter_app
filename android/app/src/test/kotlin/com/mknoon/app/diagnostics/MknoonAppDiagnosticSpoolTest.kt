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
    private val activityProfileA = "v1:" + "a".repeat(64)
    private val activityProfileB = "v1:" + "b".repeat(64)
    private val activityAccountA = "12D3KooWJsEmQWn5WGGn9AZX79emq3RkGNx2ihFwWzZAqbiUQGMF"
    private val activityAccountB = "12D3KooWJsEmQWn5WGGn9AZX79emq3RkGNx2ihFwWzZAqbiUQGMG"

    @Test fun activeIdentityPublishesBeforeHeldConfiguration() {
        val order = mutableListOf<String>()
        val publications = mutableListOf<Triple<MknoonActiveIdentityReporterFence, Boolean, Boolean>>()
        val queued = mutableListOf<() -> Unit>()
        var configured = 0
        val admission = MknoonActiveIdentityReporterAdmission { fence, enabled, preserve ->
            order.add("publish"); publications.add(Triple(fence, enabled, preserve)); true
        }
        val result = admission.admitConfiguration(10, true, activityProfileA, activityAccountA, true)
        assertNotNull("Positive publisher control", result)
        val fence = result!!
        assertEquals(listOf("publish"), order)
        assertEquals(1, publications.size); assertTrue(fence.revision > 0)
        assertEquals(10L, fence.consentEpoch); assertEquals(activityProfileA, fence.profileBinding)
        assertEquals(activityAccountA, fence.accountPeerID)
        assertTrue(publications.single().second); assertFalse(publications.single().third)
        order.add("queued")
        queued.add { if (admission.isCurrent(fence)) configured++ }
        assertEquals(0, configured)
        queued.removeAt(0).invoke()
        assertEquals(listOf("publish", "queued"), order); assertEquals(1, configured)
        assertTrue(admission.admitMark(fence))
    }

    @Test fun activeIdentityOffReceiptFencesHeldConfigurationAndMark() {
        val publications = mutableListOf<Triple<MknoonActiveIdentityReporterFence, Boolean, Boolean>>()
        val queued = mutableListOf<() -> Unit>()
        var configured = 0; var marked = 0
        val admission = MknoonActiveIdentityReporterAdmission { fence, enabled, preserve ->
            publications.add(Triple(fence, enabled, preserve)); true
        }
        val result = admission.admitConfiguration(10, true, activityProfileA, activityAccountA, true)
        assertNotNull("Positive publisher control", result)
        val old = result!!
        assertEquals(1, publications.size)
        queued.add {
            if (admission.isCurrent(old)) configured++
            if (admission.admitMark(old)) marked++
        }
        assertTrue(admission.observeConsent(11, false))
        assertEquals("OFF publication must happen while the background job is held", 2, publications.size)
        val off = publications.last().first
        assertFalse(publications.last().second); assertEquals(11L, off.consentEpoch)
        assertTrue(off.revision > old.revision)
        assertTrue("Current disabled work may still clear durably", admission.isCurrent(off))
        assertFalse(admission.admitMark(off)); assertFalse(admission.isCurrent(old))
        queued.removeAt(0).invoke()
        assertEquals(0, configured); assertEquals(0, marked)
    }

    @Test fun activeIdentityNewProfileRequiresExactCapturedTuple() {
        val published = mutableListOf<MknoonActiveIdentityReporterFence>()
        val admission = MknoonActiveIdentityReporterAdmission { fence, _, _ -> published.add(fence); true }
        val first = admission.admitConfiguration(10, true, activityProfileA, activityAccountA, true)
        assertNotNull(first)
        val old = first!!
        val second = admission.admitConfiguration(10, true, activityProfileB, activityAccountB, true)
        assertNotNull(second)
        val current = second!!
        assertEquals(2, published.size); assertTrue(current.revision > old.revision)
        assertFalse(admission.isCurrent(old)); assertFalse(admission.admitMark(old))
        assertTrue(admission.isCurrent(current)); assertTrue(admission.admitMark(current))
        val mutations = listOf(
            current.copy(revision = current.revision + 1),
            current.copy(consentEpoch = current.consentEpoch + 1),
            current.copy(profileBinding = activityProfileA),
            current.copy(accountPeerID = activityAccountA),
        )
        mutations.forEach { changed ->
            assertFalse(admission.isCurrent(changed)); assertFalse(admission.admitMark(changed))
        }
    }

    @Test fun activeIdentityConsentMirrorCannotRestoreProfileAuthority() {
        val publications = mutableListOf<Triple<MknoonActiveIdentityReporterFence, Boolean, Boolean>>()
        val admission = MknoonActiveIdentityReporterAdmission { fence, enabled, preserve ->
            publications.add(Triple(fence, enabled, preserve)); true
        }
        val result = admission.admitConfiguration(10, true, activityProfileA, activityAccountA, true)
        assertNotNull("Positive full-configuration control", result)
        val initial = result!!
        assertTrue(admission.observeConsent(10, true))
        assertEquals(1, publications.size); assertTrue(admission.admitMark(initial))
        assertFalse(admission.observeConsent(9, false))
        assertTrue(admission.observeConsent(10, false))
        assertFalse(admission.admitMark(initial)); assertEquals(2, publications.size)
        assertTrue(admission.observeConsent(11, false))
        assertFalse(admission.observeConsent(10, true))
        assertFalse(admission.observeConsent(11, true))
        assertTrue(admission.observeConsent(12, true))
        val mirrorOn = publications.last().first
        assertEquals(12L, mirrorOn.consentEpoch); assertTrue(admission.isCurrent(mirrorOn))
        assertFalse("Mirror ON cannot arm without root configuration", admission.admitMark(mirrorOn))
        assertFalse(admission.admitMark(initial))
        assertFalse(admission.admitMark(mirrorOn.copy(
            profileBinding = activityProfileA, accountPeerID = activityAccountA)))
    }

    @Test fun activeIdentitySameScopeRefreshReusesNativeRevision() {
        val published = mutableListOf<MknoonActiveIdentityReporterFence>()
        val admission = MknoonActiveIdentityReporterAdmission { fence, _, _ -> published.add(fence); true }
        val firstResult = admission.admitConfiguration(10, true, activityProfileA, activityAccountA, true)
        assertNotNull(firstResult)
        val first = firstResult!!
        // Restarted Dart callers provide no caller counter or wall-clock revision.
        val refreshed = admission.admitConfiguration(10, true, activityProfileA, activityAccountA, true)
        assertNotNull(refreshed)
        assertEquals(first, refreshed); assertEquals(1, published.size)
        assertTrue(admission.observeConsent(10, true))
        assertEquals(1, published.size); assertTrue(admission.admitMark(first))
        val replacement = admission.admitConfiguration(10, true, activityProfileB, activityAccountB, true)
        assertNotNull(replacement)
        assertTrue(replacement!!.revision > first.revision); assertEquals(2, published.size)
    }

    @Test fun activeIdentityUnarmPolicyAndMalformedRequestsHaveFixedPrivateErrors() {
        val privateError = "b294-native-private-account-signature-error"
        var failPublisher = false
        val publications = mutableListOf<Triple<MknoonActiveIdentityReporterFence, Boolean, Boolean>>()
        val admission = MknoonActiveIdentityReporterAdmission { fence, enabled, preserve ->
            publications.add(Triple(fence, enabled, preserve))
            if (failPublisher) error(privateError)
            true
        }
        val originalResult = admission.admitConfiguration(10, true, activityProfileA, activityAccountA, true)
        assertNotNull(originalResult)
        val original = originalResult!!
        val retiredResult = admission.admitConfiguration(10, true, "", "", false)
        assertNotNull(retiredResult)
        val retired = retiredResult!!
        assertFalse("Discard policy must publish before any background clear", publications.last().third)
        assertTrue(admission.isCurrent(retired)); assertFalse(admission.admitMark(retired))
        assertFalse(admission.isCurrent(original))
        val rebound = admission.admitConfiguration(10, true, activityProfileA, activityAccountA, true)
        assertNotNull(rebound); assertTrue(rebound!!.revision > retired.revision)
        val disposedResult = admission.admitConfiguration(10, true, "", "", false, preservePendingOnUnarm = true)
        assertNotNull(disposedResult)
        val disposed = disposedResult!!
        assertTrue(publications.last().third)
        assertTrue(admission.isCurrent(disposed)); assertFalse(admission.admitMark(disposed))
        data class Bad(val epoch: Long, val profile: String, val account: String, val root: Boolean, val preserve: Boolean = false)
        val malformed = listOf(
            Bad(0, activityProfileA, activityAccountA, true),
            Bad(-1, activityProfileA, activityAccountA, true),
            Bad(10, "", activityAccountA, true), Bad(10, activityProfileA, "", true),
            Bad(10, "not-a-binding", activityAccountA, true),
            Bad(10, activityProfileA + "a", activityAccountA, true),
            Bad(10, activityProfileA, " $activityAccountA", true),
            Bad(10, activityProfileA, "x".repeat(129), true),
            Bad(10, activityProfileA, activityAccountA, false),
            Bad(10, "", "", true), Bad(10, activityProfileA, activityAccountA, true, true),
            Bad(10, privateError, privateError, true),
        )
        val beforeInvalid = publications.size
        malformed.forEach { bad ->
            assertNull(admission.admitConfiguration(bad.epoch, true, bad.profile, bad.account, bad.root, bad.preserve))
            assertEquals("ACTIVE_IDENTITY_INVALID_REQUEST", admission.errorCode)
            assertTrue(admission.isCurrent(disposed))
        }
        assertEquals(beforeInvalid, publications.size)
        failPublisher = true
        assertNull(admission.admitConfiguration(10, true, activityProfileB, activityAccountB, true))
        assertEquals("ACTIVE_IDENTITY_UNAVAILABLE", admission.errorCode)
        assertFalse(admission.errorCode.contains(privateError))
        assertFalse(admission.errorCode.contains(activityAccountB))
        assertFalse(admission.admitMark(publications.last().first))
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
    @Test fun activeIdentitySameEpochAutomaticOffRevokesHeldOwner() {
        val publications = mutableListOf<Triple<MknoonActiveIdentityReporterFence, Boolean, Boolean>>()
        val admission = MknoonActiveIdentityReporterAdmission { fence, enabled, preserve ->
            publications.add(Triple(fence, enabled, preserve)); true
        }
        val armedResult = admission.admitConfiguration(10, true, activityProfileA, activityAccountA, true)
        assertNotNull("Positive full-configuration control", armedResult)
        val armed = armedResult!!
        assertEquals(1, publications.size)
        assertTrue(admission.isCurrent(armed)); assertTrue(admission.admitMark(armed))
        var heldMarkAccepted = false
        val heldMark = {
            if (admission.isCurrent(armed) && admission.admitMark(armed)) heldMarkAccepted = true
        }
        // AppDiagnostics archive failure disables locally without advancing its epoch.
        assertTrue("Same-epoch automatic OFF must publish before returning", admission.observeConsent(10, false))
        assertEquals(2, publications.size)
        val off = publications.last().first
        assertEquals(armed.consentEpoch, off.consentEpoch)
        assertTrue(off.revision > armed.revision)
        assertFalse(publications.last().second); assertFalse(publications.last().third)
        assertTrue(admission.isCurrent(off)); assertFalse(admission.admitMark(off))
        assertFalse(admission.isCurrent(armed)); assertFalse(admission.admitMark(armed))
        heldMark()
        assertFalse(heldMarkAccepted)
        assertFalse(admission.observeConsent(10, true))
        assertNull(admission.admitConfiguration(10, true, activityProfileA, activityAccountA, true))
        assertEquals(2, publications.size); assertTrue(admission.isCurrent(off))
        val rearmedResult = admission.admitConfiguration(11, true, activityProfileA, activityAccountA, true)
        assertNotNull(rearmedResult)
        val rearmed = rearmedResult!!
        assertEquals(3, publications.size); assertTrue(rearmed.revision > off.revision)
        assertTrue(admission.isCurrent(rearmed)); assertTrue(admission.admitMark(rearmed))
        assertFalse(admission.isCurrent(off)); assertFalse(admission.admitMark(armed))
    }

}
