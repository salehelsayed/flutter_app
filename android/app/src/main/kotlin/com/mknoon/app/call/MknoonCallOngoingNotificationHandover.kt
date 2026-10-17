package com.mknoon.app.call

/**
 * Moves the call's foreground service from the ringing notification to the
 * quiet ongoing one. The service takes the ongoing id first, so it is never
 * without a foreground notification, and only then is the ringing id (and its
 * heads-up) removed. A refused start leaves the ringing notification in place.
 */
internal fun handOverToOngoingCallNotification(
    startForeground: (notificationId: Int) -> Unit,
    cancel: (notificationId: Int) -> Unit,
) {
    startForeground(MknoonCallNotificationFactory.ONGOING_NOTIFICATION_ID)
    cancel(MknoonCallNotificationFactory.NOTIFICATION_ID)
}
