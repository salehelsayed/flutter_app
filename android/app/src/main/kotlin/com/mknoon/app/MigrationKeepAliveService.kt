package com.mknoon.app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder

/**
 * Foreground service that keeps the app process alive while a Move Account
 * transfer is in flight (old-phone segment upload or new-phone receiver).
 *
 * Without it, backgrounding the app mid-transfer lets Android freeze or kill
 * the process, which stalls the sender's segment POSTs or silences the
 * receiver's local HTTP server until the peer's request budget times out
 * (audit gap G7, background half). Started/stopped from Dart via the
 * `mknoon/migration_keepalive` method channel registered in [MainActivity].
 */
class MigrationKeepAliveService : Service() {
    companion object {
        private const val CHANNEL_ID = "mknoon_account_move"
        private const val NOTIFICATION_ID = 41217

        fun start(context: Context) {
            val intent = Intent(context, MigrationKeepAliveService::class.java)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, MigrationKeepAliveService::class.java))
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val notification = buildNotification()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC,
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
        // The transfer is driven from Dart; if the system kills the service
        // there is nothing useful to restart on its own.
        return START_NOT_STICKY
    }

    private fun buildNotification(): Notification {
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            manager.createNotificationChannel(
                NotificationChannel(
                    CHANNEL_ID,
                    "Account move",
                    NotificationManager.IMPORTANCE_LOW,
                ),
            )
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
        return builder
            .setContentTitle("Moving account")
            .setContentText("Keep both phones on and on the same Wi-Fi.")
            .setSmallIcon(applicationInfo.icon)
            .setOngoing(true)
            .build()
    }
}
