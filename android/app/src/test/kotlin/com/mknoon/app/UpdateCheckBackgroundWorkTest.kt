package com.mknoon.app

import android.app.Application
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.NetworkType
import androidx.work.PeriodicWorkRequest
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMethodCodec
import java.io.File
import java.nio.ByteBuffer
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [33])
class UpdateCheckBackgroundWorkTest {
    private val request = UpdateCheckRunRequest(
        reason = "android_periodic",
        budgetMillis = 18_000L,
        installedBuildNumber = "110",
        inCall = false,
    )

    private fun snapshot(
        state: CanonicalRuntimeLeaseBroker.State,
        ownerId: String? = null,
        role: CanonicalRuntimeLeaseBroker.Role? = null,
    ) = CanonicalRuntimeLeaseBroker.Snapshot(
        state = state,
        generation = if (state == CanonicalRuntimeLeaseBroker.State.RELEASED) null else 1L,
        ownerId = ownerId,
        binding = if (ownerId == null) null else "binding",
        role = role,
        maximumConcurrentWritableOwners = if (ownerId == null) 0 else 1,
    )

    @Test
    fun `the lease decides handoff, minimal engine or defer`() {
        val active = CanonicalRuntimeLeaseBroker.State.ACTIVE
        val draining = CanonicalRuntimeLeaseBroker.State.DRAINING
        val released = CanonicalRuntimeLeaseBroker.State.RELEASED
        val foreground = CanonicalRuntimeLeaseBroker.Role.FOREGROUND
        val recovery = CanonicalRuntimeLeaseBroker.Role.RECOVERY

        // Main engine alive and owns the lease: hand off.
        assertEquals(
            UpdateCheckRoute.HANDOFF,
            routeUpdateCheckRun(snapshot(active, "foreground-1", foreground), "foreground-1"),
        )
        // Lease free and no main engine: minimal engine.
        assertEquals(UpdateCheckRoute.MINIMAL_ENGINE, routeUpdateCheckRun(snapshot(released), null))
        // Another owner (headless recovery or call admission): defer.
        assertEquals(
            UpdateCheckRoute.DEFER,
            routeUpdateCheckRun(snapshot(active, "headless-recovery-9", recovery), null),
        )
        assertEquals(
            UpdateCheckRoute.DEFER,
            routeUpdateCheckRun(snapshot(active, "headless-recovery-9", recovery), "foreground-1"),
        )
        // A foreground lease of a different (old) engine: defer.
        assertEquals(
            UpdateCheckRoute.DEFER,
            routeUpdateCheckRun(snapshot(active, "foreground-2", foreground), "foreground-1"),
        )
        // The main engine is tearing down (PiP delay) or not yet registered.
        assertEquals(
            UpdateCheckRoute.DEFER,
            routeUpdateCheckRun(snapshot(draining, "foreground-1", foreground), "foreground-1"),
        )
        assertEquals(
            UpdateCheckRoute.DEFER,
            routeUpdateCheckRun(snapshot(active, "foreground-1", foreground), null),
        )
        // Lease free but a main engine is up (before it takes the lease):
        // never a second engine next to it.
        assertEquals(UpdateCheckRoute.DEFER, routeUpdateCheckRun(snapshot(released), "foreground-1"))
    }

    @Test
    fun `F3 a claimed headless engine defers even before it takes the lease`() {
        val released = snapshot(CanonicalRuntimeLeaseBroker.State.RELEASED)
        assertEquals(
            UpdateCheckRoute.DEFER,
            routeUpdateCheckRun(released, null, headlessEngineClaimed = true),
        )
        assertEquals(
            UpdateCheckRoute.MINIMAL_ENGINE,
            routeUpdateCheckRun(released, null, headlessEngineClaimed = false),
        )
        assertFalse(isHeadlessEngineClaimed())
    }

