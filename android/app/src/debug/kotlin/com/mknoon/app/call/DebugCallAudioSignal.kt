package com.mknoon.app.call

import java.nio.ByteBuffer
import java.nio.ByteOrder
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.sin

/**
 * Synthetic mono PCM only. Never stores microphone or decoded speech samples.
 * WebRTC SDK ExternalAudioProcessor passes channels()[0] as native-order float
 * PCM on the signed-16-bit amplitude scale, in one 10 ms block. The oracle
 * covers this digital boundary, not physical microphone/speaker transducers.
 */
internal class DebugCallAudioSignal(
    private val caller: Boolean,
    private val verifyTrackMute: Boolean = false,
    private val nowMs: () -> Long = System::currentTimeMillis,
) {
    companion object {
        private val SYMBOLS = intArrayOf(0, 2, 1, 3, 1, 0, 3, 2)
        private const val SYMBOL_FRAMES = 20 // 200 ms at WebRTC's 10 ms callback.
        private const val AMPLITUDE = 4096.0
    }

    private var phase = 0.0
    private var lastSymbol = -1
    private var stableSymbol = -1
    private var stableFrames = 0
    private var sequenceIndex = -1
    private var symbolMask = 0
    private var consecutiveTransitions = 0
    private var longestTransitions = 0
    private var injectedFrames = 0
    private var renderedFrames = 0
    private var matchingFrames = 0
    private var mutedFrames = 0
    private var injectedWhileNativeMutedFrames = 0
    private var firstMatchingAtMs = 0L
    private var firstVerifiedAtMs = 0L
    private var invalidBuffers = 0

    @Synchronized
    fun inject(numFrames: Int, buffer: ByteBuffer, muted: Boolean) {
        if (!valid(numFrames, buffer)) return
        val samples = buffer.order(ByteOrder.nativeOrder())
        val symbol = SYMBOLS[(injectedFrames / SYMBOL_FRAMES) % SYMBOLS.size]
        val frequency = (if (caller) 600 else 1800) + symbol * 100
        val step = 2 * PI * frequency / (numFrames * 100)
        val silence = muted && !verifyTrackMute
        for (index in 0 until numFrames) {
            samples.putFloat(index * 4, if (silence) 0f else (AMPLITUDE * sin(phase)).toFloat())
            phase = (phase + step) % (2 * PI)
        }
        if (muted) mutedFrames++
        if (!silence) {
            injectedFrames++
            if (muted) injectedWhileNativeMutedFrames++
        }
    }

    @Synchronized
    fun observe(numFrames: Int, buffer: ByteBuffer) {
        if (!valid(numFrames, buffer)) return
        val samples = buffer.order(ByteOrder.nativeOrder())
        renderedFrames++
        var total = 0.0
        for (index in 0 until numFrames) {
            val value = samples.getFloat(index * 4).toDouble()
            if (!value.isFinite()) { invalidBuffers++; return }
            total += value * value
        }
        if (total / numFrames < 128.0 * 128.0) return
        var bestSymbol = -1
        var bestRatio = 0.0
        for (symbol in 0..3) {
            val frequency = (if (caller) 1800 else 600) + symbol * 100
            val coefficient = 2 * cos(2 * PI * frequency / (numFrames * 100))
            var previous = 0.0
            var beforePrevious = 0.0
            for (index in 0 until numFrames) {
                val value = samples.getFloat(index * 4) + coefficient * previous - beforePrevious
                beforePrevious = previous
                previous = value
            }
            val power = previous * previous + beforePrevious * beforePrevious -
                coefficient * previous * beforePrevious
            val ratio = 2 * power / (numFrames * total)
            if (ratio > bestRatio) { bestRatio = ratio; bestSymbol = symbol }
        }
        if (bestRatio < 0.60) return
        matchingFrames++
        if (firstMatchingAtMs == 0L) firstMatchingAtMs = nowMs()
        symbolMask = symbolMask or (1 shl bestSymbol)
        if (bestSymbol == stableSymbol) stableFrames++ else {
            stableSymbol = bestSymbol
            stableFrames = 1
        }
        if (stableFrames < 4 || bestSymbol == lastSymbol) return
        lastSymbol = bestSymbol
        if (sequenceIndex < 0) {
            sequenceIndex = SYMBOLS.indexOf(bestSymbol)
            return
        }
        val next = (sequenceIndex + 1) % SYMBOLS.size
        if (SYMBOLS[next] == bestSymbol) {
            sequenceIndex = next
            consecutiveTransitions++
            longestTransitions = maxOf(longestTransitions, consecutiveTransitions)
            if (firstVerifiedAtMs == 0L && matchingFrames >= 120 && symbolMask == 15 &&
                longestTransitions >= 12 && invalidBuffers == 0) firstVerifiedAtMs = nowMs()
        } else {
            sequenceIndex = SYMBOLS.indexOf(bestSymbol)
            consecutiveTransitions = 0
        }
    }

    private fun valid(numFrames: Int, buffer: ByteBuffer): Boolean {
        val valid = (numFrames == 80 || numFrames == 160 || numFrames == 320 || numFrames == 480) &&
            buffer.capacity() >= numFrames * 4
        if (!valid) invalidBuffers++
        return valid
    }

    @Synchronized
    fun result(): Map<String, Any> = linkedMapOf(
        "injectedFrames" to injectedFrames,
        "renderedFrames" to renderedFrames,
        "matchingFrames" to matchingFrames,
        "mutedFrames" to mutedFrames,
        "verifyTrackMute" to verifyTrackMute,
        "injectedWhileNativeMutedFrames" to injectedWhileNativeMutedFrames,
        "firstMatchingAtMs" to firstMatchingAtMs,
        "firstVerifiedAtMs" to firstVerifiedAtMs,
        "invalidBuffers" to invalidBuffers,
        "allRemoteSymbolsObserved" to (symbolMask == 15),
        "longestOrderedTransitions" to longestTransitions,
        "decodedSignalVerified" to (matchingFrames >= 120 && symbolMask == 15 &&
            longestTransitions >= 12 && invalidBuffers == 0),
    )
}
