package com.mknoon.app.call

import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import com.mknoon.app.PushNotificationSettingsLauncher

/**
 * O4 (beta 2026-10-08): without Android 14's full-screen notification access an
 * incoming call cannot turn the screen on; it only rings and posts a collapsed
 * lock-screen notification. Records that a call was affected, so the app can ask
 * the user for the access once it is open again.
 */
internal object FullScreenCallAccess {
    const val READ_METHOD = "readFullScreenCallAccess"
    const val OPEN_METHOD = "openFullScreenCallSettings"
    const val DISMISS_METHOD = "dismissFullScreenCallPrompt"

    private const val PREFS = "mknoon_full_screen_call_access"
    private const val DENIED_CALL_AT = "denied_call_at_ms"
    private const val DISMISSED_AT = "prompt_dismissed_at_ms"

    fun supported(): Boolean = Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE

    fun allowed(context: Context): Boolean =
        !supported() ||
            context.getSystemService(NotificationManager::class.java).canUseFullScreenIntent()

    fun recordDeniedCall(context: Context, nowMs: Long = System.currentTimeMillis()) {
        runCatching { prefs(context).edit().putLong(DENIED_CALL_AT, nowMs).apply() }
    }

    fun dismiss(context: Context, nowMs: Long = System.currentTimeMillis()): Boolean =
        runCatching { prefs(context).edit().putLong(DISMISSED_AT, nowMs).apply() }.isSuccess

    fun read(context: Context): Map<String, Any?> {
        val prefs = runCatching { prefs(context) }.getOrNull()
        return mapOf(
            "supported" to supported(),
            "allowed" to runCatching { allowed(context) }.getOrDefault(true),
            "deniedCallAtMs" to prefs?.longOrNull(DENIED_CALL_AT),
            "dismissedAtMs" to prefs?.longOrNull(DISMISSED_AT),
        )
    }

    /** Opens the system page for this app's full-screen access; falls back to its notification settings. */
    fun openSettings(context: Context): Boolean {
        if (!supported()) return PushNotificationSettingsLauncher.open(context)
        return runCatching {
            context.startActivity(
                Intent(
                    Settings.ACTION_MANAGE_APP_USE_FULL_SCREEN_INTENT,
                    Uri.parse("package:${context.packageName}"),
                ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
            )
            true
        }.getOrElse { PushNotificationSettingsLauncher.open(context) }
    }

    private fun prefs(context: Context) =
        context.applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    private fun android.content.SharedPreferences.longOrNull(key: String): Long? =
        if (contains(key)) getLong(key, 0L) else null
}
