package com.mknoon.app

import com.mknoon.app.diagnostics.MknoonActiveIdentityReporterFence
import org.json.JSONArray
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
    @Test fun weeklyProjectionReachesTheExistingFencedOperationBranch() {
        val fields = decoded(request(op = "weeklyProjection"))
        assertEquals(1L, GoBridge.activityMarkRevision(fields))
        assertEquals(true, GoBridge.activityNonConfigurationOperation(fields["op"] as? String))
    }

    @Test fun weeklyMarkReachesTheExistingFencedOperationBranch() {
        val fields = decoded(JSONObject(request(op = "markWeekly"))
            .put("week", "2026-W47").put("kinds", JSONArray(listOf("active", "group"))).toString())
        assertEquals(1L, GoBridge.activityMarkRevision(fields))
        assertEquals(true, GoBridge.activityNonConfigurationOperation(fields["op"] as? String))
    }

    @Test fun dailyOperationsAndPrivateAckRejectionKeepTheirExistingBranch() {
        for (op in listOf("mark", "flush")) {
            val fields = decoded(request(op = op))
            assertEquals(1L, GoBridge.activityMarkRevision(fields))
            assertEquals(true, GoBridge.activityNonConfigurationOperation(fields["op"] as? String))
        }
        for (op in listOf(null, "", "configure", "ackWeekly", "weeklyprojection", "markweekly", "unknown")) {
            assertEquals(false, GoBridge.activityNonConfigurationOperation(op))
        }
    }

    @Test fun weeklyProjectionKeepsTheRealNestedReplyIncludingEmptyAndDstWeeks() {
        for (empty in listOf(true, false)) {
            val weekly = weeklyProjection(empty)
            val result = JSONObject(GoBridge.activityAnswer(weeklyReply(weekly), replyFence, "weeklyProjection"))
            assertEquals(true, result.opt("ok"))
            val data = result.getJSONObject("data")
            assertEquals(setOf("revision", "consentEpoch", "weekly"), data.keys().asSequence().toSet())
            assertEquals(1L, data.getLong("revision"))
            assertEquals(91L, data.getLong("consentEpoch"))
            val projection = data.getJSONObject("weekly")
            assertEquals(setOf("week", "startUnixMillis", "endUnixMillis", "kinds", "acknowledged"),
                projection.keys().asSequence().toSet())
            assertEquals("2026-W13", projection.getString("week"))
            assertEquals(167L * 60 * 60 * 1000,
                projection.getLong("endUnixMillis") - projection.getLong("startUnixMillis"))
            assertEquals(if (empty) 0 else 2, projection.getJSONArray("kinds").length())
            assertEquals(if (empty) 0 else 1, projection.getJSONArray("acknowledged").length())
            assertEquals(weekly.getJSONArray("kinds").toString(), projection.getJSONArray("kinds").toString())
            if (!empty) {
                val ack = projection.getJSONArray("acknowledged").getJSONObject(0)
                assertEquals(setOf("relayPeerId", "kinds"), ack.keys().asSequence().toSet())
                assertEquals("relay-one", ack.getString("relayPeerId"))
                assertEquals("group", ack.getJSONArray("kinds").getString(0))
                assertEquals(1, ack.getJSONArray("kinds").length())
            }
        }
    }

    @Test fun weeklyMarkReturnsTheExistingAcceptedBooleanShape() {
        for (accepted in listOf(true, false)) {
            val raw = JSONObject().put("ok", true).put("data", JSONObject()
                .put("revision", 1L).put("consentEpoch", 91L).put("accepted", accepted)).toString()
            val result = JSONObject(GoBridge.activityAnswer(raw, replyFence, "markWeekly"))
            assertEquals(true, result.opt("ok"))
            val data = result.getJSONObject("data")
            assertEquals(setOf("revision", "consentEpoch", "accepted"), data.keys().asSequence().toSet())
            assertEquals(accepted, data.opt("accepted"))
        }
    }

    @Test fun weeklyProjectionRejectsMalformedNestedFieldsAndUnsafeMillis() {
        val mutations = listOf<(JSONObject) -> Unit>(
            { it.put("extra", "not-a-weekly-field") },
            { it.put("week", "2026-W7") },
            { it.put("startUnixMillis", true) },
            { it.put("startUnixMillis", 1.5) },
            { it.put("startUnixMillis", Long.MIN_VALUE).put("endUnixMillis", 0L) },
            { it.put("startUnixMillis", -9_007_199_254_740_992L) },
            { it.put("endUnixMillis", 9_007_199_254_740_992L) },
            { it.put("endUnixMillis", 0L) },
            { it.put("kinds", JSONArray(listOf("group", "group"))) },
            { it.put("kinds", JSONArray(listOf("unknown"))) },
            { it.put("acknowledged", JSONArray().put(JSONObject()
                .put("relayPeerId", "").put("kinds", JSONArray(listOf("group"))))) },
            { it.put("acknowledged", JSONArray().put(JSONObject()
                .put("relayPeerId", "relay-one").put("kinds", JSONArray()))) },
            { it.put("acknowledged", JSONArray().put(JSONObject()
                .put("relayPeerId", "relay-one").put("kinds", JSONArray(listOf("group")))
                .put("extra", true))) },
            { it.put("acknowledged", JSONArray((0..64).map { index -> JSONObject()
                .put("relayPeerId", "relay-$index").put("kinds", JSONArray(listOf("group"))) })) },
        )
        for (mutate in mutations) {
            val weekly = weeklyProjection(false)
            mutate(weekly)
            val result = JSONObject(GoBridge.activityAnswer(weeklyReply(weekly), replyFence, "weeklyProjection"))
            assertEquals(false, result.opt("ok"))
        }
    }

    @Test fun legacyReplyBooleansAndOwnerFencesRemainUnchanged() {
        for ((op, field) in listOf("configure" to "configured", "mark" to "accepted", "flush" to "queued")) {
            for (value in listOf(true, false)) {
                val data = JSONObject().put("revision", 1L).put("consentEpoch", 91L).put(field, value)
                val raw = JSONObject().put("ok", true).put("data", data)
                val result = JSONObject(GoBridge.activityAnswer(raw.toString(), replyFence, op))
                assertEquals(true, result.opt("ok"))
                assertEquals(value, result.getJSONObject("data").opt(field))
                data.put("consentEpoch", 92L)
                assertEquals(false, JSONObject(GoBridge.activityAnswer(raw.toString(), replyFence, op)).opt("ok"))
            }
        }
    }

    private val replyFence = MknoonActiveIdentityReporterFence(1L, 91L, "v1:${"a".repeat(64)}", "logical-account")

    private fun weeklyProjection(empty: Boolean): JSONObject = JSONObject()
        .put("week", "2026-W13").put("startUnixMillis", 1_774_220_400_000L)
        .put("endUnixMillis", 1_774_821_600_000L)
        .put("kinds", if (empty) JSONArray() else JSONArray(listOf("active", "group")))
        .put("acknowledged", if (empty) JSONArray() else JSONArray().put(JSONObject()
            .put("relayPeerId", "relay-one").put("kinds", JSONArray(listOf("group")))))

    private fun weeklyReply(weekly: JSONObject): String = JSONObject().put("ok", true)
        .put("data", JSONObject().put("revision", 1L).put("consentEpoch", 91L)
            .put("weekly", weekly)).toString()

    @Test fun weeklyMarkKindsCrossTheRealRequestCodecUnchanged() {
        for (kinds in listOf(listOf("group"), listOf("active", "chat", "call", "group"))) {
            val raw = request("markWeekly").dropLast(1) +
                ",\"week\":\"2026-W47\",\"kinds\":${JSONArray(kinds)}}"
            val fields = decoded(raw)
            assertEquals("2026-W47", fields["week"])
            assertEquals(kinds, fields["kinds"])
            assertEquals(requiredKeys + setOf("week", "kinds"), fields.keys)
            assertEquals(fields, decoded(JSONObject(fields).toString()))
        }
    }

    @Test fun weeklyMarkUsesTheExistingOwnerRevisionShapeGuard() {
        val fields = decoded(request("markWeekly"))
        fields["week"] = "2026-W47"
        fields["kinds"] = listOf("group")
        val original = fields.toMap()
        assertEquals(1L, GoBridge.activityMarkRevision(fields))
        assertEquals(original, fields)
    }

    @Test fun weeklyMarkRejectsMalformedKindsWeekAndExtraFields() {
        for (kinds in listOf("[]", "[\"group\",\"group\"]", "[\"unknown\"]", "[1]",
            "[\"active\",\"chat\",\"call\",\"group\",\"group\"]", "null", "true")) {
            assertRejected(request("markWeekly").dropLast(1) +
                ",\"week\":\"2026-W47\",\"kinds\":$kinds}")
        }
        for (week in listOf("2026-W7", "2026-W00", "2026-W54", "2026-W47-private")) {
            assertRejected(request("markWeekly").dropLast(1) +
                ",\"week\":\"$week\",\"kinds\":[\"group\"]}")
        }
        val valid = request("markWeekly").dropLast(1) +
            ",\"week\":\"2026-W47\",\"kinds\":[\"group\"]"
        assertRejected("$valid,\"occurredAtUnixMillis\":0}")
        assertRejected("$valid,\"unknown\":0}")
        for (duplicate in listOf("kinds", "\\u006binds")) {
            assertNull(GoBridge.activityFields("$valid,\"$duplicate\":[\"active\"]}"))
        }
    }

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
