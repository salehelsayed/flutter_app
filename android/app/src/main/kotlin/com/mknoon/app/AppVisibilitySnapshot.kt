package com.mknoon.app

import java.io.ByteArrayOutputStream
import java.math.BigDecimal
import java.math.BigInteger
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.charset.CodingErrorAction
import java.nio.charset.StandardCharsets
import java.security.MessageDigest
import org.json.JSONObject

internal const val APP_VISIBILITY_SCHEMA_VERSION = 1
internal const val APP_VISIBILITY_FRESHNESS_MS = 90_000L

internal enum class AppVisibilityLifecycle {
    FOREGROUND_ACTIVE,
    INACTIVE,
    BACKGROUND,
}

internal data class AppVisibilitySnapshotV1(
    val schemaVersion: Int = APP_VISIBILITY_SCHEMA_VERSION,
    val revision: Long,
    val lifecycleGeneration: Long,
    val lifecycle: AppVisibilityLifecycle,
    val visibleConversationDigest: String?,
    val updatedMonotonicMs: Long,
    val bootSession: String,
) {
    init {
        require(schemaVersion == APP_VISIBILITY_SCHEMA_VERSION)
        require(revision > 0L)
        require(lifecycleGeneration > 0L)
        require(updatedMonotonicMs >= 0L)
        require(bootSession.isValidBootSession())
        require(
            visibleConversationDigest == null ||
                APP_VISIBILITY_DIGEST.matches(visibleConversationDigest),
        )
    }

    fun toChannelMap(): Map<String, Any?> = linkedMapOf(
        "schemaVersion" to schemaVersion,
        "revision" to revision,
        "lifecycleGeneration" to lifecycleGeneration,
        "lifecycle" to lifecycle.name,
        "visibleConversationDigest" to visibleConversationDigest,
        "updatedMonotonicMs" to updatedMonotonicMs,
        "bootSession" to bootSession,
    )
}

private val APP_VISIBILITY_DIGEST = Regex("^[0-9a-f]{64}$")
private val APP_VISIBILITY_KEYS = setOf(
    "schemaVersion",
    "revision",
    "lifecycleGeneration",
    "lifecycle",
    "visibleConversationDigest",
    "updatedMonotonicMs",
    "bootSession",
)

internal sealed interface AppVisibilitySnapshotDecodeResult {
    data class Supported(val snapshot: AppVisibilitySnapshotV1) :
        AppVisibilitySnapshotDecodeResult

    data object FutureSchema : AppVisibilitySnapshotDecodeResult
    data object UnsupportedBounds : AppVisibilitySnapshotDecodeResult
    data object Corrupt : AppVisibilitySnapshotDecodeResult
}

internal object AppVisibilitySnapshotCodec {
    fun encode(snapshot: AppVisibilitySnapshotV1): ByteArray {
        val json = JSONObject()
        json.put("schemaVersion", snapshot.schemaVersion)
        json.put("revision", snapshot.revision)
        json.put("lifecycleGeneration", snapshot.lifecycleGeneration)
        json.put("lifecycle", snapshot.lifecycle.name)
        json.put(
            "visibleConversationDigest",
            snapshot.visibleConversationDigest ?: JSONObject.NULL,
        )
        json.put("updatedMonotonicMs", snapshot.updatedMonotonicMs)
        json.put("bootSession", snapshot.bootSession)
        return json.toString().toByteArray(StandardCharsets.UTF_8)
    }

