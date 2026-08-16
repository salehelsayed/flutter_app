package com.mknoon.app

import android.content.Context
import java.util.Collections
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
class DroppedPushRecoveryStoreTest {
    private lateinit var context: Context

    @Before
    fun setUp() {
        context = RuntimeEnvironment.getApplication()
        context.getSharedPreferences(
            DroppedPushRecoveryStore.PREFERENCES_NAME,
            Context.MODE_PRIVATE,
        ).edit().clear().commit()
        DroppedPushRecoveryStore(context).setCurrentBinding("installation-a/account-a")
    }

    @Test
    fun testTC37502FixedAndDeletedTriggersShareOneCrashSafeAudibleDisposition() {
        val preferences = context.getSharedPreferences(
            DroppedPushRecoveryStore.PREFERENCES_NAME,
            Context.MODE_PRIVATE,
        )
        val store = DroppedPushRecoveryStore(context)
        val binding = "installation-a/account-a"

        // A legacy record with neither kind nor disposition decodes as the old
        // deletion service's possibly-audible marker.
        preferences.edit()
            .putLong("last_generation", 7L)
            .putLong("pending_generation", 7L)
            .putString("pending_binding", binding)
            .commit()
        val legacy = requireNotNull(DroppedPushRecoveryStore(context).pendingRecovery())
        assertEquals(
            DroppedPushRecoveryStore.PendingRecovery(
                generation = 7L,
                binding = binding,
                triggerKind = DroppedPushRecoveryStore.TriggerKind.DELETED_BATCH,
                genericMayHaveAlerted = true,
            ),
            legacy,
        )

        // Coalescing a fixed trigger over that ambiguity allocates a newer
        // generation, replaces the one record atomically, and never downgrades
        // the audible ambiguity to false.
        assertEquals(8L, store.recordFixedWake())
        val coalesced = requireNotNull(store.pendingRecovery())
        assertEquals(8L, coalesced.generation)
        assertEquals(DroppedPushRecoveryStore.TriggerKind.FIXED_WAKE, coalesced.triggerKind)
        assertTrue(coalesced.genericMayHaveAlerted)

        // Exact-CAS acknowledgement clears generation, binding, kind and
        // disposition in one durable transaction; a stale generation cannot.
        assertFalse(store.acknowledgeRecovery(7L, binding))
        assertTrue(store.acknowledgeRecovery(8L, binding))
        assertNull(store.pendingRecovery())
        assertFalse(preferences.contains("pending_generation"))
        assertFalse(preferences.contains("pending_binding"))
        assertFalse(preferences.contains("pending_trigger_kind"))
        assertFalse(preferences.contains("pending_generic_may_have_alerted"))

        // A fixed-only marker commits an explicitly silent disposition, and a
        // reopened store decodes the same committed record.
        assertEquals(9L, store.recordFixedWake())
        val fixedOnly = requireNotNull(DroppedPushRecoveryStore(context).pendingRecovery())
        assertEquals(DroppedPushRecoveryStore.TriggerKind.FIXED_WAKE, fixedOnly.triggerKind)
        assertFalse(fixedOnly.genericMayHaveAlerted)

        // A deletion coalescing over fixed-only work restores the conservative
        // possibly-audible commitment before its own notify attempt.
        assertEquals(10L, store.recordDeletion())
        val deletion = requireNotNull(store.pendingRecovery())
        assertEquals(DroppedPushRecoveryStore.TriggerKind.DELETED_BATCH, deletion.triggerKind)
        assertTrue(deletion.genericMayHaveAlerted)
        assertEquals(11L, store.recordFixedWake())
        assertTrue(requireNotNull(store.pendingRecovery()).genericMayHaveAlerted)

        // An unknown or malformed future kind retains the exact binding and
        // generation as conservative pending work: it never decodes as no work
        // and never authorizes acknowledgement or card cancellation.
        preferences.edit()
            .putString("pending_trigger_kind", "future_kind_v9")
            .putBoolean("pending_generic_may_have_alerted", false)
            .commit()
        val unsupported = requireNotNull(store.pendingRecovery())
        assertEquals(11L, unsupported.generation)
        assertEquals(binding, unsupported.binding)
        assertEquals(
            DroppedPushRecoveryStore.TriggerKind.UNSUPPORTED_PENDING,
            unsupported.triggerKind,
        )
        assertFalse(unsupported.genericMayHaveAlerted)
        val cancelled = mutableListOf<Long>()
        assertFalse(store.acknowledgeRecovery(11L, binding) { cancelled += 11L })
        assertFalse(store.acknowledgeGeneration(11L) { cancelled += 11L })
        assertTrue(cancelled.isEmpty())
        assertEquals(11L, store.pendingGeneration())
        assertFalse(store.reconcileNoPendingGeneration { cancelled += -1L })
        assertTrue(cancelled.isEmpty())

        // Account cutover removes marker, kind and disposition in the one
        // incumbent rotation transaction even for an unsupported kind.
        val rotation = store.setCurrentBinding("installation-b/account-b")
        assertTrue(rotation.committed)
        assertNull(store.pendingRecovery())
        assertFalse(preferences.contains("pending_trigger_kind"))
        assertFalse(preferences.contains("pending_generic_may_have_alerted"))

        // Missing binding consumes a fixed trigger fail-closed.
        store.setCurrentBinding(null)
        assertNull(store.recordFixedWake())
        assertNull(store.pendingRecovery())

        // Concurrent mixed triggers allocate unique generations, keep exactly
        // one newest pending record, and the audible ambiguity is absorbing:
        // any committed deletion leaves the final disposition true.
        store.setCurrentBinding(binding)
        val executor = Executors.newFixedThreadPool(6)
        val start = CountDownLatch(1)
        val generations = Collections.synchronizedList(mutableListOf<Long>())
        repeat(6) { index ->
            executor.execute {
                start.await()
                val generation = if (index % 2 == 0) {
                    DroppedPushRecoveryStore(context).recordFixedWake()
                } else {
                    DroppedPushRecoveryStore(context).recordDeletion()
                }
                generation?.let(generations::add)
            }
        }
        start.countDown()
        executor.shutdown()
        assertTrue(executor.awaitTermination(20, TimeUnit.SECONDS))
        assertEquals(6, generations.size)
        assertEquals(6, generations.toSet().size)
        val finalPending = requireNotNull(store.pendingRecovery())
        assertEquals(generations.max(), finalPending.generation)
        assertTrue(finalPending.genericMayHaveAlerted)
    }

