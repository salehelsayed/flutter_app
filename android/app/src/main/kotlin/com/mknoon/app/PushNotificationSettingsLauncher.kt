package com.mknoon.app

import android.content.Context
import android.content.Intent
import android.os.Build
import android.provider.Settings

/** Opens the OS page that owns this app's notification permission. */
internal object PushNotificationSettingsLauncher {
    const val METHOD_CHANNEL = "mknoon/push_notification_settings"
    const val OPEN_METHOD = "openAppNotificationSettings"

    private const val LEGACY_APP_NOTIFICATION_SETTINGS =
        "android.settings.APP_NOTIFICATION_SETTINGS"
    private const val LEGACY_APP_PACKAGE_EXTRA = "app_package"
    private const val LEGACY_APP_UID_EXTRA = "app_uid"

    fun open(context: Context): Boolean = runCatching {
        val intent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).apply {
                putExtra(Settings.EXTRA_APP_PACKAGE, context.packageName)
            }
        } else {
            Intent(LEGACY_APP_NOTIFICATION_SETTINGS).apply {
                putExtra(LEGACY_APP_PACKAGE_EXTRA, context.packageName)
                putExtra(LEGACY_APP_UID_EXTRA, context.applicationInfo.uid)
            }
        }
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        context.startActivity(intent)
        true
    }.getOrDefault(false)
}
