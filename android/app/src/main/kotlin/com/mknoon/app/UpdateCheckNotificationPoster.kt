package com.mknoon.app

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat

/**
 * SE-41 T4a: posts the background update reminder.
 *
 * - Channel `mknoon_app_updates` ("App updates", default importance), the same
 *   values as `mknoonAppUpdatesChannel` in local_notification_support.dart.
 * - Never asks for a permission. Notifications off, POST_NOTIFICATIONS not
 *   granted, or the channel blocked: returns false and posts nothing.
 * - One fixed tag and id per kind, so a reminder replaces the previous one.
 * - The tap is a direct ACTION_VIEW of the built-in Play page. Nothing from a
 *   payload or the version file reaches the intent.
 */
internal object UpdateCheckNotificationPoster {
    const val CHANNEL_ID = "mknoon_app_updates"
    const val CHANNEL_NAME = "App updates"
    const val CHANNEL_DESCRIPTION = "Reminders to install a new version"
    const val TAG = "mknoon_app_update"
    const val PLAY_STORE_URL = "https://play.google.com/store/apps/details?id=com.mknoon.app"
    const val SOFT_ID = 41_001
    const val HARD_ID = 41_002

    fun notificationId(kind: String): Int? = when (kind) {
        "soft" -> SOFT_ID
        "hard" -> HARD_ID
        else -> null
    }

    fun ensureChannel(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = context.getSystemService(NotificationManager::class.java) ?: return
        // Never touch an existing channel: the user may have changed it.
        if (manager.getNotificationChannel(CHANNEL_ID) != null) return
        val channel = NotificationChannel(
            CHANNEL_ID,
            CHANNEL_NAME,
            NotificationManager.IMPORTANCE_DEFAULT,
        ).apply { description = CHANNEL_DESCRIPTION }
        manager.createNotificationChannel(channel)
    }

    /** Reads the current state only; never prompts. */
    fun canPost(context: Context): Boolean {
        if (!NotificationManagerCompat.from(context).areNotificationsEnabled()) return false
        if (
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            return false
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val manager = context.getSystemService(NotificationManager::class.java) ?: return false
            val channel = manager.getNotificationChannel(CHANNEL_ID)
            if (channel != null && channel.importance == NotificationManager.IMPORTANCE_NONE) {
                return false
            }
        }
        return true
    }

    fun post(context: Context, kind: String, title: String, body: String): Boolean {
        val id = notificationId(kind) ?: return false
        if (title.isBlank() || body.isBlank()) return false
        return runCatching {
            ensureChannel(context)
            if (!canPost(context)) return@runCatching false
            val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                Notification.Builder(context, CHANNEL_ID)
            } else {
                @Suppress("DEPRECATION")
                Notification.Builder(context)
            }
            val notification = builder
                .setSmallIcon(R.mipmap.ic_launcher)
                .setContentTitle(title)
                .setContentText(body)
                .setStyle(Notification.BigTextStyle().bigText(body))
                .setAutoCancel(true)
                .setContentIntent(storeIntent(context, id))
                .setVisibility(Notification.VISIBILITY_PRIVATE)
                .build()
            context.getSystemService(NotificationManager::class.java)
                ?.notify(TAG, id, notification)
                ?: return@runCatching false
            true
        }.getOrDefault(false)
    }

    internal fun storeIntent(context: Context, requestCode: Int): PendingIntent {
        val intent = Intent(Intent.ACTION_VIEW, Uri.parse(PLAY_STORE_URL))
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        return PendingIntent.getActivity(
            context,
            requestCode,
            intent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
    }
}
