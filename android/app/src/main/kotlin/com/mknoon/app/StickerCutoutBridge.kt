package com.mknoon.app

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.media.ExifInterface
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.system.ErrnoException
import android.system.Os
import android.system.OsConstants
import android.system.StructStat
import com.google.android.gms.tasks.Task
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.DataOutputStream
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.io.IOException
import java.util.concurrent.Executor
import java.util.concurrent.Executors
import java.util.concurrent.RejectedExecutionException
import java.util.zip.CRC32
import java.util.zip.DeflaterOutputStream
import kotlin.math.max
import kotlin.math.min

/** The caller retains an inference input until its returned Task completes. */
internal interface StickerCutoutClient : AutoCloseable {
    fun areModulesAvailable(): Task<Boolean>
    fun deferredInstall(): Task<Void>
    fun process(uprightBitmap: Bitmap): Task<Bitmap?>
}

/** One still-image job; Dart owns its directory and every successfully returned PNG. */
internal class StickerCutoutBridge(
    messenger: BinaryMessenger,
    cacheDirectory: File,
    private val clientFactory: () -> StickerCutoutClient?,
    private val sdkInt: Int = Build.VERSION.SDK_INT,
    worker: Executor? = null,
) : AutoCloseable {
    private val channel = MethodChannel(messenger, "mknoon/custom_sticker_cutout")
    private val main = Handler(Looper.getMainLooper())
    private val lock = Any()
    private val ownedWorker = if (worker == null) Executors.newSingleThreadExecutor() else null
    private val worker: Executor = worker ?: requireNotNull(ownedWorker)
    private val cacheRoot = runCatching { cacheDirectory.canonicalFile }.getOrElse { cacheDirectory.absoluteFile }
    private val rootIdentity = runCatching { directoryIdentity(cacheRoot) }.getOrNull()
    private var closed = false
    private var active: Job? = null
    private var cachedClient: ClientHandle? = null
    private val availabilityCalls = mutableSetOf<AvailabilityCall>()

    init {
        channel.setMethodCallHandler(::handle)
    }

    private fun handle(call: MethodCall, result: MethodChannel.Result) {
        val args = call.arguments as? Map<*, *>
        when (call.method) {
            "availability" -> availability(result)
            "extract" -> extract(args, result)
            "cancel" -> {
                cancel(args?.get("jobId") as? String)
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun availability(result: MethodChannel.Result) {
        val call = AvailabilityCall(result)
        synchronized(lock) {
            if (closed || sdkInt < 24) {
                result.success("unsupported")
                return
            }
            availabilityCalls.add(call)
        }
        try {
            worker.execute {
                val handle = synchronized(lock) {
                    if (call in availabilityCalls) clientLocked() else null
                }
                if (handle == null) finishAvailability(call, "unsupported")
                else probe(handle) { state -> finishAvailability(call, state) }
            }
        } catch (_: RejectedExecutionException) {
            finishAvailability(call, "unsupported")
        }
    }

    private fun finishAvailability(call: AvailabilityCall, state: String) = onMain {
        synchronized(lock) {
            if (availabilityCalls.remove(call)) call.result.success(if (closed) "unsupported" else state)
        }
    }

    /** Called under lock, after the OS guard, and only for a still-live request. */
    private fun clientLocked(): ClientHandle? {
        if (closed || sdkInt < 24) return null
        cachedClient?.let { return it }
        return try {
            clientFactory()?.let { ClientHandle(it).also { handle -> cachedClient = handle } }
        } catch (_: Exception) {
            null
        }
    }

    private fun probe(handle: ClientHandle, completion: (String) -> Unit) {
        val task = try {
            synchronized(lock) {
                if (closed || handle.retired) null else handle.client.areModulesAvailable()
            }
        } catch (_: Exception) {
            null
        }
        if (task == null) {
            completion("unsupported")
            return
        }
        task.addOnCompleteListener(DIRECT) { completed ->
            val state = synchronized(lock) {
                when {
                    closed || handle.retired || !completed.isSuccessful -> "unsupported"
                    completed.result == true -> "ready"
                    else -> {
                        requestDeferredInstallLocked(handle)
                        "needsModel"
                    }
                }
            }
            completion(state)
        }
    }

    private fun requestDeferredInstallLocked(handle: ClientHandle) {
        if (closed || handle.retired || handle.installPending) return
        handle.installPending = true
        try {
            handle.client.deferredInstall().addOnCompleteListener(DIRECT) {
                // Scheduling acknowledgement never becomes model readiness.
                synchronized(lock) { handle.installPending = false }
            }
        } catch (_: Exception) {
            handle.installPending = false
        }
    }

    private fun extract(args: Map<*, *>?, result: MethodChannel.Result) {
        val job = synchronized(lock) {
            if (closed || active != null) {
                result.error("unavailable", null, null)
                return
            }
            if (sdkInt < 24) {
                result.error("unsupported", null, null)
                return
            }
            val id = args?.get("jobId") as? String
            val source = args?.get("sourceImagePath") as? String
            val output = args?.get("outputPath") as? String
            if (id.isNullOrEmpty() || source.isNullOrEmpty() || output.isNullOrEmpty()) {
                result.error("invalid_source", null, null)
                return
            }
            Job(id, File(source), File(output), result).also { active = it }
        }
        runWorker(job) {
            val destination = destination(job)
            val handle = synchronized(lock) {
                checkLiveLocked(job)
                job.destination = destination
                clientLocked()?.also { job.client = it }
            }
            if (handle == null) finish(job, error = "unsupported")
            else probe(handle) { state ->
                when (state) {
                    "ready" -> runWorker(job) { decodeAndProcess(job, handle) }
                    "needsModel" -> finish(job, error = "unavailable")
                    else -> finish(job, error = "unsupported")
                }
            }
        }
    }

    private fun decodeAndProcess(job: Job, handle: ClientHandle) {
        val input = decodeUpright(job)
        var submitted = false
        try {
            val task = synchronized(lock) {
                checkLiveLocked(job)
                if (handle.retired) throw CutoutError("unavailable")
                validateDestination(requireNotNull(job.destination), null)
                handle.client.process(input)
            }
            submitted = true
            // DIRECT is intentional: completion after close must still release
            // its own bitmap even if our owned worker has already shut down.
            task.addOnCompleteListener(DIRECT) { completed ->
                val foreground = if (completed.isSuccessful) completed.result else null
                if (!completed.isSuccessful) {
                    // A failed native client is not carried into the next job.
                    closeClient(synchronized(lock) { retireLocked(handle) })
                }
                val release = {
                    recycle(input)
                    if (foreground !== input) recycle(foreground)
                }
                if (!isLive(job)) {
                    release()
                } else {
                    runWorker(job, release) {
                        if (!completed.isSuccessful) throw CutoutError("unavailable")
                        if (foreground == null) {
                            finish(job)
                        } else {
                            if (foreground.width != input.width || foreground.height != input.height) {
                                throw CutoutError("failed")
                            }
                            val encoded = encode(job, foreground)
                            if (encoded == null) finish(job)
                            else publish(job, encoded)
                        }
                    }
                }
            }
        } finally {
            // Once submitted, even cancel/close must leave this allocation alive
            // until the native Task acknowledges completion.
            if (!submitted) recycle(input)
        }
    }

    private fun runWorker(job: Job, release: () -> Unit = {}, block: () -> Unit) {
        try {
            worker.execute {
                try {
                    if (isLive(job)) block()
                } catch (_: InactiveJob) {
                    // Its caller was already settled by cancel or detach.
                } catch (error: CutoutError) {
                    finish(job, error = error.code)
                } catch (_: Exception) {
                    finish(job, error = "unavailable")
                } catch (_: OutOfMemoryError) {
                    finish(job, error = "unavailable")
                } finally {
                    release()
                }
            }
        } catch (_: RejectedExecutionException) {
            release()
            finish(job, error = "unavailable")
        }
    }

    private fun cancel(id: String?) {
        val client = synchronized(lock) {
            val job = active?.takeIf { it.id == id } ?: return
            active = null
            job.settled = true
            val closing = retireLocked(job.client)
            removeOwnedOutput(job)
            onMain { job.result.success(null) }
            closing
        }
        closeClient(client)
    }

    override fun close() {
        val client = synchronized(lock) {
            if (closed) return
            closed = true
            channel.setMethodCallHandler(null)
            active?.let { job ->
                job.settled = true
                removeOwnedOutput(job)
                onMain { job.result.success(null) }
            }
            active = null
            val pending = availabilityCalls.toList()
            availabilityCalls.clear()
            pending.forEach { call -> onMain { call.result.success("unsupported") } }
            retireLocked(cachedClient)
        }
        closeClient(client)
        // Queued canceled work can run its cleanup; no external executor is owned.
        ownedWorker?.shutdown()
    }

    private fun retireLocked(handle: ClientHandle?): StickerCutoutClient? {
        if (handle == null || handle.retired) return null
        handle.retired = true
        if (cachedClient === handle) cachedClient = null
        return handle.client
    }

    private fun closeClient(client: StickerCutoutClient?) {
        try {
            client?.close()
        } catch (_: Exception) {
            // Native cancellation is best effort; job identity gates publication.
        }
    }

    private fun finish(job: Job, value: Map<String, Any>? = null, error: String? = null) = onMain {
        synchronized(lock) {
            if (!isLiveLocked(job)) return@synchronized
            var code = error
            if (code == null && value != null) {
                try {
                    validateDestination(requireNotNull(job.destination), requireNotNull(job.ownedOutput))
                } catch (_: Exception) {
                    code = "unavailable"
                }
            }
            if (code != null || value == null) removeOwnedOutput(job)
            else job.ownedOutput = null // Result publication transfers ownership to Dart.
            active = null
            job.settled = true
            if (code == null) job.result.success(value)
            else job.result.error(code, null, null)
        }
    }

    private fun isLive(job: Job): Boolean = synchronized(lock) { isLiveLocked(job) }
    private fun isLiveLocked(job: Job): Boolean = !closed && !job.settled && active === job
    private fun checkLiveLocked(job: Job) {
        if (!isLiveLocked(job)) throw InactiveJob()
    }

    private fun onMain(block: () -> Unit) {
        if (Looper.myLooper() == main.looper) block() else main.post { block() }
    }

    private fun decodeUpright(job: Job): Bitmap {
        if (!job.source.isAbsolute || !job.source.isFile) throw CutoutError("invalid_source")
        try {
            FileInputStream(job.source).use { stream ->
                val stat = Os.fstat(stream.fd)
                if (!OsConstants.S_ISREG(stat.st_mode) || stat.st_size <= 0) throw CutoutError("invalid_source")
                val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
                BitmapFactory.decodeFileDescriptor(stream.fd, null, bounds)
                if (bounds.outWidth <= 0 || bounds.outHeight <= 0) throw CutoutError("invalid_source")
                stream.channel.position(0)
                val orientation = try {
                    ExifInterface(stream.fd).getAttributeInt(ExifInterface.TAG_ORIENTATION, ExifInterface.ORIENTATION_NORMAL)
                } catch (_: IOException) {
                    ExifInterface.ORIENTATION_NORMAL
                }
                stream.channel.position(0)
                var sample = 1
                val longest = max(bounds.outWidth, bounds.outHeight).toLong()
                while ((longest + sample - 1) / sample > MAX_SIDE) sample *= 2
                val options = BitmapFactory.Options().apply {
                    inSampleSize = sample
                    inPreferredConfig = Bitmap.Config.ARGB_8888
                    inScaled = false
                }
                if (!isLive(job)) throw InactiveJob()
                var decoded = BitmapFactory.decodeFileDescriptor(stream.fd, null, options)
                    ?: throw CutoutError("invalid_source")
                try {
                    if (decoded.width > MAX_SIDE || decoded.height > MAX_SIDE) {
                        val ratio = min(MAX_SIDE.toDouble() / decoded.width, MAX_SIDE.toDouble() / decoded.height)
                        val scaled = Bitmap.createScaledBitmap(decoded, max(1, (decoded.width * ratio).toInt()), max(1, (decoded.height * ratio).toInt()), true)
                        if (scaled !== decoded) recycle(decoded)
                        decoded = scaled
                    }
                    if (decoded.width !in 1..MAX_SIDE || decoded.height !in 1..MAX_SIDE) throw CutoutError("invalid_source")
                    if (!isLive(job)) throw InactiveJob()
                    val upright = orient(decoded, orientation)
                    if (upright !== decoded) recycle(decoded)
                    return upright
                } catch (error: Throwable) {
                    recycle(decoded)
                    throw error
                }
            }
        } catch (error: InactiveJob) {
            throw error
        } catch (error: CutoutError) {
            throw error
        } catch (_: Exception) {
            throw CutoutError("invalid_source")
        }
    }

    /** Integer transforms avoid interpolation for the eight EXIF orientations. */
    private fun orient(source: Bitmap, orientation: Int): Bitmap {
        if (orientation !in 2..8) return source
        val width = source.width
        val height = source.height
        val swapped = orientation >= 5
        val outWidth = if (swapped) height else width
        val outHeight = if (swapped) width else height
        val pixels = IntArray(width * height)
        val upright = IntArray(pixels.size)
        source.getPixels(pixels, 0, width, 0, 0, width, height)
        for (y in 0 until height) {
            for (x in 0 until width) {
                val targetX = when (orientation) {
                    2, 3 -> width - 1 - x
                    5, 8 -> y
                    6, 7 -> height - 1 - y
                    else -> x
                }
                val targetY = when (orientation) {
                    3, 4 -> height - 1 - y
                    5, 6 -> x
                    7, 8 -> width - 1 - x
                    else -> y
                }
                upright[targetY * outWidth + targetX] = pixels[y * width + x]
            }
        }
        return Bitmap.createBitmap(upright, outWidth, outHeight, Bitmap.Config.ARGB_8888)
    }

    private fun encode(job: Job, bitmap: Bitmap): Encoded? {
        val width = bitmap.width
        val height = bitmap.height
        if (width !in 1..MAX_SIDE || height !in 1..MAX_SIDE) throw CutoutError("failed")
        var left = width
        var top = height
        var right = 0
        var bottom = 0
        val pixels = IntArray(width)
        val row = ByteArray(width * 4 + 1) // PNG filter 0, then straight RGBA samples.
        val compressed = ByteArrayOutputStream()
        DeflaterOutputStream(compressed).use { zlib ->
            for (y in 0 until height) {
                if (!isLive(job)) throw InactiveJob()
                bitmap.getPixels(pixels, 0, width, 0, y, width, 1)
                for (x in 0 until width) {
                    val pixel = pixels[x]
                    val alpha = pixel ushr 24
                    val start = 1 + x * 4
                    row[start] = if (alpha == 0) 0 else (pixel ushr 16).toByte()
                    row[start + 1] = if (alpha == 0) 0 else (pixel ushr 8).toByte()
                    row[start + 2] = if (alpha == 0) 0 else pixel.toByte()
                    row[start + 3] = alpha.toByte()
                    if (alpha != 0) {
                        left = min(left, x)
                        top = min(top, y)
                        right = max(right, x + 1)
                        bottom = y + 1
                    }
                }
                zlib.write(row)
            }
        }
        if (right == 0) return null
        val header = ByteArrayOutputStream(13).also { bytes ->
            DataOutputStream(bytes).apply {
                writeInt(width)
                writeInt(height)
                write(byteArrayOf(8, 6, 0, 0, 0))
            }
        }.toByteArray()
        val png = ByteArrayOutputStream(compressed.size() + 57)
        DataOutputStream(png).use { output ->
            output.write(byteArrayOf(137.toByte(), 80, 78, 71, 13, 10, 26, 10))
            chunk(output, "IHDR", header)
            chunk(output, "IDAT", compressed.toByteArray())
            chunk(output, "IEND", ByteArray(0))
        }
        if (png.size() > MAX_PNG_BYTES) throw CutoutError("failed")
        return Encoded(png.toByteArray(), mapOf(
            "width" to width,
            "height" to height,
            "subjectBounds" to mapOf(
                "left" to left.toDouble() / width,
                "top" to top.toDouble() / height,
                "right" to right.toDouble() / width,
                "bottom" to bottom.toDouble() / height,
            ),
        ))
    }

    private fun chunk(output: DataOutputStream, name: String, bytes: ByteArray) {
        val type = name.toByteArray(Charsets.US_ASCII)
        output.writeInt(bytes.size)
        output.write(type)
        output.write(bytes)
        val crc = CRC32().apply { update(type); update(bytes) }
        output.writeInt(crc.value.toInt())
    }

    private fun destination(job: Job): Destination {
        val file = job.output
        val directory = file.parentFile ?: throw CutoutError("invalid_source")
        if (!file.isAbsolute || file != file.canonicalFile || file.name != "result.png" ||
            directory.parentFile != cacheRoot || directory.name != job.id ||
            !job.id.startsWith(JOB_PREFIX) || job.id.length <= JOB_PREFIX.length
        ) throw CutoutError("invalid_source")
        val destination = Destination(file, directory, directoryIdentity(directory))
        validateDestination(destination, null)
        return destination
    }

    private fun validateDestination(destination: Destination, output: OwnedOutput?) {
        if (rootIdentity == null || directoryIdentity(cacheRoot) != rootIdentity ||
            directoryIdentity(destination.directory) != destination.directoryIdentity ||
            destination.file.canonicalFile != destination.file
        ) throw CutoutError("unavailable")
        val stat = statOrNull(destination.file)
        if (output == null) {
            if (stat != null) throw CutoutError("unavailable")
        } else if (stat == null || !OsConstants.S_ISREG(stat.st_mode) || identity(stat) != output.identity) {
            throw CutoutError("unavailable")
        }
    }

    private fun publish(job: Job, encoded: Encoded) {
        // File creation/write and cancellation cleanup share this short commit
        // section. Encoding and native inference never hold this lock.
        synchronized(lock) {
            checkLiveLocked(job)
            val destination = requireNotNull(job.destination)
            validateDestination(destination, null)
            val descriptor = Os.open(destination.file.path,
                OsConstants.O_WRONLY or OsConstants.O_CREAT or OsConstants.O_EXCL or OsConstants.O_NOFOLLOW,
                0x180, // 0600, account-private output.
            )
            FileOutputStream(descriptor).use { stream ->
                job.ownedOutput = OwnedOutput(destination.file, identity(Os.fstat(descriptor)))
                validateDestination(destination, job.ownedOutput)
                stream.write(encoded.bytes)
                stream.flush()
                validateDestination(destination, job.ownedOutput)
            }
        }
        finish(job, encoded.descriptor)
    }

    private fun removeOwnedOutput(job: Job) {
        val output = job.ownedOutput ?: return
        job.ownedOutput = null
        try {
            val stat = statOrNull(output.file)
            if (stat != null && OsConstants.S_ISREG(stat.st_mode) && identity(stat) == output.identity) {
                output.file.delete()
            }
        } catch (_: Exception) {
            // Never fall back to recursive/path-only deletion of caller files.
        }
    }

    private fun directoryIdentity(directory: File): Identity {
        if (directory.canonicalFile != directory) throw CutoutError("unavailable")
        val stat = Os.lstat(directory.path)
        if (!OsConstants.S_ISDIR(stat.st_mode)) throw CutoutError("unavailable")
        return identity(stat)
    }

    private fun statOrNull(file: File): StructStat? = try {
        Os.lstat(file.path)
    } catch (error: ErrnoException) {
        if (error.errno == OsConstants.ENOENT) null else throw error
    }

    private fun identity(stat: StructStat) = Identity(stat.st_dev, stat.st_ino)
    private fun recycle(bitmap: Bitmap?) {
        if (bitmap != null && !bitmap.isRecycled) bitmap.recycle()
    }

    private class AvailabilityCall(val result: MethodChannel.Result)
    private class ClientHandle(val client: StickerCutoutClient) {
        var retired = false
        var installPending = false
    }
    private class Job(val id: String, val source: File, val output: File, val result: MethodChannel.Result) {
        var settled = false
        var client: ClientHandle? = null
        var destination: Destination? = null
        var ownedOutput: OwnedOutput? = null
    }
    private data class Identity(val device: Long, val inode: Long)
    private data class Destination(val file: File, val directory: File, val directoryIdentity: Identity)
    private data class OwnedOutput(val file: File, val identity: Identity)
    private data class Encoded(val bytes: ByteArray, val descriptor: Map<String, Any>)
    private class CutoutError(val code: String) : Exception()
    private class InactiveJob : Exception()

    private companion object {
        const val JOB_PREFIX = "mknoon-sticker-cutout-"
        const val MAX_SIDE = 2048
        const val MAX_PNG_BYTES = 24 * 1024 * 1024
        val DIRECT = Executor { it.run() }
    }
}