    fun decode(bytes: ByteArray): AppVisibilitySnapshotDecodeResult {
        val text = try {
            StandardCharsets.UTF_8.newDecoder()
                .onMalformedInput(CodingErrorAction.REPORT)
                .onUnmappableCharacter(CodingErrorAction.REPORT)
                .decode(ByteBuffer.wrap(bytes))
                .toString()
        } catch (_: Exception) {
            return AppVisibilitySnapshotDecodeResult.Corrupt
        }
        val json = try {
            JSONObject(text)
        } catch (_: Exception) {
            return AppVisibilitySnapshotDecodeResult.Corrupt
        }
        val schemaToken = text.strictIntegerToken("schemaVersion")
        if (!schemaToken.present || !schemaToken.integral) {
            return AppVisibilitySnapshotDecodeResult.Corrupt
        }
        if (!schemaToken.inSignedLongRange) {
            return if (schemaToken.positive) {
                AppVisibilitySnapshotDecodeResult.FutureSchema
            } else {
                AppVisibilitySnapshotDecodeResult.UnsupportedBounds
            }
        }
        val schemaVersion = checkNotNull(schemaToken.value)
        if (json.strictLong("schemaVersion") != schemaVersion) {
            return AppVisibilitySnapshotDecodeResult.Corrupt
        }
        if (schemaVersion > APP_VISIBILITY_SCHEMA_VERSION) {
            return AppVisibilitySnapshotDecodeResult.FutureSchema
        }
        if (schemaVersion != APP_VISIBILITY_SCHEMA_VERSION.toLong()) {
            return AppVisibilitySnapshotDecodeResult.Corrupt
        }
        val revisionToken = text.strictIntegerToken("revision")
        val generationToken = text.strictIntegerToken("lifecycleGeneration")
        val updatedToken = text.strictIntegerToken("updatedMonotonicMs")
        val integerTokens = listOf(revisionToken, generationToken, updatedToken)
        if (integerTokens.any { it.present && it.integral && !it.inSignedLongRange }) {
            return AppVisibilitySnapshotDecodeResult.UnsupportedBounds
        }
        if (
            json.keys().asSequence().toSet() != APP_VISIBILITY_KEYS ||
            integerTokens.any { !it.present || !it.integral }
        ) {
            return AppVisibilitySnapshotDecodeResult.Corrupt
        }
        val revision = checkNotNull(revisionToken.value)
        val lifecycleGeneration = checkNotNull(generationToken.value)
        val updatedMonotonicMs = checkNotNull(updatedToken.value)
        if (
            json.strictLong("revision") != revision ||
            json.strictLong("lifecycleGeneration") != lifecycleGeneration ||
            json.strictLong("updatedMonotonicMs") != updatedMonotonicMs
        ) {
            return AppVisibilitySnapshotDecodeResult.Corrupt
        }
        val lifecycle = try {
            AppVisibilityLifecycle.valueOf(json.getString("lifecycle"))
        } catch (_: Exception) {
            return AppVisibilitySnapshotDecodeResult.Corrupt
        }
        val digest = when (val raw = json.opt("visibleConversationDigest")) {
            null, JSONObject.NULL -> null
            is String -> raw
            else -> return AppVisibilitySnapshotDecodeResult.Corrupt
        }
        val bootSession = json.opt("bootSession") as? String
            ?: return AppVisibilitySnapshotDecodeResult.Corrupt
        val snapshot = try {
            AppVisibilitySnapshotV1(
                revision = revision,
                lifecycleGeneration = lifecycleGeneration,
                lifecycle = lifecycle,
                visibleConversationDigest = digest,
                updatedMonotonicMs = updatedMonotonicMs,
                bootSession = bootSession,
            )
        } catch (_: IllegalArgumentException) {
            return AppVisibilitySnapshotDecodeResult.Corrupt
        }
        return AppVisibilitySnapshotDecodeResult.Supported(snapshot)
    }

    private fun JSONObject.strictLong(key: String): Long? {
        val value = opt(key)
        return when (value) {
            is Byte -> value.toLong()
            is Short -> value.toLong()
            is Int -> value.toLong()
            is Long -> value
            is BigInteger -> try {
                value.longValueExact()
            } catch (_: ArithmeticException) {
                null
            }
            is BigDecimal -> try {
                value.longValueExact()
            } catch (_: ArithmeticException) {
                null
            }
            else -> null
        }
    }

    private fun String.strictIntegerToken(key: String): StrictIntegerToken {
        val quotedKey = Regex.escape("\"$key\"")
        val field = Regex("$quotedKey\\s*:\\s*([^,}\\s]+)")
        val matches = field.findAll(this).toList()
        if (matches.size != 1) return StrictIntegerToken(present = false)
        val token = matches.single().groupValues[1]
        if (!SIGNED_INTEGER.matches(token)) {
            return StrictIntegerToken(present = true, integral = false)
        }
        val integer = try {
            BigInteger(token)
        } catch (_: NumberFormatException) {
            return StrictIntegerToken(present = true, integral = false)
        }
        val inRange = integer >= SIGNED_LONG_MIN && integer <= SIGNED_LONG_MAX
        return StrictIntegerToken(
            present = true,
            integral = true,
            inSignedLongRange = inRange,
            positive = integer.signum() > 0,
            value = if (inRange) integer.toLong() else null,
        )
    }

    private data class StrictIntegerToken(
        val present: Boolean,
        val integral: Boolean = false,
        val inSignedLongRange: Boolean = false,
        val positive: Boolean = false,
        val value: Long? = null,
    )

    private val SIGNED_INTEGER = Regex("^-?[0-9]+$")
    private val SIGNED_LONG_MIN = BigInteger.valueOf(Long.MIN_VALUE)
    private val SIGNED_LONG_MAX = BigInteger.valueOf(Long.MAX_VALUE)
}

