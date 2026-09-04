package com.mknoon.app.call

import android.content.Context
import android.media.AudioAttributes
import android.media.MediaPlayer
import android.media.RingtoneManager
import android.os.PowerManager
import java.util.UUID

internal fun interface MknoonCallRingtoneSession {
    fun stop()
}

internal fun interface MknoonCallRingtoneStarter {
    fun start(): MknoonCallRingtoneSession?
}

/**
 * Owns exactly one best-effort incoming ringtone session.
 *
 * Call admission and terminal cleanup never depend on ringtone availability,
 * but a successful session is exact-call bound so answer/end cannot leak audio
 * into a later call.
 */
internal class MknoonIncomingCallRinger(
    private val starter: MknoonCallRingtoneStarter,
) {
    private var activeCallId: UUID? = null
    private var activeSession: MknoonCallRingtoneSession? = null

    @Synchronized
    fun start(nativeCallId: UUID): Boolean {
        if (activeCallId == nativeCallId && activeSession != null) return true
        stopLocked()
        val session = try {
            starter.start()
        } catch (_: Exception) {
            null
        } ?: return false
        activeCallId = nativeCallId
        activeSession = session
        return true
    }

    @Synchronized
    fun stop(nativeCallId: UUID): Boolean {
        if (activeCallId != nativeCallId || activeSession == null) return false
        stopLocked()
        return true
    }

    private fun stopLocked() {
        val session = activeSession
        activeSession = null
        activeCallId = null
        if (session != null) {
            try {
                session.stop()
            } catch (_: Exception) {
                // Ringtone release is best effort and must never block call cleanup.
            }
        }
    }
}

internal class AndroidMknoonCallRingtoneStarter(context: Context) :
    MknoonCallRingtoneStarter {
    private val applicationContext = context.applicationContext

    override fun start(): MknoonCallRingtoneSession? {
        val uri = RingtoneManager.getActualDefaultRingtoneUri(
            applicationContext,
            RingtoneManager.TYPE_RINGTONE,
        ) ?: return null
        val player = MediaPlayer()
        return try {
            player.setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_NOTIFICATION_RINGTONE)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                    .build(),
            )
            player.setWakeMode(applicationContext, PowerManager.PARTIAL_WAKE_LOCK)
            player.setDataSource(applicationContext, uri)
            player.isLooping = true
            player.prepare()
            player.start()
            MknoonCallRingtoneSession {
                try {
                    if (player.isPlaying) player.stop()
                } finally {
                    player.release()
                }
            }
        } catch (_: Exception) {
            runCatching { player.release() }
            null
        }
    }
}
