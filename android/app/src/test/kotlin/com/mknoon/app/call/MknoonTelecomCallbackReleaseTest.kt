package com.mknoon.app.call

import java.util.UUID
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import kotlin.coroutines.CoroutineContext
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.awaitCancellation
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import kotlinx.coroutines.withTimeoutOrNull
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Test

class MknoonTelecomCallbackReleaseTest {
    private class QueuedDispatcher : CoroutineDispatcher() {
        private val queue = java.util.concurrent.ConcurrentLinkedQueue<Runnable>()
        override fun dispatch(context: CoroutineContext, block: Runnable) { queue.add(block) }
        fun drain() { while (true) (queue.poll() ?: return).run() }
    }

    private class Fixture {
        val dispatcher = QueuedDispatcher()
        val scope = CoroutineScope(SupervisorJob() + dispatcher)
        val id = UUID.randomUUID()
        var session = Any()
        val markers = ConcurrentHashMap<UUID, Any>()
        val calls = mutableListOf<Any>()
        val outcomes = mutableListOf<MknoonTelecomReleaseOutcome>()
        var result = true
        var error: Throwable? = null
        val release = MknoonTelecomCallbackRelease(
            scope = scope,
            current = { if (it == id) session else null },
            disconnect = { exact: Any ->
                calls.add(exact)
                error?.let { throw it }
                result
            },
            markLocal = { id, exact -> markers[id] = exact },
            clearLocal = { id, exact -> markers.remove(id, exact) },
            report = outcomes::add,
        )
    }

    @Test
    fun `duplicate pending and released callbacks disconnect once until exact retirement`() {
        val f = Fixture()
        assertTrue(f.release.request(f.id, f.session))
        assertTrue(f.release.request(f.id, f.session))
        assertTrue(f.calls.isEmpty())
        f.dispatcher.drain()
        assertTrue(f.release.request(f.id, f.session))
        assertEquals(listOf(f.session), f.calls)
        assertEquals(listOf(MknoonTelecomReleaseOutcome.RELEASED), f.outcomes)
        assertSame(f.session, f.markers[f.id])
        f.release.retire(f.id, f.session)
        assertTrue(f.markers.isEmpty())
        f.scope.cancel()
    }

    @Test
    fun `provider rejection is observable clears marker and does not retry on duplicate`() {
        val f = Fixture()
        f.result = false
        assertTrue(f.release.request(f.id, f.session))
        f.dispatcher.drain()
        assertFalse(f.release.request(f.id, f.session))
        assertEquals(1, f.calls.size)
        assertTrue(f.markers.isEmpty())
        assertEquals(listOf(MknoonTelecomReleaseOutcome.FAILED), f.outcomes)
        f.scope.cancel()
    }

    @Test
    fun `provider exception is observable and clears exact marker`() {
        val f = Fixture()
        f.error = IllegalStateException("synthetic provider failure")
        assertTrue(f.release.request(f.id, f.session))
        f.dispatcher.drain()
        assertTrue(f.markers.isEmpty())
        assertEquals(listOf(MknoonTelecomReleaseOutcome.FAILED), f.outcomes)
        f.scope.cancel()
    }

    @Test
    fun `scope cancellation before dispatched body clears local marker`() {
        val f = Fixture()
        assertTrue(f.release.request(f.id, f.session))
        f.scope.cancel()
        f.dispatcher.drain()
        assertTrue(f.calls.isEmpty())
        assertTrue(f.markers.isEmpty())
        assertEquals(listOf(MknoonTelecomReleaseOutcome.CANCELED), f.outcomes)
        assertFalse(f.release.request(f.id, f.session))
    }

    @Test
    fun `registration ends during successful provider release without claiming rejection`() {
        val dispatcher = QueuedDispatcher()
        val process = CoroutineScope(SupervisorJob() + dispatcher)
        val id = UUID.randomUUID()
        val session = Any()
        val outcomes = mutableListOf<MknoonTelecomReleaseOutcome>()
        lateinit var release: MknoonTelecomCallbackRelease<Any>
        release = MknoonTelecomCallbackRelease(
            scope = process,
            current = { session },
            disconnect = { _: Any ->
                // CoreTelecom ends addCall's lifetime before disconnect returns.
                release.retire(id, session)
                true
            },
            markLocal = { _, _ -> }, clearLocal = { _, _ -> },
            report = outcomes::add,
        )
        assertTrue(release.request(id, session))
        dispatcher.drain()
        assertEquals(listOf(MknoonTelecomReleaseOutcome.RETIRED), outcomes)
        process.cancel()
    }

    @Test
    fun `provider await times out independently after callback queues release`() = runBlocking {
        val process = CoroutineScope(SupervisorJob() + Dispatchers.Default)
        val session = Any()
        val id = UUID.randomUUID()
        val outcomes = CompletableDeferred<MknoonTelecomReleaseOutcome>()
        val local = AtomicBoolean(false)
        val release = MknoonTelecomCallbackRelease(
            scope = process,
            current = { session },
            disconnect = { _: Any -> delay(5_000L); true },
            markLocal = { _, _ -> local.set(true) },
            clearLocal = { _, _ -> local.set(false) },
            report = { outcomes.complete(it) },
        )
        try {
            assertTrue(release.request(id, session))
            assertEquals(
                MknoonTelecomReleaseOutcome.FAILED,
                withTimeout(2_000L) { outcomes.await() },
            )
            assertFalse(local.get())
            assertFalse(release.request(id, session))
        } finally { process.cancel() }
    }

