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
import com.mknoon.app.call.CallPayloadParseResult
import com.mknoon.app.call.CallPayloadParser
import com.mknoon.app.call.CallWakePayload
import com.mknoon.app.call.HeadlessCallAdmissionWorkScheduler
import com.mknoon.app.call.MknoonCallForegroundService
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
        val appDiagnostics = com.mknoon.app.diagnostics.MknoonAppDiagnostics.get(this)
        val appTrace = java.util.UUID.randomUUID().toString()
        appDiagnostics.record("push", "receive", "ok", values = mapOf("direction" to "incoming"), traceId = appTrace)
        if (message.data["w"] == "call") {
            val diagnostics = com.mknoon.app.call.MknoonCallDiagnostics.get(this)
            val trace = message.data["diagnostics"]?.takeIf { it.length <= 128 }?.let { raw ->
                runCatching {
                    val metadata = org.json.JSONObject(raw)
                    metadata.getString("traceId").takeIf {
                        metadata.length() == 2 && metadata.getInt("schemaVersion") == 1 &&
                            com.mknoon.app.call.MknoonCallDiagnosticSpool.uuid(it) &&
                            it.lowercase() != com.mknoon.app.call.MknoonCallDiagnosticSpool.canonical(message.data["c"] ?: "")
                    }
                }.getOrNull()
            }
            val parsed = CallPayloadParser(nowMs = ::callWakeNowMs).parse(
                // Android ArrayMap reuses its iterator entry: copy each pair
                // before filtering so diagnostic removal cannot alter authority.
                entries = message.data.entries.map { it.key to it.value }.filter { it.first != "diagnostics" },
                hasNotification = message.notification != null,
            )
            if (parsed is CallPayloadParseResult.Accepted) {
                appDiagnostics.record("push", "parse", "ok", traceId = appTrace)
                if (trace != null) diagnostics.bind(parsed.payload.callHandle, trace)
                diagnostics.record(parsed.payload.callHandle, "push", "receive", "ok", context = mapOf("role" to "callee"))
                dispatchValidatedCallWake(parsed.payload)
            } else {
                appDiagnostics.record("push", "parse", "rejected", "invalid_payload", traceId = appTrace)
                diagnostics.record(stage = "push", action = "parse", outcome = "rejected", reason = "rejected_payload")
            }
            // `w=call` reserves this namespace even when the rest of the
            // payload is malformed. It must never enter ordinary FlutterFire
            // staging, fixed-wake recovery, or user-visible recovery cards.
            return
        }
        if (!isExactFixedOpaqueWake(message)) {
            appDiagnostics.record("push", "process", "started", traceId = appTrace)
            delegateRichMessageToFlutterFire(message)
            appDiagnostics.record("push", "process", "ok", traceId = appTrace)
            return
        }
        // An exact fixed wake never enters FlutterFire rich staging and never
        // calls super. It is only a durable mailbox signal: a missing current
        // binding is consumed fail-closed with zero marker, card or schedule,
        // and the one generic card is always requested explicitly silent.
        val committed = productionRecoverySeam().recordGenericRecoveryTrigger(
            DroppedPushRecoveryStore.TriggerKind.FIXED_WAKE,
        ) { generation ->
            postRecoveryNotification(generation, silent = true, appTrace = appTrace)
        }
        emitPlan393FixedWakeIngressDiagnostic(committed)
        appDiagnostics.record("push", "commit", if (committed == null) "blocked" else "ok", if (committed == null) "authority_rejected" else "none", mapOf("committed" to (committed != null)), traceId = appTrace)
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

    internal open fun callWakeNowMs(): Long = System.currentTimeMillis()

    internal open fun dispatchValidatedCallWake(payload: CallWakePayload) {
        if (!HeadlessCallAdmissionWorkScheduler(applicationContext).enqueue(payload)) return
        startCallAdmissionForeground(payload)
    }

    /**
     * Enter the call foreground service now, inside the high-priority FCM
     * start window. The headless admission that follows can outlast that
     * window; upgrading an already-foreground service to ringing is always
     * allowed, while starting one from the background then is not.
     */
    private fun startCallAdmissionForeground(payload: CallWakePayload) {
        if (!BuildConfig.ENABLE_ANDROID_NATIVE_CALLS || Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            return
        }
        val intent = Intent(applicationContext, MknoonCallForegroundService::class.java)
            .setAction(MknoonCallForegroundService.ACTION_START_ADMISSION)
            .putExtra(
                MknoonCallForegroundService.EXTRA_NATIVE_CALL_ID,
                payload.nativeCallId.toString(),
            )
        runCatching { applicationContext.startForegroundService(intent) }
    }

    override fun onDeletedMessages() {
        com.mknoon.app.diagnostics.MknoonAppDiagnostics.get(this).record("push", "recover", "pending", "unknown", traceId = java.util.UUID.randomUUID().toString())
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

    private fun postRecoveryNotification(generation: Long, silent: Boolean, appTrace: String = java.util.UUID.randomUUID().toString()) {
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
        // notify returning means a post was requested, not that a banner was seen.
        com.mknoon.app.diagnostics.MknoonAppDiagnostics.get(this).record("push", "presentation", "pending", traceId = appTrace)
    }
}