internal enum class AppVisibilityConversationLane(val wireByte: Byte) {
    DIRECT(0x01.toByte()),
    GROUP(0x02.toByte()),
}

internal object AppVisibilityConversationDigest {
    private const val DOMAIN = "mknoon/app-visibility/v1"
    private const val GROUP_PREFIX = "group:"
    private const val MESSAGE_MARKER = "|message:"

    fun normalizedLocalId(
        lane: AppVisibilityConversationLane,
        rawLocalId: String,
    ): String? {
        val trimmed = rawLocalId.trim()
        if (trimmed.isEmpty() || !trimmed.hasValidUnicodeAndNoControlScalars()) {
            return null
        }
        return when (lane) {
            AppVisibilityConversationLane.DIRECT -> {
                if (trimmed.startsWith(GROUP_PREFIX)) {
                    null
                } else {
                    trimmed
                }
            }
            AppVisibilityConversationLane.GROUP -> normalizeGroupId(trimmed)
        }
    }

    fun preimage(
        lane: AppVisibilityConversationLane,
        rawLocalId: String,
    ): ByteArray? {
        val normalized = normalizedLocalId(lane, rawLocalId) ?: return null
        val normalizedBytes = normalized.toByteArray(StandardCharsets.UTF_8)
        val output = ByteArrayOutputStream(
            DOMAIN.length + 2 + Int.SIZE_BYTES + normalizedBytes.size,
        )
        output.write(DOMAIN.toByteArray(StandardCharsets.UTF_8))
        output.write(0)
        output.write(lane.wireByte.toInt())
        output.write(
            ByteBuffer.allocate(Int.SIZE_BYTES)
                .order(ByteOrder.BIG_ENDIAN)
                .putInt(normalizedBytes.size)
                .array(),
        )
        output.write(normalizedBytes)
        return output.toByteArray()
    }

    fun digest(
        lane: AppVisibilityConversationLane,
        rawLocalId: String,
    ): String? = preimage(lane, rawLocalId)?.let { bytes ->
        MessageDigest.getInstance("SHA-256")
            .digest(bytes)
            .joinToString(separator = "") { byte -> "%02x".format(byte) }
    }

    private fun normalizeGroupId(value: String): String? {
        if (!value.startsWith(GROUP_PREFIX)) return null
        val markerIndex = value.indexOf(MESSAGE_MARKER)
        val owner = if (markerIndex < 0) value else value.substring(0, markerIndex)
        val groupId = owner.removePrefix(GROUP_PREFIX)
        if (groupId.isEmpty() || groupId != groupId.trim()) return null
        if (groupId.contains('|') || groupId.contains(':')) return null
        if (markerIndex >= 0) {
            val messageId = value.substring(markerIndex + MESSAGE_MARKER.length)
            if (messageId.isEmpty() || messageId != messageId.trim()) return null
            if (messageId.contains('|')) return null
        }
        return "$GROUP_PREFIX$groupId"
    }
}

private fun String.hasValidUnicodeAndNoControlScalars(): Boolean {
    var index = 0
    while (index < length) {
        val character = this[index]
        if (character.code in 0x00..0x1f || character.code in 0x7f..0x9f) {
            return false
        }
        when {
            character.isHighSurrogate() -> {
                if (index + 1 >= length || !this[index + 1].isLowSurrogate()) {
                    return false
                }
                index += 2
            }
            character.isLowSurrogate() -> return false
            else -> index += 1
        }
    }
    return true
}

private fun String.isValidBootSession(): Boolean =
    isNotEmpty() &&
        this != "unavailable" &&
        this == trim() &&
        hasValidUnicodeAndNoControlScalars()

internal object AppVisibilitySnapshotPredicate {
    fun maySuppress(
        snapshot: AppVisibilitySnapshotV1?,
        currentMonotonicMs: Long,
        currentBootSession: String,
        expectedConversationDigest: String?,
    ): Boolean {
        if (snapshot == null || currentMonotonicMs < 0L) return false
        if (!currentBootSession.isValidBootSession() || snapshot.bootSession != currentBootSession) {
            return false
        }
        val age = currentMonotonicMs - snapshot.updatedMonotonicMs
        if (age < 0L || age >= APP_VISIBILITY_FRESHNESS_MS) return false
        if (snapshot.lifecycle != AppVisibilityLifecycle.FOREGROUND_ACTIVE) return false
        val visible = snapshot.visibleConversationDigest ?: return false
        val expected = expectedConversationDigest ?: return false
        return APP_VISIBILITY_DIGEST.matches(expected) && visible == expected
    }
}
