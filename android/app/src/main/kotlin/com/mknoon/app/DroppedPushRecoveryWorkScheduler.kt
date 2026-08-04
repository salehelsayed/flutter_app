package com.mknoon.app

import android.content.Context
import androidx.work.BackoffPolicy
import androidx.work.Constraints
import androidx.work.Data
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.ExistingWorkPolicy
import androidx.work.NetworkType
import androidx.work.OneTimeWorkRequest
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.OutOfQuotaPolicy
import androidx.work.PeriodicWorkRequest
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import java.nio.charset.StandardCharsets
import java.security.MessageDigest
import java.util.concurrent.TimeUnit

internal interface RecoveryWorkEnqueuer {
    fun enqueueUniqueImmediate(
        uniqueName: String,
        policy: ExistingWorkPolicy,
        request: OneTimeWorkRequest,
    )

    fun enqueueUniquePeriodic(
        uniqueName: String,
        policy: ExistingPeriodicWorkPolicy,
        request: PeriodicWorkRequest,
    )

    fun cancelUniqueWork(uniqueName: String)
}

internal fun interface RecoveryBindingScheduler {
    fun onBindingRotated(rotation: DroppedPushRecoveryStore.BindingRotation)
}

private class AndroidXRecoveryWorkEnqueuer(context: Context) : RecoveryWorkEnqueuer {
    private val applicationContext = context.applicationContext

    private fun workManager(): WorkManager = WorkManager.getInstance(applicationContext)

    override fun enqueueUniqueImmediate(
        uniqueName: String,
        policy: ExistingWorkPolicy,
        request: OneTimeWorkRequest,
    ) {
        workManager().enqueueUniqueWork(uniqueName, policy, request)
    }

    override fun enqueueUniquePeriodic(
        uniqueName: String,
        policy: ExistingPeriodicWorkPolicy,
        request: PeriodicWorkRequest,
    ) {
        workManager().enqueueUniquePeriodicWork(uniqueName, policy, request)
    }

    override fun cancelUniqueWork(uniqueName: String) {
        workManager().cancelUniqueWork(uniqueName)
    }
}

/** Builds the persistent, serial wake requests; workers resnapshot the store. */
internal class DroppedPushRecoveryWorkScheduler(
    context: Context,
    private val enqueuer: RecoveryWorkEnqueuer = AndroidXRecoveryWorkEnqueuer(context),
    private val store: DroppedPushRecoveryStore = DroppedPushRecoveryStore(context),
) : RecoveryBindingScheduler {
    companion object {
        internal const val INPUT_REASON = "recovery_reason"
        internal const val INPUT_WAKE_GENERATION = "wake_generation"
        internal const val INPUT_BINDING_DIGEST = "binding_digest"
        internal const val REASON_DELETED_BATCH = "deleted_batch"
        internal const val REASON_PERIODIC_SWEEP = "periodic_sweep"
        private const val IMMEDIATE_PREFIX = "mknoon-recovery-immediate-"
        private const val PERIODIC_PREFIX = "mknoon-recovery-periodic-"
        private const val WORK_TAG = "mknoon-canonical-recovery"

        internal fun bindingDigest(binding: String): String {
            val digest = MessageDigest.getInstance("SHA-256")
                .digest(binding.toByteArray(StandardCharsets.UTF_8))
            return digest.joinToString(separator = "") { byte -> "%02x".format(byte) }
        }

        internal fun immediateUniqueName(binding: String): String =
            IMMEDIATE_PREFIX + bindingDigest(binding).take(24)

        internal fun periodicUniqueName(binding: String): String =
            PERIODIC_PREFIX + bindingDigest(binding).take(24)
    }

    fun enqueueDeletedBatch(snapshot: DroppedPushRecoveryStore.PendingRecovery) {
        val request = OneTimeWorkRequestBuilder<HeadlessCanonicalRecoveryWorker>()
            .setConstraints(connectedConstraints())
            .setInputData(
                Data.Builder()
                    .putString(INPUT_REASON, REASON_DELETED_BATCH)
                    .putLong(INPUT_WAKE_GENERATION, snapshot.generation)
                    .putString(INPUT_BINDING_DIGEST, bindingDigest(snapshot.binding))
                    .build(),
            )
            .setBackoffCriteria(BackoffPolicy.EXPONENTIAL, 30, TimeUnit.SECONDS)
            .setExpedited(OutOfQuotaPolicy.RUN_AS_NON_EXPEDITED_WORK_REQUEST)
            .addTag(WORK_TAG)
            .build()
        enqueuer.enqueueUniqueImmediate(
            immediateUniqueName(snapshot.binding),
            ExistingWorkPolicy.APPEND_OR_REPLACE,
            request,
        )
    }

    fun ensurePeriodic(binding: String) {
        if (binding.isBlank()) return
        val request = PeriodicWorkRequestBuilder<HeadlessCanonicalRecoveryWorker>(
            6,
            TimeUnit.HOURS,
            1,
            TimeUnit.HOURS,
        )
            .setConstraints(connectedConstraints())
            .setInputData(
                Data.Builder()
                    .putString(INPUT_REASON, REASON_PERIODIC_SWEEP)
                    .putString(INPUT_BINDING_DIGEST, bindingDigest(binding))
                    .build(),
            )
            .addTag(WORK_TAG)
            .build()
        enqueuer.enqueueUniquePeriodic(
            periodicUniqueName(binding),
            ExistingPeriodicWorkPolicy.UPDATE,
            request,
        )
    }

    override fun onBindingRotated(rotation: DroppedPushRecoveryStore.BindingRotation) {
        if (!rotation.committed || !rotation.changed) return
        rotation.previousBinding?.let { previous ->
            enqueuer.cancelUniqueWork(immediateUniqueName(previous))
            enqueuer.cancelUniqueWork(periodicUniqueName(previous))
        }
        if (rotation.recoveryWorkEnabled) {
            rotation.currentBinding?.let { binding ->
                ensurePeriodic(binding)
                store.pendingRecovery()
                    ?.takeIf { pending -> pending.binding == binding }
                    ?.let(::enqueueDeletedBatch)
            }
        }
    }

    private fun connectedConstraints(): Constraints = Constraints.Builder()
        .setRequiredNetworkType(NetworkType.CONNECTED)
        .build()
}
