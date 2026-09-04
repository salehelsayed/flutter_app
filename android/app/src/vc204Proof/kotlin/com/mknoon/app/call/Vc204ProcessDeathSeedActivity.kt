package com.mknoon.app.call

import android.Manifest
import android.app.Activity
import android.app.Notification
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Bundle
import android.os.SystemClock
import java.nio.charset.StandardCharsets

/**
 * Disposable proof-only Activity that seeds a real call and leaves the host to
 * background its resident process before the measured `am kill` boundary.
 */
class Vc204ProcessDeathSeedActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        check(intent.action == ACTION)
        val mode = checkNotNull(intent.getStringExtra(EXTRA_MODE))
        check(mode == MODE_RINGING || mode == MODE_ACTIVE)
        Thread({ seedAndBackground(mode) }, "vc204-process-death-seed").start()
    }

    private fun seedAndBackground(mode: String) {
        val appContext = applicationContext
        val runtime = MknoonCallRuntime.get(appContext)
        check(runtime.setCapabilityEnabled(true))
        val payload = payload(if (mode == MODE_RINGING) SLOT_RINGING else SLOT_ACTIVE)
        val presentation = runtime.present(payload)
        if (presentation != MknoonCallPresentationResult.PRESENTED) {
            writeStatus(appContext, "VC204_PROOF_PRESENT_${presentation.name}")
            error("platform presentation did not reach the required coarse state")
        }

        if (mode == MODE_ACTIVE) {
            check(
                appContext.checkSelfPermission(Manifest.permission.RECORD_AUDIO) ==
                    PackageManager.PERMISSION_GRANTED,
            )
            check(runtime.controller.answer(payload.nativeCallId))
            checkNotNull(runtime.controller.attach())
            check(runtime.controller.markAdopted(payload.nativeCallId))
            val beforeAdoption = checkNotNull(runtime.controller.snapshot())
            check(
                runtime.controller.acknowledge(
                    payload.nativeCallId,
                    beforeAdoption.highestSequence,
                    PendingNativeCallAcknowledgement.ADOPTED,
                ),
            )
            check(runtime.controller.activateAudio(payload.nativeCallId))
            check(runtime.controller.snapshot()?.phase == PendingNativeCallPhase.JOURNAL)
        } else {
            val descriptor = checkNotNull(runtime.controller.snapshot())
            check(descriptor.terminalEvent == null)
            check(descriptor.phase == PendingNativeCallPhase.PRE_START)
        }

        awaitForegroundCallNotification(appContext)
        check(
            appContext.stopService(
                Intent(appContext, MknoonCallForegroundService::class.java),
            ),
        )
        awaitNotificationCount(appContext, 0)
        val ready = if (mode == MODE_RINGING) RESULT_RINGING else RESULT_ACTIVE
        writeStatus(appContext, ready)
    }

    private fun awaitNotificationCount(context: Context, expected: Int) {
        val manager = context.getSystemService(NotificationManager::class.java)
        val deadline = SystemClock.elapsedRealtime() + NOTIFICATION_TIMEOUT_MS
        do {
            val count = manager.activeNotifications.count {
                it.id == MknoonCallNotificationFactory.NOTIFICATION_ID &&
                    it.notification.category == Notification.CATEGORY_CALL
            }
            if (count == expected) return
            SystemClock.sleep(POLL_MS)
        } while (SystemClock.elapsedRealtime() < deadline)
        error("call notification did not reach the required coarse state")
    }

    private fun awaitForegroundCallNotification(context: Context) {
        val manager = context.getSystemService(NotificationManager::class.java)
        val deadline = SystemClock.elapsedRealtime() + NOTIFICATION_TIMEOUT_MS
        do {
            val foreground = manager.activeNotifications.any {
                it.id == MknoonCallNotificationFactory.NOTIFICATION_ID &&
                    it.notification.category == Notification.CATEGORY_CALL &&
                    it.notification.flags and Notification.FLAG_FOREGROUND_SERVICE != 0
            }
            if (foreground) return
            SystemClock.sleep(POLL_MS)
        } while (SystemClock.elapsedRealtime() < deadline)
        error("call foreground service did not reach the required coarse state")
    }

    private fun writeStatus(context: Context, status: String) {
        context.openFileOutput(STATUS_FILE, Context.MODE_PRIVATE).use { output ->
            output.write(status.toByteArray(StandardCharsets.US_ASCII))
        }
    }

    private fun payload(slot: Int): CallWakePayload {
        val observedNow = System.currentTimeMillis()
        val opaqueHandle = slot.toString(16).padStart(32, '0')
        val nativeCallId = nativeCallIdFromCallHandle(opaqueHandle)
        return CallWakePayload(
            nativeCallId = nativeCallId,
            callHandle = nativeCallId.toString(),
            wakeHandle = (slot + WAKE_HANDLE_OFFSET).toString(16).padStart(32, '0'),
            receivedAtMs = observedNow,
            expiresAtMs = observedNow + PAYLOAD_LIFETIME_MS,
        )
    }

    companion object {
        const val ACTION = "com.mknoon.app.vc204proof.PROCESS_DEATH_SEED"
        const val EXTRA_MODE = "mode"
        const val MODE_RINGING = "ringing"
        const val MODE_ACTIVE = "active"
        const val RESULT_RINGING = "VC204_PROOF_RINGING_READY"
        const val RESULT_ACTIVE = "VC204_PROOF_ACTIVE_READY"
        const val STATUS_FILE = "vc204-process-death-seed.status"

        private const val SLOT_RINGING = 3
        private const val SLOT_ACTIVE = 9
        private const val WAKE_HANDLE_OFFSET = 10_000
        private const val PAYLOAD_LIFETIME_MS = 40_000L
        private const val NOTIFICATION_TIMEOUT_MS = 8_000L
        private const val POLL_MS = 50L
    }
}
