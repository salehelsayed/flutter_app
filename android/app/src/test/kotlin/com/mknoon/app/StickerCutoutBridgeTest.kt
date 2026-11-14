package com.mknoon.app

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.media.ExifInterface
import android.os.Looper
import com.google.android.gms.tasks.Task
import com.google.android.gms.tasks.TaskCompletionSource
import com.google.android.gms.tasks.Tasks
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.FlutterException
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.StandardMethodCodec
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.DataInputStream
import java.io.File
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.file.Files
import java.util.ArrayDeque
import java.util.concurrent.Executor
import java.util.zip.CRC32
import java.util.zip.Inflater
import kotlin.math.abs
import org.junit.After
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode
import org.robolectric.annotation.LooperMode

/** Real channel, codec, files and image encoding; only the remote model tasks are fake. */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [33], shadows = [StickerCutoutHostPosixShadow::class, StickerCutoutHostOsConstantsShadow::class, StickerCutoutHostBlockGuardOsShadow::class])
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@LooperMode(LooperMode.Mode.PAUSED)
class StickerCutoutBridgeTest {
    @get:Rule
    val temporary = TemporaryFolder()

    private val harnesses = mutableListOf<Harness>()
    private val bitmaps = mutableListOf<Bitmap>()

    @After
    fun releaseOwnedResources() {
        harnesses.asReversed().forEach { it.bridge.close() }
        shadowOf(Looper.getMainLooper()).idle()
        bitmaps.forEach { if (!it.isRecycled) it.recycle() }
    }

    @Test
    fun constructionDoesNotLoadProvider() {
        val h = harness()
        h.flush()
        assertEquals(0, h.factoryCalls)
        assertNull(h.call("cancel", mapOf("jobId" to "unknown")).success())
        h.bridge.close()
        h.flush()
        assertEquals(0, h.factoryCalls)
        assertEquals(0, h.client.probes)
        assertEquals(0, h.client.installs)
        assertTrue(h.client.requests.isEmpty())
        assertNull(h.messenger.handler)
    }

    @Test
    fun pre24DoesNotLoadProvider() {
        // The injectable API level exercises the guard without requiring an
        // unavailable device or lowering the application's actual minSdk.
        val h = harness(sdkInt = 23)
        val reply = h.call("availability")
        h.flush()
        assertEquals("unsupported", reply.success())
        assertEquals(0, h.factoryCalls)
        assertEquals(0, h.client.probes)
    }

    @Test
    fun absentProviderIsUnsupported() {
        val h = harness(providerAvailable = false)
        val reply = h.call("availability")
        h.flush()
        assertEquals("unsupported", reply.success())
        assertEquals("availability must actually query the lazy provider", 1, h.factoryCalls)
        assertEquals(0, h.client.installs)
        assertTrue(h.client.requests.isEmpty())
    }

    @Test
    fun availabilityWaitsForInstalledModule() {
        val h = harness()
        val module = TaskCompletionSource<Boolean>()
        h.client.moduleReplies.add(module.task)
        val reply = h.call("availability")
        h.flush()
        assertEquals(1, h.factoryCalls)
        assertEquals(1, h.client.probes)
        assertEquals("an unresolved probe cannot claim readiness", 0, reply.count)

        module.setResult(true)
        h.flush()
        assertEquals("ready", reply.success())
        assertEquals(0, h.client.installs)
        assertTrue(h.client.requests.isEmpty())
    }

    @Test
    fun missingModelSchedulesDeferredInstallWithoutReportingReady() {
        val h = harness()
        h.client.moduleReplies.add(Tasks.forResult(false))
        val reply = h.call("availability")
        h.flush()
        assertEquals("needsModel", reply.success())
        assertEquals(1, h.client.probes)
        assertEquals(1, h.client.installs)
        assertFalse("the download acknowledgement is deliberately still pending", h.client.install.task.isComplete)
        assertTrue(h.client.requests.isEmpty())

        h.client.install.setResult(null)
        h.flush()
        assertEquals("acknowledging deferred installation is not model readiness", "needsModel", reply.success())
        h.client.moduleReplies.add(Tasks.forResult(false))
        val stillMissing = h.call("availability")
        h.flush()
        assertEquals("needsModel", stillMissing.success())
        assertEquals(2, h.client.probes)
        assertTrue(h.client.requests.isEmpty())
    }

