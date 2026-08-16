package com.mknoon.app

import android.content.Context

/**
 * Shared production seam for the two generic recovery triggers: a
 * Play-services deleted batch and an exact content-free fixed wake.
 *
 * The store's [DroppedPushRecoveryStore.recordDeletion] and
 * [DroppedPushRecoveryStore.recordFixedWake] callbacks deliberately remain the
 * transaction boundary. Resnapshotting, optional scheduling, and the caller's
 * post-commit work all run while acknowledgement is still fenced by the store
 * lock, and scheduling adopts the committed snapshot's own trigger kind.
 */
internal class ProductionDeletedBatchRecovery(
    context: Context,
    private val store: DroppedPushRecoveryStore = DroppedPushRecoveryStore(context),
    scheduler: DroppedPushRecoveryWorkScheduler = DroppedPushRecoveryWorkScheduler(context),
    private val scheduleRecovery: (DroppedPushRecoveryStore.PendingRecovery) -> Unit =
        scheduler::enqueueDeletedBatch,
    private val scheduleFixedWakeRecovery: (DroppedPushRecoveryStore.PendingRecovery) -> Unit =
        scheduler::enqueueFixedWake,
) {
    fun commitAndSchedule(
        afterCommit: (Long) -> Unit = {},
    ): DroppedPushRecoveryStore.PendingRecovery? = recordGenericRecoveryTrigger(
        DroppedPushRecoveryStore.TriggerKind.DELETED_BATCH,
        afterCommit,
    )

    /** The one commit/schedule entry used by deletion, fixed ingress and the debug probe. */
    fun recordGenericRecoveryTrigger(
        kind: DroppedPushRecoveryStore.TriggerKind,
        afterCommit: (Long) -> Unit = {},
    ): DroppedPushRecoveryStore.PendingRecovery? {
        require(kind != DroppedPushRecoveryStore.TriggerKind.UNSUPPORTED_PENDING) {
            "unsupported trigger kinds are decode-only"
        }
        var committedSnapshot: DroppedPushRecoveryStore.PendingRecovery? = null
        val commitWork: (Long) -> Unit = { generation ->
            val snapshot = store.pendingRecovery()
            if (snapshot != null && snapshot.generation == generation) {
                committedSnapshot = snapshot
                if (store.recoveryWorkEnabled()) {
                    runCatching { scheduleCommittedTrigger(snapshot) }
                }
                runCatching { afterCommit(generation) }
            }
        }
        when (kind) {
            DroppedPushRecoveryStore.TriggerKind.DELETED_BATCH ->
                store.recordDeletion { generation -> commitWork(generation) }
            DroppedPushRecoveryStore.TriggerKind.FIXED_WAKE ->
                store.recordFixedWake { generation -> commitWork(generation) }
            DroppedPushRecoveryStore.TriggerKind.UNSUPPORTED_PENDING -> Unit
        }
        return committedSnapshot
    }

    private fun scheduleCommittedTrigger(
        snapshot: DroppedPushRecoveryStore.PendingRecovery,
    ) = when (snapshot.triggerKind) {
        DroppedPushRecoveryStore.TriggerKind.FIXED_WAKE ->
            scheduleFixedWakeRecovery(snapshot)
        else -> scheduleRecovery(snapshot)
    }
}
