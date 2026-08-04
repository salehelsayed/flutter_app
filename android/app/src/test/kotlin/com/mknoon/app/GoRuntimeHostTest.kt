package com.mknoon.app

import bridge.EventCallback
import java.util.ArrayDeque
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executor
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class GoRuntimeHostTest {
    @Test
    fun `Initialize does not hold the ownership monitor across JNI`() {
        val enteredInitialize = CountDownLatch(1)
        val releaseInitialize = CountDownLatch(1)
        val lifecycle = object : GoRuntimeLifecycle {
            override fun initialize(callback: EventCallback) {
                enteredInitialize.countDown()
                check(releaseInitialize.await(2, TimeUnit.SECONDS))
            }

            override fun stopNode(): Boolean = true
        }
        val host = GoRuntimeHost(lifecycle, ManualExecutor(), ManualDispatcher())
        val threads = Executors.newFixedThreadPool(2)
        try {
            val registration = threads.submit<GoRuntimeHost.OwnerToken> {
                host.registerOwner("foreground") { }
            }
            assertTrue(enteredInitialize.await(1, TimeUnit.SECONDS))

            val snapshot = threads.submit<GoRuntimeHost.Snapshot> {
                host.snapshot()
            }.get(500, TimeUnit.MILLISECONDS)
            assertEquals(GoRuntimeHost.State.ACTIVE, snapshot.state)
            assertFalse(snapshot.initialized)

            releaseInitialize.countDown()
            assertEquals("foreground", registration.get(1, TimeUnit.SECONDS).ownerId)
            assertTrue(host.snapshot().initialized)
        } finally {
            releaseInitialize.countDown()
            threads.shutdownNow()
        }
    }

    @Test
    fun `one initialization and active owner admission`() {
        val work = ManualExecutor()
        val delivery = ManualDispatcher()
        val lifecycle = FakeGoRuntimeLifecycle()
        val host = GoRuntimeHost(lifecycle, work, delivery)
        val results = mutableListOf<String>()

        val foreground = host.registerOwner("foreground") { }
        assertEquals(1, lifecycle.initializeCalls)
        assertEquals(GoRuntimeHost.State.ACTIVE, host.snapshot().state)
        assertTrue(host.execute(foreground, { "foreground-result" }, results::add) { throw it })

        assertTrue(host.requestDrain(foreground))
        assertFalse(host.execute(foreground, { "late" }, results::add) { throw it })
        work.runNext()
        assertTrue(results.isEmpty())
        delivery.runNext()
        work.runNext() // process-global StopNode
        assertEquals(listOf("foreground-result"), results)
        assertEquals(GoRuntimeHost.State.RELEASED, host.snapshot().state)

        val recovery = host.registerOwner("recovery") { }
        assertEquals(1, lifecycle.initializeCalls)
        assertTrue(host.execute(recovery, { "recovery-result" }, results::add) { throw it })
        assertFalse(host.execute(foreground, { "stale" }, results::add) { throw it })
    }

    @Test
    fun `draining fences late call result and callback`() {
        val work = ManualExecutor()
        val delivery = ManualDispatcher()
        val lifecycle = FakeGoRuntimeLifecycle()
        val host = GoRuntimeHost(lifecycle, work, delivery)
        val trace = mutableListOf<String>()
        val token = host.registerOwner("recovery") { trace += "event:$it" }

        assertTrue(host.execute(token, { trace += "work"; "value" }, { trace += "result:$it" }) { throw it })
        work.runNext()
        assertEquals(listOf("work"), trace)
        lifecycle.emit("callback-admitted-before-drain")
        assertTrue(host.requestDrain(token))
        assertEquals(GoRuntimeHost.State.DRAINING, host.snapshot().state)
        assertEquals(0, lifecycle.stopCalls)

        lifecycle.emit("callback-rejected-after-drain")
        delivery.runNext() // call result
        assertEquals(0, lifecycle.stopCalls)
        delivery.runNext() // callback admitted before drain
        work.runNext() // StopNode is ordered after admitted work and queued delivery

        assertEquals(
            listOf("work", "result:value", "event:callback-admitted-before-drain"),
            trace,
        )
        assertFalse(trace.contains("event:callback-rejected-after-drain"))
        assertEquals(1, lifecycle.stopCalls)
        assertEquals(GoRuntimeHost.State.RELEASED, host.snapshot().state)

        lifecycle.emit("callback-after-release")
        delivery.runAll()
        assertFalse(trace.contains("event:callback-after-release"))
    }

    @Test
    fun `stop waits for start`() {
        val work = ManualExecutor()
        val delivery = ManualDispatcher()
        val lifecycle = FakeGoRuntimeLifecycle()
        val host = GoRuntimeHost(lifecycle, work, delivery)
        val trace = mutableListOf<String>()
        val token = host.registerOwner("foreground") { }

        assertTrue(
            host.execute(
                token,
                work = {
                    trace += "start-finished"
                    "started"
                },
                onSuccess = { trace += "result:$it" },
                onError = { throw it },
            ),
        )
        assertTrue(host.requestDrain(token))

        work.runNext()
        assertEquals(listOf("start-finished"), trace)
        assertEquals(0, lifecycle.stopCalls)
        delivery.runNext()
        assertEquals(listOf("start-finished", "result:started"), trace)
        assertEquals(0, lifecycle.stopCalls)
        work.runNext()

        assertEquals(1, lifecycle.stopCalls)
        assertEquals(GoRuntimeHost.State.RELEASED, host.snapshot().state)
    }

    @Test
    fun `dispose cannot leak engine callback or result`() {
        val work = ManualExecutor()
        val delivery = ManualDispatcher()
        val lifecycle = FakeGoRuntimeLifecycle()
        val host = GoRuntimeHost(lifecycle, work, delivery)
        val delivered = mutableListOf<String>()
        val token = host.registerOwner("foreground") { delivered += "event:$it" }

        assertTrue(host.execute(token, { "late-result" }, { delivered += it }) { throw it })
        lifecycle.emit("late-event")
        assertTrue(host.unregister(token))

        work.runNext()
        delivery.runAll()
        work.runNext()

        assertTrue(delivered.isEmpty())
        assertEquals(GoRuntimeHost.State.RELEASED, host.snapshot().state)
        assertFalse(host.execute(token, { "stale" }, { delivered += it }) { throw it })
    }

    @Test
    fun `failed StopNode retains draining ownership`() {
        val work = ManualExecutor()
        val lifecycle = FakeGoRuntimeLifecycle(stopSucceeds = false)
        val host = GoRuntimeHost(lifecycle, work, ManualDispatcher())
        val token = host.registerOwner("foreground") { }

        assertTrue(host.requestDrain(token))
        work.runNext()

        assertEquals(GoRuntimeHost.State.DRAINING, host.snapshot().state)
        assertEquals("foreground", host.snapshot().ownerId)
        assertFalse(host.releaseIfDrained(token))
    }

    @Test
    fun `callback and owner event arriving after drain are rejected`() {
        val work = ManualExecutor()
        val delivery = ManualDispatcher()
        val lifecycle = FakeGoRuntimeLifecycle()
        val host = GoRuntimeHost(lifecycle, work, delivery)
        val events = mutableListOf<String>()
        val token = host.registerOwner("recovery") { events += it }

        assertTrue(host.requestDrain(token)) // queues StopNode while idle
        lifecycle.emit("racing-callback")
        assertFalse(host.emitOwnerEvent(token, "racing-owner-event"))

        work.runNext()

        delivery.runAll()
        assertTrue(events.isEmpty())
        assertEquals(1, lifecycle.stopCalls)
        assertEquals(GoRuntimeHost.State.RELEASED, host.snapshot().state)
    }
}

private class FakeGoRuntimeLifecycle(
    private val stopSucceeds: Boolean = true,
) : GoRuntimeLifecycle {
    var initializeCalls = 0
    var stopCalls = 0
    private var callback: EventCallback? = null

    override fun initialize(callback: EventCallback) {
        initializeCalls += 1
        this.callback = callback
    }

    override fun stopNode(): Boolean {
        stopCalls += 1
        return stopSucceeds
    }

    fun emit(value: String) {
        callback?.onEvent(value)
    }
}

private class ManualExecutor : Executor {
    private val tasks = ArrayDeque<Runnable>()

    override fun execute(command: Runnable) {
        tasks.addLast(command)
    }

    fun runNext() {
        check(tasks.isNotEmpty()) { "No executor task is queued" }
        tasks.removeFirst().run()
    }
}

private class ManualDispatcher : GoRuntimeDeliveryDispatcher {
    private val tasks = ArrayDeque<() -> Unit>()

    override fun dispatch(block: () -> Unit) {
        tasks.addLast(block)
    }

    fun runNext() {
        check(tasks.isNotEmpty()) { "No delivery is queued" }
        tasks.removeFirst().invoke()
    }

    fun runAll() {
        while (tasks.isNotEmpty()) runNext()
    }
}
