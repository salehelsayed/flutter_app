package com.mknoon.app.call

import java.nio.charset.StandardCharsets
import java.util.UUID
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class CallPayloadParserTest {
    @Test
    fun `exact relay call wake is admitted and maps the call handle deterministically`() {
        val parser = CallPayloadParser(nowMs = { NOW_MS })

        val first = accepted(parser.parse(validEntries(), hasNotification = false))
        val second = accepted(parser.parse(validEntries(), hasNotification = false))

        assertEquals(UUID.fromString("00112233-4455-6677-8899-aabbccddeeff"), first.nativeCallId)
        assertEquals(first.nativeCallId, second.nativeCallId)
        assertEquals("00112233-4455-6677-8899-aabbccddeeff", first.callHandle)
        assertEquals(WAKE_HANDLE_A, first.wakeHandle)
        assertEquals(NOW_MS, first.receivedAtMs)
        assertEquals(NOW_MS + CallPayloadParser.MAX_FUTURE_SKEW_MS, first.expiresAtMs)
        assertEquals(45_000L, CallPayloadParser.MAX_FUTURE_SKEW_MS)
        assertEquals(256, CallPayloadParser.MAX_PAYLOAD_BYTES)
    }

    @Test
    fun `field order is irrelevant but the five relay fields and values are exact`() {
        val parser = CallPayloadParser(nowMs = { NOW_MS })
        val shuffled = listOf(
            "e" to (NOW_MS + 1L).toString(),
            "h" to WAKE_HANDLE_A,
            "v" to "1",
            "c" to CALL_HANDLE_A,
            "w" to "call",
        )

        val payload = accepted(parser.parse(shuffled, hasNotification = false))

        assertEquals(NOW_MS + 1L, payload.expiresAtMs)
    }

    @Test
    fun `canonical UUID call handles used by Dart signaling remain opaque and deterministic`() {
        val parser = CallPayloadParser(nowMs = { NOW_MS })
        val canonicalCallHandle = "33333333-3333-4333-8333-333333333333"
        val entries = validEntries().map { entry ->
            if (entry.first == "c") entry.first to canonicalCallHandle else entry
        }

        val payload = accepted(parser.parse(entries, hasNotification = false))

        assertEquals(UUID.fromString(canonicalCallHandle), payload.nativeCallId)
        assertEquals(canonicalCallHandle, payload.callHandle)
    }

    @Test
    fun `compact and canonical aliases normalize to one internal call handle`() {
        val parser = CallPayloadParser(nowMs = { NOW_MS })
        val compact = "33333333333343338333333333333333"
        val canonical = "33333333-3333-4333-8333-333333333333"
        fun parse(callHandle: String) = accepted(
            parser.parse(
                validEntries().map { entry ->
                    if (entry.first == "c") entry.first to callHandle else entry
                },
                hasNotification = false,
            ),
        )

        val compactPayload = parse(compact)
        val canonicalPayload = parse(canonical)

        assertEquals(compactPayload.nativeCallId, canonicalPayload.nativeCallId)
        assertEquals(canonical, compactPayload.callHandle)
        assertEquals(canonical, canonicalPayload.callHandle)
    }

    @Test
    fun `notification unknown duplicate and oversized shapes reject before admission`() {
        val parser = CallPayloadParser(nowMs = { NOW_MS })
        val oversized = validEntries().map { entry ->
            if (entry.first == "h") entry.first to "é".repeat(128) else entry
        }
        assertTrue(payloadBytes(oversized) > CallPayloadParser.MAX_PAYLOAD_BYTES)
        val cases = listOf(
            RejectionCase(
                entries = validEntries(),
                hasNotification = true,
                reason = CallPayloadRejectionReason.NOT_DATA_ONLY,
            ),
            RejectionCase(
                entries = validEntries() + ("x" to "opaque-extension"),
                reason = CallPayloadRejectionReason.INVALID_SHAPE,
            ),
            RejectionCase(
                entries = validEntries() + ("e" to (NOW_MS + 2L).toString()),
                reason = CallPayloadRejectionReason.DUPLICATE_KEY,
            ),
            RejectionCase(
                entries = oversized,
                reason = CallPayloadRejectionReason.TOO_LARGE,
            ),
        )
        val admitted = mutableListOf<CallWakePayload>()

        for (case in cases) {
            val result = parser.parse(case.entries, case.hasNotification)
            if (result is CallPayloadParseResult.Accepted) admitted += result.payload
            assertEquals(case.reason, rejected(result).reason)
        }

        assertTrue(admitted.isEmpty())
    }

    @Test
    fun `malformed keys handles and strict millisecond expiry reject`() {
        val parser = CallPayloadParser(nowMs = { NOW_MS })
        val malformed = listOf(
            validEntries().filterNot { it.first == "e" },
            replace("v", "01"),
            replace("v", " 1"),
            replace("w", "Call"),
            replace("w", "call "),
            replace("c", CALL_HANDLE_A.uppercase()),
            replace("c", CALL_HANDLE_A.dropLast(1)),
            replace("c", "00112233-4455-1677-8899-aabbccddeeff"),
            replace("c", "g" + CALL_HANDLE_A.drop(1)),
            replace("h", WAKE_HANDLE_A.uppercase()),
            replace("h", WAKE_HANDLE_A + "0"),
            replace("e", "${NOW_MS + 1L} "),
            replace("e", "+${NOW_MS + 1L}"),
            replace("e", "0${NOW_MS + 1L}"),
            replace("e", "${NOW_MS + 1L}.0"),
            replace("e", "1.800000000001e12"),
            replace("e", "9223372036854775808"),
            replace("e", ""),
        )

        for (entries in malformed) {
            val result = parser.parse(entries, hasNotification = false)
            val reason = rejected(result).reason
            assertTrue(
                reason == CallPayloadRejectionReason.INVALID_SHAPE ||
                    reason == CallPayloadRejectionReason.MALFORMED,
            )
        }
    }

    @Test
    fun `expiry must be later than now and no farther than the relay ttl`() {
        val parser = CallPayloadParser(nowMs = { NOW_MS })

        for (expiry in listOf(NOW_MS - 1L, NOW_MS, NOW_MS / 1_000L)) {
            assertEquals(
                CallPayloadRejectionReason.STALE,
                rejected(parser.parse(validEntries(expiry), hasNotification = false)).reason,
            )
        }
        assertEquals(
            CallPayloadRejectionReason.TOO_FAR_FUTURE,
            rejected(
                parser.parse(
                    validEntries(NOW_MS + CallPayloadParser.MAX_FUTURE_SKEW_MS + 1L),
                    hasNotification = false,
                ),
            ).reason,
        )
        assertTrue(
            parser.parse(
                validEntries(NOW_MS + CallPayloadParser.MAX_FUTURE_SKEW_MS),
                hasNotification = false,
            ) is CallPayloadParseResult.Accepted,
        )
    }

    private fun validEntries(
        expiresAtMs: Long = NOW_MS + CallPayloadParser.MAX_FUTURE_SKEW_MS,
    ): List<Pair<String, String>> = listOf(
        "v" to "1",
        "w" to "call",
        "c" to CALL_HANDLE_A,
        "h" to WAKE_HANDLE_A,
        "e" to expiresAtMs.toString(),
    )

    private fun replace(key: String, value: String): List<Pair<String, String>> =
        validEntries().map { entry -> if (entry.first == key) key to value else entry }

    private fun payloadBytes(entries: List<Pair<String, String>>): Int = entries.sumOf { entry ->
        entry.first.toByteArray(StandardCharsets.UTF_8).size +
            entry.second.toByteArray(StandardCharsets.UTF_8).size
    }

    private fun accepted(result: CallPayloadParseResult): CallWakePayload {
        assertTrue(result is CallPayloadParseResult.Accepted)
        return (result as CallPayloadParseResult.Accepted).payload
    }

    private fun rejected(
        result: CallPayloadParseResult,
    ): CallPayloadParseResult.Rejected {
        assertTrue(result is CallPayloadParseResult.Rejected)
        return result as CallPayloadParseResult.Rejected
    }

    private data class RejectionCase(
        val entries: List<Pair<String, String>>,
        val hasNotification: Boolean = false,
        val reason: CallPayloadRejectionReason,
    )

    private companion object {
        const val NOW_MS = 1_800_000_000_000L
        const val CALL_HANDLE_A = "00112233445566778899aabbccddeeff"
        const val WAKE_HANDLE_A = "50112233445566778899aabbccddeeff"
    }
}