    @Test
    fun `read is non-consuming and matching acknowledgement retains monotonic last generation`() {
        val store = DroppedPushRecoveryStore(context)

        assertNull(store.pendingGeneration())
        assertEquals(1L, store.recordDeletion())
        assertEquals(1L, store.pendingGeneration())
        assertEquals(1L, store.pendingGeneration())

        assertFalse(store.acknowledgeGeneration(2L))
        assertEquals(1L, store.pendingGeneration())
        assertTrue(store.acknowledgeGeneration(1L))
        assertNull(store.pendingGeneration())

        assertEquals(2L, DroppedPushRecoveryStore(context).recordDeletion())
        assertEquals(2L, store.pendingGeneration())
    }

    @Test
    fun `stale acknowledgement cannot clear a newer generation or cancel its card`() {
        val store = DroppedPushRecoveryStore(context)
        val cancelled = mutableListOf<Long>()

        assertEquals(1L, store.recordDeletion())
        assertEquals(2L, store.recordDeletion())

        assertFalse(store.acknowledgeGeneration(1L) { cancelled += 1L })
        assertEquals(2L, store.pendingGeneration())
        assertTrue(store.acknowledgeGeneration(2L) { cancelled += 2L })
        assertEquals(listOf(2L), cancelled)
    }

    @Test
    fun `stale-card reconciliation runs only without a pending generation`() {
        val store = DroppedPushRecoveryStore(context)
        val reconciled = mutableListOf<String>()

        assertTrue(store.reconcileNoPendingGeneration { reconciled += "idle" })
        assertEquals(1L, store.recordDeletion())
        assertFalse(store.reconcileNoPendingGeneration { reconciled += "pending" })
        assertEquals(listOf("idle"), reconciled)
    }

