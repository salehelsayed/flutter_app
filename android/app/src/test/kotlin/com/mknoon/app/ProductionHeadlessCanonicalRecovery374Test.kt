package com.mknoon.app

import android.content.Context
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.ExistingWorkPolicy
import androidx.work.OneTimeWorkRequest
import androidx.work.PeriodicWorkRequest
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [33])
class ProductionHeadlessCanonicalRecovery374Test {
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
    }

    @Test
    fun `TC-374-05 typed readiness requires and echoes exact binding and enabled bit`() {
        val binding = "installation-a/account-a"
        store.setCurrentBinding(binding, recoveryWorkEnabled = false)
        assertEquals(1L, store.recordDeletion())
        val enqueuer = Plan374RecoveryWorkEnqueuer()
        val bridge = readinessBridge(enqueuer)

        listOf(
            mapOf<String, Any?>("binding" to binding),
            mapOf<String, Any?>(
                "binding" to binding,
                "activateRecoveryWork" to "true",
            ),
        ).forEach { malformed ->
            val rejected = Plan374BridgeResult()
            bridge.onMethodCall(MethodCall("setCurrentBinding", malformed), rejected)
            assertEquals("bad_args", rejected.errorCode)
        }
        assertFalse(store.recoveryWorkEnabled())
        assertTrue(enqueuer.immediate.isEmpty())
        assertTrue(enqueuer.periodic.isEmpty())

        val enabled = Plan374BridgeResult()
        bridge.onMethodCall(
            MethodCall(
                "setCurrentBinding",
                mapOf(
                    "binding" to binding,
                    "activateRecoveryWork" to true,
                ),
            ),
            enabled,
        )

        assertEquals(
            mapOf(
                "changed" to true,
                "committed" to true,
                "currentBinding" to binding,
                "retiredGeneration" to null,
                "recoveryWorkEnabled" to true,
            ),
            enabled.value,
        )
        assertNull(enabled.errorCode)
        assertTrue(store.recoveryWorkEnabled())
        assertEquals(
            DroppedPushRecoveryStore.PendingRecovery(1L, binding),
            store.pendingRecovery(),
        )
        assertEquals(1, enqueuer.immediate.size)
        assertEquals(1, enqueuer.periodic.size)
        val authority = Plan374BridgeResult()
        bridge.onMethodCall(MethodCall("recoveryAuthority", null), authority)
        assertEquals(
            mapOf(
                "currentBinding" to binding,
                "recoveryWorkEnabled" to true,
                "pendingGeneration" to 1L,
                "pendingBinding" to binding,
                "authorityRevision" to 1L,
                "authorityMutationInProgress" to false,
            ),
            authority.value,
        )
    }

    @Test
    fun `TC-374-05 same binding rollback preserves marker and atomically fences late headless ACK`() {
        val binding = "installation-a/account-a"
        store.setCurrentBinding(binding, recoveryWorkEnabled = false)
        assertEquals(1L, store.recordDeletion())
        val marker = requireNotNull(store.pendingRecovery())
        val enqueuer = Plan374RecoveryWorkEnqueuer()
        val bridge = readinessBridge(enqueuer)

        bridge.onMethodCall(
            MethodCall(
                "setCurrentBinding",
                mapOf("binding" to binding, "activateRecoveryWork" to true),
            ),
            Plan374BridgeResult(),
        )
        val initialAuthorityRevision = store.recoveryAuthority().authorityRevision
        assertEquals(1L, initialAuthorityRevision)
        val disabled = Plan374BridgeResult()
        bridge.onMethodCall(
            MethodCall(
                "setCurrentBinding",
                mapOf("binding" to binding, "activateRecoveryWork" to false),
            ),
            disabled,
        )

        assertEquals(
            mapOf(
                "changed" to true,
                "committed" to true,
                "currentBinding" to binding,
                "retiredGeneration" to null,
                "recoveryWorkEnabled" to false,
            ),
            disabled.value,
        )
        assertFalse(store.recoveryWorkEnabled())
        assertEquals(marker, store.pendingRecovery())
        assertEquals(1, enqueuer.immediate.size)
        assertEquals(1, enqueuer.periodic.size)
        assertEquals(
            listOf(
                DroppedPushRecoveryWorkScheduler.immediateUniqueName(binding),
                DroppedPushRecoveryWorkScheduler.periodicUniqueName(binding),
                DroppedPushRecoveryWorkScheduler.immediateUniqueName(binding),
                DroppedPushRecoveryWorkScheduler.periodicUniqueName(binding),
            ),
            enqueuer.cancelled,
        )
        assertEquals(
            CanonicalRuntimeLeaseBroker.State.RELEASED,
            ProcessCanonicalRuntimeLease.broker.snapshot().state,
        )
        assertEquals(
            GoRuntimeHost.State.RELEASED,
            ProcessGoRuntimeHost.instance.snapshot().state,
        )
        assertFalse(isHeadlessCanonicalRecoveryEngineRetained())

        val disabledAuthority = Plan374BridgeResult()
        bridge.onMethodCall(MethodCall("recoveryAuthority", null), disabledAuthority)
        assertEquals(
            mapOf(
                "currentBinding" to binding,
                "recoveryWorkEnabled" to false,
                "pendingGeneration" to marker.generation,
                "pendingBinding" to binding,
                "authorityRevision" to initialAuthorityRevision,
                "authorityMutationInProgress" to false,
            ),
            disabledAuthority.value,
        )
        val fencedHeadlessAck = Plan374BridgeResult()
        bridge.onMethodCall(
            MethodCall(
                "headlessAcknowledgeRecovery",
                mapOf(
                    "generation" to marker.generation,
                    "binding" to binding,
                    "authorityRevision" to initialAuthorityRevision,
                ),
            ),
            fencedHeadlessAck,
        )
        assertEquals(false, fencedHeadlessAck.value)
        assertEquals(marker, store.pendingRecovery())

        // Warm recovery remains intentionally available after operational
        // rollback; only the headless final-ACK method is readiness-fenced.
        val warmAck = Plan374BridgeResult()
        bridge.onMethodCall(
            MethodCall(
                "acknowledgeRecovery",
                mapOf("generation" to marker.generation, "binding" to binding),
            ),
            warmAck,
        )
        assertEquals(true, warmAck.value)
        assertNull(store.pendingRecovery())

        // Once rollback is reversed, a secure-state mutation advances the
        // authority revision before its first write. Finishing the mutation
        // may re-enable work, but an ACK holding the earlier revision remains
        // stale and cannot consume the newly pending generation.
        assertEquals(2L, store.recordDeletion())
        val postRollbackMarker = requireNotNull(store.pendingRecovery())
        val reenabled = Plan374BridgeResult()
        bridge.onMethodCall(
            MethodCall(
                "setCurrentBinding",
                mapOf("binding" to binding, "activateRecoveryWork" to true),
            ),
            reenabled,
        )
        assertEquals(
            mapOf(
                "changed" to true,
                "committed" to true,
                "currentBinding" to binding,
                "retiredGeneration" to null,
                "recoveryWorkEnabled" to true,
            ),
            reenabled.value,
        )

        val mutationStarted = Plan374BridgeResult()
        bridge.onMethodCall(
            MethodCall("beginRecoveryAuthorityMutation", null),
            mutationStarted,
        )
        val mutationToken = requireNotNull(
            (mutationStarted.value as Map<*, *>)["token"] as? String,
        )
        assertEquals(
            mapOf(
                "changed" to true,
                "committed" to true,
                "token" to mutationToken,
                "currentBinding" to binding,
                "recoveryWorkEnabled" to false,
                "authorityRevision" to 2L,
                "authorityMutationInProgress" to true,
            ),
            mutationStarted.value,
        )
        assertFalse(store.recoveryWorkEnabled())
        assertEquals(postRollbackMarker, store.pendingRecovery())
        assertEquals(
            listOf(
                DroppedPushRecoveryWorkScheduler.immediateUniqueName(binding),
                DroppedPushRecoveryWorkScheduler.periodicUniqueName(binding),
            ),
            enqueuer.cancelled.takeLast(2),
        )

        val mutationFinished = Plan374BridgeResult()
        bridge.onMethodCall(
            MethodCall(
                "finishRecoveryAuthorityMutation",
                mapOf("token" to mutationToken),
            ),
            mutationFinished,
        )
        assertEquals(
            mapOf(
                "changed" to true,
                "committed" to true,
                "token" to null,
                "currentBinding" to binding,
                "recoveryWorkEnabled" to true,
                "authorityRevision" to 2L,
                "authorityMutationInProgress" to false,
            ),
            mutationFinished.value,
        )
        assertTrue(store.recoveryWorkEnabled())
        assertEquals(3, enqueuer.immediate.size)
        assertEquals(3, enqueuer.periodic.size)

        val staleRevisionAck = Plan374BridgeResult()
        bridge.onMethodCall(
            MethodCall(
                "headlessAcknowledgeRecovery",
                mapOf(
                    "generation" to postRollbackMarker.generation,
                    "binding" to binding,
                    "authorityRevision" to initialAuthorityRevision,
                ),
            ),
            staleRevisionAck,
        )
        assertEquals(false, staleRevisionAck.value)
        assertEquals(postRollbackMarker, store.pendingRecovery())

        val currentRevisionAck = Plan374BridgeResult()
        bridge.onMethodCall(
            MethodCall(
                "headlessAcknowledgeRecovery",
                mapOf(
                    "generation" to postRollbackMarker.generation,
                    "binding" to binding,
                    "authorityRevision" to 2L,
                ),
            ),
            currentRevisionAck,
        )
        assertEquals(true, currentRevisionAck.value)
        assertNull(store.pendingRecovery())
    }

    @Test
    fun `TC-374-05 account rotation retires old marker instead of operational rollback preservation`() {
        val bindingA = "installation-a/account-a"
        val bindingB = "installation-a/account-b"
        store.setCurrentBinding(bindingA, recoveryWorkEnabled = true)
        assertEquals(1L, store.recordDeletion())
        val accountAMarker = requireNotNull(store.pendingRecovery())
        val enqueuer = Plan374RecoveryWorkEnqueuer()
        var cardCancellations = 0
        val bridge = DroppedPushRecoveryBridge(
            context = context,
            messenger = null,
            store = store,
            cancelRecoveryNotification = { cardCancellations += 1 },
            bindingScheduler = DroppedPushRecoveryWorkScheduler(
                context,
                enqueuer,
                store,
            ),
        )

        val liveMutationStarted = Plan374BridgeResult()
        bridge.onMethodCall(
            MethodCall("beginRecoveryAuthorityMutation", null),
            liveMutationStarted,
        )
        val liveMutationToken = requireNotNull(
            (liveMutationStarted.value as Map<*, *>)["token"] as? String,
        )
        assertEquals(
            mapOf(
                "changed" to true,
                "committed" to true,
                "token" to liveMutationToken,
                "currentBinding" to bindingA,
                "recoveryWorkEnabled" to false,
                "authorityRevision" to 2L,
                "authorityMutationInProgress" to true,
            ),
            liveMutationStarted.value,
        )
        assertEquals(
            listOf(
                DroppedPushRecoveryWorkScheduler.immediateUniqueName(bindingA),
                DroppedPushRecoveryWorkScheduler.periodicUniqueName(bindingA),
            ),
            enqueuer.cancelled,
        )
        assertFalse(store.recoveryWorkEnabled())
        assertTrue(store.recoveryAuthority().authorityMutationInProgress)

        // Rotation is not proof that an overlapping secure write died. It
        // retires only account A's marker while carrying the live token into
        // account B, whose desired readiness stays fenced until that exact
        // token finishes.
        val rotated = Plan374BridgeResult()
        bridge.onMethodCall(
            MethodCall(
                "setCurrentBinding",
                mapOf(
                    "binding" to bindingB,
                    "activateRecoveryWork" to true,
                ),
            ),
            rotated,
        )
        assertEquals(
            mapOf(
                "changed" to true,
                "committed" to true,
                "currentBinding" to bindingB,
                "retiredGeneration" to accountAMarker.generation,
                "recoveryWorkEnabled" to false,
            ),
            rotated.value,
        )
        assertEquals(1, cardCancellations)
        assertEquals(bindingB, store.currentBinding())
        assertFalse(store.recoveryWorkEnabled())
        assertNull(store.pendingRecovery())
        val rotatedAuthority = Plan374BridgeResult()
        bridge.onMethodCall(
            MethodCall("recoveryAuthority", null),
            rotatedAuthority,
        )
        assertEquals(
            mapOf(
                "currentBinding" to bindingB,
                "recoveryWorkEnabled" to false,
                "pendingGeneration" to null,
                "pendingBinding" to null,
                "authorityRevision" to 3L,
                "authorityMutationInProgress" to true,
            ),
            rotatedAuthority.value,
        )
        assertEquals(
            listOf(
                DroppedPushRecoveryWorkScheduler.immediateUniqueName(bindingA),
                DroppedPushRecoveryWorkScheduler.periodicUniqueName(bindingA),
                DroppedPushRecoveryWorkScheduler.immediateUniqueName(bindingA),
                DroppedPushRecoveryWorkScheduler.periodicUniqueName(bindingA),
            ),
            enqueuer.cancelled,
        )

        val liveMutationFinished = Plan374BridgeResult()
        bridge.onMethodCall(
            MethodCall(
                "finishRecoveryAuthorityMutation",
                mapOf("token" to liveMutationToken),
            ),
            liveMutationFinished,
        )
        assertEquals(
            mapOf(
                "changed" to true,
                "committed" to true,
                "token" to null,
                "currentBinding" to bindingB,
                "recoveryWorkEnabled" to true,
                "authorityRevision" to 3L,
                "authorityMutationInProgress" to false,
            ),
            liveMutationFinished.value,
        )
        assertTrue(store.recoveryWorkEnabled())
        assertFalse(store.recoveryAuthority().authorityMutationInProgress)
        assertEquals(0, enqueuer.immediate.size)
        assertEquals(1, enqueuer.periodic.size)

        assertEquals(2L, store.recordDeletion())
        val accountBMarker = requireNotNull(store.pendingRecovery())
        val crashMutationStarted = Plan374BridgeResult()
        bridge.onMethodCall(
            MethodCall("beginRecoveryAuthorityMutation", null),
            crashMutationStarted,
        )
        val staleCrashToken = requireNotNull(
            (crashMutationStarted.value as Map<*, *>)["token"] as? String,
        )
        assertEquals(
            mapOf(
                "changed" to true,
                "committed" to true,
                "token" to staleCrashToken,
                "currentBinding" to bindingB,
                "recoveryWorkEnabled" to false,
                "authorityRevision" to 4L,
                "authorityMutationInProgress" to true,
            ),
            crashMutationStarted.value,
        )

        // A process restart has no in-memory token owner. The next full
        // binding publication explicitly reconciles that stale token and
        // restores the previously desired readiness. The abandoned token can
        // never finish a later mutation or perturb scheduling.
        val reopenedStore = DroppedPushRecoveryStore(context)
        val recoveredBridge = DroppedPushRecoveryBridge(
            context = context,
            messenger = null,
            store = reopenedStore,
            cancelRecoveryNotification = { cardCancellations += 1 },
            bindingScheduler = DroppedPushRecoveryWorkScheduler(
                context,
                enqueuer,
                reopenedStore,
            ),
        )
        val recovered = Plan374BridgeResult()
        recoveredBridge.onMethodCall(
            MethodCall(
                "setCurrentBinding",
                mapOf(
                    "binding" to bindingB,
                    "activateRecoveryWork" to true,
                    "recoverStaleAuthorityMutations" to true,
                ),
            ),
            recovered,
        )
        assertEquals(
            mapOf(
                "changed" to true,
                "committed" to true,
                "currentBinding" to bindingB,
                "retiredGeneration" to null,
                "recoveryWorkEnabled" to true,
            ),
            recovered.value,
        )
        val recoveredAuthority = Plan374BridgeResult()
        recoveredBridge.onMethodCall(
            MethodCall("recoveryAuthority", null),
            recoveredAuthority,
        )
        assertEquals(
            mapOf(
                "currentBinding" to bindingB,
                "recoveryWorkEnabled" to true,
                "pendingGeneration" to accountBMarker.generation,
                "pendingBinding" to bindingB,
                "authorityRevision" to 4L,
                "authorityMutationInProgress" to false,
            ),
            recoveredAuthority.value,
        )
        assertEquals(1, enqueuer.immediate.size)
        assertEquals(2, enqueuer.periodic.size)

        val staleFinish = Plan374BridgeResult()
        recoveredBridge.onMethodCall(
            MethodCall(
                "finishRecoveryAuthorityMutation",
                mapOf("token" to staleCrashToken),
            ),
            staleFinish,
        )
        assertEquals("persistence_failed", staleFinish.errorCode)
        assertTrue(reopenedStore.recoveryWorkEnabled())
        assertFalse(reopenedStore.recoveryAuthority().authorityMutationInProgress)
        assertEquals(accountBMarker, reopenedStore.pendingRecovery())
        assertEquals(
            listOf(
                DroppedPushRecoveryWorkScheduler.immediateUniqueName(bindingA),
                DroppedPushRecoveryWorkScheduler.periodicUniqueName(bindingA),
                DroppedPushRecoveryWorkScheduler.immediateUniqueName(bindingA),
                DroppedPushRecoveryWorkScheduler.periodicUniqueName(bindingA),
                DroppedPushRecoveryWorkScheduler.immediateUniqueName(bindingB),
                DroppedPushRecoveryWorkScheduler.periodicUniqueName(bindingB),
                DroppedPushRecoveryWorkScheduler.immediateUniqueName(bindingB),
                DroppedPushRecoveryWorkScheduler.periodicUniqueName(bindingB),
                DroppedPushRecoveryWorkScheduler.immediateUniqueName(bindingB),
                DroppedPushRecoveryWorkScheduler.periodicUniqueName(bindingB),
            ),
            enqueuer.cancelled,
        )
    }

    @Test
    fun `TC-374-08 shared deleted batch seam commits resnapshots and schedules before caller work`() {
        val binding = "installation-a/account-a"
        store.setCurrentBinding(binding, recoveryWorkEnabled = true)
        val trace = mutableListOf<String>()
        val seam = ProductionDeletedBatchRecovery(
            context = context,
            store = store,
            scheduleRecovery = { snapshot ->
                assertEquals(snapshot, store.pendingRecovery())
                trace += "schedule:${snapshot.generation}"
            },
        )

        val committed = seam.commitAndSchedule { generation ->
            assertEquals(generation, store.pendingGeneration())
            trace += "afterCommit:$generation"
        }

        assertEquals(
            DroppedPushRecoveryStore.PendingRecovery(1L, binding),
            committed,
        )
        assertEquals(listOf("schedule:1", "afterCommit:1"), trace)
        assertEquals(committed, store.pendingRecovery())
    }

    @Test
    fun `TC-374-08 default off shared seam stays serialized with acknowledgement without scheduling`() {
        val binding = "installation-a/account-a"
        store.setCurrentBinding(binding, recoveryWorkEnabled = false)
        val callbackStarted = CountDownLatch(1)
        val releaseCallback = CountDownLatch(1)
        val acknowledgementDone = CountDownLatch(1)
        var callbackObservedCommittedMarker = false
        var scheduleCalls = 0
        val seam = ProductionDeletedBatchRecovery(
            context = context,
            store = store,
            scheduleRecovery = { scheduleCalls += 1 },
        )
        val executor = Executors.newFixedThreadPool(2)
        try {
            val commit = executor.submit<DroppedPushRecoveryStore.PendingRecovery?> {
                seam.commitAndSchedule { generation ->
                    callbackObservedCommittedMarker = store.pendingGeneration() == generation
                    callbackStarted.countDown()
                    releaseCallback.await(5, TimeUnit.SECONDS)
                }
            }
            assertTrue(callbackStarted.await(5, TimeUnit.SECONDS))
            val acknowledgement = executor.submit<Boolean> {
                store.acknowledgeRecovery(1L, binding).also {
                    acknowledgementDone.countDown()
                }
            }

            assertFalse(
                "acknowledgement must not overtake commit/schedule caller work",
                acknowledgementDone.await(100, TimeUnit.MILLISECONDS),
            )
            releaseCallback.countDown()
            assertEquals(
                DroppedPushRecoveryStore.PendingRecovery(1L, binding),
                commit.get(5, TimeUnit.SECONDS),
            )
            assertTrue(acknowledgement.get(5, TimeUnit.SECONDS))
        } finally {
            releaseCallback.countDown()
            executor.shutdownNow()
        }

        assertTrue(callbackObservedCommittedMarker)
        assertEquals(0, scheduleCalls)
        assertFalse(store.recoveryWorkEnabled())
        assertNull(store.pendingRecovery())
    }

    @Test
    fun `TC-374-08 Firebase deletion override delegates to the one production seam`() {
        val service = sourceFile("MknoonFirebaseMessagingService.kt").readText()
        val seam = sourceFile("ProductionDeletedBatchRecovery.kt").readText()

        assertEquals(1, service.windowedCount("ProductionDeletedBatchRecovery("))
        assertEquals(1, service.windowedCount(".commitAndSchedule { generation ->"))
        assertFalse(service.contains(".recordDeletion"))
        assertEquals(1, seam.windowedCount("store.recordDeletion { generation ->"))
        assertEquals(1, seam.windowedCount("DroppedPushRecoveryWorkScheduler(context)"))
        assertFalse(seam.contains("WorkManager.getInstance"))
        assertFalse(seam.contains("HeadlessCanonicalRecoveryWorker("))
    }

    private fun readinessBridge(
        enqueuer: Plan374RecoveryWorkEnqueuer,
    ): DroppedPushRecoveryBridge = DroppedPushRecoveryBridge(
        context = context,
        messenger = null,
        store = store,
        cancelRecoveryNotification = {},
        bindingScheduler = DroppedPushRecoveryWorkScheduler(
            context,
            enqueuer,
            store,
        ),
    )

    private fun sourceFile(name: String): File = sequenceOf(
        File("src/main/kotlin/com/mknoon/app/$name"),
        File("android/app/src/main/kotlin/com/mknoon/app/$name"),
    ).firstOrNull(File::isFile) ?: error("Cannot locate $name")

    private fun String.windowedCount(needle: String): Int {
        if (needle.isEmpty()) return 0
        var count = 0
        var offset = 0
        while (true) {
            val found = indexOf(needle, offset)
            if (found < 0) return count
            count += 1
            offset = found + needle.length
        }
    }
}

private class Plan374BridgeResult : MethodChannel.Result {
    var value: Any? = null
    var errorCode: String? = null

    override fun success(result: Any?) {
        value = result
    }

    override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {
        this.errorCode = errorCode
    }

    override fun notImplemented() {
        errorCode = "not_implemented"
    }
}

private class Plan374RecoveryWorkEnqueuer : RecoveryWorkEnqueuer {
    val immediate = mutableListOf<OneTimeWorkRequest>()
    val periodic = mutableListOf<PeriodicWorkRequest>()
    val cancelled = mutableListOf<String>()

    override fun enqueueUniqueImmediate(
        uniqueName: String,
        policy: ExistingWorkPolicy,
        request: OneTimeWorkRequest,
    ) {
        immediate += request
    }

    override fun enqueueUniquePeriodic(
        uniqueName: String,
        policy: ExistingPeriodicWorkPolicy,
        request: PeriodicWorkRequest,
    ) {
        periodic += request
    }

    override fun cancelUniqueWork(uniqueName: String) {
        cancelled += uniqueName
    }
}
