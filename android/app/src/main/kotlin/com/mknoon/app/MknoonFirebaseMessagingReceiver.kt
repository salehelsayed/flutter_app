package com.mknoon.app

import android.content.Context
import android.content.Intent
import com.google.firebase.messaging.RemoteMessage
import io.flutter.plugins.firebase.messaging.FlutterFirebaseMessagingReceiver

/**
 * Owns FlutterFire's raw C2DM broadcast boundary.
 *
 * Firebase delivers the same data message through both its messaging service
 * and the plugin's broadcast receiver. The app-owned service consumes the
 * exact identity-free fixed wake; this receiver must therefore suppress that
 * same exact shape before FlutterFire starts a Dart background isolate. Every
 * other payload remains delegated to FlutterFire unchanged.
 */
open class MknoonFirebaseMessagingReceiver : FlutterFirebaseMessagingReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val reservedCallWake = intent.extras?.let { extras ->
            runCatching { RemoteMessage(extras).data["w"] == "call" }
                .getOrDefault(false)
        } ?: false
        if (reservedCallWake) return

        val fixedWake = intent.extras?.let { extras ->
            runCatching {
                MknoonFirebaseMessagingService.isExactFixedOpaqueWake(
                    RemoteMessage(extras),
                )
            }.getOrDefault(false)
        } ?: false
        if (fixedWake) return

        delegateRichMessageToFlutterFire(context, intent)
    }

    internal open fun delegateRichMessageToFlutterFire(
        context: Context,
        intent: Intent,
    ) {
        super.onReceive(context, intent)
    }
}
