package com.mknoon.app

import android.content.Context
import android.graphics.Bitmap
import android.os.Looper
import com.google.android.gms.tasks.Task
import com.google.android.gms.tasks.TaskCompletionSource
import com.google.android.gms.tasks.Tasks
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineGroup
import io.flutter.embedding.engine.FlutterJNI
import io.flutter.embedding.engine.loader.FlutterLoader
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMethodCodec
import io.flutter.plugin.platform.PlatformViewsController
import java.io.File
import java.nio.ByteBuffer
import java.util.ArrayDeque
import java.util.UUID
import java.util.concurrent.Executor
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNotSame
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode
import org.robolectric.annotation.Implementation
import org.robolectric.annotation.Implements
import org.robolectric.annotation.LooperMode
import org.robolectric.shadows.ShadowActivity

/**
 * MainActivity's real cutout hooks and complete cleanup override execute here.
 * Only embedding superclass cleanup and engine construction exclude Flutter JNI.
 * Model tasks are controlled through the existing real bridge constructor.
 */
@RunWith(RobolectricTestRunner::class)
@Config(
    sdk = [33],
    shadows = [StickerCutoutRegistrationFlutterActivityShadow::class, StickerCutoutRegistrationFlutterEngineShadow::class, StickerCutoutHostPosixShadow::class, StickerCutoutHostOsConstantsShadow::class, StickerCutoutHostBlockGuardOsShadow::class],
    instrumentedPackages = ["io.flutter.embedding.android", "io.flutter.embedding.engine"],
)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@LooperMode(LooperMode.Mode.PAUSED)
class StickerCutoutRegistrationTest {
    @get:Rule val temporary = TemporaryFolder()

    private val events = mutableListOf<String>()
    private val activities = mutableListOf<MainActivity>()
    private val controlledBridges = mutableListOf<ControlledBridge>()
    private val messengers = mutableListOf<RecordingMessenger>()
    private val jobDirectories = mutableListOf<File>()
    private var ownedLease: CanonicalRuntimeLeaseBroker.Token? = null

    @Before
    fun establishIsolatedLeaseAndEmbeddingBoundary() {
        assertEquals("fixture must not steal another runtime owner", CanonicalRuntimeLeaseBroker.State.RELEASED, ProcessCanonicalRuntimeLease.broker.snapshot().state)
        StickerCutoutRegistrationFlutterActivityShadow.events = events
        StickerCutoutRegistrationFlutterActivityShadow.superCleanups = 0
    }

    @After
    fun releaseOnlyFixtureOwnership() {
        releaseLeaseAndReplyToShutdown()
        // Cleanup must remain effective even while production hooks are RED.
        activities.forEach { activity ->
            owner(activity)?.close()
            setField(activity, "stickerCutoutBridge", null)
            (field(activity, "androidCallWakeBridge") as AndroidCallWakeBridge?)?.dispose()
            setField(activity, "androidCallWakeBridge", null)
        }
        controlledBridges.forEach {
            it.bridge.close()
            if (!it.client.inference.task.isComplete) it.client.inference.setResult(null)
            it.flush()
        }
        shadowOf(Looper.getMainLooper()).idle()
        jobDirectories.forEach { it.deleteRecursively() }
        StickerCutoutRegistrationFlutterActivityShadow.events = null
        StickerCutoutRegistrationFlutterActivityShadow.superCleanups = 0
    }

    @Test
    fun setupRegistersOneCurrentHandlerAndClosesBeforeSameEngineReplacement() {
        val activity = activity()
        val messenger = messenger("engine")
        attach(activity, messenger)
        val first = owner(activity)
        assertNotNull("setup must retain the engine's real cutout bridge", first)
        assertNull(messenger.call("cancel", mapOf("jobId" to "idle")).success())

        attach(activity, messenger)
        assertNotSame(first, owner(activity))
        assertEquals(listOf("engine.cutout.attach", "engine.cutout.remove", "engine.cutout.attach"), channelEvents())
        assertNull(messenger.call("cancel", mapOf("jobId" to "idle")).success())

        detach(activity)
        assertNull(owner(activity))
        assertNull(messenger.handler)
        detach(activity)
        assertEquals(2, channelEvents().count { it == "engine.cutout.remove" })
    }