    @Test
    fun failedModuleProbeIsUnsupported() {
        val h = harness()
        val module = TaskCompletionSource<Boolean>()
        h.client.moduleReplies.add(module.task)
        val reply = h.call("availability")
        h.flush()
        assertEquals(0, reply.count)
        module.setException(IllegalStateException("provider unavailable"))
        h.flush()
        assertEquals("unsupported", reply.success())
        assertEquals(0, h.client.installs)
        assertTrue(h.client.requests.isEmpty())
    }

    @Test
    fun laterAvailabilityChecksObserveInstalledModule() {
        val h = harness()
        h.client.moduleReplies.add(Tasks.forResult(false))
        val missing = h.call("availability")
        h.flush()
        assertEquals("needsModel", missing.success())

        h.client.moduleReplies.add(Tasks.forResult(true))
        val installed = h.call("availability")
        h.flush()
        assertEquals("ready", installed.success())
        assertEquals(2, h.client.probes)
        assertTrue(h.client.requests.isEmpty())
    }

    @Test
    fun extractCannotRunWhileModelIsMissing() {
        val h = harness()
        val source = png(h.root, "caller.png", 5, 4)
        h.client.moduleReplies.add(Tasks.forResult(false))
        val job = h.job(source, "missing-model")
        val reply = h.call("extract", job.arguments)
        h.flush()
        assertEquals("unavailable", reply.error().code)
        assertEquals(1, h.client.probes)
        assertTrue(h.client.installs >= 1)
        assertTrue(h.client.requests.isEmpty())
        assertFalse(job.output.exists())

        h.client.moduleReplies.add(Tasks.forResult(true))
        val next = h.begin(h.job(source, "model-installed"))
        h.complete(next, foreground(5, 4))
        assertDescriptor(next.reply.success(), 5, 4, 0.2, 0.25, 0.8, 0.75)
    }

    @Test
    fun encodesCanonicalFullCanvasPngAndTightBounds() {
        val h = harness()
        val source = png(h.root, "caller.png", 5, 4)
        val original = source.readBytes()
        val canary = File(h.root, "unrelated.png").apply { writeText("caller-owned canary") }
        val job = h.job(source, "canonical")
        val foreground = foreground(5, 4)
        val running = h.begin(job, mapOf("posterPath" to canary.path, "imagePath" to canary.path))
        h.complete(running, foreground)

        assertDescriptor(running.reply.success(), 5, 4, 0.2, 0.25, 0.8, 0.75)
        val decoded = assertCanonicalPng(job.output, 5, 4)
        assertEquals("even alpha one contributes to the tight bounds", 1, decoded.getRGB(1, 1) ushr 24)
        assertEquals(128, decoded.getRGB(2, 1) ushr 24)
        assertEquals(0xff0000ff.toInt(), decoded.getRGB(3, 2))
        assertArrayEquals(original, source.readBytes())
        assertEquals("caller-owned canary", canary.readText())
        assertEquals(listOf("result.png"), job.output.parentFile!!.list()!!.sorted())
    }

    @Test
    fun resolvesEveryExifOrientationBeforeInference() {
        val h = harness()
        for (orientation in 1..8) {
            val source = jpegWithOrientation(h.root, orientation)
            val original = source.readBytes()
            assertEquals(orientation, ExifInterface(source.path).getAttributeInt(ExifInterface.TAG_ORIENTATION, 0))
            val raw = owned(requireNotNull(BitmapFactory.decodeFile(source.path)))
            val running = h.begin(h.job(source, "exif-$orientation"))
            val upright = running.request.input
            val swapsAxes = orientation >= 5
            assertEquals(if (swapsAxes) raw.height else raw.width, upright.width)
            assertEquals(if (swapsAxes) raw.width else raw.height, upright.height)
            for ((x, y) in listOf(0 to 0, raw.width - 1 to 0, 0 to raw.height - 1, raw.width - 1 to raw.height - 1, 4 to 7)) {
                val (targetX, targetY) = when (orientation) {
                    1 -> x to y
                    2 -> raw.width - 1 - x to y
                    3 -> raw.width - 1 - x to raw.height - 1 - y
                    4 -> x to raw.height - 1 - y
                    5 -> y to x
                    6 -> raw.height - 1 - y to x
                    7 -> raw.height - 1 - y to raw.width - 1 - x
                    else -> y to raw.width - 1 - x
                }
                assertEquals("EXIF $orientation at source ($x,$y)", raw.getPixel(x, y), upright.getPixel(targetX, targetY))
            }
            h.complete(running, null)
            assertNull(running.reply.success())
            assertArrayEquals(original, source.readBytes())
        }
    }

