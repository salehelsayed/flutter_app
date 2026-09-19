package com.mknoon.app.call

import java.util.UUID

/** Volatile custody only. This is neither call authority nor a durable native journal. */
internal data class MknoonCallAdmissionToken(
    val nativeCallId: UUID,
    val ownerId: UUID,
    val expiresAtMs: Long,
    val wakeHandle: String,
) {
    fun toMap(): Map<String, Any> = mapOf(
        "nativeCallId" to nativeCallId.toString(),
        "ownerId" to ownerId.toString(),
        "expiresAtMs" to expiresAtMs,
        "wakeHandle" to wakeHandle,
    )

    override fun toString(): String = "MknoonCallAdmissionToken(<redacted>)"

    companion object {
        fun parse(value: Any?): MknoonCallAdmissionToken? {
            val fields = value as? Map<*, *> ?: return null
            if (fields.keys != setOf("nativeCallId", "ownerId", "expiresAtMs", "wakeHandle")) return null
            fun id(key: String): UUID? {
                val raw = fields[key] as? String ?: return null
                if (!CANONICAL_CALL_HANDLE.matches(raw)) return null
                return runCatching { UUID.fromString(raw) }.getOrNull()
            }
            val expiry = when (val raw = fields["expiresAtMs"]) {
                is Long -> raw
                is Int -> raw.toLong()
                else -> return null
            }
            val wake = fields["wakeHandle"] as? String ?: return null
            if (expiry <= 0L || !CALL_RANDOM_ID.matches(wake)) return null
            return MknoonCallAdmissionToken(id("nativeCallId") ?: return null,
                id("ownerId") ?: return null, expiry, wake)
        }
    }
}

/**
 * One current WorkRequest per call, registered before notifying the foreground
 * mailbox owner. A completed authenticated/ACKed terminal may arrive before
 * Android delivers START_ADMISSION; its receipt survives that ordering, but
 * never settles a successor WorkRequest. Unknown/deferred work cannot commit.
 */
internal class MknoonCallAdmissionSettlementStore(
    private val nowMs: () -> Long = System::currentTimeMillis,
    private val capacity: Int = 32,
) {
    companion object { internal const val RETENTION_MS = 75_000L }
    private data class Entry(
        val token: MknoonCallAdmissionToken,
        val registeredAtMs: Long,
        val retainUntilMs: Long,
        var declined: Boolean = false,
        var blocked: Boolean = false,
        var settled: Boolean = false,
    )
    private val entries = LinkedHashMap<UUID, Entry>()

    init { require(capacity in 1..32) }

    @Synchronized fun register(payload: CallWakePayload, ownerId: UUID, declineReply: Boolean = false): MknoonCallAdmissionToken? {
        val now = clock() ?: return null
        prune(now)
        if (payload.receivedAtMs < 0L || payload.receivedAtMs > now ||
            payload.expiresAtMs <= payload.receivedAtMs ||
            payload.expiresAtMs - payload.receivedAtMs > CallPayloadParser.MAX_FUTURE_SKEW_MS ||
            now - payload.receivedAtMs >= RETENTION_MS || !CALL_RANDOM_ID.matches(payload.wakeHandle)
        ) return null
        val token = MknoonCallAdmissionToken(payload.nativeCallId, ownerId, payload.expiresAtMs, payload.wakeHandle)
        val previous = entries[payload.nativeCallId]
        if (previous?.token == token) {
            if (declineReply) { previous.declined = true; previous.settled = false }
            return token
        }
        val end = runCatching { Math.addExact(payload.receivedAtMs, RETENTION_MS) }.getOrNull() ?: return null
        entries.remove(payload.nativeCallId)
        entries[payload.nativeCallId] = Entry(token, now, end, declined = declineReply || previous?.declined == true)
        while (entries.size > capacity) entries.remove(entries.keys.first())
        return token
    }

    @Synchronized fun capture(nativeCallId: UUID): MknoonCallAdmissionToken? {
        val entry = current(nativeCallId) ?: return null
        return entry.token.takeUnless { entry.declined || entry.blocked || entry.settled }
    }

    @Synchronized fun settle(token: MknoonCallAdmissionToken, commit: () -> Boolean = { true }): Boolean {
        val entry = current(token.nativeCallId) ?: return false
        if (entry.token != token || entry.declined || entry.blocked) return false
        if (!entry.settled && !runCatching(commit).getOrDefault(false)) return false
        entry.settled = true
        return true
    }

    @Synchronized fun isSettled(token: MknoonCallAdmissionToken): Boolean {
        val entry = current(token.nativeCallId) ?: return false
        return entry.token == token && entry.settled && !entry.declined && !entry.blocked
    }

    @Synchronized fun hasSuccessor(token: MknoonCallAdmissionToken): Boolean =
        current(token.nativeCallId)?.let { it.token != token } == true

    @Synchronized fun protectDecline(nativeCallId: UUID) {
        current(nativeCallId)?.let { it.declined = true; it.settled = false }
    }

    @Synchronized fun block(nativeCallId: UUID, ownerId: UUID?) {
        current(nativeCallId)?.takeIf { it.token.ownerId == ownerId }?.let {
            it.blocked = true
            it.settled = false
        }
    }

    @Synchronized fun retire(nativeCallId: UUID, ownerId: UUID?) {
        val entry = current(nativeCallId) ?: return
        if (entry.token.ownerId == ownerId && !entry.settled) entries.remove(nativeCallId)
    }

    private fun current(nativeCallId: UUID): Entry? {
        val now = clock() ?: return null
        prune(now)
        return entries[nativeCallId]?.takeIf { now >= it.registeredAtMs }
    }
    private fun clock(): Long? = runCatching(nowMs).getOrNull()?.takeIf { it >= 0L }
    private fun prune(now: Long) { entries.entries.removeAll { now >= it.value.retainUntilMs } }
}

internal object ProcessMknoonCallAdmissionSettlements {
    val store = MknoonCallAdmissionSettlementStore()
}

internal fun admissionSettlementHasNativeOwner(observe: () -> MknoonCallJournalObservation): Boolean =
    runCatching { observe().let { it.liveOwnerPresent || it.cleanupPending } }.getOrDefault(true)

/** Caller holds the runtime's authenticated-ingress lock across these fences. */
internal fun commitAuthenticatedAdmissionSettlement(
    store: MknoonCallAdmissionSettlementStore,
    token: MknoonCallAdmissionToken,
    capabilityEnabled: Boolean,
    hasNativeOwner: Boolean,
    recordTerminal: (UUID, Long) -> Boolean,
    release: (MknoonCallAdmissionToken) -> Unit,
): Boolean {
    if (!capabilityEnabled || hasNativeOwner) return false
    if (!store.settle(token) { recordTerminal(token.nativeCallId, token.expiresAtMs) }) return false
    // The terminal receipt is committed already. Failed intent submission must
    // not undo it; a delayed START or later duplicate wake uses that receipt.
    runCatching { release(token) }
    return true
}
