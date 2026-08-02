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
}