    @Test
    fun limitsUprightInputTo2048OnEachAxis() {
        val h = harness()
        for ((width, height) in listOf(4096 to 1024, 1024 to 4096)) {
            val source = png(h.root, "large-$width.png", width, height)
            val original = source.readBytes()
            val running = h.begin(h.job(source, "large-$width"))
            val input = running.request.input
            assertTrue(input.width in 1..2048)
            assertTrue(input.height in 1..2048)
            assertEquals(width.toDouble() / height, input.width.toDouble() / input.height, 0.002)
            h.complete(running, null)
            assertNull(running.reply.success())
            assertFalse(running.job.output.exists())
            assertArrayEquals(original, source.readBytes())
        }
    }

    @Test
    fun absentOrTransparentForegroundReturnsNull() {
        val h = harness()
        val source = png(h.root, "caller.png", 5, 4)
        val original = source.readBytes()
        for (hasTransparentBitmap in listOf(false, true)) {
            val running = h.begin(h.job(source, "empty-$hasTransparentBitmap"))
            h.complete(running, if (hasTransparentBitmap) transparent(5, 4) else null)
            assertNull(running.reply.success())
            assertFalse(running.job.output.exists())
            assertArrayEquals(original, source.readBytes())
        }
    }

    @Test
    fun rejectsMalformedSourceAndRemainsUsable() {
        val h = harness()
        val malformed = File(h.root, "not-an-image.png").apply { writeText("not an image") }
        val bad = h.job(malformed, "malformed")
        val reply = h.call("extract", bad.arguments)
        h.flush()
        assertTrue(reply.error().code in setOf("invalidSource", "invalid_source"))
        assertTrue(h.client.requests.isEmpty())
        assertFalse(bad.output.exists())
        assertEquals("not an image", malformed.readText())

        val good = h.begin(h.job(png(h.root, "valid.png", 5, 4), "after-malformed"))
        h.complete(good, foreground(5, 4))
        assertDescriptor(good.reply.success(), 5, 4, 0.2, 0.25, 0.8, 0.75)
    }

    @Test
    fun refusesUnownedExistingAndSymlinkOutputs() {
        val h = harness()
        val source = png(h.root, "caller.png", 5, 4)
        val original = source.readBytes()
        val outside = File(h.root, "outside").apply { mkdirs() }
        val canary = File(outside, "caller-owned.png").apply { writeText("preserve me") }
        val existing = h.job(source, "existing").also { it.output.writeText("existing private file") }
        val wrongName = h.job(source, "wrong-name").let { it.copy(output = File(it.output.parentFile, "other.png")) }
        val wrongId = h.job(source, "wrong-id").let { it.copy(id = "mknoon-sticker-cutout-other") }
        val outputLink = h.job(source, "output-link")
        Files.createSymbolicLink(outputLink.output.toPath(), canary.toPath())
        val parentLink = File(h.cache, "mknoon-sticker-cutout-parent-link")
        Files.createSymbolicLink(parentLink.toPath(), outside.toPath())
        val outsideJob = Job("mknoon-sticker-cutout-outside", source, File(outside, "result.png"))
        val parentLinkJob = Job(parentLink.name, source, File(parentLink, "result.png"))

        for (job in listOf(outsideJob, wrongName, wrongId, existing, outputLink, parentLinkJob)) {
            val reply = h.call("extract", job.arguments)
            h.flush()
            reply.error()
            assertTrue("unsafe output must not reach inference", h.client.requests.isEmpty())
            assertArrayEquals(original, source.readBytes())
            assertEquals("preserve me", canary.readText())
            assertEquals("existing private file", existing.output.readText())
            assertFalse(File(outside, "result.png").exists())
            assertFalse(wrongName.output.exists())
            assertFalse(wrongId.output.exists())
            assertTrue(Files.isSymbolicLink(outputLink.output.toPath()))
            assertTrue(Files.isSymbolicLink(parentLink.toPath()))
        }

        // A blanket "unavailable" response is insufficient: rejection must
        // leave the same bridge able to perform a valid private job.
        val good = h.begin(h.job(source, "after-rejections"))
        h.complete(good, foreground(5, 4))
        assertDescriptor(good.reply.success(), 5, 4, 0.2, 0.25, 0.8, 0.75)
    }