    @Test
    fun `F3 the minimal engine re-checks everything right before posting`() {
        val released = snapshot(CanonicalRuntimeLeaseBroker.State.RELEASED)
        assertTrue(minimalEngineMayPost(released, null, headlessEngineClaimed = false, inCall = false))
        // A call started during the run.
        assertFalse(minimalEngineMayPost(released, null, headlessEngineClaimed = false, inCall = true))
        // A headless call engine appeared.
        assertFalse(minimalEngineMayPost(released, null, headlessEngineClaimed = true, inCall = false))
        // The user opened the app: a main engine registered and/or took the lease.
        assertFalse(
            minimalEngineMayPost(released, FakeHandoff("foreground-1", emptyMap()), false, false),
        )
        assertFalse(
            minimalEngineMayPost(
                snapshot(
                    CanonicalRuntimeLeaseBroker.State.ACTIVE,
                    "foreground-1",
                    CanonicalRuntimeLeaseBroker.Role.FOREGROUND,
                ),
                null,
                false,
                false,
            ),
        )
        val source = File("src/main/kotlin/com/mknoon/app/UpdateCheckBackgroundWork.kt").readText()
        val runner = source.substringAfter("private class FlutterUpdateCheckMinimalEngineRunner")
        assertTrue(runner.contains("mayPost && postFromArguments("))
    }

    @Test
    fun `F3 a claimed headless engine defers the whole run`() = runBlocking {
        var ran = false
        val execution = UpdateCheckWorkExecution(
            leaseSnapshot = { snapshot(CanonicalRuntimeLeaseBroker.State.RELEASED) },
            registeredMainEngine = { null },
            headlessEngineClaimed = { true },
            handoffRunner = { error("no handoff expected") },
            minimalEngineRunner = { UpdateCheckRunner { ran = true; null } },
            scheduler = UpdateCheckWorkScheduler(RecordingEnqueuer()),
        )
        assertEquals(UpdateCheckWorkOutcome.DEFERRED, execution.execute(request))
        assertFalse(ran)
    }

    @Test
    fun `switch on schedules one unique periodic work, switch off only cancels`() {
        val enqueuer = RecordingEnqueuer()
        val scheduler = UpdateCheckWorkScheduler(enqueuer)

        scheduler.apply(true)
        assertEquals(1, enqueuer.periodic.size)
        val (name, policy, work) = enqueuer.periodic.single()
        assertEquals("mknoon-se41-update-check", name)
        assertEquals(ExistingPeriodicWorkPolicy.KEEP, policy)
        assertEquals(TimeUnit.HOURS.toMillis(12), work.workSpec.intervalDuration)
        assertEquals(NetworkType.CONNECTED, work.workSpec.constraints.requiredNetworkType)
        assertEquals(UpdateCheckWorker::class.java.name, work.workSpec.workerClassName)
        assertTrue(enqueuer.cancelled.isEmpty())

        val off = RecordingEnqueuer()
        UpdateCheckWorkScheduler(off).apply(false)
        assertTrue(off.periodic.isEmpty())
        assertEquals(listOf("mknoon-se41-update-check"), off.cancelled)
    }

    @Test
    fun `handoff runs on the main engine and never starts the minimal engine`() = runBlocking {
        val handoff = FakeHandoff("foreground-1", mapOf("outcome" to "noUpdate", "enabled" to true))
        var minimalStarted = false
        val execution = execution(
            lease = snapshot(
                CanonicalRuntimeLeaseBroker.State.ACTIVE,
                "foreground-1",
                CanonicalRuntimeLeaseBroker.Role.FOREGROUND,
            ),
            mainEngine = handoff,
            minimal = UpdateCheckRunner { minimalStarted = true; emptyMap<String, Any>() },
        )

        assertEquals(UpdateCheckWorkOutcome.COMPLETED, execution.execute(request))
        assertEquals(listOf(request), handoff.requests)
        assertFalse(minimalStarted)
    }

    @Test
    fun `another lease owner defers without running anything`() = runBlocking {
        var ran = false
        val execution = execution(
            lease = snapshot(
                CanonicalRuntimeLeaseBroker.State.ACTIVE,
                "headless-recovery-3",
                CanonicalRuntimeLeaseBroker.Role.RECOVERY,
            ),
            mainEngine = null,
            minimal = UpdateCheckRunner { ran = true; null },
        )

        assertEquals(UpdateCheckWorkOutcome.DEFERRED, execution.execute(request))
        assertFalse(ran)
    }

