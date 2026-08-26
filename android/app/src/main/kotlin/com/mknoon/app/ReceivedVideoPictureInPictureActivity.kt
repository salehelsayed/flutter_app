package com.mknoon.app

import android.app.Activity
import android.app.PictureInPictureParams
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.res.Configuration
import android.graphics.Color
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.media.MediaPlayer
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.util.Rational
import android.view.ViewGroup
import android.widget.FrameLayout
import android.widget.VideoView

/**
 * Classifies an Android PiP exit from lifecycle evidence, never elapsed time.
 *
 * Android reports `isInPictureInPictureMode=false` for both a user return and
 * a SystemUI close. A return is accepted only after the Activity is both
 * resumed and focused after having entered PiP. Stop/destroy evidence and the
 * bounded no-evidence fallback conservatively classify the exit as close.
 */
internal class PictureInPictureExitClassifier {
    private var enteredPictureInPicture = false
    private var awaitingExit = false
    private var resumedAfterPictureInPicture = false
    private var focusedAfterPictureInPicture = false
    private var stoppedAfterPictureInPicture = false
    private var destroyedAfterPictureInPicture = false
    private var terminalReason: String? = null

    fun onPictureInPictureModeChanged(inPictureInPicture: Boolean): String? {
        if (terminalReason != null) return null
        if (inPictureInPicture) {
            enteredPictureInPicture = true
            awaitingExit = false
            resumedAfterPictureInPicture = false
            focusedAfterPictureInPicture = false
            stoppedAfterPictureInPicture = false
            destroyedAfterPictureInPicture = false
            return null
        }
        if (!enteredPictureInPicture) return null
        awaitingExit = true
        if (stoppedAfterPictureInPicture || destroyedAfterPictureInPicture) {
            return settle(SYSTEM_CLOSE)
        }
        return settleReturnIfConfirmed()
    }

    fun onResume(): String? {
        if (!enteredPictureInPicture || terminalReason != null) return null
        resumedAfterPictureInPicture = true
        return settleReturnIfConfirmed()
    }

    fun onPause(): String? {
        if (!enteredPictureInPicture || terminalReason != null) return null
        resumedAfterPictureInPicture = false
        focusedAfterPictureInPicture = false
        return null
    }

    fun onWindowFocusChanged(hasFocus: Boolean): String? {
        if (!enteredPictureInPicture || terminalReason != null) return null
        focusedAfterPictureInPicture = hasFocus
        return settleReturnIfConfirmed()
    }

    fun onStop(): String? {
        if (!enteredPictureInPicture || terminalReason != null) return null
        stoppedAfterPictureInPicture = true
        return if (awaitingExit) settle(SYSTEM_CLOSE) else null
    }

    fun onDestroy(): String? {
        if (!enteredPictureInPicture || terminalReason != null) return null
        destroyedAfterPictureInPicture = true
        return if (awaitingExit) settle(SYSTEM_CLOSE) else null
    }

    fun onFallbackTimeout(): String? =
        if (awaitingExit) settle(SYSTEM_CLOSE) else null

    private fun settleReturnIfConfirmed(): String? =
        if (
            awaitingExit &&
            resumedAfterPictureInPicture &&
            focusedAfterPictureInPicture
        ) {
            settle(SYSTEM_RETURN)
        } else {
            null
        }

    private fun settle(reason: String): String? {
        if (terminalReason != null) return null
        terminalReason = reason
        return reason
    }

    private companion object {
        const val SYSTEM_RETURN = "system_return"
        const val SYSTEM_CLOSE = "system_close"
    }
}

internal enum class PictureInPictureAudioFocusAction {
    NONE,
    PAUSE,
    RESUME,
    STOP,
}

/**
 * Preserves playback ownership across reversible audio-focus changes.
 *
 * Duckable focus leaves playback state unchanged. A plain transient loss
 * pauses only media that was actively playing and owns exactly one resume on
 * gain. A noisy output change pauses active media and always clears that
 * transient resume ownership so unplugging cannot later restart on a speaker.
 * Already-paused or completed media never restarts, while permanent focus loss
 * remains terminal.
 */
internal class PictureInPictureAudioFocusPolicy {
    private var resumeAfterTransientLoss = false

