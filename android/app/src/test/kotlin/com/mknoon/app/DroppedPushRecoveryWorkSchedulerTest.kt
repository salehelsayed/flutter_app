package com.mknoon.app

import android.app.NotificationManager
import android.content.Context
import android.content.pm.ServiceInfo
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.ExistingWorkPolicy
import androidx.work.NetworkType
import androidx.work.OneTimeWorkRequest
import androidx.work.OutOfQuotaPolicy
import androidx.work.PeriodicWorkRequest
import java.util.concurrent.TimeUnit
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [33])
class DroppedPushRecoveryWorkSchedulerTest {
    private lateinit var context: Context
    private lateinit var store: DroppedPushRecoveryStore

    @Before
    fun setUp() {
        context = RuntimeEnvironment.getApplication()
        context.getSharedPreferences(
            DroppedPushRecoveryStore.PREFERENCES_NAME,
            Context.MODE_PRIVATE,
        ).edit().clear().commit()
        store = DroppedPushRecoveryStore(context)
        store.setCurrentBinding(
            "installation-a/account-a",
            recoveryWorkEnabled = true,
        )
    }

    @Test
    fun `deleted batch commits then enqueues unique connected work`() {
        val enqueuer = RecordingRecoveryWorkEnqueuer()
        val scheduler = DroppedPushRecoveryWorkScheduler(context, enqueuer)
        val marker = requireNotNull(store.recordDeletion())
        val snapshot = requireNotNull(store.pendingRecovery())

        scheduler.enqueueDeletedBatch(snapshot)
        scheduler.enqueueDeletedBatch(requireNotNull(store.pendingRecovery()))

        assertEquals(2, enqueuer.immediate.size)
        assertEquals(1, enqueuer.immediate.map { it.uniqueName }.distinct().size)
        enqueuer.immediate.forEach { recorded ->
            assertEquals(ExistingWorkPolicy.APPEND_OR_REPLACE, recorded.policy)
            assertEquals(NetworkType.CONNECTED, recorded.request.workSpec.constraints.requiredNetworkType)
            assertTrue(recorded.request.workSpec.expedited)
            assertEquals(OutOfQuotaPolicy.RUN_AS_NON_EXPEDITED_WORK_REQUEST, recorded.request.workSpec.outOfQuotaPolicy)
            assertEquals(marker, recorded.request.workSpec.input.getLong(DroppedPushRecoveryWorkScheduler.INPUT_WAKE_GENERATION, -1L))
            assertEquals(
                DroppedPushRecoveryWorkScheduler.REASON_DELETED_BATCH,
                recorded.request.workSpec.input.getString(DroppedPushRecoveryWorkScheduler.INPUT_REASON),
            )
        }
        assertFalse(enqueuer.immediate.first().uniqueName.contains("installation-a/account-a"))
    }