    @Test
    fun `the minimal engine run never takes the lease`() = runBlocking {
        val broker = CanonicalRuntimeLeaseBroker()
        val execution = UpdateCheckWorkExecution(
            leaseSnapshot = { broker.snapshot() },
            registeredMainEngine = { null },
            headlessEngineClaimed = { false },
            handoffRunner = { error("no handoff expected") },
            minimalEngineRunner = {
                UpdateCheckRunner { mapOf("outcome" to "notified", "enabled" to true) }
            },
            scheduler = UpdateCheckWorkScheduler(RecordingEnqueuer()),
        )

        assertEquals(UpdateCheckWorkOutcome.COMPLETED, execution.execute(request))
        val after = broker.snapshot()
        assertEquals(CanonicalRuntimeLeaseBroker.State.RELEASED, after.state)
        assertEquals(0, after.maximumConcurrentWritableOwners)
    }

    @Test
    fun `the minimal engine registers no lease, Go, SQLCipher or Firebase plugin`() {
        val source = File("src/main/kotlin/com/mknoon/app/UpdateCheckBackgroundWork.kt").readText()
        val runner = source.substringAfter("private class FlutterUpdateCheckMinimalEngineRunner")
        for (forbidden in listOf(
            "CanonicalRuntimeLeaseBridge",
            "broker.acquire",
            "GoBridge",
            "SqfliteSqlCipherPlugin",
            "FlutterSecureStoragePlugin",
            "Firebase",
            "FlutterLocalNotificationsPlugin",
        )) {
            assertFalse(forbidden, runner.contains(forbidden))
        }
        assertTrue(runner.contains("plugins.add(PathProviderPlugin())"))
        assertEquals(1, Regex("plugins\\.add\\(").findAll(runner).count())
        assertTrue(runner.contains("UpdateCheckBackgroundWork.MINIMAL_ENTRYPOINT"))
        assertTrue(source.contains("\"androidUpdateCheckMinimalMain\""))
    }

    @Test
    fun `the budget abort reports a timeout and ends the run`() = runBlocking {
        val never = CompletableDeferred<Map<*, *>?>()
        var cancelled = false
        val execution = execution(
            lease = snapshot(CanonicalRuntimeLeaseBroker.State.RELEASED),
            mainEngine = null,
            minimal = UpdateCheckRunner {
                try {
                    never.await()
                } finally {
                    cancelled = true
                }
            },
            timeoutMillis = 50L,
        )

        assertEquals(UpdateCheckWorkOutcome.TIMED_OUT, execution.execute(request))
        assertTrue("the runner's finally (engine teardown) ran", cancelled)
    }

    @Test
    fun `a disabled result cancels the schedule`() = runBlocking {
        val enqueuer = RecordingEnqueuer()
        val execution = execution(
            lease = snapshot(CanonicalRuntimeLeaseBroker.State.RELEASED),
            mainEngine = null,
            minimal = UpdateCheckRunner { mapOf("outcome" to "disabled", "enabled" to false) },
            enqueuer = enqueuer,
        )

        assertEquals(UpdateCheckWorkOutcome.DISABLED, execution.execute(request))
        assertEquals(listOf("mknoon-se41-update-check"), enqueuer.cancelled)
        assertTrue(enqueuer.periodic.isEmpty())
    }