    @Test
    fun overlappingExtractDoesNotDisplaceActiveJob() {
        val h = harness()
        val source = png(h.root, "caller.png", 5, 4)
        val firstJob = h.job(source, "first")
        val firstReply = h.call("extract", firstJob.arguments)
        val second = h.job(source, "second")
        // Both calls arrive before the queued decode has had a chance to run.
        val blocked = h.call("extract", second.arguments)
        h.flush()
        assertEquals("unavailable", blocked.error().code)
        assertEquals(1, h.client.requests.size)
        assertEquals(0, firstReply.count)
        val first = Running(firstJob, firstReply, h.client.requests.single())
        assertFalse(second.output.exists())

        assertNull(h.call("cancel", mapOf("jobId" to "not-the-active-job")).success())
        h.flush()
        assertEquals(0, first.reply.count)
        h.complete(first, foreground(5, 4))
        assertDescriptor(first.reply.success(), 5, 4, 0.2, 0.25, 0.8, 0.75)
        val next = h.begin(second)
        h.complete(next, null)
        assertNull(next.reply.success())
    }

    @Test
    fun cancellationSettlesOnceAndLateSuccessCannotTouchSuccessor() {
        val h = harness()
        val source = png(h.root, "caller.png", 5, 4)
        val original = source.readBytes()
        val old = h.begin(h.job(source, "cancelled"))
        assertNull(h.call("cancel", mapOf("jobId" to old.job.id)).success())
        h.flush()
        assertNull(old.reply.success())
        assertFalse(old.job.output.exists())
        // Dart may remove its job directory immediately after native cancel.
        old.job.output.parentFile!!.deleteRecursively()

        val next = h.begin(h.job(source, "successor"))
        h.complete(old, foreground(5, 4))
        assertEquals(1, old.reply.count)
        assertFalse(old.job.output.parentFile!!.exists())
        assertEquals(0, next.reply.count)
        assertFalse(next.job.output.exists())
        val third = h.call("extract", h.job(source, "still-busy").arguments)
        h.flush()
        assertEquals("unavailable", third.error().code)
        assertEquals(2, h.client.requests.size)

        h.complete(next, foreground(5, 4))
        assertDescriptor(next.reply.success(), 5, 4, 0.2, 0.25, 0.8, 0.75)
        assertCanonicalPng(next.job.output, 5, 4)
        assertArrayEquals(original, source.readBytes())
    }

    @Test
    fun detachSettlesOnceAndLateSuccessCannotTouchNewBridge() {
        val h = harness()
        val source = png(h.root, "caller.png", 5, 4)
        val old = h.begin(h.job(source, "detached"))
        h.bridge.close()
        h.flush()
        assertNull(h.messenger.handler)
        assertNull(old.reply.success())
        assertTrue("the lazy client must release its native resources", h.client.closes >= 1)
        old.job.output.parentFile!!.deleteRecursively()

        val next = harness(messenger = h.messenger, cache = h.cache)
        val current = next.begin(next.job(source, "new-engine"))
        h.complete(old, foreground(5, 4))
        next.flush()
        assertEquals(1, old.reply.count)
        assertFalse(old.job.output.parentFile!!.exists())
        assertNotNull(next.messenger.handler)
        assertEquals(0, current.reply.count)
        assertNull(next.call("cancel", mapOf("jobId" to "unrelated")).success())
        next.complete(current, foreground(5, 4))
        assertDescriptor(current.reply.success(), 5, 4, 0.2, 0.25, 0.8, 0.75)
        assertCanonicalPng(current.job.output, 5, 4)
    }

    @Test
    fun cancellationAndDetachPreservePublishedOutput() {
        val h = harness()
        val source = png(h.root, "caller.png", 5, 4)
        val running = h.begin(h.job(source, "published"))
        h.complete(running, foreground(5, 4))
        assertDescriptor(running.reply.success(), 5, 4, 0.2, 0.25, 0.8, 0.75)
        assertCanonicalPng(running.job.output, 5, 4)
        val published = running.job.output.readBytes()

        assertNull(h.call("cancel", mapOf("jobId" to running.job.id)).success())
        h.flush()
        h.bridge.close()
        h.flush()
        assertArrayEquals(published, running.job.output.readBytes())
        assertEquals(1, running.reply.count)
    }

    @Test
    fun failedInferenceIsPrivateAndDoesNotPoisonSuccessor() {
        val h = harness()
        val source = png(h.root, "caller.png", 5, 4)
        val running = h.begin(h.job(source, "failure"))
        running.request.result.setException(IllegalStateException("private provider detail ${source.path}"))
        h.flush()
        val error = running.reply.error()
        assertFalse(error.message.orEmpty().contains(source.path))
        assertFalse(error.details?.toString().orEmpty().contains(source.path))
        assertFalse(running.job.output.exists())

        val next = h.begin(h.job(source, "after-failure"))
        h.complete(next, foreground(5, 4))
        assertDescriptor(next.reply.success(), 5, 4, 0.2, 0.25, 0.8, 0.75)
    }