    @Test
    fun replacementSettlesOldAvailabilityBeforeAttachingTheNewEngine() {
        val activity = activity()
        val old = controlled(activity, "old")
        val module = TaskCompletionSource<Boolean>()
        old.client.availabilityTask = module.task
        val pending = old.messenger.call("availability")
        old.flush()
        assertEquals("fixture must reach a pending real bridge module probe", 1, old.client.probes)
        assertEquals(0, pending.count)
        val next = messenger("next")

        attach(activity, next)

        assertNull(old.messenger.handler)
        assertEquals("unsupported", pending.success())
        assertEquals(1, old.client.closes)
        assertNotSame(old.bridge, owner(activity))
        assertBefore("old.cutout.remove", "next.cutout.attach")
        assertBefore("old.availability.reply", "next.cutout.attach")

        module.setResult(true)
        old.flush()
        assertEquals("the old engine must not get a second availability reply", 1, pending.count)
        assertNull(next.call("cancel", mapOf("jobId" to "idle")).success())
    }

    @Test
    fun cleanupSettlesExtractionBeforeDelayedRuntimeShutdownAndPreservesSuccessor() {
        val activity = activity()
        val old = controlled(activity, "old")
        val source = png()
        val directory = File(activity.cacheDir.canonicalFile, "mknoon-sticker-cutout-registration-${UUID.randomUUID()}")
        assertTrue(directory.mkdir())
        jobDirectories.add(directory)
        val output = File(directory, "result.png")
        val pending = old.messenger.call("extract", mapOf(
            "jobId" to directory.name,
            "sourceImagePath" to source.path,
            "outputPath" to output.path,
        ))
        old.flush()
        assertEquals("fixture must reach pending inference before engine cleanup", 1, old.client.inferences)
        assertEquals(0, pending.count)
        assertFalse(output.exists())

        ownedLease = requireNotNull(ProcessCanonicalRuntimeLease.broker.acquire(
            "cutout-registration", "fixture-account", CanonicalRuntimeLeaseBroker.Role.FOREGROUND,
        ))
        setField(activity, "androidCallWakeBridge", AndroidCallWakeBridge(
            old.messenger, "cutout-cleanup-witness", registry = AndroidCallWakeSignalRegistry(),
        ))
        setField(activity, "canonicalRuntimeShutdownChannel", MethodChannel(old.messenger, SHUTDOWN_CHANNEL))
        val engine = FlutterEngine(activity)

        // This is MainActivity's complete production override, not a direct
        // call to closeStickerCutoutBridge or a source-order assertion.
        activity.cleanUpFlutterEngine(engine)

        assertEquals(1, old.messenger.pendingShutdownReplies)
        assertEquals(CanonicalRuntimeLeaseBroker.State.ACTIVE, ProcessCanonicalRuntimeLease.broker.snapshot().state)
        assertEquals(true, field(activity, "retainEngineForCanonicalShutdown"))
        assertEquals(1, StickerCutoutRegistrationFlutterActivityShadow.superCleanups)
        assertNull("cutout must close while Dart's runtime shutdown is still pending", old.messenger.handler)
        assertNull(owner(activity))
        assertNull(pending.success())
        assertEquals(1, old.client.closes)
        assertBefore("old.cutout.remove", "old.callWake.remove")
        assertBefore("old.extract.reply", "old.callWake.remove")
        assertBefore("old.cutout.remove", "embedding.shouldDestroy")
        assertBefore("old.extract.reply", "old.shutdown.send")

        val next = messenger("next")
        attach(activity, next)
        assertNotNull(next.handler)
        val lateForeground = Bitmap.createBitmap(2, 2, Bitmap.Config.ARGB_8888).apply { eraseColor(0xffff0000.toInt()) }
        old.client.inference.setResult(lateForeground)
        old.flush()
        assertEquals(1, pending.count)
        assertFalse(output.exists())
        assertNull(next.call("cancel", mapOf("jobId" to "idle")).success())

        // The delayed Go/Dart completion belongs to the detached engine. It
        // must not run a late cutout close against the newly attached owner.
        releaseLeaseAndReplyToShutdown()
        assertEquals(false, field(activity, "retainEngineForCanonicalShutdown"))
        assertNotNull(next.handler)
        assertNull(next.call("cancel", mapOf("jobId" to "idle")).success())
    }

