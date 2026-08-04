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
        private const val PENDING_BINDING_KEY = "pending_binding"
        private const val CURRENT_BINDING_KEY = "current_binding"
        private const val RECOVERY_WORK_ENABLED_KEY = "recovery_work_enabled"
        private val transactionLock = Any()
    }

    data class PendingRecovery(
        val generation: Long,
        val binding: String,
    )

    data class BindingRotation(
        val changed: Boolean,
        val previousBinding: String?,
        val currentBinding: String?,
        val retiredRecovery: PendingRecovery?,
        val committed: Boolean,
        val recoveryWorkEnabled: Boolean,
    )

    private val preferences = context.applicationContext.getSharedPreferences(
        PREFERENCES_NAME,
        Context.MODE_PRIVATE,
    )

    /**
     * Atomically rotates the opaque installation/account binding. Any marker
     * owned by the previous binding is retired in the same durable edit, so it
     * cannot be acquired or acknowledged after account cutover.
     */
    fun setCurrentBinding(
        binding: String?,
        recoveryWorkEnabled: Boolean = false,
    ): BindingRotation = synchronized(transactionLock) {
        val normalized = binding?.trim()?.takeIf { it.isNotEmpty() }
        val desiredRecoveryWorkEnabled = normalized != null && recoveryWorkEnabled
        val previous = preferences.getString(CURRENT_BINDING_KEY, null)
        val previousRecoveryWorkEnabled = preferences.getBoolean(
            RECOVERY_WORK_ENABLED_KEY,
            false,
        )
        val bindingChanged = previous != normalized
        if (previous == normalized && previousRecoveryWorkEnabled == desiredRecoveryWorkEnabled) {
            return@synchronized BindingRotation(
                changed = false,
                previousBinding = previous,
                currentBinding = previous,
                retiredRecovery = null,
                committed = true,
                recoveryWorkEnabled = previousRecoveryWorkEnabled,
            )
        }
        val pending = pendingRecoveryLocked(requireCurrentBinding = false)
        val retired = pending?.takeIf { bindingChanged && it.binding != normalized }
        val hasPendingMarkerKeys =
            preferences.contains(PENDING_GENERATION_KEY) ||
                preferences.contains(PENDING_BINDING_KEY)
        val editor = preferences.edit()
        if (normalized == null) {
            editor.remove(CURRENT_BINDING_KEY)
        } else {
            editor.putString(CURRENT_BINDING_KEY, normalized)
        }
        editor.putBoolean(RECOVERY_WORK_ENABLED_KEY, desiredRecoveryWorkEnabled)
        // Rotation is also the repair boundary for an interrupted/corrupt
        // legacy marker whose generation or binding half is missing. Such a
        // marker has no safe owner and must not survive account cutover.
        if (bindingChanged && hasPendingMarkerKeys) {
            editor.remove(PENDING_GENERATION_KEY)
            editor.remove(PENDING_BINDING_KEY)
        }
        val committed = editor.commit()
        BindingRotation(
            changed = committed,
            previousBinding = previous,
            currentBinding = if (committed) normalized else previous,
            retiredRecovery = if (committed) retired else null,
            committed = committed,
            recoveryWorkEnabled = if (committed) {
                desiredRecoveryWorkEnabled
            } else {
                previousRecoveryWorkEnabled
            },
        )
    }

    fun currentBinding(): String? = synchronized(transactionLock) {
        preferences.getString(CURRENT_BINDING_KEY, null)
            ?.trim()
            ?.takeIf { it.isNotEmpty() }
    }

    fun recoveryWorkEnabled(): Boolean = synchronized(transactionLock) {
        preferences.getBoolean(RECOVERY_WORK_ENABLED_KEY, false) &&
            preferences.getString(CURRENT_BINDING_KEY, null)
                ?.trim()
                ?.isNotEmpty() == true
    }

    /**
     * Returns the committed generation, or null when persistence failed.
     * [afterCommit] remains serialized with acknowledgement so an ack cannot
     * clear/cancel between the durable write and this generation's card.
     */
    fun recordDeletion(afterCommit: (Long) -> Unit = {}): Long? = synchronized(transactionLock) {
        val binding = preferences.getString(CURRENT_BINDING_KEY, null)
            ?.trim()
            ?.takeIf { it.isNotEmpty() }
            ?: return@synchronized null
        val lastGeneration = preferences.getLong(LAST_GENERATION_KEY, 0L)
        if (lastGeneration == Long.MAX_VALUE) return@synchronized null
        val generation = lastGeneration + 1L
        val committed = preferences.edit()
            .putLong(LAST_GENERATION_KEY, generation)
            .putLong(PENDING_GENERATION_KEY, generation)
            .putString(PENDING_BINDING_KEY, binding)
            .commit()
        if (!committed) return@synchronized null
        afterCommit(generation)
        generation
    }

    /** Returns the pending marker without clearing or otherwise mutating it. */
    fun pendingGeneration(): Long? = synchronized(transactionLock) {
        pendingRecoveryLocked(requireCurrentBinding = true)?.generation
    }

    /** Returns the account-bound marker without consuming it. */
    fun pendingRecovery(): PendingRecovery? = synchronized(transactionLock) {
        pendingRecoveryLocked(requireCurrentBinding = true)
    }

    /** Runs [onNoPending] only while no valid recovery marker exists. */
    fun reconcileNoPendingGeneration(onNoPending: () -> Unit): Boolean =
        synchronized(transactionLock) {
            val hasPending = pendingRecoveryLocked(requireCurrentBinding = true) != null
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
        val binding = preferences.getString(CURRENT_BINDING_KEY, null)
            ?: return@synchronized false
        acknowledgeRecoveryLocked(expectedGeneration, binding, onAcknowledged)
    }

    /** Compare-and-acknowledges both generation and account/install binding. */
    fun acknowledgeRecovery(
        expectedGeneration: Long,
        expectedBinding: String,
        onAcknowledged: () -> Unit = {},
    ): Boolean = synchronized(transactionLock) {
        acknowledgeRecoveryLocked(expectedGeneration, expectedBinding, onAcknowledged)
    }

    private fun acknowledgeRecoveryLocked(
        expectedGeneration: Long,
        expectedBinding: String,
        onAcknowledged: () -> Unit,
    ): Boolean {
        val pending = pendingRecoveryLocked(requireCurrentBinding = true)
        if (
            expectedGeneration <= 0L ||
            expectedBinding.isBlank() ||
            pending?.generation != expectedGeneration ||
            pending.binding != expectedBinding
        ) {
            return false
        }
        if (
            !preferences.edit()
                .remove(PENDING_GENERATION_KEY)
                .remove(PENDING_BINDING_KEY)
                .commit()
        ) {
            return false
        }
        onAcknowledged()
        return true
    }

    private fun pendingRecoveryLocked(requireCurrentBinding: Boolean): PendingRecovery? {
        if (!preferences.contains(PENDING_GENERATION_KEY)) return null
        val generation = preferences.getLong(PENDING_GENERATION_KEY, 0L)
            .takeIf { it > 0L }
            ?: return null
        val binding = preferences.getString(PENDING_BINDING_KEY, null)
            ?.trim()
            ?.takeIf { it.isNotEmpty() }
            ?: return null
        if (
            requireCurrentBinding &&
            preferences.getString(CURRENT_BINDING_KEY, null) != binding
        ) {
            return null
        }
        return PendingRecovery(generation, binding)
    }
}
