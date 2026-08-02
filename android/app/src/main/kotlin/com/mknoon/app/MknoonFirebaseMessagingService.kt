package com.mknoon.app

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import io.flutter.plugins.firebase.messaging.FlutterFirebaseMessagingService

/** App-owned FlutterFire service that durably records deleted FCM batches. */
class MknoonFirebaseMessagingService : FlutterFirebaseMessagingService() {
    companion object {
        internal const val RECOVERY_CHANNEL_ID = "mknoon_dropped_push_recovery"
        internal const val RECOVERY_NOTIFICATION_TAG = "mknoon_dropped_push_recovery"
        internal const val RECOVERY_NOTIFICATION_ID = 329
        internal const val RECOVERY_INTENT_ACTION =
            "com.mknoon.app.action.DROPPED_PUSH_RECOVERY"
        internal const val RECOVERY_GENERATION_EXTRA =
            "com.mknoon.app.extra.DROPPED_PUSH_RECOVERY_GENERATION"
        private const val RECOVERY_PENDING_INTENT_REQUEST_CODE = 329

        internal fun cancelRecoveryNotification(context: android.content.Context) {
            context.getSystemService(NotificationManager::class.java).cancel(
                RECOVERY_NOTIFICATION_TAG,
                RECOVERY_NOTIFICATION_ID,
            )
        }
    }

    override fun onDeletedMessages() {
        super.onDeletedMessages()

        // commit() is intentional: the recovery marker must reach durable
        // storage before any notification API (including permission checks).
        DroppedPushRecoveryStore(this).recordDeletion { generation ->
            // The marker is already committed. Notification failure or denied
            // permission can therefore never erase the recovery request.
            runCatching { postRecoveryNotification(generation) }
        }
    }

    private fun postRecoveryNotification(generation: Long) {
        val manager = getSystemService(NotificationManager::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            manager.createNotificationChannel(
                NotificationChannel(
                    RECOVERY_CHANNEL_ID,
                    "Message recovery",
                    NotificationManager.IMPORTANCE_DEFAULT,
                ).apply {
                    description = "Alerts when messages may be waiting to be recovered"
                    lockscreenVisibility = Notification.VISIBILITY_PRIVATE
                },
            )
        }

        if (
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            return
        }

        val launchIntent = Intent(this, MainActivity::class.java).apply {
            action = RECOVERY_INTENT_ACTION
            flags = Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
            putExtra(RECOVERY_GENERATION_EXTRA, generation)
        }
        val contentIntent = PendingIntent.getActivity(
            this,
            RECOVERY_PENDING_INTENT_REQUEST_CODE,
            launchIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val notificationBuilder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, RECOVERY_CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
        val notification = notificationBuilder
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle("MKnoon")
            .setContentText("Messages may be waiting")
            .setContentIntent(contentIntent)
            .setAutoCancel(false)
            // Replacing the one reserved recovery card must not re-alert for
            // every additional deleted FCM batch while recovery is pending.
            .setOnlyAlertOnce(true)
            .setCategory(Notification.CATEGORY_MESSAGE)
            .setVisibility(Notification.VISIBILITY_PRIVATE)
            .build()

        manager.notify(
            RECOVERY_NOTIFICATION_TAG,
            RECOVERY_NOTIFICATION_ID,
            notification,
        )
    }
}