    @Test
    fun testTC37503FixedWakeUsesExistingUniqueExpeditedChain() {
        val enqueuer = RecordingRecoveryWorkEnqueuer()
        val scheduler = DroppedPushRecoveryWorkScheduler(context, enqueuer, store)

        // The fixed wake rides the exact deleted-batch unique immediate chain:
        // same unique name, same append policy, same expedited/connected shape.
        store.recordDeletion()
        scheduler.enqueueDeletedBatch(requireNotNull(store.pendingRecovery()))
        val fixedGeneration = requireNotNull(store.recordFixedWake())
        scheduler.enqueueFixedWake(requireNotNull(store.pendingRecovery()))

        assertEquals(2, enqueuer.immediate.size)
        assertEquals(1, enqueuer.immediate.map { it.uniqueName }.distinct().size)
        val fixedRecorded = enqueuer.immediate.last()
        assertEquals(ExistingWorkPolicy.APPEND_OR_REPLACE, fixedRecorded.policy)
        assertTrue(fixedRecorded.request.workSpec.expedited)
        assertEquals(
            OutOfQuotaPolicy.RUN_AS_NON_EXPEDITED_WORK_REQUEST,
            fixedRecorded.request.workSpec.outOfQuotaPolicy,
        )
        assertEquals(
            NetworkType.CONNECTED,
            fixedRecorded.request.workSpec.constraints.requiredNetworkType,
        )
        assertEquals(
            DroppedPushRecoveryWorkScheduler.REASON_FIXED_WAKE,
            fixedRecorded.request.workSpec.input.getString(
                DroppedPushRecoveryWorkScheduler.INPUT_REASON,
            ),
        )
        assertEquals(
            fixedGeneration,
            fixedRecorded.request.workSpec.input.getLong(
                DroppedPushRecoveryWorkScheduler.INPUT_WAKE_GENERATION,
                -1L,
            ),
        )

        // A stale queued deleted-batch reason adopts the newest current marker
        // with that marker's own fixed trigger semantics.
        val staleDeletedInput = enqueuer.immediate.first().request.workSpec.input
        val adopted = requireNotNull(
            HeadlessCanonicalRecoveryWorker.resolveStartSnapshot(
                store,
                staleDeletedInput,
            ),
        )
        assertEquals(DroppedPushRecoveryWorkScheduler.REASON_FIXED_WAKE, adopted.reason)
        assertEquals(fixedGeneration, adopted.pendingRecovery?.generation)
        assertEquals(
            DroppedPushRecoveryStore.TriggerKind.FIXED_WAKE,
            adopted.pendingRecovery?.triggerKind,
        )

        // Immediate enqueue failure leaves the durable marker; a same-binding
        // re-enable re-enqueues the pending fixed trigger on the same chain and
        // keeps the one bounded periodic recovery path armed.
        val disabled = store.setCurrentBinding(
            "installation-a/account-a",
            recoveryWorkEnabled = false,
        )
        scheduler.onBindingRotated(disabled)
        assertEquals(fixedGeneration, store.pendingGeneration())
        val reEnabled = store.setCurrentBinding(
            "installation-a/account-a",
            recoveryWorkEnabled = true,
        )
        scheduler.onBindingRotated(reEnabled)
        val reEnqueued = enqueuer.immediate.last()
        assertEquals(enqueuer.immediate.first().uniqueName, reEnqueued.uniqueName)
        assertEquals(
            DroppedPushRecoveryWorkScheduler.REASON_FIXED_WAKE,
            reEnqueued.request.workSpec.input.getString(
                DroppedPushRecoveryWorkScheduler.INPUT_REASON,
            ),
        )
        assertEquals(1, enqueuer.periodic.size)
        assertEquals(
            DroppedPushRecoveryWorkScheduler.REASON_PERIODIC_SWEEP,
            enqueuer.periodic.single().request.workSpec.input.getString(
                DroppedPushRecoveryWorkScheduler.INPUT_REASON,
            ),
        )
    }

    @Test
    fun `generation arriving during active work is resnapshotted`() {
        val enqueuer = RecordingRecoveryWorkEnqueuer()
        val scheduler = DroppedPushRecoveryWorkScheduler(context, enqueuer)

        store.recordDeletion()
        scheduler.enqueueDeletedBatch(requireNotNull(store.pendingRecovery()))
        val generationAWake = enqueuer.immediate.single().request.workSpec.input
        val generationB = requireNotNull(store.recordDeletion())
        scheduler.enqueueDeletedBatch(requireNotNull(store.pendingRecovery()))

        assertEquals(listOf(1L, generationB), enqueuer.immediate.map {
            it.request.workSpec.input.getLong(DroppedPushRecoveryWorkScheduler.INPUT_WAKE_GENERATION, -1L)
        })
        assertTrue(enqueuer.immediate.all { it.policy == ExistingWorkPolicy.APPEND_OR_REPLACE })

        val beginSnapshot = HeadlessCanonicalRecoveryWorker.resolveStartSnapshot(
            store,
            generationAWake,
        )
        assertEquals(generationB, beginSnapshot?.pendingRecovery?.generation)

        store.setCurrentBinding("installation-a/account-b")
        assertNull(
            HeadlessCanonicalRecoveryWorker.resolveStartSnapshot(
                store,
                generationAWake,
            ),
        )
    }

    @Test
    fun `periodic sweep is unique bounded and account gated`() {
        val enqueuer = RecordingRecoveryWorkEnqueuer()
        val scheduler = DroppedPushRecoveryWorkScheduler(context, enqueuer)

        scheduler.ensurePeriodic("installation-a/account-a")
        scheduler.ensurePeriodic("installation-a/account-a")
        scheduler.ensurePeriodic("installation-b/account-b")

        assertEquals(3, enqueuer.periodic.size)
        assertEquals(enqueuer.periodic[0].uniqueName, enqueuer.periodic[1].uniqueName)
        assertNotEquals(enqueuer.periodic[0].uniqueName, enqueuer.periodic[2].uniqueName)
        enqueuer.periodic.forEach { recorded ->
            assertEquals(ExistingPeriodicWorkPolicy.UPDATE, recorded.policy)
            assertEquals(NetworkType.CONNECTED, recorded.request.workSpec.constraints.requiredNetworkType)
            assertEquals(TimeUnit.HOURS.toMillis(6), recorded.request.workSpec.intervalDuration)
            assertEquals(TimeUnit.HOURS.toMillis(1), recorded.request.workSpec.flexDuration)
            assertEquals(
                DroppedPushRecoveryWorkScheduler.REASON_PERIODIC_SWEEP,
                recorded.request.workSpec.input.getString(DroppedPushRecoveryWorkScheduler.INPUT_REASON),
            )
        }
        val periodicSnapshot = HeadlessCanonicalRecoveryWorker.resolveStartSnapshot(
            store,
            enqueuer.periodic.first().request.workSpec.input,
        )
        assertEquals(
            DroppedPushRecoveryWorkScheduler.REASON_PERIODIC_SWEEP,
            periodicSnapshot?.reason,
        )
        assertNull(periodicSnapshot?.pendingRecovery)
    }