    @Test
    fun rejectsForegroundSizeMismatchWithoutPublishing() {
        val h = harness()
        val source = png(h.root, "caller.png", 5, 4)
        val running = h.begin(h.job(source, "wrong-size"))
        h.complete(running, foreground(6, 4))
        running.reply.error()
        assertFalse(running.job.output.exists())

        val next = h.begin(h.job(source, "after-wrong-size"))
        h.complete(next, foreground(5, 4))
        assertDescriptor(next.reply.success(), 5, 4, 0.2, 0.25, 0.8, 0.75)
    }

    @Test
    fun replacedOutputDirectoryCannotRedirectPublication() {
        val h = harness()
        val source = png(h.root, "caller.png", 5, 4)
        val running = h.begin(h.job(source, "replaced-directory"))
        val outside = File(h.root, "outside-replacement").apply { mkdirs() }
        val canary = File(outside, "result.png").apply { writeText("outside caller-owned file") }
        val directory = running.job.output.parentFile!!
        assertTrue(directory.delete())
        Files.createSymbolicLink(directory.toPath(), outside.toPath())

        h.complete(running, foreground(5, 4))
        running.reply.error()
        assertEquals("outside caller-owned file", canary.readText())
        assertTrue(Files.isSymbolicLink(directory.toPath()))

        val next = h.begin(h.job(source, "after-replacement"))
        h.complete(next, foreground(5, 4))
        assertDescriptor(next.reply.success(), 5, 4, 0.2, 0.25, 0.8, 0.75)
    }

    private fun harness(
        sdkInt: Int = 33,
        providerAvailable: Boolean = true,
        messenger: RecordingMessenger = RecordingMessenger(),
        cache: File? = null,
    ): Harness = Harness(sdkInt, providerAvailable, messenger, cache).also { harnesses.add(it) }

    private inner class Harness(
        sdkInt: Int,
        providerAvailable: Boolean,
        val messenger: RecordingMessenger,
        existingCache: File?,
    ) {
        val root: File = temporary.newFolder().canonicalFile
        val cache: File = existingCache ?: File(root, "cache").apply { mkdirs() }.canonicalFile
        val client = FakeClient()
        val worker = QueuedExecutor()
        var factoryCalls = 0
        val bridge = StickerCutoutBridge(
            messenger = messenger,
            cacheDirectory = cache,
            clientFactory = {
                factoryCalls += 1
                if (providerAvailable) client else null
            },
            sdkInt = sdkInt,
            worker = worker,
        )

        fun job(source: File, suffix: String): Job {
            val directory = File(cache, "mknoon-sticker-cutout-$suffix")
            assertTrue(directory.mkdir())
            return Job(directory.name, source, File(directory, "result.png"))
        }

        fun call(method: String, arguments: Any? = null): Reply = messenger.call(method, arguments)

        fun flush() {
            // Both queues are explicitly controlled. There are no wall-clock
            // waits, retry sleeps or model downloads in these host tests.
            repeat(12) {
                worker.runQueued()
                shadowOf(Looper.getMainLooper()).idle()
            }
            assertEquals("the bounded host queues must settle", 0, worker.size)
        }

        fun begin(job: Job, extra: Map<String, Any> = emptyMap()): Running {
            val before = client.requests.size
            val reply = call("extract", job.arguments + extra)
            flush()
            assertEquals("a valid job must reach the actual asynchronous client seam", before + 1, client.requests.size)
            assertEquals("extract must remain pending while ML inference is pending", 0, reply.count)
            assertFalse(job.output.exists())
            return Running(job, reply, client.requests.last())
        }

        fun complete(running: Running, foreground: Bitmap?) {
            running.request.result.setResult(foreground)
            flush()
        }
    }

    private inner class FakeClient : StickerCutoutClient {
        val moduleReplies = ArrayDeque<Task<Boolean>>()
        val install = TaskCompletionSource<Void>()
        val requests = mutableListOf<Inference>()
        var probes = 0
        var installs = 0
        var closes = 0

        override fun areModulesAvailable(): Task<Boolean> {
            probes += 1
            return if (moduleReplies.isEmpty()) Tasks.forResult(true) else moduleReplies.removeFirst()
        }

        override fun deferredInstall(): Task<Void> {
            installs += 1
            return install.task
        }

        override fun process(uprightBitmap: Bitmap): Task<Bitmap?> {
            val snapshot = owned(requireNotNull(uprightBitmap.copy(Bitmap.Config.ARGB_8888, false)))
            val inference = Inference(snapshot, TaskCompletionSource<Bitmap?>())
            requests.add(inference)
            return inference.result.task
        }

        override fun close() {
            closes += 1
        }
    }