    @Test
    fun releasedRuntimeCleanupIsIdempotentAndAllowsReattachment() {
        val activity = activity()
        detach(activity)
        val old = controlled(activity, "old")
        val engine = FlutterEngine(activity)
        assertEquals(CanonicalRuntimeLeaseBroker.State.RELEASED, ProcessCanonicalRuntimeLease.broker.snapshot().state)

        activity.cleanUpFlutterEngine(engine)

        assertEquals(1, StickerCutoutRegistrationFlutterActivityShadow.superCleanups)
        assertEquals(true, field(activity, "canonicalRuntimeCleanupFinished"))
        assertNull(old.messenger.handler)
        assertNull(owner(activity))
        assertBefore("old.cutout.remove", "embedding.shouldDestroy")
        activity.cleanUpFlutterEngine(engine)
        assertEquals(1, channelEvents().count { it == "old.cutout.remove" })

        val next = messenger("next")
        attach(activity, next)
        assertNull(next.call("cancel", mapOf("jobId" to "idle")).success())
        detach(activity)
        assertNull(next.handler)
    }

    private fun activity(): MainActivity = Robolectric.buildActivity(MainActivity::class.java).get().also { activities.add(it) }

    private fun messenger(name: String): RecordingMessenger = RecordingMessenger(name, events).also { messengers.add(it) }

    private fun controlled(activity: MainActivity, name: String): ControlledBridge = ControlledBridge(activity, messenger(name)).also {
        controlledBridges.add(it)
        setField(activity, "stickerCutoutBridge", it.bridge)
    }

    private fun attach(activity: MainActivity, messenger: BinaryMessenger) {
        MainActivity::class.java.getDeclaredMethod("setupStickerCutoutBridge", BinaryMessenger::class.java)
            .apply { isAccessible = true }.invoke(activity, messenger)
    }

    private fun detach(activity: MainActivity) {
        MainActivity::class.java.getDeclaredMethod("closeStickerCutoutBridge")
            .apply { isAccessible = true }.invoke(activity)
    }

    private fun owner(activity: MainActivity): StickerCutoutBridge? = field(activity, "stickerCutoutBridge") as StickerCutoutBridge?

    private fun field(activity: MainActivity, name: String): Any? = MainActivity::class.java.getDeclaredField(name)
        .apply { isAccessible = true }.get(activity)

    private fun setField(activity: MainActivity, name: String, value: Any?) {
        MainActivity::class.java.getDeclaredField(name).apply { isAccessible = true }.set(activity, value)
    }

    private fun channelEvents(): List<String> = events.filter { it.endsWith(".cutout.attach") || it.endsWith(".cutout.remove") }

    private fun assertBefore(first: String, second: String) {
        assertTrue("missing event $first in $events", events.contains(first))
        assertTrue("missing event $second in $events", events.contains(second))
        assertTrue("$first must precede $second: $events", events.indexOf(first) < events.indexOf(second))
    }

    private fun releaseLeaseAndReplyToShutdown() {
        ownedLease?.let { token ->
            val broker = ProcessCanonicalRuntimeLease.broker
            assertTrue(broker.beginDrain(token))
            assertTrue(broker.release(token, databaseClosed = true))
            ownedLease = null
        }
        messengers.forEach { it.replyToShutdown() }
        shadowOf(Looper.getMainLooper()).idle()
    }

    private fun png(): File {
        val bitmap = Bitmap.createBitmap(2, 2, Bitmap.Config.ARGB_8888).apply { eraseColor(0xff427a69.toInt()) }
        try {
            return File(temporary.root.canonicalFile, "caller.png").also { file ->
                file.outputStream().use { assertTrue(bitmap.compress(Bitmap.CompressFormat.PNG, 100, it)) }
            }
        } finally {
            bitmap.recycle()
        }
    }

    private inner class ControlledBridge(activity: MainActivity, val messenger: RecordingMessenger) {
        val client = PendingClient(messenger.name, events)
        val worker = QueuedExecutor()
        val bridge = StickerCutoutBridge(messenger, activity.cacheDir, clientFactory = { client }, worker = worker)

        fun flush() {
            repeat(8) {
                worker.drain()
                shadowOf(Looper.getMainLooper()).idle()
            }
            assertEquals(0, worker.size)
        }
    }

    private class PendingClient(private val name: String, private val events: MutableList<String>) : StickerCutoutClient {
        var availabilityTask: Task<Boolean> = Tasks.forResult(true)
        val inference = TaskCompletionSource<Bitmap?>()
        var probes = 0
        var inferences = 0
        var closes = 0

        override fun areModulesAvailable(): Task<Boolean> {
            probes += 1
            return availabilityTask
        }
        override fun deferredInstall(): Task<Void> = Tasks.forResult<Void>(null)
        override fun process(uprightBitmap: Bitmap): Task<Bitmap?> {
            inferences += 1
            return inference.task
        }
        override fun close() {
            closes += 1
            events.add("$name.client.close")
        }
    }

