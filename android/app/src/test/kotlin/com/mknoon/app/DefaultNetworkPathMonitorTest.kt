package com.mknoon.app

import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import org.robolectric.shadows.ShadowNetwork
import org.robolectric.shadows.ShadowNetworkCapabilities

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [33])
class DefaultNetworkPathMonitorTest {
    private class ManualScheduler : DefaultNetworkPathMonitor.Scheduler {
        private val pending = mutableListOf<Runnable>()
        var shutdowns = 0

        /** Models a delivery the executor already dequeued when cancel arrived. */
        var ignoreCancel = false

        override fun schedule(delayMs: Long, work: Runnable): DefaultNetworkPathMonitor.Cancellable {
            pending += work
            return DefaultNetworkPathMonitor.Cancellable { if (!ignoreCancel) pending.remove(work) }
        }

        override fun shutdown() {
            shutdowns++
        }

        fun advance() {
            val due = pending.toList()
            pending.clear()
            due.forEach(Runnable::run)
        }

        val pendingCount: Int get() = pending.size
    }

    private class RecordingSender(var admitted: Boolean = true) : DefaultNetworkPathMonitor.Sender {
        val sends = mutableListOf<Pair<Long, Boolean>>()
        val threads = mutableListOf<String>()
        private val answers = mutableListOf<(String) -> Unit>()
        private val checks = mutableListOf<() -> Boolean>()

        override fun send(
            epoch: Long,
            usable: Boolean,
            stillCurrent: () -> Boolean,
            onAnswer: (String) -> Unit,
        ): Boolean {
            sends += epoch to usable
            threads += Thread.currentThread().name
            answers += onAnswer
            checks += stillCurrent
            return admitted
        }

        /** Delivers Go's answer for the n-th send (0-based). */
        fun answer(index: Int, reason: String) = answers[index](reason)

        /** The executor-hop check for the n-th send, asked right before the Go call. */
        fun stillCurrent(index: Int): Boolean = checks[index]()
    }

    private lateinit var connectivity: ConnectivityManager
    private val scheduler = ManualScheduler()
    private val sender = RecordingSender()
    private val wifi: Network = ShadowNetwork.newInstance(101)
    private val cellular: Network = ShadowNetwork.newInstance(202)
    private val otherWifi: Network = ShadowNetwork.newInstance(303)

    @Before
    fun setUp() {
        connectivity = RuntimeEnvironment.getApplication()
            .getSystemService(ConnectivityManager::class.java)
    }

    private fun monitor(
        sender: DefaultNetworkPathMonitor.Sender = this.sender,
        scheduler: DefaultNetworkPathMonitor.Scheduler = this.scheduler,
        debounceMs: Long = DefaultNetworkPathMonitor.DEFAULT_DEBOUNCE_MS,
    ): DefaultNetworkPathMonitor {
        val monitor = DefaultNetworkPathMonitor(connectivity, sender, scheduler, debounceMs)
        assertTrue(monitor.start())
        return monitor
    }

    private fun callback(): ConnectivityManager.NetworkCallback =
        shadowOf(connectivity).networkCallbacks.single()