    @Test
    fun `notification attempt observes committed marker and remains serialized with acknowledgement`() {
        val store = DroppedPushRecoveryStore(context)
        val callbackStarted = CountDownLatch(1)
        val releaseCallback = CountDownLatch(1)
        val acknowledgementDone = CountDownLatch(1)
        val acknowledgementResult = mutableListOf<Boolean>()
        val executor = Executors.newFixedThreadPool(2)

        executor.execute {
            store.recordDeletion { generation ->
                assertEquals(generation, DroppedPushRecoveryStore(context).pendingGeneration())
                callbackStarted.countDown()
                assertTrue(releaseCallback.await(5, TimeUnit.SECONDS))
            }
        }
        assertTrue(callbackStarted.await(5, TimeUnit.SECONDS))
        executor.execute {
            acknowledgementResult += store.acknowledgeGeneration(1L)
            acknowledgementDone.countDown()
        }

        assertFalse(
            "acknowledgement must not overtake the committed generation's display attempt",
            acknowledgementDone.await(100, TimeUnit.MILLISECONDS),
        )
        releaseCallback.countDown()
        assertTrue(acknowledgementDone.await(5, TimeUnit.SECONDS))
        executor.shutdownNow()
        assertEquals(listOf(true), acknowledgementResult)
    }

    @Test
    fun `concurrent writers allocate unique generations and publish the newest pending value`() {
        val workers = 16
        val ready = CountDownLatch(workers)
        val start = CountDownLatch(1)
        val done = CountDownLatch(workers)
        val results = Collections.synchronizedList(mutableListOf<Long>())
        val executor = Executors.newFixedThreadPool(workers)

        repeat(workers) {
            executor.execute {
                ready.countDown()
                start.await()
                DroppedPushRecoveryStore(context).recordDeletion()?.let(results::add)
                done.countDown()
            }
        }

        assertTrue(ready.await(5, TimeUnit.SECONDS))
        start.countDown()
        assertTrue(done.await(5, TimeUnit.SECONDS))
        executor.shutdownNow()

        assertEquals((1L..workers.toLong()).toList(), results.sorted())
        assertEquals(workers.toLong(), DroppedPushRecoveryStore(context).pendingGeneration())
    }

    @Test
    fun `binding rotation retires stale generation and prevents cross account acknowledgement`() {
        val store = DroppedPushRecoveryStore(context)
        assertEquals(1L, store.recordDeletion())
        val accountA = requireNotNull(store.pendingRecovery())

        val rotation = store.setCurrentBinding("installation-a/account-b")

        assertEquals(accountA, rotation.retiredRecovery)
        assertNull(store.pendingRecovery())
        assertFalse(store.acknowledgeRecovery(accountA.generation, accountA.binding))
        assertEquals(2L, store.recordDeletion())
        val accountB = requireNotNull(store.pendingRecovery())
        assertEquals("installation-a/account-b", accountB.binding)
        assertFalse(store.acknowledgeRecovery(accountB.generation, accountA.binding))
        assertTrue(store.acknowledgeRecovery(accountB.generation, accountB.binding))
    }

