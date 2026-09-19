package com.mknoon.app.call

import java.nio.ByteBuffer
import java.nio.ByteOrder
import org.junit.Assert.assertEquals
import org.junit.Test

class DebugCallAudioSignalTest {
    @Test fun bothDirectionsRecognizeDecodedSyntheticSequenceAtSupportedRates() {
        for (frames in listOf(80, 160, 320, 480)) {
            val caller = DebugCallAudioSignal(true)
            val callee = DebugCallAudioSignal(false)
            val buffer = ByteBuffer.allocateDirect(frames * 4).order(ByteOrder.nativeOrder())
            repeat(500) {
                caller.inject(frames, buffer, false)
                callee.observe(frames, buffer)
                callee.inject(frames, buffer, false)
                caller.observe(frames, buffer)
            }
            assertEquals(true, caller.result()["decodedSignalVerified"])
            assertEquals(true, callee.result()["decodedSignalVerified"])
        }
    }

    @Test fun ownToneAndSilenceCannotProveRemoteAudio() {
        val caller = DebugCallAudioSignal(true)
        val receiver = DebugCallAudioSignal(true)
        val buffer = ByteBuffer.allocateDirect(480 * 4)
        repeat(500) {
            caller.inject(480, buffer, false)
            receiver.observe(480, buffer)
        }
        assertEquals(false, receiver.result()["decodedSignalVerified"])
        assertEquals(0, receiver.result()["matchingFrames"])
        repeat(500) {
            caller.inject(480, buffer, true)
            receiver.observe(480, buffer)
        }
        assertEquals(0, receiver.result()["matchingFrames"])
    }

    @Test fun repeatedSingleToneCannotProveOrderedSignature() {
        val receiver = DebugCallAudioSignal(false)
        val buffer = ByteBuffer.allocateDirect(480 * 4)
        repeat(500) {
            // Every new generator emits only the first signature symbol.
            DebugCallAudioSignal(true).inject(480, buffer, false)
            receiver.observe(480, buffer)
        }
        assertEquals(false, receiver.result()["decodedSignalVerified"])
        assertEquals(0, receiver.result()["longestOrderedTransitions"])
    }

    @Test fun lateReceiverRecognizesAttenuatedSignalWithNoise() {
        val sender = DebugCallAudioSignal(true)
        val receiver = DebugCallAudioSignal(false)
        val buffer = ByteBuffer.allocateDirect(480 * 4).order(ByteOrder.nativeOrder())
        repeat(650) { frame ->
            sender.inject(480, buffer, false)
            for (index in 0 until 480) {
                val noise = ((index * 31 + frame * 7) % 127 - 63).toFloat()
                buffer.putFloat(index * 4, buffer.getFloat(index * 4) * 0.25f + noise)
            }
            if (frame >= 75 && frame % 29 != 0) receiver.observe(480, buffer)
        }
        assertEquals(true, receiver.result()["decodedSignalVerified"])
    }

    @Test fun mutedRemoteSenderCannotProduceSignature() {
        val sender = DebugCallAudioSignal(true)
        val receiver = DebugCallAudioSignal(false)
        val buffer = ByteBuffer.allocateDirect(480 * 4)
        repeat(500) {
            sender.inject(480, buffer, true)
            receiver.observe(480, buffer)
        }
        assertEquals(false, receiver.result()["decodedSignalVerified"])
        assertEquals(0, receiver.result()["matchingFrames"])
    }

    @Test fun malformedBufferFailsClosed() {
        val signal = DebugCallAudioSignal(true)
        signal.inject(480, ByteBuffer.allocateDirect(4), false)
        signal.observe(479, ByteBuffer.allocateDirect(480 * 4))
        assertEquals(2, signal.result()["invalidBuffers"])
        assertEquals(false, signal.result()["decodedSignalVerified"])
    }

    @Test fun explicitTrackMuteProofKeepsSyntheticToneDespiteNativeMuteFlag() {
        val sender = DebugCallAudioSignal(true, verifyTrackMute = true)
        val receiver = DebugCallAudioSignal(false, nowMs = { 123456L })
        val buffer = ByteBuffer.allocateDirect(480 * 4)
        repeat(500) {
            sender.inject(480, buffer, true)
            receiver.observe(480, buffer)
        }
        // If WebRTC fails to disable the track, the remote detector still
        // recognizes it: the native mute flag cannot manufacture a negative.
        assertEquals(500, sender.result()["mutedFrames"])
        assertEquals(500, sender.result()["injectedFrames"])
        assertEquals(500, sender.result()["injectedWhileNativeMutedFrames"])
        assertEquals(true, receiver.result()["decodedSignalVerified"])
        assertEquals(123456L, receiver.result()["firstMatchingAtMs"])
        assertEquals(123456L, receiver.result()["firstVerifiedAtMs"])
    }
}
