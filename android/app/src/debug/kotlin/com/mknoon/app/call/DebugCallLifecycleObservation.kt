package com.mknoon.app.call

import android.os.SystemClock
import java.security.MessageDigest
import java.util.UUID

/** Debug-source-only, volatile observation. It has no controller or persistence authority. */
internal class DebugCallLifecycleRecorder(
    private val wallMs: () -> Long,
    private val elapsedMs: () -> Long,
) {
    private data class Armed(val nonce: String, val call: UUID, val expiry: Long,
        val direction: String, val wall: Long, val elapsed: Long,
        val events: MutableList<Map<String, Any>> = mutableListOf(), var overflow: Boolean = false)
    private var armed: Armed? = null

    @Synchronized fun arm(nonce: String, observation: MknoonCallJournalObservation): Map<String, Any> {
        require(Regex("^[0-9a-f]{16,64}$").matches(nonce))
        val d = requireNotNull(observation.descriptor)
        require(observation.liveOwnerPresent && !observation.cleanupPending && d.terminalEvent == null)
        require(d.expiresAtMs > 0 && d.direction == PendingNativeCallDirection.INCOMING)
        val old = armed
        require(old == null || elapsedMs() - old.elapsed > 90000 || old.nonce == nonce && old.call == d.nativeCallId)
        if (old == null || old.nonce != nonce || old.call != d.nativeCallId || elapsedMs() - old.elapsed > 90000) {
            armed = Armed(nonce, d.nativeCallId, d.expiresAtMs, d.direction.name.lowercase(), wallMs(), elapsedMs())
        }
        return snapshot(nonce, observation)
    }

    @Synchronized fun record(call: String, kind: String, outcome: String) {
        val a = armed ?: return
        val age = elapsedMs() - a.elapsed
        if (age !in 0..90000 || call != a.call.toString()) return
        if (kind !in setOf("journal", "answer")) return
        val allowed = if (kind == "journal") PendingNativeCallEventType.values().map { it.name }.toSet()
            else setOf("ok", "failed", "rejected", "duplicate")
        if (outcome !in allowed) return
        if (a.events.size >= 16) { a.overflow = true; return }
        a.events.add(mapOf("ordinal" to a.events.size + 1, "kind" to kind,
            "outcome" to outcome, "wallMs" to wallMs(), "elapsedMs" to elapsedMs()))
    }

    @Synchronized fun snapshot(nonce: String, observation: MknoonCallJournalObservation?): Map<String, Any> {
        val a = requireNotNull(armed)
        require(nonce == a.nonce && elapsedMs() - a.elapsed in 0..90000)
        val d = observation?.descriptor
        return mapOf("schema" to "mknoon.debug-call-expiry.v1", "status" to "snapshot",
            "timestampBasis" to "synchronous_post_commit_or_answer_result",
            "nonce" to nonce, "callBindingSha256" to debugEvidenceHash("$nonce:${a.call}"),
            "authenticatedExpiresAtMs" to a.expiry, "direction" to a.direction,
            "armedWallMs" to a.wall, "armedElapsedMs" to a.elapsed,
            "observedWallMs" to wallMs(), "observedElapsedMs" to elapsedMs(),
            "currentOwnerMatches" to (d?.nativeCallId == a.call),
            "successorPresent" to (d != null && d.nativeCallId != a.call),
            "journalReadable" to (observation != null),
            "overflow" to a.overflow, "events" to a.events.map { it.toMap() })
    }
}

internal fun debugEvidenceHash(value: String): String = MessageDigest.getInstance("SHA-256")
    .digest(value.toByteArray(Charsets.UTF_8)).joinToString("") { "%02x".format(it) }

/** Reflected only behind BuildConfig.DEBUG. Release/profile artifacts omit this class. */
object DebugCallLifecycleObservation {
    internal val recorder = DebugCallLifecycleRecorder(System::currentTimeMillis, SystemClock::elapsedRealtime)
    @JvmStatic fun record(call: String, kind: String, outcome: String) = recorder.record(call, kind, outcome)
}
