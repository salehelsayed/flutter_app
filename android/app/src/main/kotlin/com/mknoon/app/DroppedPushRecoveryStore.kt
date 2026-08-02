package com.mknoon.app

import android.content.Context

/**
 * Credential-protected, crash-safe marker for FCM batches deleted by Play services.
 *
 * Reads never consume the marker. The last allocated generation is deliberately
 * retained after acknowledgement so a later deletion cannot reuse an old value.
 */
class DroppedPushRecoveryStore(context: Context) {
    companion object {
        internal const val PREFERENCES_NAME = "mknoon_dropped_push_recovery"
        private const val LAST_GENERATION_KEY = "last_generation"
        private const val PENDING_GENERATION_KEY = "pending_generation"
        private val transactionLock = Any()
    }

    private val preferences = context.applicationContext.getSharedPreferences(
        PREFERENCES_NAME,
        Context.MODE_PRIVATE,
    )

    /**
     * Returns the committed generation, or null when persistence failed.
     * [afterCommit] remains serialized with acknowledgement so an ack cannot
     * clear/cancel between the durable write and this generation's card.
     */
    fun recordDeletion(afterCommit: (Long) -> Unit = {}): Long? = synchronized(transactionLock) {
        val lastGeneration = preferences.getLong(LAST_GENERATION_KEY, 0L)
        if (lastGeneration == Long.MAX_VALUE) return@synchronized null
        val generation = lastGeneration + 1L
        val committed = preferences.edit()
            .putLong(LAST_GENERATION_KEY, generation)
            .putLong(PENDING_GENERATION_KEY, generation)
            .commit()
        if (!committed) return@synchronized null
        afterCommit(generation)
        generation
    }

    /** Returns the pending marker without clearing or otherwise mutating it. */
    fun pendingGeneration(): Long? = synchronized(transactionLock) {
        if (!preferences.contains(PENDING_GENERATION_KEY)) {
            null
        } else {
            preferences.getLong(PENDING_GENERATION_KEY, 0L)
                .takeIf { it > 0L }
        }
    }

    /** Runs [onNoPending] only while no valid recovery marker exists. */
    fun reconcileNoPendingGeneration(onNoPending: () -> Unit): Boolean =
        synchronized(transactionLock) {
            val hasPending = preferences.contains(PENDING_GENERATION_KEY) &&
                preferences.getLong(PENDING_GENERATION_KEY, 0L) > 0L
            if (hasPending) {
                false
            } else {
                onNoPending()
                true
            }
        }

    /**
     * Compare-and-acknowledges [expectedGeneration]. [onAcknowledged] runs
     * under the same process lock as deletion recording, after the clear is
     * durably committed. This ordering prevents a stale cancellation racing a
     * newer deletion's reserved notification.
     */
    fun acknowledgeGeneration(
        expectedGeneration: Long,
        onAcknowledged: () -> Unit = {},
    ): Boolean = synchronized(transactionLock) {
        if (
            expectedGeneration <= 0L ||
            !preferences.contains(PENDING_GENERATION_KEY) ||
            preferences.getLong(PENDING_GENERATION_KEY, 0L) != expectedGeneration
        ) {
            return@synchronized false
        }
        if (!preferences.edit().remove(PENDING_GENERATION_KEY).commit()) {
            return@synchronized false
        }
        onAcknowledged()
        true
    }
}
