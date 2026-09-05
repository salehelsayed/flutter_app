package com.mknoon.app.call

import android.media.AudioManager
import android.media.ToneGenerator

internal const val MKNOON_CALL_RINGBACK_DIAGNOSTIC_TAG = "MknoonCallRingback"

internal fun interface MknoonCallRingbackToneSession {
    fun stop()
}

internal fun interface MknoonCallRingbackToneStarter {
    fun start(): MknoonCallRingbackToneSession?
}

/**
 * Owns the single best-effort ringback tone: what the caller hears while the
 * far end rings. Dart starts and stops it from the call state through the
 * lifecycle bridge, and the runtime also stops it on the native answer and
 * terminal paths so it can never outlive the call. The session is bound to
 * the Dart call handle so a stale stop cannot silence a later call.
 */
internal class MknoonOutgoingCallRingback(
    private val starter: MknoonCallRingbackToneStarter,
) {
    private var activeHandle: String? = null
    private var activeSession: MknoonCallRingbackToneSession? = null

    val activeCallHandle: String?
        get() = synchronized(this) { activeHandle }

    @Synchronized
    fun start(callHandle: String): Boolean {
        if (activeHandle == callHandle && activeSession != null) return true
        stopLocked()
        val session = try {
            starter.start()
        } catch (_: Exception) {
            null
        } ?: return false
        activeHandle = callHandle
        activeSession = session
        return true
    }

    @Synchronized
    fun stop(callHandle: String): Boolean {
        if (activeHandle != callHandle || activeSession == null) return false
        stopLocked()
        return true
    }

    @Synchronized
    fun stopAll(): Boolean {
        if (activeSession == null) return false
        stopLocked()
        return true
    }

    private fun stopLocked() {
        val session = activeSession
        activeSession = null
        activeHandle = null
        if (session != null) {
            try {
                session.stop()
            } catch (_: Exception) {
                // Tone release is best effort and must never block call control.
            }
        }
    }
}

/**
 * Plays the platform's supervisory ringback tone on the voice-call stream, so
 * it follows the in-call route (earpiece, speaker, headset) and volume.
 */
internal class AndroidMknoonCallRingbackToneStarter : MknoonCallRingbackToneStarter {
    override fun start(): MknoonCallRingbackToneSession? {
        val generator = try {
            ToneGenerator(AudioManager.STREAM_VOICE_CALL, RINGBACK_VOLUME)
        } catch (_: RuntimeException) {
            return null
        }
        return try {
            if (!generator.startTone(ToneGenerator.TONE_SUP_RINGTONE)) {
                generator.release()
                return null
            }
            MknoonCallRingbackToneSession {
                try {
                    generator.stopTone()
                } finally {
                    generator.release()
                }
            }
        } catch (_: Exception) {
            runCatching { generator.release() }
            null
        }
    }

    private companion object {
        /** ToneGenerator volume is 0..100; ringback sits below the voice level. */
        const val RINGBACK_VOLUME = 70
    }
}