    private fun capabilities(validated: Boolean = true): NetworkCapabilities {
        val caps = ShadowNetworkCapabilities.newInstance()
        shadowOf(caps).addCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
        if (validated) shadowOf(caps).addCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED)
        return caps
    }

    private fun seedWifi() {
        callback().onAvailable(wifi)
        callback().onCapabilitiesChanged(wifi, capabilities())
        scheduler.advance()
    }

    private fun switchTo(network: Network, validated: Boolean = true) {
        callback().onAvailable(network)
        callback().onCapabilitiesChanged(network, capabilities(validated))
    }

    /**
     * Runs the pending delivery on its own thread while the test holds the
     * monitor lock, so the timer has already fired when [whileBlocked] changes
     * the state under that lock. This is the interleaving a cancelled
     * ScheduledFuture cannot stop.
     */
    private fun advanceWhileBlockedOn(monitor: DefaultNetworkPathMonitor, whileBlocked: () -> Unit) {
        val field = DefaultNetworkPathMonitor::class.java.getDeclaredField("lock")
        field.isAccessible = true
        val monitorLock = checkNotNull(field.get(monitor))
        val delivery = Thread { scheduler.advance() }
        synchronized(monitorLock) {
            delivery.start()
            val deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(3)
            while (delivery.state != Thread.State.BLOCKED && System.nanoTime() < deadline) Thread.yield()
            assertEquals(
                "precondition: timer is inside deliver and waiting for its monitor",
                Thread.State.BLOCKED,
                delivery.state,
            )
            whileBlocked()
        }
        delivery.join(3000)
        assertTrue("timer thread must finish", !delivery.isAlive)
    }

    @Test
    fun `the path observer learns the seed as epoch 0 and each delivered epoch`() {
        val seen = mutableListOf<Pair<Network, Long>>()
        val monitor = DefaultNetworkPathMonitor(
            connectivity,
            sender,
            scheduler,
            DefaultNetworkPathMonitor.DEFAULT_DEBOUNCE_MS,
            DefaultNetworkPathMonitor.PathObserver { network, epoch -> seen += network to epoch },
        )
        assertTrue(monitor.start())

        seedWifi()
        switchTo(cellular)
        scheduler.advance()

        assertEquals(listOf(wifi to 0L, cellular to 1L), seen)
    }

    @Test
    fun `the first default network is a seed and sends nothing`() {
        monitor()
        seedWifi()
        callback().onCapabilitiesChanged(wifi, capabilities())
        scheduler.advance()

        assertEquals(emptyList<Pair<Long, Boolean>>(), sender.sends)
    }

    @Test
    fun `wifi to cellular with no none in between sends one new epoch after the debounce`() {
        monitor()
        seedWifi()

        switchTo(cellular)
        assertEquals(emptyList<Pair<Long, Boolean>>(), sender.sends)
        scheduler.advance()

        assertEquals(listOf(1L to true), sender.sends)
    }

    @Test
    fun `repeated capabilities for the current path send nothing more`() {
        monitor()
        seedWifi()
        switchTo(cellular)
        scheduler.advance()

        callback().onCapabilitiesChanged(cellular, capabilities())
        callback().onCapabilitiesChanged(cellular, capabilities())
        scheduler.advance()

        assertEquals(listOf(1L to true), sender.sends)
    }

    @Test
    fun `an old network's late onLost does not disturb the new path`() {
        monitor()
        seedWifi()
        switchTo(cellular)
        scheduler.advance()

        callback().onLost(wifi)
        callback().onCapabilitiesChanged(cellular, capabilities(validated = false))
        callback().onCapabilitiesChanged(cellular, capabilities())
        scheduler.advance()

        assertEquals(listOf(1L to true, 2L to true), sender.sends)
    }

    @Test
    fun `a flap keeps the latest path and epochs stay monotonic`() {
        monitor()
        seedWifi()

        switchTo(cellular)
        scheduler.advance()
        switchTo(wifi)
        scheduler.advance()
        switchTo(cellular)
        switchTo(otherWifi)
        assertEquals(1, scheduler.pendingCount)
        scheduler.advance()

        assertEquals(listOf(1L to true, 2L to true, 3L to true), sender.sends)
    }

    @Test
    fun `an unvalidated path sends nothing until it validates`() {
        monitor()
        seedWifi()

        switchTo(cellular, validated = false)
        scheduler.advance()
        assertEquals(emptyList<Pair<Long, Boolean>>(), sender.sends)

        callback().onCapabilitiesChanged(cellular, capabilities())
        scheduler.advance()
        assertEquals(listOf(1L to true), sender.sends)
    }

    @Test
    fun `losing the current default sends nothing and the next usable path is a new epoch`() {
        monitor()
        seedWifi()

        callback().onLost(wifi)
        scheduler.advance()
        assertEquals(emptyList<Pair<Long, Boolean>>(), sender.sends)

        switchTo(cellular)
        scheduler.advance()
        assertEquals(listOf(1L to true), sender.sends)
    }

    @Test
    fun `switching back to the announced path before the debounce sends nothing`() {
        monitor()
        seedWifi()
        switchTo(cellular)
        scheduler.advance()

        switchTo(wifi)
        switchTo(cellular)
        assertEquals(0, scheduler.pendingCount)
        scheduler.advance()

        assertEquals(listOf(1L to true), sender.sends)
    }

    @Test
    fun `an inactive owner is not retried and close unregisters the callback`() {
        sender.admitted = false
        val monitor = monitor()
        seedWifi()
        switchTo(cellular)
        scheduler.advance()
        callback().onCapabilitiesChanged(cellular, capabilities())
        scheduler.advance()
        assertEquals(listOf(1L to true), sender.sends)

        switchTo(otherWifi)
        assertEquals(1, scheduler.pendingCount)
        scheduler.ignoreCancel = true
        monitor.close()
        assertTrue(shadowOf(connectivity).networkCallbacks.isEmpty())
        assertEquals(1, scheduler.shutdowns)
        assertEquals(1, scheduler.pendingCount)
        scheduler.advance()
        assertEquals(listOf(1L to true), sender.sends)
        monitor.close()
        assertEquals(1, scheduler.shutdowns)
    }

    @Test
    @Config(sdk = [24])
    fun `before API 26 a new default's capabilities are read without waiting for a callback`() {
        monitor()
        shadowOf(connectivity).setNetworkCapabilities(wifi, capabilities())
        shadowOf(connectivity).setNetworkCapabilities(cellular, capabilities())
        callback().onAvailable(wifi)
        scheduler.advance()
        assertEquals(emptyList<Pair<Long, Boolean>>(), sender.sends)

        callback().onAvailable(cellular)
        scheduler.advance()

        assertEquals(listOf(1L to true), sender.sends)
    }

    @Test
    fun `delivery runs on the monitor thread, not the callback thread`() {
        val sender = RecordingSender()
        val delivered = CountDownLatch(1)
        val monitor = DefaultNetworkPathMonitor(
            connectivity,
            { epoch, usable, stillCurrent, onAnswer ->
                sender.send(epoch, usable, stillCurrent, onAnswer)
                delivered.countDown()
                true
            },
            debounceMs = 0,
        )
        assertTrue(monitor.start())
        try {
            callback().onAvailable(wifi)
            callback().onCapabilitiesChanged(wifi, capabilities())
            switchTo(cellular)

            assertTrue(delivered.await(5, TimeUnit.SECONDS))
            assertEquals(listOf(1L to true), sender.sends)
            assertEquals(DefaultNetworkPathMonitor.THREAD_NAME, sender.threads.single())
            assertNotEquals(Thread.currentThread().name, sender.threads.single())
        } finally {
            monitor.close()
        }
    }

    // SE-42 D27: an epoch that reached a stopped node is owed to it once this
    // owner starts one. Go buffers nothing for `not_started`.

    @Test
    fun `an epoch the stopped node refused is re-sent once after the node starts`() {
        val monitor = monitor()
        seedWifi()
        switchTo(cellular)
        scheduler.advance()
        assertEquals(listOf(1L to true), sender.sends)

        sender.answer(0, DefaultNetworkPathMonitor.REASON_NOT_STARTED)
        scheduler.advance()
        assertEquals(listOf(1L to true), sender.sends)

        monitor.nodeStarted()
        scheduler.advance()
        assertEquals(listOf(1L to true, 2L to true), sender.sends)

        sender.answer(1, "none")
        monitor.nodeStarted()
        scheduler.advance()
        assertEquals(listOf(1L to true, 2L to true), sender.sends)
    }

    @Test
    fun `a seed and an accepted epoch are not re-sent when the node starts`() {
        val monitor = monitor()
        seedWifi()
        monitor.nodeStarted()
        scheduler.advance()
        assertEquals(emptyList<Pair<Long, Boolean>>(), sender.sends)

        switchTo(cellular)
        scheduler.advance()
        sender.answer(0, "none")
        monitor.nodeStarted()
        scheduler.advance()
        assertEquals(listOf(1L to true), sender.sends)
    }

    @Test
    fun `a newer path pending when the node starts wins over the refused one`() {
        val monitor = monitor()
        seedWifi()
        switchTo(cellular)
        scheduler.advance()
        sender.answer(0, DefaultNetworkPathMonitor.REASON_NOT_STARTED)

        switchTo(otherWifi)
        monitor.nodeStarted()
        assertEquals(1, scheduler.pendingCount)
        scheduler.advance()
        assertEquals(listOf(1L to true, 2L to true), sender.sends)

        sender.answer(1, "none")
        monitor.nodeStarted()
        scheduler.advance()
        assertEquals(listOf(1L to true, 2L to true), sender.sends)
    }

    @Test
    fun `a not_started answer that lands after the node started is re-sent at once`() {
        val monitor = monitor()
        seedWifi()
        switchTo(cellular)
        scheduler.advance()

        monitor.nodeStarted()
        scheduler.advance()
        assertEquals(listOf(1L to true), sender.sends)

        sender.answer(0, DefaultNetworkPathMonitor.REASON_NOT_STARTED)
        scheduler.advance()
        assertEquals(listOf(1L to true, 2L to true), sender.sends)
    }

    @Test
    fun `a late not_started answer for an older epoch does not re-send`() {
        val monitor = monitor()
        seedWifi()
        switchTo(cellular)
        scheduler.advance()
        switchTo(otherWifi)
        scheduler.advance()
        assertEquals(listOf(1L to true, 2L to true), sender.sends)

        sender.answer(0, DefaultNetworkPathMonitor.REASON_NOT_STARTED)
        sender.answer(1, "none")
        monitor.nodeStarted()
        scheduler.advance()
        assertEquals(listOf(1L to true, 2L to true), sender.sends)
    }

    @Test
    fun `flapping back to the refused path before the debounce still re-sends it once`() {
        val monitor = monitor()
        seedWifi()
        switchTo(cellular)
        scheduler.advance()
        sender.answer(0, DefaultNetworkPathMonitor.REASON_NOT_STARTED)

        switchTo(otherWifi)
        monitor.nodeStarted()
        switchTo(cellular)
        assertEquals(1, scheduler.pendingCount)
        scheduler.advance()
        assertEquals(listOf(1L to true, 2L to true), sender.sends)

        callback().onCapabilitiesChanged(cellular, capabilities())
        scheduler.advance()
        assertEquals(listOf(1L to true, 2L to true), sender.sends)
    }

    @Test
    fun `repeated capabilities while the node stays stopped send nothing more`() {
        val monitor = monitor()
        seedWifi()
        switchTo(cellular)
        scheduler.advance()
        sender.answer(0, DefaultNetworkPathMonitor.REASON_NOT_STARTED)

        callback().onCapabilitiesChanged(cellular, capabilities())
        callback().onCapabilitiesChanged(cellular, capabilities())
        scheduler.advance()
        assertEquals(listOf(1L to true), sender.sends)

        monitor.nodeStarted()
        scheduler.advance()
        assertEquals(listOf(1L to true, 2L to true), sender.sends)
    }

    @Test
    fun `a refused path that was lost meanwhile is not re-sent`() {
        val monitor = monitor()
        seedWifi()
        switchTo(cellular)
        scheduler.advance()
        sender.answer(0, DefaultNetworkPathMonitor.REASON_NOT_STARTED)

        callback().onLost(cellular)
        monitor.nodeStarted()
        scheduler.advance()
        assertEquals(listOf(1L to true), sender.sends)
    }

    // SE-42 D27 (Task 15 finding 6): a cancelled timer whose work already
    // left the executor queue still runs. Losing VALIDATED, or a newer
    // default, must void that delivery, and the void delivery must not pose
    // as the announced path afterwards.

    @Test
    fun `a delivery already running when VALIDATED is lost sends nothing`() {
        val owned = monitor()
        try {
            seedWifi()
            switchTo(cellular)
            advanceWhileBlockedOn(owned) {
                callback().onCapabilitiesChanged(cellular, capabilities(validated = false))
            }
            assertEquals(
                "lost VALIDATED must fence an already-running delivery",
                emptyList<Pair<Long, Boolean>>(),
                sender.sends,
            )
        } finally {
            owned.close()
        }
    }

    @Test
    fun `a fenced delivery does not dedupe the same network's revalidation`() {
        val owned = monitor()
        try {
            seedWifi()
            switchTo(cellular)
            advanceWhileBlockedOn(owned) {
                callback().onCapabilitiesChanged(cellular, capabilities(validated = false))
            }
            assertEquals(emptyList<Pair<Long, Boolean>>(), sender.sends)

            callback().onCapabilitiesChanged(cellular, capabilities())
            assertEquals(1, scheduler.pendingCount)
            scheduler.advance()
            assertEquals(listOf(1L to true), sender.sends)
        } finally {
            owned.close()
        }
    }

    @Test
    fun `a delivery already running when a newer default arrives sends nothing`() {
        val owned = monitor()
        try {
            seedWifi()
            switchTo(cellular)
            advanceWhileBlockedOn(owned) {
                callback().onAvailable(otherWifi)
            }
            assertEquals(emptyList<Pair<Long, Boolean>>(), sender.sends)

            callback().onCapabilitiesChanged(otherWifi, capabilities())
            scheduler.advance()
            assertEquals(listOf(1L to true), sender.sends)
        } finally {
            owned.close()
        }
    }

    @Test
    fun `an epoch the path outran before the executor hop is dropped and not announced`() {
        monitor()
        seedWifi()
        switchTo(cellular)
        scheduler.advance()
        assertEquals(listOf(1L to true), sender.sends)
        assertTrue("nothing changed since the send", sender.stillCurrent(0))

        callback().onCapabilitiesChanged(cellular, capabilities(validated = false))
        assertFalse("lost VALIDATED voids the queued epoch", sender.stillCurrent(0))

        callback().onCapabilitiesChanged(cellular, capabilities())
        scheduler.advance()
        assertEquals(listOf(1L to true, 2L to true), sender.sends)
        assertTrue(sender.stillCurrent(1))

        switchTo(otherWifi)
        assertFalse("a newer default voids the queued epoch", sender.stillCurrent(1))
        switchTo(cellular)
        assertEquals(1, scheduler.pendingCount)
        scheduler.advance()
        assertEquals(
            "the dropped epoch never reached Go, so cellular is a fresh path",
            listOf(1L to true, 2L to true, 3L to true),
            sender.sends,
        )
    }
}
