package com.mknoon.app.call

internal const val ONGOING_ACCEPTANCE_TIMEOUT_MS = 1_000L
private const val ONGOING_ACCEPTANCE_POLL_MS = 50L

/**
 * Keep the current foreground id until this call's fresh 505 request is visible
 * through the app's notification API. That API also returns enqueued records:
 * this establishes OS acceptance/order, never a SystemUI or drawn-frame ack.
 *
 * Android cancels the old foreground id inside startForeground(newId). Merely
 * delaying our explicit cancel is insufficient. Both final operations run under
 * the same current-call fence as native admission and incoming publication.
 * Returns whether the foreground type was applied synchronously; a failed or
 * timed-out publication leaves 504 and the call/audio owner intact.
 */
internal fun handOverToOngoingCallNotification(
    foregroundNotificationId: Int,
    startForeground: (notificationId: Int) -> Unit,
    cancel: (notificationId: Int) -> Unit,
    postOngoing: () -> Unit,
    isOngoingAccepted: () -> Boolean,
    withCurrent: (operation: () -> Unit) -> Boolean,
    scheduleCheck: (delayMs: Long, check: () -> Unit) -> Unit,
    nowMs: () -> Long,
): Boolean {
    require(foregroundNotificationId == MknoonCallNotificationFactory.NOTIFICATION_ID ||
        foregroundNotificationId == MknoonCallNotificationFactory.ONGOING_NOTIFICATION_ID)
    var postRequested = false
    val deadline = nowMs() + ONGOING_ACCEPTANCE_TIMEOUT_MS
    if (!withCurrent {
            startForeground(foregroundNotificationId)
            postRequested = nowMs() < deadline && runCatching { postOngoing() }.isSuccess
        }) return false
    if (!postRequested) return true

    fun inspect() {
        if (nowMs() >= deadline || !runCatching { withCurrent {} }.getOrDefault(false)) return
        val accepted = runCatching { isOngoingAccepted() }.getOrElse { return }
        if (nowMs() >= deadline) return
        if (accepted) {
            runCatching {
                withCurrent {
                    if (nowMs() < deadline) {
                        startForeground(MknoonCallNotificationFactory.ONGOING_NOTIFICATION_ID)
                        cancel(MknoonCallNotificationFactory.NOTIFICATION_ID)
                    }
                }
            }
            return
        }
        val remaining = deadline - nowMs()
        if (remaining <= 0) return
        runCatching { scheduleCheck(minOf(ONGOING_ACCEPTANCE_POLL_MS, remaining), ::inspect) }
    }
    inspect()
    return true
}
