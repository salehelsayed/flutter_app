package com.mknoon.app

import android.content.Context
import java.util.UUID

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
        private const val PENDING_TRIGGER_KIND_KEY = "pending_trigger_kind"
        private const val PENDING_GENERIC_MAY_HAVE_ALERTED_KEY =
            "pending_generic_may_have_alerted"
        private const val CURRENT_BINDING_KEY = "current_binding"
        private const val RECOVERY_WORK_ENABLED_KEY = "recovery_work_enabled"
        private const val DESIRED_RECOVERY_WORK_ENABLED_KEY =
            "desired_recovery_work_enabled"
        private const val AUTHORITY_REVISION_KEY = "authority_revision"
        private const val AUTHORITY_MUTATION_TOKENS_KEY =
            "authority_mutation_tokens"
        internal const val TRIGGER_KIND_DELETED_BATCH = "deleted_batch"
        internal const val TRIGGER_KIND_FIXED_WAKE = "fixed_wake"
        private val transactionLock = Any()
    }

    /**
     * Strict wire decode of the one pending marker's trigger. A legacy record
     * with no kind is a deletion; an unrecognized future kind stays durable as
     * conservative unsupported work and never authorizes ACK or card cancel.
     */
    enum class TriggerKind {
        DELETED_BATCH,
        FIXED_WAKE,
        UNSUPPORTED_PENDING,
    }

    data class PendingRecovery(
        val generation: Long,
        val binding: String,
        val triggerKind: TriggerKind = TriggerKind.DELETED_BATCH,
        val genericMayHaveAlerted: Boolean = true,
    )

    /** One transaction-locked view used by headless final authority checks. */
    data class RecoveryAuthority(
        val currentBinding: String?,
        val recoveryWorkEnabled: Boolean,
        val pendingRecovery: PendingRecovery?,
        val authorityRevision: Long,
        val authorityMutationInProgress: Boolean,
    )

    data class AuthorityMutationPublication(
        val changed: Boolean,
        val committed: Boolean,
        val token: String?,
        val currentBinding: String?,
        val recoveryWorkEnabled: Boolean,
        val authorityRevision: Long,
        val authorityMutationInProgress: Boolean,
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
        recoverStaleAuthorityMutations: Boolean = false,
    ): BindingRotation = synchronized(transactionLock) {
        val normalized = binding?.trim()?.takeIf { it.isNotEmpty() }
        val desiredRecoveryWorkEnabled = normalized != null && recoveryWorkEnabled
        val previous = preferences.getString(CURRENT_BINDING_KEY, null)
        val previousRecoveryWorkEnabled = recoveryAuthorityLocked().recoveryWorkEnabled
        val bindingChanged = previous != normalized
        val previousTokens = authorityMutationTokensLocked()
        // A binding change can legitimately overlap another secure authority
        // write. Never retire that live token implicitly: doing so would
        // re-enable recovery while the other write is still in flight. Only
        // the explicit, startup-only reconciliation path may retire tokens
        // left durable by a dead process.
        val remainingTokens = if (recoverStaleAuthorityMutations) {
            emptySet()
        } else {
            previousTokens
        }
        val effectiveRecoveryWorkEnabled =
            desiredRecoveryWorkEnabled && remainingTokens.isEmpty()
        val previousDesiredRecoveryWorkEnabled = preferences.getBoolean(
            DESIRED_RECOVERY_WORK_ENABLED_KEY,
            previousRecoveryWorkEnabled,
        )
        val revision = preferences.getLong(AUTHORITY_REVISION_KEY, 0L)
        val nextRevision = if (bindingChanged) {
            revision.takeIf { it < Long.MAX_VALUE }?.plus(1L)
                ?: return@synchronized BindingRotation(
                    changed = false,
                    previousBinding = previous,
                    currentBinding = previous,
                    retiredRecovery = null,
                    committed = false,
                    recoveryWorkEnabled = previousRecoveryWorkEnabled,
                )
        } else {
            revision
        }
        if (
            previous == normalized &&
            preferences.contains(DESIRED_RECOVERY_WORK_ENABLED_KEY) &&
            previousDesiredRecoveryWorkEnabled == desiredRecoveryWorkEnabled &&
            previousRecoveryWorkEnabled == effectiveRecoveryWorkEnabled &&
            previousTokens == remainingTokens
        ) {
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
                preferences.contains(PENDING_BINDING_KEY) ||
                preferences.contains(PENDING_TRIGGER_KIND_KEY) ||
                preferences.contains(PENDING_GENERIC_MAY_HAVE_ALERTED_KEY)
        val editor = preferences.edit()
        if (normalized == null) {
            editor.remove(CURRENT_BINDING_KEY)
        } else {
            editor.putString(CURRENT_BINDING_KEY, normalized)
        }
        editor.putBoolean(
            DESIRED_RECOVERY_WORK_ENABLED_KEY,
            desiredRecoveryWorkEnabled,
        )
        editor.putBoolean(
            RECOVERY_WORK_ENABLED_KEY,
            effectiveRecoveryWorkEnabled,
        )
        editor.putLong(AUTHORITY_REVISION_KEY, nextRevision)
        if (remainingTokens.isEmpty()) {
            editor.remove(AUTHORITY_MUTATION_TOKENS_KEY)
        } else {
            editor.putStringSet(AUTHORITY_MUTATION_TOKENS_KEY, remainingTokens)
        }
        // Rotation is also the repair boundary for an interrupted/corrupt
        // legacy marker whose generation or binding half is missing. Such a
        // marker has no safe owner and must not survive account cutover. Kind
        // and audible disposition are removed in the same durable edit.
        if (bindingChanged && hasPendingMarkerKeys) {
            editor.remove(PENDING_GENERATION_KEY)
            editor.remove(PENDING_BINDING_KEY)
            editor.remove(PENDING_TRIGGER_KIND_KEY)
            editor.remove(PENDING_GENERIC_MAY_HAVE_ALERTED_KEY)
        }
        val committed = editor.commit()
        BindingRotation(
            changed = committed,
            previousBinding = previous,
            currentBinding = if (committed) normalized else previous,
            retiredRecovery = if (committed) retired else null,
            committed = committed,
            recoveryWorkEnabled = if (committed) {
                effectiveRecoveryWorkEnabled
            } else {
                previousRecoveryWorkEnabled
            },
        )
    }

    /**
     * Durably fences a secure authority mutation before its first write.
     * Recovery is disabled until every overlapping token finishes. The
     * revision advances at begin, so a worker that already performed its final
     * Dart read can no longer acknowledge under the old authority.
     */
    fun beginAuthorityMutation(): AuthorityMutationPublication =
        synchronized(transactionLock) {
            val authority = recoveryAuthorityLocked()
            if (authority.authorityRevision == Long.MAX_VALUE) {
                val disabledCommitted = preferences.edit()
                    .putBoolean(RECOVERY_WORK_ENABLED_KEY, false)
                    .commit()
                return@synchronized authorityMutationPublicationLocked(
                    changed = disabledCommitted,
                    committed = disabledCommitted,
                    token = null,
                )
            }
            val token = UUID.randomUUID().toString()
            val tokens = authorityMutationTokensLocked().toMutableSet()
            tokens.add(token)
            val editor = preferences.edit()
                .putLong(AUTHORITY_REVISION_KEY, authority.authorityRevision + 1L)
                .putStringSet(AUTHORITY_MUTATION_TOKENS_KEY, tokens)
                .putBoolean(RECOVERY_WORK_ENABLED_KEY, false)
            if (!preferences.contains(DESIRED_RECOVERY_WORK_ENABLED_KEY)) {
                editor.putBoolean(
                    DESIRED_RECOVERY_WORK_ENABLED_KEY,
                    authority.recoveryWorkEnabled,
                )
            }
            val committed = editor.commit()
            authorityMutationPublicationLocked(
                changed = committed,
                committed = committed,
                token = token.takeIf { committed },
            )
        }

    /** Completes exactly one mutation token; wrong/stale tokens fail closed. */
    fun finishAuthorityMutation(token: String): AuthorityMutationPublication =
        synchronized(transactionLock) {
            val normalized = token.trim()
            val tokens = authorityMutationTokensLocked().toMutableSet()
            if (normalized.isEmpty() || !tokens.remove(normalized)) {
                return@synchronized authorityMutationPublicationLocked(
                    changed = false,
                    committed = false,
                    token = null,
                )
            }
            val binding = preferences.getString(CURRENT_BINDING_KEY, null)
                ?.trim()
                ?.takeIf { it.isNotEmpty() }
            val desired = binding != null && preferences.getBoolean(
                DESIRED_RECOVERY_WORK_ENABLED_KEY,
                preferences.getBoolean(RECOVERY_WORK_ENABLED_KEY, false),
            )
            val effective = desired && tokens.isEmpty()
            val editor = preferences.edit()
                .putBoolean(RECOVERY_WORK_ENABLED_KEY, effective)
            if (tokens.isEmpty()) {
                editor.remove(AUTHORITY_MUTATION_TOKENS_KEY)
            } else {
                editor.putStringSet(AUTHORITY_MUTATION_TOKENS_KEY, tokens)
            }
            val committed = editor.commit()
            authorityMutationPublicationLocked(
                changed = committed,
                committed = committed,
                token = null,
            )
        }

    fun currentBinding(): String? = synchronized(transactionLock) {
        preferences.getString(CURRENT_BINDING_KEY, null)
            ?.trim()
            ?.takeIf { it.isNotEmpty() }
    }

    fun recoveryWorkEnabled(): Boolean = synchronized(transactionLock) {
        recoveryAuthorityLocked().recoveryWorkEnabled
    }

    /** Atomically snapshots binding, readiness, and the account-bound marker. */
    fun recoveryAuthority(): RecoveryAuthority = synchronized(transactionLock) {
        recoveryAuthorityLocked()
    }

    /**
     * Returns the committed generation, or null when persistence failed.
     * [afterCommit] remains serialized with acknowledgement so an ack cannot
     * clear/cancel between the durable write and this generation's card.
     */
    fun recordDeletion(afterCommit: (Long) -> Unit = {}): Long? = synchronized(transactionLock) {
        recordTriggerLocked(TriggerKind.DELETED_BATCH, afterCommit)
    }

    /**
     * Records one exact content-free fixed wake as the newest pending trigger.
     *
     * The replacement commits kind and audible disposition atomically with the
     * marker. A fixed trigger is always requested silent, so it publishes
     * `genericMayHaveAlerted = false` — unless the record it coalesces over
     * already carries an audible ambiguity, which is never downgraded.
     */
    fun recordFixedWake(afterCommit: (Long) -> Unit = {}): Long? = synchronized(transactionLock) {
        recordTriggerLocked(TriggerKind.FIXED_WAKE, afterCommit)
    }

    private fun recordTriggerLocked(
        kind: TriggerKind,
        afterCommit: (Long) -> Unit,
    ): Long? {
        require(kind != TriggerKind.UNSUPPORTED_PENDING) {
            "unsupported trigger kinds are decode-only"
        }
        val binding = preferences.getString(CURRENT_BINDING_KEY, null)
            ?.trim()
            ?.takeIf { it.isNotEmpty() }
            ?: return null
        val lastGeneration = preferences.getLong(LAST_GENERATION_KEY, 0L)
        if (lastGeneration == Long.MAX_VALUE) return null
        val generation = lastGeneration + 1L
        val genericMayHaveAlerted = when (kind) {
            // The incumbent deletion card is possibly audible; commit the
            // conservative ambiguity before any notify attempt runs.
            TriggerKind.DELETED_BATCH -> true
            // Fixed generic requests are always silent. Coalescing over a
            // same-binding record that may already have alerted preserves that
            // ambiguity instead of downgrading it.
            TriggerKind.FIXED_WAKE ->
                pendingRecoveryLocked(requireCurrentBinding = false)
                    ?.takeIf { it.binding == binding }
                    ?.genericMayHaveAlerted == true
            TriggerKind.UNSUPPORTED_PENDING -> true
        }
        val committed = preferences.edit()
            .putLong(LAST_GENERATION_KEY, generation)
            .putLong(PENDING_GENERATION_KEY, generation)
            .putString(PENDING_BINDING_KEY, binding)
            .putString(PENDING_TRIGGER_KIND_KEY, wireTriggerKind(kind))
            .putBoolean(PENDING_GENERIC_MAY_HAVE_ALERTED_KEY, genericMayHaveAlerted)
            .commit()
        if (!committed) return null
        afterCommit(generation)
        return generation
    }

    private fun wireTriggerKind(kind: TriggerKind): String = when (kind) {
        TriggerKind.DELETED_BATCH -> TRIGGER_KIND_DELETED_BATCH
        TriggerKind.FIXED_WAKE -> TRIGGER_KIND_FIXED_WAKE
        TriggerKind.UNSUPPORTED_PENDING ->
            throw IllegalArgumentException("unsupported trigger kinds are decode-only")
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

    /**
     * Headless-only compare-and-acknowledgement.
     *
     * Unlike the warm-app API above, this additionally requires recovery work
     * to remain enabled in the same transaction as the exact marker clear. A
     * committed same-binding rollback therefore fences a late worker ACK while
     * retaining the marker for warm-app recovery.
     */
    fun acknowledgeHeadlessRecovery(
        expectedGeneration: Long,
        expectedBinding: String,
        expectedAuthorityRevision: Long,
        onAcknowledged: () -> Unit = {},
    ): Boolean = synchronized(transactionLock) {
        val authority = recoveryAuthorityLocked()
        val pending = authority.pendingRecovery ?: return@synchronized false
        if (
            !authority.recoveryWorkEnabled ||
            authority.authorityMutationInProgress ||
            authority.authorityRevision != expectedAuthorityRevision ||
            authority.currentBinding != expectedBinding ||
            pending.generation != expectedGeneration ||
            pending.binding != expectedBinding
        ) {
            return@synchronized false
        }
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
            pending.binding != expectedBinding ||
            // An unrecognized future trigger kind never decodes as no work and
            // never authorizes this binary's ACK/cancel path. Binding rotation
            // remains its only repair boundary.
            pending.triggerKind == TriggerKind.UNSUPPORTED_PENDING
        ) {
            return false
        }
        if (
            !preferences.edit()
                .remove(PENDING_GENERATION_KEY)
                .remove(PENDING_BINDING_KEY)
                .remove(PENDING_TRIGGER_KIND_KEY)
                .remove(PENDING_GENERIC_MAY_HAVE_ALERTED_KEY)
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
        // Legacy records predate the kind/disposition fields: no kind means the
        // old deletion service wrote it, and its card may already have alerted.
        val triggerKind = when {
            !preferences.contains(PENDING_TRIGGER_KIND_KEY) ->
                TriggerKind.DELETED_BATCH
            else -> when (preferences.getString(PENDING_TRIGGER_KIND_KEY, null)) {
                TRIGGER_KIND_DELETED_BATCH -> TriggerKind.DELETED_BATCH
                TRIGGER_KIND_FIXED_WAKE -> TriggerKind.FIXED_WAKE
                else -> TriggerKind.UNSUPPORTED_PENDING
            }
        }
        return PendingRecovery(
            generation = generation,
            binding = binding,
            triggerKind = triggerKind,
            genericMayHaveAlerted = preferences.getBoolean(
                PENDING_GENERIC_MAY_HAVE_ALERTED_KEY,
                true,
            ),
        )
    }

    private fun recoveryAuthorityLocked(): RecoveryAuthority {
        val binding = preferences.getString(CURRENT_BINDING_KEY, null)
            ?.trim()
            ?.takeIf { it.isNotEmpty() }
        return RecoveryAuthority(
            currentBinding = binding,
            recoveryWorkEnabled = binding != null &&
                preferences.getBoolean(RECOVERY_WORK_ENABLED_KEY, false) &&
                authorityMutationTokensLocked().isEmpty(),
            pendingRecovery = pendingRecoveryLocked(requireCurrentBinding = true),
            authorityRevision = preferences.getLong(AUTHORITY_REVISION_KEY, 0L),
            authorityMutationInProgress = authorityMutationTokensLocked().isNotEmpty(),
        )
    }

    private fun authorityMutationTokensLocked(): Set<String> =
        preferences.getStringSet(AUTHORITY_MUTATION_TOKENS_KEY, emptySet())
            ?.mapNotNull { value -> value.trim().takeIf { it.isNotEmpty() } }
            ?.toSet()
            ?: emptySet()

    private fun authorityMutationPublicationLocked(
        changed: Boolean,
        committed: Boolean,
        token: String?,
    ): AuthorityMutationPublication {
        val authority = recoveryAuthorityLocked()
        return AuthorityMutationPublication(
            changed = changed,
            committed = committed,
            token = token,
            currentBinding = authority.currentBinding,
            recoveryWorkEnabled = authority.recoveryWorkEnabled,
            authorityRevision = authority.authorityRevision,
            authorityMutationInProgress = authority.authorityMutationInProgress,
        )
    }
}
