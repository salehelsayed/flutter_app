package com.mknoon.app

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [33])
class GoBridgeActivityReporterContractTest {
    @Test fun markAcceptsZeroOccurrenceUnchanged() = assertOccurrenceUnchanged(0L)

    @Test fun markAcceptsCurrentMillisOccurrenceUnchanged() = assertOccurrenceUnchanged(1_794_902_400_123L)

    @Test fun markAcceptsAboveDoublePrecisionOccurrenceUnchanged() = assertOccurrenceUnchanged(9_007_199_254_740_993L)

    @Test fun markAcceptsInt64MaxOccurrenceUnchanged() = assertOccurrenceUnchanged(Long.MAX_VALUE)

    @Test fun legacyMarkAndFlushKeepExactlySixFields() {
        for (op in listOf("mark", "flush")) {
            val fields = decoded(request(op))
            val original = fields.toMap()
            assertEquals(1L, GoBridge.activityMarkRevision(fields))
            assertEquals(requiredKeys, fields.keys)
            assertEquals(original, decoded(JSONObject(fields).toString()))
            assertEquals(original, fields)
        }
    }

    @Test fun everyRequiredFieldRemainsRequiredWithAndWithoutOccurrence() {
        for (timestamp in listOf<String?>(null, "0")) {
            for (missing in requiredKeys) {
                val fields = decoded(request(timestamp = timestamp))
                fields.remove(missing)
                assertNull("Missing $missing, occurrence=$timestamp", GoBridge.activityMarkRevision(fields))
            }
        }
    }

    @Test fun unknownFieldRemainsRejectedWithoutOccurrence() {
        assertRejected(request().dropLast(1) + ",\"unknown\":0}")
    }

    @Test fun unknownFieldRemainsRejectedWithOccurrence() {
        assertRejected(request(timestamp = "0").dropLast(1) + ",\"unknown\":0}")
    }

    @Test fun flushRejectsOccurrenceIncludingZero() {
        for (timestamp in listOf("0", "1794902400123", "9223372036854775807")) {
            assertRejected(request("flush", timestamp))
        }
    }

    @Test fun malformedOccurrenceValuesRemainRejected() {
        for (timestamp in listOf("null", "true", "false", "\"0\"", "-1", "0.0", "1.5", "1e3", "9223372036854775808", "[]", "{}")) {
            assertRejected(request(timestamp = timestamp))
        }
    }

    @Test fun duplicateOccurrenceNamesAndDecodedAliasesRemainRejected() {
        val timestamped = request(timestamp = "0").dropLast(1)
        for (duplicate in listOf("occurredAtUnixMillis", "\\u006fccurredAtUnixMillis")) {
            assertNull(GoBridge.activityFields("$timestamped,\"$duplicate\":1}"))
        }
    }

    @Test fun revisionRetainsItsOriginalPositiveSafeIntegerBounds() {
        for (op in listOf("mark", "flush")) {
            assertEquals(9_007_199_254_740_991L, GoBridge.activityMarkRevision(decoded(request(op, revision = "9007199254740991"))))
            for (revision in listOf("0", "9007199254740992", "9223372036854775807", "-1", "true", "\"1\"", "1.0")) {
                assertRejected(request(op, revision = revision))
            }
        }
    }

    @Test fun duplicateRequiredNamesAndDecodedAliasesRemainRejected() {
        for (duplicate in listOf("revision", "\\u0072evision")) {
            assertNull(GoBridge.activityFields(request().dropLast(1) + ",\"$duplicate\":1}"))
        }
    }

    private fun assertOccurrenceUnchanged(timestamp: Long) {
        val fields = decoded(request(timestamp = timestamp.toString()))
        val original = fields.toMap()
        assertEquals("A valid mark occurrence must pass the real handler's shape guard", 1L, GoBridge.activityMarkRevision(fields))
        assertEquals(timestamp, fields["occurredAtUnixMillis"])
        assertEquals(requiredKeys + "occurredAtUnixMillis", fields.keys)
        val forwarded = JSONObject(fields).toString()
        assertEquals(timestamp, decoded(forwarded)["occurredAtUnixMillis"])
        assertEquals(original, decoded(forwarded))
        assertEquals(original, fields)
    }

    private fun assertRejected(raw: String) {
        val fields = GoBridge.activityFields(raw)
        if (fields != null) assertNull("Must reject $raw", GoBridge.activityMarkRevision(fields))
    }

    private fun decoded(raw: String): MutableMap<String, Any> {
        val fields = GoBridge.activityFields(raw)
        assertNotNull("Canonical fixture must parse: $raw", fields)
        return requireNotNull(fields)
    }

    private fun request(op: String = "mark", timestamp: String? = null, revision: String = "1"): String =
        "{\"version\":1,\"op\":\"$op\",\"revision\":$revision,\"consentEpoch\":1," +
            "\"profileBinding\":\"v1:${"a".repeat(64)}\",\"accountPeerId\":\"12D3KooWJsEmQWn5WGGn9AZX79emq3RkGNx2ihFwWzZAqbiUQGMF\"" +
            (timestamp?.let { ",\"occurredAtUnixMillis\":$it" } ?: "") + "}"

    private val requiredKeys = setOf("version", "op", "revision", "consentEpoch", "profileBinding", "accountPeerId")
}