    @Test
    fun `the main-engine bridge configures, hands off and unregisters`() {
        val application: Application = RuntimeEnvironment.getApplication()
        val messenger = RecordingMessenger()
        val enqueuer = RecordingEnqueuer()
        val bridge = UpdateCheckBackgroundBridge(
            context = application,
            messenger = messenger,
            ownerId = "foreground-7",
            scheduler = UpdateCheckWorkScheduler(enqueuer),
        )
        assertEquals(bridge, UpdateCheckMainEngineRegistry.current())

        val replies = mutableListOf<Any?>()
        val result = object : MethodChannel.Result {
            override fun success(result: Any?) {
                replies.add(result)
            }

            override fun error(code: String, message: String?, details: Any?) {
                replies.add("error:$code")
            }

            override fun notImplemented() {
                replies.add("notImplemented")
            }
        }
        for (enabled in listOf(false, true)) {
            bridge.onMethodCall(MethodCall("configure", mapOf("enabled" to enabled)), result)
        }
        assertEquals(listOf("mknoon-se41-update-check"), enqueuer.cancelled)
        assertEquals(1, enqueuer.periodic.size)
        bridge.onMethodCall(MethodCall("configure", null), result)
        assertEquals("error:bad_args", replies.last())

        var handed: Map<*, *>? = null
        bridge.run(request.copy(inCall = true)) { handed = it }
        val sent = StandardMethodCodec.INSTANCE.decodeMethodCall(messenger.lastMessage!!)
        assertEquals("run", sent.method)
        assertEquals(true, sent.argument<Boolean>("inCall"))
        assertEquals(18_000, sent.argument<Int>("budgetMs"))
        messenger.reply(StandardMethodCodec.INSTANCE.encodeSuccessEnvelope(mapOf("outcome" to "inCall")))
        assertEquals("inCall", handed?.get("outcome"))

        bridge.dispose()
        assertNull(UpdateCheckMainEngineRegistry.current())
    }

    private fun execution(
        lease: CanonicalRuntimeLeaseBroker.Snapshot,
        mainEngine: UpdateCheckMainEngineHandoff?,
        minimal: UpdateCheckRunner,
        enqueuer: RecordingEnqueuer = RecordingEnqueuer(),
        timeoutMillis: Long = 1_000L,
    ) = UpdateCheckWorkExecution(
        leaseSnapshot = { lease },
        registeredMainEngine = { mainEngine },
        headlessEngineClaimed = { false },
        handoffRunner = { handoff ->
            UpdateCheckRunner { req ->
                val reply = CompletableDeferred<Map<*, *>?>()
                handoff.run(req) { reply.complete(it) }
                reply.await()
            }
        },
        minimalEngineRunner = { minimal },
        scheduler = UpdateCheckWorkScheduler(enqueuer),
        timeoutMillis = timeoutMillis,
    )

    private class FakeHandoff(
        override val ownerId: String,
        private val reply: Map<String, Any?>,
    ) : UpdateCheckMainEngineHandoff {
        val requests = mutableListOf<UpdateCheckRunRequest>()

        override fun run(request: UpdateCheckRunRequest, callback: (Map<*, *>?) -> Unit) {
            requests.add(request)
            callback(reply)
        }
    }

    private class RecordingEnqueuer : UpdateCheckWorkEnqueuer {
        val periodic = mutableListOf<Triple<String, ExistingPeriodicWorkPolicy, PeriodicWorkRequest>>()
        val cancelled = mutableListOf<String>()

        override fun enqueueUniquePeriodic(
            uniqueName: String,
            policy: ExistingPeriodicWorkPolicy,
            request: PeriodicWorkRequest,
        ) {
            periodic.add(Triple(uniqueName, policy, request))
        }

        override fun cancelUniqueWork(uniqueName: String) {
            cancelled.add(uniqueName)
        }
    }

    private class RecordingMessenger : BinaryMessenger {
        var lastMessage: ByteBuffer? = null
        private var lastReply: BinaryMessenger.BinaryReply? = null

        override fun send(channel: String, message: ByteBuffer?) {
            lastMessage = message
        }

        override fun send(
            channel: String,
            message: ByteBuffer?,
            callback: BinaryMessenger.BinaryReply?,
        ) {
            message?.rewind()
            lastMessage = message
            lastReply = callback
        }

        override fun setMessageHandler(
            channel: String,
            handler: BinaryMessenger.BinaryMessageHandler?,
        ) = Unit

        fun reply(envelope: ByteBuffer) {
            envelope.rewind()
            lastReply?.reply(envelope)
        }
    }
}
