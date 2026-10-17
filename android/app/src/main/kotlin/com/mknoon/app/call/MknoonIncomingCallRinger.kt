package com.mknoon.app.call

import android.app.NotificationManager
import android.content.Context
import android.media.AudioAttributes
import android.media.AudioManager
import android.media.MediaPlayer
import android.media.RingtoneManager
import android.os.Build
import android.os.PowerManager
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.provider.Settings
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

    // Sessions whose stop threw may still be vibrating, so their handles are kept
    // and the stop retried later. A retry cancels the app-wide vibrator, so it only
    // runs when nothing rings or the ringing session is about to stop anyway.
    private val failedStops = mutableListOf<MknoonCallRingtoneSession>()

    @Synchronized
    fun start(nativeCallId: UUID): Boolean {
        if (activeCallId == nativeCallId && activeSession != null) return true
        retryFailedStops()
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
        if (activeSession == null) {
            retryFailedStops()
            return false
        }
        if (activeCallId != nativeCallId) return false
        retryFailedStops()
        stopLocked()
        return true
    }

    private fun stopLocked() {
        val session = activeSession ?: return
        activeSession = null
        activeCallId = null
        stopOrRetain(session)
    }

    private fun retryFailedStops() {
        val pending = failedStops.toList()
        failedStops.clear()
        pending.forEach(::stopOrRetain)
    }

    private fun stopOrRetain(session: MknoonCallRingtoneSession) {
        try {
            session.stop()
        } catch (_: Exception) {
            // Ringtone release is best effort and must never block call cleanup.
            failedStops += session
        }
    }
}

internal data class MknoonRingAlertPlan(val soundUsage: Int, val vibrate: Boolean)

/** The notification interruption filter as the ring plan reads it. */
internal enum class MknoonDndFilter { All, Priority, AlarmsOnly, None, Unknown }

internal fun mknoonDndFilter(interruptionFilter: Int): MknoonDndFilter = when (interruptionFilter) {
    NotificationManager.INTERRUPTION_FILTER_ALL -> MknoonDndFilter.All
    NotificationManager.INTERRUPTION_FILTER_PRIORITY -> MknoonDndFilter.Priority
    NotificationManager.INTERRUPTION_FILTER_ALARMS -> MknoonDndFilter.AlarmsOnly
    NotificationManager.INTERRUPTION_FILTER_NONE -> MknoonDndFilter.None
    else -> MknoonDndFilter.Unknown
}

internal data class MknoonRingAlertState(
    val ringerMode: Int,
    val vibrateWhenRinging: Boolean,
    val dndFilter: MknoonDndFilter,
    val channelBypassesDnd: Boolean,
)

/**
 * The ringtone channel keeps sound and vibration off, so this player and
 * vibrator are the only alert owners. Under Do Not Disturb the system mutes a
 * USAGE_NOTIFICATION_RINGTONE player even when the channel may bypass DND, so
 * a ring the user allowed plays as USAGE_ALARM instead.
 */
internal fun mknoonRingAlertPlan(
    ringerMode: Int,
    vibrateWhenRinging: Boolean,
    dndFilter: MknoonDndFilter,
    channelBypassesDnd: Boolean,
): MknoonRingAlertPlan {
    // Only the priority filter honours a channel's bypass flag. Alarms-only,
    // total silence and an unreadable filter keep the ring silent.
    val bypassesDnd = dndFilter == MknoonDndFilter.Priority && channelBypassesDnd
    val ringAllowed = when (dndFilter) {
        MknoonDndFilter.All -> true
        MknoonDndFilter.Priority -> bypassesDnd
        MknoonDndFilter.AlarmsOnly, MknoonDndFilter.None, MknoonDndFilter.Unknown -> false
    }
    val vibrate = ringAllowed && when (ringerMode) {
        AudioManager.RINGER_MODE_SILENT -> false
        AudioManager.RINGER_MODE_VIBRATE -> true
        else -> vibrateWhenRinging
    }
    val soundUsage = if (bypassesDnd && ringerMode == AudioManager.RINGER_MODE_NORMAL) {
        AudioAttributes.USAGE_ALARM
    } else {
        AudioAttributes.USAGE_NOTIFICATION_RINGTONE
    }
    return MknoonRingAlertPlan(soundUsage = soundUsage, vibrate = vibrate)
}

internal fun interface MknoonRingAlertStateReader {
    fun read(): MknoonRingAlertState
}

internal fun interface MknoonRingSoundStarter {
    fun start(soundUsage: Int): MknoonCallRingtoneSession?
}

internal interface MknoonRingVibrator {
    /** False when this device cannot vibrate. */
    fun start(): Boolean

    fun cancel()
}