    fun onAudioFocusChange(change: Int, isPlaying: Boolean): PictureInPictureAudioFocusAction =
        when (change) {
            AudioManager.AUDIOFOCUS_LOSS -> {
                resumeAfterTransientLoss = false
                PictureInPictureAudioFocusAction.STOP
            }
            AudioManager.AUDIOFOCUS_LOSS_TRANSIENT -> {
                if (isPlaying) {
                    resumeAfterTransientLoss = true
                    PictureInPictureAudioFocusAction.PAUSE
                } else {
                    PictureInPictureAudioFocusAction.NONE
                }
            }
            AudioManager.AUDIOFOCUS_GAIN -> {
                if (resumeAfterTransientLoss) {
                    resumeAfterTransientLoss = false
                    PictureInPictureAudioFocusAction.RESUME
                } else {
                    PictureInPictureAudioFocusAction.NONE
                }
            }
            else -> PictureInPictureAudioFocusAction.NONE
        }

    fun onAudioBecomingNoisy(isPlaying: Boolean): PictureInPictureAudioFocusAction {
        resumeAfterTransientLoss = false
        return if (isPlaying) {
            PictureInPictureAudioFocusAction.PAUSE
        } else {
            PictureInPictureAudioFocusAction.NONE
        }
    }

    fun reset() {
        resumeAfterTransientLoss = false
    }
}

/** Dedicated video-only Android PiP owner. It never hosts Flutter or chat UI. */
class ReceivedVideoPictureInPictureActivity : Activity() {
    private val registry = PictureInPictureProcessRegistry.registry
    private val mainHandler = Handler(Looper.getMainLooper())
    private val exitClassifier = PictureInPictureExitClassifier()
    private val audioFocusPolicy = PictureInPictureAudioFocusPolicy()
    private val audioManager by lazy {
        getSystemService(Context.AUDIO_SERVICE) as AudioManager
    }

    private var request: PictureInPictureSessionRequest? = null
    private var videoView: VideoView? = null
    private var mediaPlayer: MediaPlayer? = null
    private var audioFocusRequest: AudioFocusRequest? = null
    private var audioBecomingNoisyReceiverRegistered = false
    private var prepared = false
    private var activated = false
    private var enteredPictureInPicture = false
    private var terminating = false
    private var playbackReleased = false
    private var lastKnownPositionMs = 0
    private var discoveredDurationMs: Int? = null

    private val checkpointRunnable = object : Runnable {
        override fun run() {
            if (terminating || !activated) return
            val current = request ?: return
            val observedPositionMs = safeCurrentPosition()
            lastKnownPositionMs = maxOf(lastKnownPositionMs, observedPositionMs)
            registry.checkpoint(
                session = current.session,
                attachment = current.attachment,
                observedPositionMs = lastKnownPositionMs,
                durationMs = discoveredDurationMs,
            )
            mainHandler.postDelayed(this, CHECKPOINT_INTERVAL_MS)
        }
    }

    private val settleUnconfirmedSystemExitRunnable = Runnable {
        settleSystemExit(exitClassifier.onFallbackTimeout())
    }

    private val audioFocusListener = AudioManager.OnAudioFocusChangeListener { change ->
        when (audioFocusPolicy.onAudioFocusChange(change, safeIsPlaying())) {
            PictureInPictureAudioFocusAction.NONE -> Unit
            PictureInPictureAudioFocusAction.PAUSE -> pauseForTransientFocusLoss()
            PictureInPictureAudioFocusAction.RESUME -> resumeAfterTransientFocusLoss()
            PictureInPictureAudioFocusAction.STOP -> stopNativePlayback("interrupted")
        }
    }

    private val audioBecomingNoisyReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (intent?.action != AudioManager.ACTION_AUDIO_BECOMING_NOISY) return
            if (
                audioFocusPolicy.onAudioBecomingNoisy(isPlayingForNoisyOutput()) ==
                PictureInPictureAudioFocusAction.PAUSE
            ) {
                pauseForNoisyOutputChange()
            }
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.decorView.setBackgroundColor(Color.BLACK)