    @Test
    fun `enabling same binding with marker enqueues immediate and periodic exactly once`() {
        val enqueuer = RecordingRecoveryWorkEnqueuer()
        val scheduler = DroppedPushRecoveryWorkScheduler(context, enqueuer, store)
        store.setCurrentBinding(
            "installation-a/account-a",
            recoveryWorkEnabled = false,
        )
        val generation = requireNotNull(store.recordDeletion())

        val enabled = store.setCurrentBinding(
            "installation-a/account-a",
            recoveryWorkEnabled = true,
        )
        scheduler.onBindingRotated(enabled)

        assertTrue(enabled.changed)
        assertEquals(1, enqueuer.immediate.size)
        assertEquals(1, enqueuer.periodic.size)
        assertEquals(
            generation,
            enqueuer.immediate.single().request.workSpec.input.getLong(
                DroppedPushRecoveryWorkScheduler.INPUT_WAKE_GENERATION,
                -1L,
            ),
        )
        assertEquals(
            ExistingWorkPolicy.APPEND_OR_REPLACE,
            enqueuer.immediate.single().policy,
        )

        val unchanged = store.setCurrentBinding(
            "installation-a/account-a",
            recoveryWorkEnabled = true,
        )
        scheduler.onBindingRotated(unchanged)

        assertFalse(unchanged.changed)
        assertEquals(1, enqueuer.immediate.size)
        assertEquals(1, enqueuer.periodic.size)
    }

    @Test
    @Config(sdk = [24])
    fun `expedited work has pre Android 12 foreground contract on API 24`() {
        val info = HeadlessCanonicalRecoveryWorker.createForegroundInfo(context)

        assertEquals(HeadlessCanonicalRecoveryWorker.FOREGROUND_NOTIFICATION_ID, info.notificationId)
        assertEquals(0, info.foregroundServiceType)
        assertTrue(
            shadowOf(context.getSystemService(NotificationManager::class.java))
                .notificationChannels
                .isEmpty(),
        )
    }

    @Test
    @Config(sdk = [30])
    fun `expedited work has data sync foreground contract on API 30`() {
        val info = HeadlessCanonicalRecoveryWorker.createForegroundInfo(context)

        assertEquals(ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC, info.foregroundServiceType)
        assertEquals(
            MknoonFirebaseMessagingService.RECOVERY_CHANNEL_ID,
            info.notification.channelId,
        )
        assertTrue(
            context.getSystemService(NotificationManager::class.java)
                .getNotificationChannel(MknoonFirebaseMessagingService.RECOVERY_CHANNEL_ID) != null,
        )
    }
}

private data class RecordedImmediate(
    val uniqueName: String,
    val policy: ExistingWorkPolicy,
    val request: OneTimeWorkRequest,
)

private data class RecordedPeriodic(
    val uniqueName: String,
    val policy: ExistingPeriodicWorkPolicy,
    val request: PeriodicWorkRequest,
)

private class RecordingRecoveryWorkEnqueuer : RecoveryWorkEnqueuer {
    val immediate = mutableListOf<RecordedImmediate>()
    val periodic = mutableListOf<RecordedPeriodic>()
    val cancelled = mutableListOf<String>()

    override fun enqueueUniqueImmediate(
        uniqueName: String,
        policy: ExistingWorkPolicy,
        request: OneTimeWorkRequest,
    ) {
        immediate += RecordedImmediate(uniqueName, policy, request)
    }

    override fun enqueueUniquePeriodic(
        uniqueName: String,
        policy: ExistingPeriodicWorkPolicy,
        request: PeriodicWorkRequest,
    ) {
        periodic += RecordedPeriodic(uniqueName, policy, request)
    }

    override fun cancelUniqueWork(uniqueName: String) {
        cancelled += uniqueName
    }
}