    private class QueuedExecutor : Executor {
        private val queue = ArrayDeque<Runnable>()
        val size: Int get() = queue.size
        override fun execute(command: Runnable) { queue.addLast(command) }
        fun drain() {
            var count = 0
            while (queue.isNotEmpty()) {
                check(count++ < 64) { "fixture worker failed to settle" }
                queue.removeFirst().run()
            }
        }
    }

    private class RecordingMessenger(val name: String, private val events: MutableList<String>) : BinaryMessenger {
        var handler: BinaryMessenger.BinaryMessageHandler? = null
            private set
        private val shutdownReplies = mutableListOf<BinaryMessenger.BinaryReply>()
        val pendingShutdownReplies: Int get() = shutdownReplies.size

        override fun send(channel: String, message: ByteBuffer?) = Unit
        override fun send(channel: String, message: ByteBuffer?, callback: BinaryMessenger.BinaryReply?) {
            assertEquals(SHUTDOWN_CHANNEL, channel)
            requireNotNull(message).rewind()
            val method = StandardMethodCodec.INSTANCE.decodeMethodCall(message)
            assertEquals("shutdown", method.method)
            assertNull(method.arguments)
            shutdownReplies.add(requireNotNull(callback))
            events.add("$name.shutdown.send")
        }
        override fun setMessageHandler(channel: String, handler: BinaryMessenger.BinaryMessageHandler?) {
            if (channel == AndroidCallWakeBridge.CHANNEL_NAME) {
                events.add("$name.callWake.${if (handler == null) "remove" else "attach"}")
                return
            }
            assertEquals(CUTOUT_CHANNEL, channel)
            this.handler = handler
            events.add("$name.cutout.${if (handler == null) "remove" else "attach"}")
        }
        fun call(method: String, args: Any? = null): Reply {
            assertNotNull("MainActivity must register the cutout channel", handler)
            val request = StandardMethodCodec.INSTANCE.encodeMethodCall(MethodCall(method, args))
            request.rewind()
            val result = Reply()
            handler!!.onMessage(request) { response ->
                events.add("$name.$method.reply")
                result.accept(response)
            }
            return result
        }
        fun replyToShutdown() {
            val pending = shutdownReplies.toList()
            shutdownReplies.clear()
            pending.forEach { reply ->
                val response = StandardMethodCodec.INSTANCE.encodeSuccessEnvelope(mapOf(
                    "released" to true, "databaseClosed" to true, "leaseState" to "released",
                ))
                response.rewind()
                reply.reply(response)
            }
        }
    }

    private class Reply {
        private val values = mutableListOf<Any?>()
        val count: Int get() = values.size
        fun accept(response: ByteBuffer?) {
            assertNotNull("native method must be implemented", response)
            response!!.rewind()
            values.add(StandardMethodCodec.INSTANCE.decodeEnvelope(response))
        }
        fun success(): Any? {
            assertEquals("pending native request must settle once", 1, count)
            return values.single()
        }
    }

    private companion object {
        const val CUTOUT_CHANNEL = "mknoon/custom_sticker_cutout"
        const val SHUTDOWN_CHANNEL = "mknoon/canonical_runtime_shutdown"
    }
}

/** Same superclass-only boundary pattern as MknoonCallAnswerActivityTest. */
@Implements(FlutterActivity::class, isInAndroidSdk = false)
class StickerCutoutRegistrationFlutterActivityShadow : ShadowActivity() {
    @Implementation
    protected fun shouldDestroyEngineWithHost(): Boolean {
        events?.add("embedding.shouldDestroy")
        return false
    }
    @Implementation
    protected fun cleanUpFlutterEngine(engine: FlutterEngine) {
        superCleanups += 1
        events?.add("embedding.cleanup")
    }
    companion object {
        var events: MutableList<String>? = null
        var superCleanups = 0
    }
}

/** Cleanup only needs stable engine identity; no engine getters are shadowed. */
@Implements(FlutterEngine::class, isInAndroidSdk = false)
class StickerCutoutRegistrationFlutterEngineShadow {
    // Flutter 3.47.2 delegates Context construction to this terminal overload
    // before Robolectric can intercept the outer constructor's body.
    @Implementation
    protected fun __constructor__(
        context: Context,
        flutterLoader: FlutterLoader?,
        flutterJNI: FlutterJNI?,
        platformViewsController: PlatformViewsController,
        dartVmArgs: Array<String>?,
        automaticallyRegisterPlugins: Boolean,
        waitForRestorationData: Boolean,
        group: FlutterEngineGroup?,
    ) = Unit
}
