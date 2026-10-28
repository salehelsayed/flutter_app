package com.mknoon.app

import android.app.ActivityManager
import android.content.Context
import android.media.AudioFormat
import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.os.Debug
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.File

/**
 * TRANSLATE_PREVIEW: memory figures for the GEMMA_PREVIEW log line, and a
 * voice message decoded to 16-bit PCM for the on-device model. Dart only calls
 * it when the preview is built in.
 */
object GemmaPreviewChannel {
    private const val NAME = "mknoon/gemma_preview"

    fun register(messenger: BinaryMessenger, context: Context) {
        val main = Handler(Looper.getMainLooper())
        MethodChannel(messenger, NAME).setMethodCallHandler { call, result ->
            when (call.method) {
                "memory" -> result.success(memory(context))
                "decodePcm" -> {
                    val path = call.argument<String>("path")
                    if (path.isNullOrBlank()) {
                        result.error("bad_args", "path is required", null)
                        return@setMethodCallHandler
                    }
                    Thread {
                        try {
                            val decoded = decodePcm(path)
                            main.post { result.success(decoded) }
                        } catch (error: Exception) {
                            main.post {
                                result.error("decode_failed", error.toString(), null)
                            }
                        }
                    }.start()
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun memory(context: Context): Map<String, Long?> {
        val info = ActivityManager.MemoryInfo()
        context.getSystemService(ActivityManager::class.java)?.getMemoryInfo(info)
        return mapOf(
            "availableBytes" to info.availMem,
            "footprintBytes" to Debug.getPss() * 1024,
            "peakFootprintBytes" to peakRssKib()?.let { it * 1024 },
        )
    }

    /** Whole-process peak RSS (VmHWM), as the benchmark harness read it. */
    private fun peakRssKib(): Long? = try {
        File("/proc/self/status").readLines()
            .firstOrNull { it.startsWith("VmHWM:") }
            ?.trim()?.split(Regex("\\s+"))?.getOrNull(1)?.toLong()
    } catch (_: Exception) {
        null
    }

    private fun decodePcm(path: String): Map<String, Any> {
        val extractor = MediaExtractor()
        try {
            extractor.setDataSource(path)
            val track = (0 until extractor.trackCount).firstOrNull {
                extractor.getTrackFormat(it).getString(MediaFormat.KEY_MIME)
                    ?.startsWith("audio/") == true
            } ?: throw IllegalStateException("no audio track")
            extractor.selectTrack(track)
            val input = extractor.getTrackFormat(track)
            var sampleRate = input.getInteger(MediaFormat.KEY_SAMPLE_RATE)
            var channels = input.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
            val codec = MediaCodec.createDecoderByType(input.getString(MediaFormat.KEY_MIME)!!)
            val pcm = ByteArrayOutputStream()
            try {
                codec.configure(input, null, null, 0)
                codec.start()
                val info = MediaCodec.BufferInfo()
                var inputDone = false
                while (true) {
                    if (!inputDone) {
                        val index = codec.dequeueInputBuffer(10_000)
                        if (index >= 0) {
                            val buffer = codec.getInputBuffer(index)!!
                            val size = extractor.readSampleData(buffer, 0)
                            if (size < 0) {
                                codec.queueInputBuffer(index, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                                inputDone = true
                            } else {
                                codec.queueInputBuffer(index, 0, size, extractor.sampleTime, 0)
                                extractor.advance()
                            }
                        }
                    }
                    val out = codec.dequeueOutputBuffer(info, 10_000)
                    if (out == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
                        val format = codec.outputFormat
                        sampleRate = format.getInteger(MediaFormat.KEY_SAMPLE_RATE)
                        channels = format.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
                        if (format.containsKey(MediaFormat.KEY_PCM_ENCODING) &&
                            format.getInteger(MediaFormat.KEY_PCM_ENCODING) != AudioFormat.ENCODING_PCM_16BIT
                        ) {
                            throw IllegalStateException("decoder output is not 16-bit PCM")
                        }
                    } else if (out >= 0) {
                        val buffer = codec.getOutputBuffer(out)!!
                        val bytes = ByteArray(info.size)
                        buffer.position(info.offset)
                        buffer.get(bytes)
                        pcm.write(bytes)
                        codec.releaseOutputBuffer(out, false)
                        if (info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) break
                    }
                }
            } finally {
                codec.release()
            }
            return mapOf("pcm" to pcm.toByteArray(), "sampleRate" to sampleRate, "channels" to channels)
        } finally {
            extractor.release()
        }
    }
}
