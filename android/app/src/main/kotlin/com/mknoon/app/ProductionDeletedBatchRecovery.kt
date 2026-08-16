package com.mknoon.app

import android.content.Context

/**
 * Shared production seam for a Play-services deleted batch.
 *
 * The store's [DroppedPushRecoveryStore.recordDeletion] callback deliberately
 * remains the transaction boundary. Resnapshotting, optional scheduling, and
 * the caller's post-commit work all run while acknowledgement is still fenced
 * by the store lock.
 */
internal class ProductionDeletedBatchRecovery(
    context: Context,
    private val store: DroppedPushRecoveryStore = DroppedPushRecoveryStore(context),
    private val scheduleRecovery: (DroppedPushRecoveryStore.PendingRecovery) -> Unit =
        DroppedPushRecoveryWorkScheduler(context)::enqueueDeletedBatch,
) {
    fun commitAndSchedule(
        afterCommit: (Long) -> Unit = {},
    ): DroppedPushRecoveryStore.PendingRecovery? {
        var committedSnapshot: DroppedPushRecoveryStore.PendingRecovery? = null
        store.recordDeletion { generation ->
            val snapshot = store.pendingRecovery()
            if (snapshot == null || snapshot.generation != generation) {
                return@recordDeletion
            }
            committedSnapshot = snapshot
            if (store.recoveryWorkEnabled()) {
                runCatching { scheduleRecovery(snapshot) }
            }
            runCatching { afterCommit(generation) }
        }
        return committedSnapshot
    }
}
