package com.mknoon.app.call

import org.junit.Assert.*
import org.junit.Test

class DebugCallHistorySnapshotTest {
    private val nonce = "1234567890abcdef"
    private fun request() = mutableMapOf<String, Any?>("operation" to "history_snapshot",
        "nonce" to nonce, "historyOperation" to "baseline")
    private fun response() = mutableMapOf<String, Any?>("schema" to "mknoon.debug-call-history.v1",
        "status" to "snapshot", "nonce" to nonce, "operation" to "baseline",
        "observedAtMs" to 123L, "accountBindingSha256" to "a".repeat(64), "totalRows" to 4)
    @Test fun exactReadOnlyGrammarNeverAllowsInjectedOwnerOrSql() {
        val a = request(); assertEquals("baseline", debugHistoryRequest(a.keys, a::get)["operation"])
        for (key in listOf("_nativeCallId", "sql", "path", "account")) {
            val bad = a + (key to "secret")
            assertThrows(IllegalArgumentException::class.java) { debugHistoryRequest(bad.keys, bad::get) }
        }
    }
    @Test fun lookupRequiresOpaqueBindingsAndTypedBoundedTimestamps() {
        val a = request().apply { put("historyOperation", "lookup"); put("callBindingSha256", "b".repeat(64))
            put("accountBindingSha256", "a".repeat(64)); put("sinceMs", 1L); put("untilMs", 2L) }
        assertEquals(1L, debugHistoryRequest(a.keys, a::get)["sinceMs"])
        for (bad in listOf(a + ("sinceMs" to "1"), a + ("callBindingSha256" to "raw UUID"))) {
            assertThrows(IllegalArgumentException::class.java) { debugHistoryRequest(bad.keys, bad::get) }
        }
    }
    @Test fun outputDropsUnknownFieldsWrongNonceAndUnhashedIdentity() {
        val good = response(); assertEquals(good, debugHistoryResponse(good, nonce, "baseline"))
        for (bad in listOf(good + ("rawCallId" to "secret"), good + ("nonce" to "other"),
            good + ("accountBindingSha256" to "private account"), good + ("totalRows" to 1.5))) {
            assertEquals(mapOf("status" to "unavailable"), debugHistoryResponse(bad, nonce, "baseline"))
        }
    }
    @Test fun replyCannotBeUsedForAnotherModeOrNativeOwner() {
        val current = response().apply { put("operation", "current"); put("callBindingSha256", "c".repeat(64))
            put("nativeCallBindingSha256", "d".repeat(64)); put("matchingRows", 0); put("startedAtMs", 1L) }
        assertEquals(current, debugHistoryResponse(current, nonce, "current", "d".repeat(64)))
        assertEquals("unavailable", debugHistoryResponse(current, nonce, "current", "e".repeat(64))["status"])
        assertEquals("unavailable", debugHistoryResponse(current, nonce, "baseline")["status"])
    }
    @Test fun heldReplyAfterEngineCutoverOrDeadlineCannotPublishAndCompletesOnlyOnce() {
        for (late in listOf(false, true)) {
            var now = 10L; var valid = true
            val output = mutableListOf<Map<String, Any?>>()
            val gate = DebugCallEvidenceReplyGate(now, { now }, { valid }, output::add)
            if (late) now += 5001 else valid = false
            gate.complete { response() }
            valid = true; now = 10L
            gate.complete { response() }
            assertEquals(listOf(mapOf("status" to "unavailable")), output)
        }
    }
    @Test fun inBudgetReplyUsesCurrentAuthorityAndThrowingReadFailsClosed() {
        val output = mutableListOf<Map<String, Any?>>()
        DebugCallEvidenceReplyGate(10, { 5010 }, { true }, output::add).complete { response() }
        assertEquals(response(), output.single())
        output.clear()
        DebugCallEvidenceReplyGate(10, { 11 }, { error("secret") }, output::add).complete { response() }
        assertEquals(mapOf("status" to "unavailable"), output.single())
    }

    @Test fun ownerReadThatCompletesPastDeadlineCannotCertifyAReply() {
        var now = 0L
        val output = mutableListOf<Map<String, Any?>>()
        val gate = DebugCallEvidenceReplyGate(0, { now }, { now = 5001; true }, output::add)
        gate.complete { response() }
        assertEquals(mapOf("status" to "unavailable"), output.single())
    }

}
