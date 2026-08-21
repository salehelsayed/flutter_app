package com.mknoon.app

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import com.google.firebase.messaging.RemoteMessage
import io.flutter.plugins.firebase.messaging.FlutterFirebaseMessagingService

/** App-owned FlutterFire service that durably records deleted FCM batches. */
open class MknoonFirebaseMessagingService : FlutterFirebaseMessagingService() {
    companion object {
        internal const val RECOVERY_CHANNEL_ID = "mknoon_dropped_push_recovery"
        internal const val RECOVERY_NOTIFICATION_TAG = "mknoon_dropped_push_recovery"
        internal const val RECOVERY_NOTIFICATION_ID = 329
        internal const val RECOVERY_INTENT_ACTION =
            "com.mknoon.app.action.DROPPED_PUSH_RECOVERY"
        internal const val RECOVERY_GENERATION_EXTRA =
            "com.mknoon.app.extra.DROPPED_PUSH_RECOVERY_GENERATION"
        private const val RECOVERY_PENDING_INTENT_REQUEST_CODE = 329

        // NotificationCompat's silent-group convention: a grouped child with
        // summary-only alert behavior never sounds even on an audible channel.
        internal const val SILENT_RECOVERY_GROUP_KEY = "silent"

        /**
         * Exact fixed classifier: data-only, exactly the two String entries
         * `v == "1"` and `w == "1"`. No numeric coercion, subset matching,
         * trimming, aliases or unknown app-owned fields. Send-side transport
         * hints (priority, TTL, collapse key) are deliberately not consulted:
         * they are not stable content authority after FCM delivery/downgrade.
         */
        internal fun isExactFixedOpaqueWake(message: RemoteMessage): Boolean {
            if (message.notification != null) return false
            val data = message.data
            return data.size == 2 && data["v"] == "1" && data["w"] == "1"
        }

        internal fun cancelRecoveryNotification(context: android.content.Context) {
            context.getSystemService(NotificationManager::class.java).cancel(
                RECOVERY_NOTIFICATION_TAG,
                RECOVERY_NOTIFICATION_ID,
            )
        }

        internal fun ensureRecoveryNotificationChannel(context: android.content.Context) {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
            context.getSystemService(NotificationManager::class.java)
                .createNotificationChannel(
                    NotificationChannel(
                        RECOVERY_CHANNEL_ID,
                        context.getString(R.string.dropped_push_recovery_channel_name),
                        NotificationManager.IMPORTANCE_DEFAULT,
                    ).apply {
                        description = context.getString(
                            R.string.dropped_push_recovery_channel_description,
                        )
                        lockscreenVisibility = Notification.VISIBILITY_PRIVATE
                    },
                )
        }
    }

    override fun onMessageReceived(message: RemoteMessage) {
        if (!isExactFixedOpaqueWake(message)) {
            delegateRichMessageToFlutterFire(message)
            return
        }
        // An exact fixed wake never enters FlutterFire rich staging and never
        // calls super. It is only a durable mailbox signal: a missing current
        // binding is consumed fail-closed with zero marker, card or schedule,
        // and the one generic card is always requested explicitly silent.
        val committed = productionRecoverySeam().recordGenericRecoveryTrigger(
            DroppedPushRecoveryStore.TriggerKind.FIXED_WAKE,
        ) { generation ->
            postRecoveryNotification(generation, silent = true)
        }
        emitPlan393FixedWakeIngressDiagnostic(committed)
        committed?.let { signalWarmRuntimeRecovery(it.generation) }
    }