internal class AndroidMknoonCallRingtoneStarter(
    private val alertState: MknoonRingAlertStateReader,
    private val sound: MknoonRingSoundStarter,
    private val vibrator: MknoonRingVibrator,
) : MknoonCallRingtoneStarter {
    constructor(context: Context) : this(
        alertState = AndroidMknoonRingAlertStateReader(context),
        sound = AndroidMknoonRingSoundStarter(context),
        vibrator = AndroidMknoonRingVibrator(context),
    )

    override fun start(): MknoonCallRingtoneSession? {
        val state = runCatching { alertState.read() }.getOrElse { PLAIN_RING }
        val plan = mknoonRingAlertPlan(
            ringerMode = state.ringerMode,
            vibrateWhenRinging = state.vibrateWhenRinging,
            dndFilter = state.dndFilter,
            channelBypassesDnd = state.channelBypassesDnd,
        )
        runCatching {
            android.util.Log.i(
                MKNOON_CALL_RINGTONE_DIAGNOSTIC_TAG,
                formatMknoonCallRingtoneDiagnostic(
                    "plan",
                    "usage=${if (plan.soundUsage == AudioAttributes.USAGE_ALARM) "alarm" else "ringtone"} " +
                        "vibrate=${plan.vibrate} filter=${state.dndFilter} bypass=${state.channelBypassesDnd} " +
                        "ringer=${state.ringerMode}",
                ),
            )
        }
        val playback = runCatching { sound.start(plan.soundUsage) }.getOrNull()
        val vibrating = plan.vibrate && runCatching { vibrator.start() }.getOrDefault(false)
        if (playback == null && !vibrating) return null
        return MknoonCallRingtoneSession {
            try {
                if (vibrating) vibrator.cancel()
            } finally {
                playback?.stop()
            }
        }
    }

    private companion object {
        // Unreadable alert state must never silence the ring: fall back to the pre-plan behaviour.
        val PLAIN_RING = MknoonRingAlertState(
            ringerMode = AudioManager.RINGER_MODE_NORMAL,
            vibrateWhenRinging = false,
            dndFilter = MknoonDndFilter.All,
            channelBypassesDnd = false,
        )
    }
}

internal class AndroidMknoonRingAlertStateReader(context: Context) : MknoonRingAlertStateReader {
    private val applicationContext = context.applicationContext

    // VIBRATE_WHEN_RINGING is deprecated, but Settings still mirrors the ring
    // vibration toggle into it and Telecom's own ringer reads the same key.
    @Suppress("DEPRECATION")
    override fun read(): MknoonRingAlertState {
        val audio = applicationContext.getSystemService(AudioManager::class.java)
        val notifications = applicationContext.getSystemService(NotificationManager::class.java)
        val filter = notifications?.currentInterruptionFilter
            ?: NotificationManager.INTERRUPTION_FILTER_ALL
        val channel = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            notifications?.getNotificationChannel(MknoonCallNotificationFactory.CHANNEL_ID)
        } else {
            null
        }
        return MknoonRingAlertState(
            // Under DND AudioManager reports SILENT; the user's own ringer choice
            // lives in MODE_RINGER, and DND is judged separately below.
            ringerMode = Settings.Global.getInt(applicationContext.contentResolver, Settings.Global.MODE_RINGER, -1)
                .takeIf { it >= 0 }
                ?: audio?.ringerMode
                ?: AudioManager.RINGER_MODE_NORMAL,
            vibrateWhenRinging = Settings.System.getInt(
                applicationContext.contentResolver,
                Settings.System.VIBRATE_WHEN_RINGING,
                0,
            ) != 0,
            dndFilter = mknoonDndFilter(filter),
            channelBypassesDnd = channel?.canBypassDnd() ?: false,
        )
    }
}

internal class AndroidMknoonRingSoundStarter(context: Context) : MknoonRingSoundStarter {
    private val applicationContext = context.applicationContext

    override fun start(soundUsage: Int): MknoonCallRingtoneSession? {
        val uri = RingtoneManager.getActualDefaultRingtoneUri(
            applicationContext,
            RingtoneManager.TYPE_RINGTONE,
        ) ?: return null
        val player = MediaPlayer()
        return try {
            player.setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(soundUsage)
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

internal class AndroidMknoonRingVibrator(context: Context) : MknoonRingVibrator {
    private val applicationContext = context.applicationContext
    private val vibrator: Vibrator? by lazy {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            applicationContext.getSystemService(VibratorManager::class.java)?.defaultVibrator
        } else {
            applicationContext.getSystemService(Vibrator::class.java)
        }
    }

    @Suppress("DEPRECATION")
    override fun start(): Boolean {
        val vibrator = vibrator?.takeIf { it.hasVibrator() } ?: return false
        val attributes = AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_NOTIFICATION_RINGTONE)
            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
            .build()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            vibrator.vibrate(VibrationEffect.createWaveform(RING_VIBRATION_MS, NO_REPEAT), attributes)
        } else {
            vibrator.vibrate(RING_VIBRATION_MS, NO_REPEAT, attributes)
        }
        return true
    }

    override fun cancel() {
        vibrator?.cancel()
    }

    private companion object {
        // 1 s on / 1 s off for 60 s, played once. That outlives the 45 s invite
        // lifetime, so a normal ring never notices, while a cancel that is lost
        // (its session's stop threw) cannot leave the phone vibrating forever.
        val RING_VIBRATION_MS = LongArray(61) { index -> if (index == 0) 0L else 1000L }
        const val NO_REPEAT = -1
    }
}