    @Test
    fun `TC-374-05 binding publication toggles recovery work only for exact committed binding`() {
        val store = DroppedPushRecoveryStore(context)

        assertFalse(store.recoveryWorkEnabled())
        assertEquals(
            DroppedPushRecoveryStore.RecoveryAuthority(
                currentBinding = "installation-a/account-a",
                recoveryWorkEnabled = false,
                pendingRecovery = null,
                authorityRevision = 1L,
                authorityMutationInProgress = false,
            ),
            store.recoveryAuthority(),
        )
        val enabled = store.setCurrentBinding(
            "installation-a/account-a",
            recoveryWorkEnabled = true,
        )
        assertTrue(enabled.changed)
        assertTrue(enabled.recoveryWorkEnabled)
        assertTrue(store.recoveryWorkEnabled())

        // Simulate an upgrade from the pre-fence preference shape. The first
        // mutation must preserve the effective enabled state as the desired
        // state before it durably disables headless work.
        context.getSharedPreferences(
            DroppedPushRecoveryStore.PREFERENCES_NAME,
            Context.MODE_PRIVATE,
        ).edit().remove("desired_recovery_work_enabled").commit()

        val firstMutation = store.beginAuthorityMutation()
        val firstToken = requireNotNull(firstMutation.token)
        assertTrue(firstMutation.changed)
        assertTrue(firstMutation.committed)
        assertFalse(firstMutation.recoveryWorkEnabled)
        assertEquals(2L, firstMutation.authorityRevision)
        assertTrue(firstMutation.authorityMutationInProgress)

        val overlappingMutation = store.beginAuthorityMutation()
        val overlappingToken = requireNotNull(overlappingMutation.token)
        assertTrue(firstToken != overlappingToken)
        assertFalse(overlappingMutation.recoveryWorkEnabled)
        assertEquals(3L, overlappingMutation.authorityRevision)
        assertTrue(overlappingMutation.authorityMutationInProgress)

        val firstFinished = store.finishAuthorityMutation(firstToken)
        assertTrue(firstFinished.changed)
        assertTrue(firstFinished.committed)
        assertFalse(firstFinished.recoveryWorkEnabled)
        assertEquals(3L, firstFinished.authorityRevision)
        assertTrue(firstFinished.authorityMutationInProgress)

        val finalFinished = store.finishAuthorityMutation(overlappingToken)
        assertTrue(finalFinished.changed)
        assertTrue(finalFinished.committed)
        assertTrue(finalFinished.recoveryWorkEnabled)
        assertEquals(3L, finalFinished.authorityRevision)
        assertFalse(finalFinished.authorityMutationInProgress)
        assertTrue(store.recoveryWorkEnabled())

        val staleFinish = store.finishAuthorityMutation(firstToken)
        assertFalse(staleFinish.changed)
        assertFalse(staleFinish.committed)
        assertTrue(staleFinish.recoveryWorkEnabled)
        assertEquals(3L, staleFinish.authorityRevision)
        assertFalse(staleFinish.authorityMutationInProgress)

        val crashMutation = store.beginAuthorityMutation()
        val crashToken = requireNotNull(crashMutation.token)
        assertFalse(store.recoveryWorkEnabled())
        assertEquals(4L, store.recoveryAuthority().authorityRevision)
        assertTrue(store.recoveryAuthority().authorityMutationInProgress)

        val reopenedStore = DroppedPushRecoveryStore(context)
        val recovered = reopenedStore.setCurrentBinding(
            "installation-a/account-a",
            recoveryWorkEnabled = true,
            recoverStaleAuthorityMutations = true,
        )
        assertTrue(recovered.changed)
        assertTrue(recovered.committed)
        assertTrue(recovered.recoveryWorkEnabled)
        assertEquals(4L, reopenedStore.recoveryAuthority().authorityRevision)
        assertFalse(reopenedStore.recoveryAuthority().authorityMutationInProgress)

        val recoveredStaleFinish = reopenedStore.finishAuthorityMutation(crashToken)
        assertFalse(recoveredStaleFinish.changed)
        assertFalse(recoveredStaleFinish.committed)
        assertTrue(recoveredStaleFinish.recoveryWorkEnabled)
        assertEquals(4L, recoveredStaleFinish.authorityRevision)
        assertFalse(recoveredStaleFinish.authorityMutationInProgress)
    }

    @Test
    fun `deletion without a current binding cannot create an unowned marker`() {
        val store = DroppedPushRecoveryStore(context)
        store.setCurrentBinding(null)

        assertNull(store.recordDeletion())
        assertNull(store.pendingRecovery())
    }

    @Test
    fun `binding rotation durably retires malformed orphan marker keys`() {
        context.getSharedPreferences(
            DroppedPushRecoveryStore.PREFERENCES_NAME,
            Context.MODE_PRIVATE,
        ).edit()
            .putLong("pending_generation", 17L)
            .remove("pending_binding")
            .commit()

        val rotation = DroppedPushRecoveryStore(context)
            .setCurrentBinding("installation-a/account-b")

        assertTrue(rotation.committed)
        assertTrue(rotation.changed)
        val preferences = context.getSharedPreferences(
            DroppedPushRecoveryStore.PREFERENCES_NAME,
            Context.MODE_PRIVATE,
        )
        assertFalse(preferences.contains("pending_generation"))
        assertFalse(preferences.contains("pending_binding"))
    }
}