    @Test
    fun `null stale and unavailable scopes never claim local disconnect`() {
        val f = Fixture()
        assertFalse(f.release.request(f.id, null))
        assertFalse(f.release.request(f.id, Any()))
        assertFalse(f.release.request(UUID.randomUUID(), f.session))
        f.scope.cancel()
        assertFalse(f.release.request(f.id, f.session))
        assertTrue(f.markers.isEmpty())
        assertTrue(f.calls.isEmpty())
    }

    @Test
    fun `replaced scope before worker submission is not disconnected`() {
        val f = Fixture()
        assertTrue(f.release.request(f.id, f.session))
        f.session = Any()
        f.dispatcher.drain()
        assertTrue(f.calls.isEmpty())
        assertTrue(f.markers.isEmpty())
        f.scope.cancel()
    }

    @Test
    fun `old canceled job and registration retirement preserve replacement marker`() {
        val f = Fixture()
        val old = f.session
        assertTrue(f.release.request(f.id, old))
        f.session = Any()
        assertTrue(f.release.request(f.id, f.session))
        f.release.retire(f.id, old)
        assertSame(f.session, f.markers[f.id])
        f.dispatcher.drain()
        assertEquals(listOf(f.session), f.calls)
        assertSame(f.session, f.markers[f.id])
        f.release.retire(f.id, f.session)
        assertTrue(f.markers.isEmpty())
        f.scope.cancel()
    }

    @Test
    fun `callback cancellation does not cancel process release`() = runBlocking {
        val process = CoroutineScope(SupervisorJob() + Dispatchers.Default)
        val callbackScope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
        val session = Any()
        val queued = CompletableDeferred<Unit>()
        val callbackReturned = CompletableDeferred<Unit>()
        val disconnected = CompletableDeferred<Unit>()
        val release = MknoonTelecomCallbackRelease(
            scope = process,
            current = { session },
            disconnect = { _: Any ->
                callbackReturned.await()
                disconnected.complete(Unit)
                true
            },
            markLocal = { _, _ -> }, clearLocal = { _, _ -> },
        )
        try {
            callbackScope.launch {
                try {
                    assertTrue(release.request(UUID.randomUUID(), session))
                    queued.complete(Unit)
                    awaitCancellation()
                } finally { callbackReturned.complete(Unit) }
            }
            withTimeout(1_000L) { queued.await() }
            callbackScope.cancel()
            withTimeout(1_000L) { disconnected.await() }
        } finally { callbackScope.cancel(); process.cancel() }
    }

    @Test
    fun `synchronous provider submission cannot block callback return`() = runBlocking {
        val process = CoroutineScope(SupervisorJob() + Dispatchers.Default)
        val session = Any()
        val callbackReturned = CountDownLatch(1)
        val disconnected = CompletableDeferred<Unit>()
        val release = MknoonTelecomCallbackRelease(
            scope = process,
            current = { session },
            disconnect = { _: Any ->
                check(callbackReturned.await(1, TimeUnit.SECONDS))
                disconnected.complete(Unit)
                true
            },
            markLocal = { _, _ -> }, clearLocal = { _, _ -> },
        )
        try {
            withTimeout(200L) {
                coroutineScope {
                    assertTrue(release.request(UUID.randomUUID(), session))
                }
                callbackReturned.countDown()
            }
            withTimeout(1_000L) { disconnected.await() }
        } finally { callbackReturned.countDown(); process.cancel() }
    }

    @Test
    fun `inactive callback returns before serialized provider permits disconnect`() =
        serializedCallbackReturns(rejectActive = false)

    @Test
    fun `rejected active callback returns before serialized provider permits disconnect`() =
        serializedCallbackReturns(rejectActive = true)

    private fun serializedCallbackReturns(rejectActive: Boolean) = runBlocking {
        val process = CoroutineScope(SupervisorJob() + Dispatchers.Default)
        val id = UUID.randomUUID()
        val session = Any()
        val providerCallbackReturned = CompletableDeferred<Unit>()
        val disconnected = CompletableDeferred<Unit>()
        val accepted = AtomicBoolean(false)
        val terminalAcknowledged = AtomicBoolean(false)
        val release = MknoonTelecomCallbackRelease(
            scope = process,
            current = { session },
            disconnect = { _: Any ->
                // Telecom serializes this operation behind the callback result.
                providerCallbackReturned.await()
                disconnected.complete(Unit)
                true
            },
            markLocal = { _, _ -> },
            clearLocal = { _, _ -> },
        )
        try {
            val callback = launch(Dispatchers.Default) {
                try {
                    coroutineScope {
                        terminalAcknowledged.set(true)
                        accepted.set(release.request(id, session))
                        if (rejectActive) error("native active transition rejected")
                    }
                } catch (_: IllegalStateException) {
                    assertTrue(rejectActive)
                } finally {
                    providerCallbackReturned.complete(Unit)
                }
            }
            val returned = withTimeoutOrNull(200L) { callback.join(); true } ?: false
            assertTrue("callback waited for its own serialized provider disconnect", returned)
            assertTrue(terminalAcknowledged.get())
            assertTrue(accepted.get())
            withTimeout(1_000L) { disconnected.await() }
        } finally {
            providerCallbackReturned.complete(Unit)
            process.cancel()
        }
    }
}