    /** Privacy-safe proof emitted only by the real production FCM ingress. */
    private fun emitPlan393FixedWakeIngressDiagnostic(
        committed: DroppedPushRecoveryStore.PendingRecovery?,
    ) {
        if (
            (
                applicationInfo.flags and
                    android.content.pm.ApplicationInfo.FLAG_DEBUGGABLE
                ) == 0
        ) {
            return
        }
        android.util.Log.i(
            DroppedPushRecoveryBridge.PLAN393_DIAGNOSTIC_TAG,
            org.json.JSONObject()
                .put("event", "plan393_fixed_wake_ingress")
                .put("pid", android.os.Process.myPid())
                .put("generation", committed?.generation)
                .put("triggerKind", committed?.triggerKind?.name)
                .put("genericMayHaveAlerted", committed?.genericMayHaveAlerted)
                .put("genericCardTag", RECOVERY_NOTIFICATION_TAG)
                .put("genericCardId", RECOVERY_NOTIFICATION_ID)
                .put("genericCardRequestedSilent", true)
                .put("richFlutterFireDelegated", false)
                .put("productionIngressInvoked", true)
                .toString(),
        )
    }

    /**
     * The one FlutterFire delegation seam. Every nonfixed/rich message enters
     * incumbent FlutterFire background staging through exactly this call.
     */
    internal open fun delegateRichMessageToFlutterFire(message: RemoteMessage) {
        super.onMessageReceived(message)
    }

    override fun onDeletedMessages() {
        super.onDeletedMessages()

        // The shared seam keeps scheduling and notification publication inside
        // the store's serialized afterCommit boundary. The marker is therefore
        // durable before either side effect and cannot race an acknowledgement.
        // The deletion branch retains its incumbent possibly-audible attempt.
        val committed = productionRecoverySeam().recordGenericRecoveryTrigger(
            DroppedPushRecoveryStore.TriggerKind.DELETED_BATCH,
        ) { generation ->
            postRecoveryNotification(generation, silent = false)
        }
        committed?.let { signalWarmRuntimeRecovery(it.generation) }
    }

    private fun productionRecoverySeam(): ProductionDeletedBatchRecovery =
        ProductionDeletedBatchRecovery(
            context = this,
            scheduleRecovery = ::scheduleRecovery,
            scheduleFixedWakeRecovery = ::scheduleFixedWakeRecovery,
        )

    internal open fun scheduleRecovery(snapshot: DroppedPushRecoveryStore.PendingRecovery) {
        DroppedPushRecoveryWorkScheduler(this).enqueueDeletedBatch(snapshot)
    }

    internal open fun scheduleFixedWakeRecovery(
        snapshot: DroppedPushRecoveryStore.PendingRecovery,
    ) {
        DroppedPushRecoveryWorkScheduler(this).enqueueFixedWake(snapshot)
    }

    /**
     * Best-effort acceleration for a foreground engine in this process. The
     * marker and scheduled worker stay authoritative when no engine is alive.
     */
    internal open fun signalWarmRuntimeRecovery(generation: Long) {
        DroppedPushRecoveryProcessSignalRegistry.signal(generation)
    }

    private fun postRecoveryNotification(generation: Long, silent: Boolean) {
        val manager = getSystemService(NotificationManager::class.java)
        ensureRecoveryNotificationChannel(this)

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
        notificationBuilder
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(getString(R.string.dropped_push_recovery_notification_title))
            .setContentText(getString(R.string.dropped_push_recovery_notification_body))
            .setContentIntent(contentIntent)
            .setAutoCancel(false)
            // Replacing the one reserved recovery card must not re-alert for
            // every additional deleted FCM batch while recovery is pending.
            .setOnlyAlertOnce(true)
            .setCategory(Notification.CATEGORY_MESSAGE)
            .setVisibility(Notification.VISIBILITY_PRIVATE)
        if (silent) {
            // Explicitly silent in every crash/retry/order: no identity-free
            // fixed wake may spend the one sound a canonical event still owns.
            // Pre-O the builder carries no sound/vibrate defaults; O+ assigns
            // the compat silent group so channel importance cannot re-alert.
            @Suppress("DEPRECATION")
            notificationBuilder
                .setSound(null)
                .setVibrate(null)
                .setDefaults(0)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                notificationBuilder
                    .setGroup(SILENT_RECOVERY_GROUP_KEY)
                    .setGroupAlertBehavior(Notification.GROUP_ALERT_SUMMARY)
            }
        }

        manager.notify(
            RECOVERY_NOTIFICATION_TAG,
            RECOVERY_NOTIFICATION_ID,
            notificationBuilder.build(),
        )
    }
}
