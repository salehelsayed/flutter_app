package com.mknoon.app

import android.graphics.Bitmap
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaMetadataRetriever
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.math.abs
import kotlin.math.roundToInt

/** Extracts bounded, oriented camera frames. Dart owns encoding and the job directory. */
internal class StickerClipFrameBridge(
    messenger: BinaryMessenger,
    private val cacheDirectory: File,
) : AutoCloseable {
    private val channel = MethodChannel(messenger, "mknoon/custom_sticker_clip_frames")
    private val main = Handler(Looper.getMainLooper())
    private val executor = Executors.newSingleThreadExecutor()
    private var active: Job? = null
    private var closed = false

    init {
        channel.setMethodCallHandler(::handle)
    }

    private fun handle(call: MethodCall, result: MethodChannel.Result) {
        val args = call.arguments as? Map<*, *>
        when (call.method) {
            "cancel" -> {
                val id = args?.get("jobId") as? String
                active?.takeIf { it.id == id }?.cancelled?.set(true)
                result.success(null)
            }
            "extract" -> {
                if (closed || active != null) {
                    result.error("unavailable", null, null)
                    return
                }
                val id = args?.get("jobId") as? String
                val clip = args?.get("clipPath") as? String
                val frames = args?.get("framesPath") as? String
                val crop = (args?.get("crop") as? List<*>)?.map {
                    (it as? Number)?.toDouble() ?: Double.NaN
                }
                if (id.isNullOrEmpty() || clip.isNullOrEmpty() || frames.isNullOrEmpty() ||
                    crop == null || crop.size != 4 || crop.any { !it.isFinite() } ||
                    crop[0] < 0 || crop[1] < 0 || crop[2] > 1 || crop[3] > 1 ||
                    crop[0] >= crop[2] || crop[1] >= crop[3]
                ) {
                    result.error("invalid_clip", null, null)
                    return
                }
                val job = Job(id)
                active = job
                executor.execute { extract(job, clip, frames, crop, result) }
            }
            else -> result.notImplemented()
        }
    }

    private fun extract(
        job: Job,
        clipPath: String,
        framesPath: String,
        crop: List<Double>,
        result: MethodChannel.Result,
    ) {
        var ownedOutput: File? = null
        var reply: Map<String, Int>? = null
        var errorCode: String? = null
        try {
            val cache = cacheDirectory.canonicalFile
            val clip = File(clipPath).canonicalFile
            if (!clip.path.startsWith(cache.path + File.separator) ||
                !clip.isFile || clip.length() !in 1L..MAX_SOURCE_BYTES
            ) invalidClip()
            val requested = File(framesPath)
            val parent = requested.parentFile?.canonicalFile ?: invalidClip()
            if (requested.name != "frames.rgba" || parent.parentFile != cache ||
                parent.name != job.id || !parent.name.startsWith(JOB_PREFIX) ||
                !parent.isDirectory
            ) invalidClip()
            job.checkActive()
            validateTracks(clip)
            val retriever = MediaMetadataRetriever()
            try {
                retriever.setDataSource(clip.path)
                val width = retriever.extractMetadata(
                    MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH,
                )?.toIntOrNull() ?: invalidClip()
                val height = retriever.extractMetadata(
                    MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT,
                )?.toIntOrNull() ?: invalidClip()
                validateDimensions(width, height)
                val sourceDuration = retriever.extractMetadata(
                    MediaMetadataRetriever.METADATA_KEY_DURATION,
                )?.toLongOrNull() ?: invalidClip()
                if (sourceDuration < 2) invalidClip()
                val duration = sourceDuration.coerceAtMost(MAX_DURATION_MS.toLong()).toInt()
                val count = maxOf(2, (duration * 12 + 999) / 1000)
                val output = File(parent, "frames.rgba")
                if (!output.createNewFile()) invalidClip()
                ownedOutput = output
                val argb = IntArray(SIDE * SIDE)
                val rgba = ByteArray(SIDE * SIDE * 4)
                FileOutputStream(output).use { stream ->
                    for (i in 0 until count) {
                        job.checkActive()
                        val timeUs = ((i * duration + count / 2) / count) * 1000L
                        // OPTION_CLOSEST can return a non-keyframe. The framework
                        // applies rotation before returning the Bitmap.
                        val frame = retriever.getFrameAtTime(
                            timeUs, MediaMetadataRetriever.OPTION_CLOSEST,
                        ) ?: throw ClipError("unavailable")
                        try {
                            writeFrame(frame, crop, argb, rgba)
                            job.checkActive()
                            stream.write(rgba)
                        } finally {
                            frame.recycle()
                        }
                    }
                }
                job.checkActive()
                reply = mapOf("durationMs" to duration, "frameCount" to count)
            } finally {
                runCatching { retriever.release() }
            }
        } catch (error: ClipError) {
            errorCode = error.code
        } catch (_: Exception) {
            errorCode = "unavailable"
        }
        if (errorCode != null || job.cancelled.get()) ownedOutput?.delete()
        val finalReply = reply
        val finalError = errorCode
        main.post {
            if (active === job) active = null
            if (job.cancelled.get()) {
                ownedOutput?.delete()
                if (!closed) result.error("cancelled", null, null)
            } else if (!closed) {
                if (finalError != null) result.error(finalError, null, null)
                else result.success(finalReply)
            }
        }
    }

    private fun validateTracks(clip: File) {
        val extractor = MediaExtractor()
        try {
            extractor.setDataSource(clip.path)
            var videos = 0
            for (i in 0 until extractor.trackCount) {
                val mime = extractor.getTrackFormat(i).getString(MediaFormat.KEY_MIME)
                if (mime?.startsWith("audio/") == true) invalidClip()
                if (mime?.startsWith("video/") == true) videos++
            }
            if (videos != 1) invalidClip()
        } finally {
            extractor.release()
        }
    }

    private fun writeFrame(
        frame: Bitmap,
        crop: List<Double>,
        argb: IntArray,
        rgba: ByteArray,
    ) {
        validateDimensions(frame.width, frame.height)
        val spanWidth = (crop[2] - crop[0]) * frame.width
        val spanHeight = (crop[3] - crop[1]) * frame.height
        if (abs(spanWidth - spanHeight) > 1.0) invalidClip()
        val x = (crop[0] * frame.width).roundToInt()
        val y = (crop[1] * frame.height).roundToInt()
        val side = minOf(
            spanWidth.roundToInt(), spanHeight.roundToInt(),
            frame.width - x, frame.height - y,
        )
        if (side < 1) invalidClip()
        val cropped = Bitmap.createBitmap(frame, x, y, side, side)
        try {
            val scaled = Bitmap.createScaledBitmap(cropped, SIDE, SIDE, true)
            try {
                scaled.getPixels(argb, 0, SIDE, 0, 0, SIDE, SIDE)
                for (i in argb.indices) {
                    val pixel = argb[i]
                    rgba[4 * i] = (pixel ushr 16).toByte()
                    rgba[4 * i + 1] = (pixel ushr 8).toByte()
                    rgba[4 * i + 2] = pixel.toByte()
                    rgba[4 * i + 3] = 0xff.toByte()
                }
            } finally {
                if (scaled !== cropped) scaled.recycle()
            }
        } finally {
            if (cropped !== frame) cropped.recycle()
        }
    }

    private fun validateDimensions(width: Int, height: Int) {
        if (width !in 1..4096 || height !in 1..4096 ||
            width.toLong() * height > MAX_SOURCE_PIXELS
        ) invalidClip()
    }

    override fun close() {
        closed = true
        channel.setMethodCallHandler(null)
        active?.cancelled?.set(true)
        executor.shutdown()
    }

    private class Job(val id: String) {
        val cancelled = AtomicBoolean(false)

        fun checkActive() {
            if (cancelled.get()) throw ClipError("cancelled")
        }
    }

    private class ClipError(val code: String) : Exception()

    private fun invalidClip(): Nothing = throw ClipError("invalid_clip")

    private companion object {
        const val SIDE = 512
        const val MAX_DURATION_MS = 2000
        const val MAX_SOURCE_BYTES = 64L * 1024 * 1024
        const val MAX_SOURCE_PIXELS = 4L * 1024 * 1024
        const val JOB_PREFIX = "mknoon-sticker-animation-"
    }
}