    private data class Job(val id: String, val source: File, val output: File) {
        val arguments: Map<String, Any>
            get() = mapOf("jobId" to id, "sourceImagePath" to source.path, "outputPath" to output.path)
    }

    private data class Inference(val input: Bitmap, val result: TaskCompletionSource<Bitmap?>)
    private data class Running(val job: Job, val reply: Reply, val request: Inference)

    private class QueuedExecutor : Executor {
        private val queue = ArrayDeque<Runnable>()
        val size: Int get() = queue.size

        override fun execute(command: Runnable) {
            queue.addLast(command)
        }

        fun runQueued() {
            var count = 0
            while (queue.isNotEmpty()) {
                check(count++ < 64) { "worker did not settle within the causal queue bound" }
                queue.removeFirst().run()
            }
        }
    }

    private class RecordingMessenger : BinaryMessenger {
        var handler: BinaryMessenger.BinaryMessageHandler? = null
            private set

        override fun send(channel: String, message: ByteBuffer?) = Unit

        override fun send(channel: String, message: ByteBuffer?, callback: BinaryMessenger.BinaryReply?) = Unit

        override fun setMessageHandler(channel: String, handler: BinaryMessenger.BinaryMessageHandler?) {
            assertEquals("mknoon/custom_sticker_cutout", channel)
            this.handler = handler
        }

        fun call(method: String, arguments: Any?): Reply {
            val active = requireNotNull(handler) { "native channel must be registered" }
            val request = StandardMethodCodec.INSTANCE.encodeMethodCall(MethodCall(method, arguments))
            request.rewind()
            val reply = Reply()
            active.onMessage(request) { response -> reply.accept(response) }
            return reply
        }
    }

    private class Reply {
        private data class Outcome(val value: Any?, val error: FlutterException?, val notImplemented: Boolean)
        private val outcomes = mutableListOf<Outcome>()
        val count: Int get() = outcomes.size

        fun accept(response: ByteBuffer?) {
            if (response == null) {
                outcomes.add(Outcome(null, null, true))
                return
            }
            response.rewind()
            try {
                outcomes.add(Outcome(StandardMethodCodec.INSTANCE.decodeEnvelope(response), null, false))
            } catch (error: FlutterException) {
                outcomes.add(Outcome(null, error, false))
            }
        }

        fun success(): Any? {
            assertEquals("each native call must settle exactly once", 1, count)
            val outcome = outcomes.single()
            assertFalse(outcome.notImplemented)
            assertNull("expected a successful native result", outcome.error)
            return outcome.value
        }

        fun error(): FlutterException {
            assertEquals("each native call must settle exactly once", 1, count)
            val outcome = outcomes.single()
            assertFalse(outcome.notImplemented)
            assertNotNull("expected a typed native error", outcome.error)
            return requireNotNull(outcome.error)
        }
    }

    private fun owned(bitmap: Bitmap): Bitmap = bitmap.also { bitmaps.add(it) }

