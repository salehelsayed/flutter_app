package com.mknoon.app.call

import java.security.MessageDigest
import java.util.Locale

/** DUMP-protected receiver projection. No IDs, handles, payloads, or exception text leave it. */
internal fun debugCallJournalSnapshot(
    nonce: String,
    observeExisting: () -> MknoonCallJournalObservation?,
): Map<String, Any> {
    if (!Regex("^[0-9a-f]{16,64}$").matches(nonce)) {
        return mapOf("status" to "rejected", "reason" to "invalid_nonce")
    }
    val base = mapOf("schema" to "mknoon.debug-call-journal.v1", "nonce" to nonce)
    val observation = try {
        observeExisting()
    } catch (_: Exception) {
        return base + mapOf("status" to "unavailable", "reason" to "read_failed")
    } ?: return base + mapOf("status" to "unavailable", "reason" to "runtime_unavailable")
    val result = base + mapOf("status" to "snapshot",
        "liveOwnerPresent" to observation.liveOwnerPresent,
        "cleanupPending" to observation.cleanupPending)
    val descriptor = observation.descriptor
        ?: return result + mapOf("recordState" to "empty")
    val terminal = descriptor.terminalEvent
    if (terminal != null && (terminal.nativeCallId != descriptor.nativeCallId ||
            terminal.sequence <= 0 || terminal.sequence != descriptor.highestSequence ||
            descriptor.events.lastOrNull() != terminal ||
            descriptor.events.count { it.type.isTerminal() } != 1 || !terminal.type.isTerminal())) {
        return base + mapOf("status" to "unavailable", "reason" to "invalid_record")
    }
    val binding = sha256("$nonce:${descriptor.nativeCallId}")
    val protectedIdentity = sha256(listOf(nonce, "journal", descriptor.nativeCallId,
        descriptor.phase, descriptor.handoffAcknowledgement, descriptor.highestSequence,
        terminal?.eventId, terminal?.sequence, terminal?.type).joinToString(":"))
    val record = result + mapOf("recordState" to if (terminal == null) "active" else "terminal",
        "callBindingSha256" to binding, "recordBindingSha256" to protectedIdentity,
        "phase" to descriptor.phase.name.lowercase(Locale.ROOT),
        "handoff" to descriptor.handoffAcknowledgement.name.lowercase(Locale.ROOT))
    return if (terminal == null) record else record + mapOf(
        "terminalType" to terminal.type.name.lowercase(Locale.ROOT),
        "terminalSequence" to terminal.sequence)
}

private fun sha256(value: String): String = MessageDigest.getInstance("SHA-256")
    .digest(value.toByteArray(Charsets.UTF_8)).joinToString("") { "%02x".format(it) }

private fun PendingNativeCallEventType.isTerminal(): Boolean = this in setOf(
    PendingNativeCallEventType.DECLINE_REQUESTED, PendingNativeCallEventType.END_REQUESTED,
    PendingNativeCallEventType.REMOTE_CANCELLED, PendingNativeCallEventType.EXPIRED,
    PendingNativeCallEventType.PROVIDER_REMOVED, PendingNativeCallEventType.NATIVE_FAILURE,
)
