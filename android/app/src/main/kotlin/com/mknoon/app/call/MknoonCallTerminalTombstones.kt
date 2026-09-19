package com.mknoon.app.call

import android.content.SharedPreferences
import java.util.UUID

/** Durable exact-call settlement, independent of invitation validity and journal acknowledgement. */
internal class MknoonCallTerminalTombstones(
    private val preferences: SharedPreferences,
) {
    companion object {
        private const val PREFIX = "terminal_tombstone_"
        internal const val MAX_ENTRIES = 32
        // A wake already in flight may remain valid for 45s and then hold its
        // admission lease for 30s. Keep terminal authority through both bounds.
        // This retention never changes payload expiry or permits presentation.
        internal const val RETENTION_MS =
            CallPayloadParser.MAX_FUTURE_SKEW_MS + MknoonCallForegroundService.ADMISSION_TIMEOUT_MS
    }

    private val lock = Any()

    fun record(nativeCallId: UUID, invitationExpiresAtMs: Long, observedNowMs: Long): Boolean =
        synchronized(lock) {
            val editor = preferences.edit()
            val retained = preferences.all.entries
                .mapNotNull { (key, value) ->
                    if (!key.startsWith(PREFIX)) return@mapNotNull null
                    val expiry = value as? Long ?: return@mapNotNull null
                    if (expiry <= observedNowMs) {
                        editor.remove(key)
                        return@mapNotNull null
                    }
                    key to expiry
                }
                .sortedBy { it.second }
                .toMutableList()
            val key = PREFIX + nativeCallId
            retained.removeAll { it.first == key }
            val retentionExpiryMs = maxOf(invitationExpiresAtMs, observedNowMs + RETENTION_MS)
            if (retentionExpiryMs > observedNowMs) {
                while (retained.size >= MAX_ENTRIES) {
                    editor.remove(retained.removeAt(0).first)
                }
                editor.putLong(key, retentionExpiryMs)
            } else {
                editor.remove(key)
            }
            editor.commit()
        }

    fun contains(nativeCallId: UUID, observedNowMs: Long): Boolean = synchronized(lock) {
        val key = PREFIX + nativeCallId
        val expiresAtMs = preferences.all[key] as? Long ?: 0L
        if (expiresAtMs <= observedNowMs) {
            if (expiresAtMs != 0L) preferences.edit().remove(key).apply()
            false
        } else {
            true
        }
    }
}
