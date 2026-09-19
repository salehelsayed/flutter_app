package com.mknoon.app.call

internal const val MKNOON_CALL_FOREGROUND_AUDIO_TAG = "MknoonCallForegroundAudio"

internal fun formatMknoonCallForegroundAudioApplied(applied: Boolean): String =
    "CALL_ANDROID_FOREGROUND_AUDIO outcome=${if (applied) "applied" else "failed"}"

/** Observes the applied microphone foreground type, not startService submission.
 * Diagnostic failures must not change the platform operation's outcome. */
internal fun applyMknoonCallForegroundAudio(
    startForeground: () -> Unit,
    reportApplied: (Boolean) -> Unit,
) {
    try {
        startForeground()
    } catch (failure: Exception) {
        runCatching { reportApplied(false) }
        throw failure
    }
    runCatching { reportApplied(true) }
}