    private fun png(directory: File, name: String, width: Int, height: Int): File {
        val bitmap = owned(Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888))
        bitmap.eraseColor(0xff526f83.toInt())
        bitmap.setPixel(0, 0, 0xffff0000.toInt())
        val output = File(directory, name)
        output.outputStream().use { assertTrue(bitmap.compress(Bitmap.CompressFormat.PNG, 100, it)) }
        return output
    }

    private fun transparent(width: Int, height: Int): Bitmap {
        val bitmap = owned(Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888))
        bitmap.setPremultiplied(false)
        bitmap.setPixels(IntArray(width * height) { 0x00123456 }, 0, width, 0, 0, width, height)
        assertEquals("fixture retains invisible RGB before native canonicalization", 0x00123456, bitmap.getPixel(0, 0))
        return bitmap
    }

    private fun foreground(width: Int, height: Int): Bitmap = transparent(width, height).apply {
        setPixel(1, 1, 0x01ff0000)
        setPixel(2, 1, 0x8000ff00.toInt())
        setPixel(3, 2, 0xff0000ff.toInt())
    }

    private fun jpegWithOrientation(directory: File, orientation: Int): File {
        val bitmap = owned(Bitmap.createBitmap(16, 12, Bitmap.Config.ARGB_8888))
        for (y in 0 until bitmap.height) {
            for (x in 0 until bitmap.width) {
                bitmap.setPixel(x, y, 0xff000000.toInt() or ((x * 15) shl 16) or ((y * 19) shl 8) or ((x * 7 + y * 3) and 255))
            }
        }
        val jpeg = ByteArrayOutputStream().also {
            assertTrue(bitmap.compress(Bitmap.CompressFormat.JPEG, 100, it))
        }.toByteArray()
        assertEquals(0xff, jpeg[0].toInt() and 255)
        assertEquals(0xd8, jpeg[1].toInt() and 255)
        val tiff = ByteBuffer.allocate(26).order(ByteOrder.LITTLE_ENDIAN)
            .put('I'.code.toByte()).put('I'.code.toByte()).putShort(42.toShort()).putInt(8)
            .putShort(1.toShort()).putShort(0x0112.toShort()).putShort(3.toShort()).putInt(1)
            .putShort(orientation.toShort()).putShort(0.toShort()).putInt(0).array()
        val payload = byteArrayOf(69, 120, 105, 102, 0, 0) + tiff
        val segmentLength = payload.size + 2
        val annotated = ByteArrayOutputStream().apply {
            write(jpeg, 0, 2)
            write(0xff)
            write(0xe1)
            write(segmentLength ushr 8)
            write(segmentLength and 255)
            write(payload)
            write(jpeg, 2, jpeg.size - 2)
        }.toByteArray()
        return File(directory, "orientation-$orientation.jpg").apply { writeBytes(annotated) }
    }

    private fun assertDescriptor(value: Any?, width: Int, height: Int, left: Double, top: Double, right: Double, bottom: Double) {
        assertTrue(value is Map<*, *>)
        val descriptor = value as Map<*, *>
        assertEquals(setOf("width", "height", "subjectBounds"), descriptor.keys)
        assertEquals(width, (descriptor["width"] as Number).toInt())
        assertEquals(height, (descriptor["height"] as Number).toInt())
        val bounds = descriptor["subjectBounds"] as Map<*, *>
        assertEquals(setOf("left", "top", "right", "bottom"), bounds.keys)
        for ((key, expected) in mapOf("left" to left, "top" to top, "right" to right, "bottom" to bottom)) {
            assertEquals(expected, (bounds[key] as Number).toDouble(), 1e-9)
        }
    }

    private fun assertCanonicalPng(file: File, width: Int, height: Int): StraightRgba {
        assertTrue(file.isFile)
        assertFalse(Files.isSymbolicLink(file.toPath()))
        assertTrue(file.length() in 45L..(24L * 1024 * 1024))
        assertTrue(width in 1..2048 && height in 1..2048)
        val bytes = file.readBytes()
        assertTrue(bytes.size >= 45)
        val input = DataInputStream(ByteArrayInputStream(bytes))
        val signature = ByteArray(8).also { input.readFully(it) }
        assertArrayEquals(byteArrayOf(137.toByte(), 80, 78, 71, 13, 10, 26, 10), signature)
        val kinds = mutableListOf<String>()
        val compressed = ByteArrayOutputStream()
        var ended = false
        while (input.available() > 0) {
            assertFalse("PNG cannot have trailing bytes after IEND", ended)
            assertTrue(input.available() >= 12)
            val length = input.readInt()
            assertTrue(length >= 0 && length <= input.available() - 8)
            val type = ByteArray(4).also { input.readFully(it) }
            val kind = type.toString(Charsets.US_ASCII)
            assertTrue("unexpected PNG chunk $kind", kind in setOf("IHDR", "IDAT", "IEND"))
            val data = ByteArray(length).also { input.readFully(it) }
            val expectedCrc = input.readInt().toLong() and 0xffffffffL
            val crc = CRC32().apply { update(type); update(data) }
            assertEquals("CRC of $kind", expectedCrc, crc.value)
            kinds.add(kind)
            if (kind == "IHDR") {
                assertEquals(1, kinds.size)
                assertEquals(13, length)
                val header = ByteBuffer.wrap(data).order(ByteOrder.BIG_ENDIAN)
                assertEquals(width, header.int)
                assertEquals(height, header.int)
                // This native encoder emits explicit RGBA8 even when every
                // foreground pixel is opaque. Dart also accepts this form.
                assertEquals("eight-bit samples", 8, data[8].toInt() and 255)
                assertEquals("explicit RGBA alpha channel", 6, data[9].toInt() and 255)
                assertEquals("PNG zlib compression", 0, data[10].toInt() and 255)
                assertEquals("PNG filter method", 0, data[11].toInt() and 255)
                assertEquals("noninterlaced output", 0, data[12].toInt() and 255)
            }
            if (kind == "IDAT") compressed.write(data)
            if (kind == "IEND") {
                assertEquals(0, length)
                ended = true
            }
        }
        assertTrue(ended)
        assertEquals("IHDR", kinds.first())
        assertEquals("IEND", kinds.last())
        assertEquals(1, kinds.count { it == "IHDR" })
        assertEquals(1, kinds.count { it == "IEND" })
        val firstData = kinds.indexOf("IDAT")
        val lastData = kinds.lastIndexOf("IDAT")
        assertTrue(firstData > 0)
        assertTrue(kinds.subList(firstData, lastData + 1).all { it == "IDAT" })

        // Decode the encoded straight-alpha bytes independently of Android:
        // BitmapFactory may conceal leaked RGB by premultiplying alpha zero.
        val decoded = decodeStraightRgba(compressed.toByteArray(), width, height)
        assertEquals(width, decoded.width)
        assertEquals(height, decoded.height)
        for (y in 0 until height) {
            for (x in 0 until width) {
                val pixel = decoded.getRGB(x, y)
                if (pixel ushr 24 == 0) assertEquals("invisible RGB at ($x,$y)", 0, pixel)
            }
        }
        return decoded
    }

    private fun decodeStraightRgba(compressed: ByteArray, width: Int, height: Int): StraightRgba {
        assertTrue(width in 1..2048 && height in 1..2048)
        val stride = width * 4
        val scanlines = ByteArray((stride + 1) * height)
        val inflater = Inflater()
        try {
            inflater.setInput(compressed)
            var written = 0
            while (written < scanlines.size) {
                val count = inflater.inflate(scanlines, written, scanlines.size - written)
                assertTrue("PNG zlib stream ended or stopped before the complete canvas", count > 0)
                written += count
            }
            // A single-byte probe permits the zlib trailer to be consumed but
            // rejects any inflated data beyond the exact bounded canvas.
            assertEquals("extra inflated PNG data", 0, inflater.inflate(ByteArray(1)))
            assertTrue("PNG zlib stream must have its complete trailer", inflater.finished())
            assertFalse("PNG cannot require an external zlib dictionary", inflater.needsDictionary())
            assertEquals("trailing compressed PNG data", 0, inflater.remaining)
        } finally {
            inflater.end()
        }

        val rgba = ByteArray(stride * height)
        for (y in 0 until height) {
            val scanline = y * (stride + 1)
            val filter = scanlines[scanline].toInt() and 255
            assertTrue("invalid PNG scanline filter $filter", filter in 0..4)
            for (column in 0 until stride) {
                val target = y * stride + column
                val left = if (column >= 4) rgba[target - 4].toInt() and 255 else 0
                val above = if (y > 0) rgba[target - stride].toInt() and 255 else 0
                val upperLeft = if (y > 0 && column >= 4) rgba[target - stride - 4].toInt() and 255 else 0
                val predictor = when (filter) {
                    0 -> 0
                    1 -> left
                    2 -> above
                    3 -> (left + above) / 2
                    else -> {
                        val estimate = left + above - upperLeft
                        val leftDistance = abs(estimate - left)
                        val aboveDistance = abs(estimate - above)
                        val diagonalDistance = abs(estimate - upperLeft)
                        when {
                            leftDistance <= aboveDistance && leftDistance <= diagonalDistance -> left
                            aboveDistance <= diagonalDistance -> above
                            else -> upperLeft
                        }
                    }
                }
                val filtered = scanlines[scanline + 1 + column].toInt() and 255
                rgba[target] = ((filtered + predictor) and 255).toByte()
            }
        }
        return StraightRgba(width, height, rgba)
    }

    private class StraightRgba(val width: Int, val height: Int, private val pixels: ByteArray) {
        fun getRGB(x: Int, y: Int): Int {
            val start = (y * width + x) * 4
            return ((pixels[start + 3].toInt() and 255) shl 24) or
                ((pixels[start].toInt() and 255) shl 16) or
                ((pixels[start + 1].toInt() and 255) shl 8) or
                (pixels[start + 2].toInt() and 255)
        }
    }
}
