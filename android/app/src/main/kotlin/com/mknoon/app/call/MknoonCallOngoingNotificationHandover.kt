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
    diagnostic: (event: String, error: Throwable?) -> Unit = { _, _ -> },
): Boolean {
    fun report(event: String, error: Throwable? = null) {
        // Diagnostics must not change call ownership or failure handling.
        runCatching { diagnostic(event, error) }
    }
    val validId = foregroundNotificationId == MknoonCallNotificationFactory.NOTIFICATION_ID ||
        foregroundNotificationId == MknoonCallNotificationFactory.ONGOING_NOTIFICATION_ID
    if (!validId) report("post_skipped reason=invalid_foreground_id id=$foregroundNotificationId")
    require(validId)
    report("begin foreground_id=$foregroundNotificationId timeout_ms=$ONGOING_ACCEPTANCE_TIMEOUT_MS")
    var postRequested = false
    val deadline = nowMs() + ONGOING_ACCEPTANCE_TIMEOUT_MS
    val initialApplied = try {
        withCurrent {
            report("foreground_requested id=$foregroundNotificationId")
            startForeground(foregroundNotificationId)
            val remaining = deadline - nowMs()
            report("foreground_returned id=$foregroundNotificationId remaining_ms=$remaining")
            if (remaining <= 0L) {
                report("post_skipped reason=deadline_before_post remaining_ms=$remaining")
            } else {
                report("post_requested id=505")
                postRequested = runCatching { postOngoing() }
                    .onSuccess { report("post_returned id=505") }
                    .onFailure { report("post_failed", it) }
                    .isSuccess
            }
        }
    } catch (error: Throwable) {
        report("post_skipped reason=initial_foreground_or_owner_failed", error)
        throw error
    }
    if (!initialApplied) {
        report("post_skipped reason=owner_not_current")
        return false
    }
    if (!postRequested) return true

    fun inspect() {
        if (nowMs() >= deadline) {
            report("acceptance_timeout phase=before_query")
            return
        }
        val current = runCatching { withCurrent {} }.getOrElse {
            report("acceptance_stopped reason=owner_check_failed", it)
            return
        }
        if (!current) {
            report("acceptance_stopped reason=owner_lost")
            return
        }
        val accepted = runCatching { isOngoingAccepted() }.getOrElse {
            report("acceptance_query_failed", it)
            return
        }
        if (nowMs() >= deadline) {
            report("acceptance_timeout phase=after_query")
            return
        }
        if (accepted) {
            report("record_visible id=505")
            runCatching {
                val promoted = withCurrent {
                    if (nowMs() < deadline) {
                        report("foreground_requested id=505")
                        startForeground(MknoonCallNotificationFactory.ONGOING_NOTIFICATION_ID)
                        report("foreground_returned id=505")
                        report("cancel_requested id=504")
                        cancel(MknoonCallNotificationFactory.NOTIFICATION_ID)
                        report("cancel_returned id=504")
                    } else {
                        report("promotion_skipped reason=deadline")
                    }
                }
                if (!promoted) report("promotion_skipped reason=owner_lost")
            }.onFailure { report("promotion_failed", it) }
            return
        }
        val remaining = deadline - nowMs()
        if (remaining <= 0) {
            report("acceptance_timeout phase=before_schedule")
            return
        }
        val delay = minOf(ONGOING_ACCEPTANCE_POLL_MS, remaining)
        report("acceptance_pending retry_ms=$delay remaining_ms=$remaining")
        runCatching { scheduleCheck(delay, ::inspect) }
            .onFailure { report("acceptance_schedule_failed", it) }
    }
    inspect()
    return true
}