        val sessionId = intent?.getStringExtra(PictureInPictureHandler.SESSION_EXTRA)
        val current = sessionId?.let { registry.current(sessionId) }
        if (savedInstanceState != null || current == null) {
            if (current != null) {
                registry.terminate(
                    session = current.session,
                    attachment = current.attachment,
                    state = "stopped",
                    reason = "activity_destroyed",
                    observedPositionMs = current.positionMs,
                    durationMs = current.durationMs,
                )
            }
            finishAndRemoveTask()
            return
        }
        if (!registry.attach(current.session, current.attachment, this)) {
            finishAndRemoveTask()
            return
        }
        request = current
        lastKnownPositionMs = current.positionMs

        val container = FrameLayout(this).apply {
            setBackgroundColor(Color.BLACK)
            importantForAccessibility = FrameLayout.IMPORTANT_FOR_ACCESSIBILITY_NO_HIDE_DESCENDANTS
        }
        val video = VideoView(this).apply {
            layoutParams = FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT,
            )
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                setAudioFocusRequest(AudioManager.AUDIOFOCUS_NONE)
            }
            setOnPreparedListener { player -> onPlayerPrepared(current, player) }
            setOnCompletionListener { onPlaybackCompleted(current) }
            setOnErrorListener { _, _, _ ->
                failPlayback(current)
                true
            }
            setVideoPath(current.path)
        }
        videoView = video
        container.addView(video)
        setContentView(container)
    }

    private fun onPlayerPrepared(
        current: PictureInPictureSessionRequest,
        player: MediaPlayer,
    ) {
        if (terminating || request?.session != current.session) return
        mediaPlayer = player
        player.isLooping = false
        val nativeDuration = player.duration.takeIf { it > 0 }
        discoveredDurationMs = nativeDuration ?: current.durationMs
        val targetPositionMs = if (discoveredDurationMs == null) {
            current.positionMs
        } else {
            current.positionMs.coerceAtMost(discoveredDurationMs!!)
        }

        var seekSettled = false
        fun settleSeek() {
            if (seekSettled || terminating) return
            seekSettled = true
            prepared = true
            lastKnownPositionMs = maxOf(lastKnownPositionMs, safeCurrentPosition())
            registry.nativeReady(
                session = current.session,
                attachment = current.attachment,
                positionMs = lastKnownPositionMs,
                durationMs = discoveredDurationMs,
            )
        }

        player.setOnSeekCompleteListener { settleSeek() }
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                player.seekTo(targetPositionMs.toLong(), MediaPlayer.SEEK_CLOSEST)
            } else {
                @Suppress("DEPRECATION")
                player.seekTo(targetPositionMs)
            }
            // Some platform decoders do not callback for an already-settled
            // zero seek. This fallback only marks readiness; it never starts.
            mainHandler.postDelayed({ settleSeek() }, SEEK_CALLBACK_FALLBACK_MS)
        } catch (_: RuntimeException) {
            failPlayback(current)
        }
    }

    /** Called only after Dart reauthorizes the nativeReady session. */
    internal fun activateNativePlayback(): Boolean {
        val current = request ?: return false
        if (terminating || !prepared || activated) return false
        if (!requestAudioFocus()) {
            stopWithTerminal(
                current = current,
                state = "stopped",
                reason = "interrupted",
            )
            return false
        }
        if (!registerAudioBecomingNoisyReceiver()) {
            stopWithTerminal(
                current = current,
                state = "stopped",
                reason = "interrupted",
            )
            return false
        }
        return try {
            val width = mediaPlayer?.videoWidth?.takeIf { it > 0 } ?: 16
            val height = mediaPlayer?.videoHeight?.takeIf { it > 0 } ?: 9
            val params = PictureInPictureParams.Builder()
                .setAspectRatio(safeAspectRatio(width, height))
                .build()
            setPictureInPictureParams(params)
            videoView?.start()
            activated = true
            lastKnownPositionMs = maxOf(lastKnownPositionMs, safeCurrentPosition())
            mainHandler.post(checkpointRunnable)
            if (!enterPictureInPictureMode(params)) {
                stopWithTerminal(
                    current = current,
                    state = "failed",
                    reason = "playback_error",
                )
                false
            } else {
                true
            }
        } catch (_: RuntimeException) {
            stopWithTerminal(
                current = current,
                state = "failed",
                reason = "playback_error",
            )
            false
        }
    }

    override fun onPictureInPictureModeChanged(
        isInPictureInPictureMode: Boolean,
        newConfig: Configuration,
    ) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
        val current = request ?: return
        val exitReason = exitClassifier.onPictureInPictureModeChanged(
            isInPictureInPictureMode,
        )
        if (isInPictureInPictureMode && !enteredPictureInPicture && !terminating) {
            enteredPictureInPicture = true
            registry.active(current.session, current.attachment)
        } else if (!isInPictureInPictureMode && enteredPictureInPicture && !terminating) {
            // Android reports false for both expand/return and SystemUI close.
            // Lifecycle evidence classifies the exit. The timeout is a bounded
            // fail-closed escape hatch and never invents a system return.
            mainHandler.removeCallbacks(settleUnconfirmedSystemExitRunnable)
            mainHandler.postDelayed(
                settleUnconfirmedSystemExitRunnable,
                SYSTEM_EXIT_FALLBACK_MS,
            )
            settleSystemExit(exitReason)
        }
    }

    override fun onResume() {
        super.onResume()
        settleSystemExit(exitClassifier.onResume())
    }

    override fun onPause() {
        settleSystemExit(exitClassifier.onPause())
        super.onPause()
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        settleSystemExit(exitClassifier.onWindowFocusChanged(hasFocus))
    }

    override fun onStop() {
        super.onStop()
        settleSystemExit(exitClassifier.onStop())
    }

    private fun settleSystemExit(reason: String?) {
        if (reason == null || terminating) return
        mainHandler.removeCallbacks(settleUnconfirmedSystemExitRunnable)
        stopNativePlayback(reason)
    }

    internal fun stopNativePlayback(reason: String): Boolean {
        val current = request ?: return false
        if (terminating) return false
        val state = when (reason) {
            "system_return" -> "restoring"
            "playback_error" -> "failed"
            "completed" -> "completed"
            else -> "stopped"
        }
        return stopWithTerminal(current = current, state = state, reason = reason)
    }

    private fun stopWithTerminal(
        current: PictureInPictureSessionRequest,
        state: String,
        reason: String,
        completed: Boolean = false,
    ): Boolean {
        if (terminating) return false
        terminating = true
        mainHandler.removeCallbacks(settleUnconfirmedSystemExitRunnable)

        val observedPositionMs = if (completed) 0 else safeCurrentPosition()
        lastKnownPositionMs = if (completed) {
            0
        } else {
            maxOf(lastKnownPositionMs, observedPositionMs)
        }
        // This ordering is the physical-device SystemUI-close regression fix:
        // freeze the monotonic checkpoint before VideoView can return zero.
        mainHandler.removeCallbacks(checkpointRunnable)
        releasePlayback()
        val emitted = registry.terminate(
            session = current.session,
            attachment = current.attachment,
            state = state,
            reason = reason,
            observedPositionMs = lastKnownPositionMs,
            durationMs = discoveredDurationMs,
        )
        finishAndRemoveTask()
        return emitted
    }

    private fun onPlaybackCompleted(current: PictureInPictureSessionRequest) {
        if (!terminating) {
            stopWithTerminal(
                current = current,
                state = "completed",
                reason = "completed",
                completed = true,
            )
        }
    }

    private fun failPlayback(current: PictureInPictureSessionRequest) {
        if (!terminating) {
            stopWithTerminal(
                current = current,
                state = "failed",
                reason = "playback_error",
            )
        }
    }

    private fun requestAudioFocus(): Boolean {
        val attributes = AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_MEDIA)
            .setContentType(AudioAttributes.CONTENT_TYPE_MOVIE)
            .build()
        val request = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN)
            .setAudioAttributes(attributes)
            .setWillPauseWhenDucked(false)
            .setOnAudioFocusChangeListener(audioFocusListener, mainHandler)
            .build()
        audioFocusRequest = request
        return audioManager.requestAudioFocus(request) == AudioManager.AUDIOFOCUS_REQUEST_GRANTED
    }

    private fun releasePlayback() {
        if (playbackReleased) return
        playbackReleased = true
        unregisterAudioBecomingNoisyReceiver()
        audioFocusPolicy.reset()
        try {
            videoView?.stopPlayback()
        } catch (_: RuntimeException) {
            // The terminal fence has already frozen the only durable value.
        }
        audioFocusRequest?.let {
            try {
                audioManager.abandonAudioFocusRequest(it)
            } catch (_: RuntimeException) {
                // Best-effort platform cleanup after ownership already ended.
            }
        }
        audioFocusRequest = null
        mediaPlayer = null
        videoView = null
    }

    private fun registerAudioBecomingNoisyReceiver(): Boolean {
        if (audioBecomingNoisyReceiverRegistered) return true
        return try {
            val filter = IntentFilter(AudioManager.ACTION_AUDIO_BECOMING_NOISY)
            // This is a system-only broadcast and is exempt from Android 14's
            // runtime receiver export-flag requirement.
            @Suppress("DEPRECATION", "UnspecifiedRegisterReceiverFlag")
            registerReceiver(audioBecomingNoisyReceiver, filter)
            audioBecomingNoisyReceiverRegistered = true
            true
        } catch (_: RuntimeException) {
            false
        }
    }

    private fun unregisterAudioBecomingNoisyReceiver() {
        if (!audioBecomingNoisyReceiverRegistered) return
        audioBecomingNoisyReceiverRegistered = false
        try {
            unregisterReceiver(audioBecomingNoisyReceiver)
        } catch (_: RuntimeException) {
            // Playback ownership is already fenced; cleanup is best-effort.
        }
    }

    private fun pauseForTransientFocusLoss() {
        if (terminating) return
        try {
            videoView?.pause()
        } catch (_: RuntimeException) {
            // A reversible focus callback must not terminate owned playback.
        }
    }

    private fun pauseForNoisyOutputChange() {
        if (terminating) return
        try {
            videoView?.pause()
        } catch (_: RuntimeException) {
            // Output is about to move to a speaker. Fail terminally if a safe
            // pause cannot be confirmed instead of allowing audio to spill.
            stopNativePlayback("interrupted")
        }
    }

    private fun resumeAfterTransientFocusLoss() {
        if (terminating || !activated) return
        try {
            videoView?.start()
        } catch (_: RuntimeException) {
            stopNativePlayback("playback_error")
        }
    }

    private fun safeCurrentPosition(): Int = try {
        videoView?.currentPosition?.coerceAtLeast(0) ?: 0
    } catch (_: RuntimeException) {
        0
    }

    private fun safeIsPlaying(): Boolean = try {
        videoView?.isPlaying == true
    } catch (_: RuntimeException) {
        false
    }

    private fun isPlayingForNoisyOutput(): Boolean {
        val video = videoView ?: return false
        return try {
            video.isPlaying
        } catch (_: RuntimeException) {
            // On an output-unplug boundary, uncertainty must fail toward pause.
            true
        }
    }

    private fun safeAspectRatio(width: Int, height: Int): Rational {
        val boundedWidth = width.coerceIn(1, 10_000)
        val boundedHeight = height.coerceIn(1, 10_000)
        val ratio = boundedWidth.toDouble() / boundedHeight.toDouble()
        return when {
            ratio < MIN_PIP_ASPECT_RATIO -> Rational(1, 2)
            ratio > MAX_PIP_ASPECT_RATIO -> Rational(2, 1)
            else -> Rational(boundedWidth, boundedHeight)
        }
    }

    override fun onDestroy() {
        mainHandler.removeCallbacks(settleUnconfirmedSystemExitRunnable)
        mainHandler.removeCallbacks(checkpointRunnable)
        if (!terminating) {
            val reason = exitClassifier.onDestroy() ?: "activity_destroyed"
            stopNativePlayback(reason)
        }
        registry.detach(this)
        releasePlayback()
        super.onDestroy()
    }

    companion object {
        private const val CHECKPOINT_INTERVAL_MS = 100L
        private const val SEEK_CALLBACK_FALLBACK_MS = 250L
        private const val SYSTEM_EXIT_FALLBACK_MS = 2_000L
        private const val MIN_PIP_ASPECT_RATIO = 0.5
        private const val MAX_PIP_ASPECT_RATIO = 2.0
    }
}
