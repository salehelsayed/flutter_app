package com.google.firebase.messaging

import android.os.Bundle

/**
 * Test-only access to the package-private [RemoteMessage] bundle constructor.
 * FCM's builder cannot express notification-bearing payloads, so the exact
 * fixed-wake classifier tests build the OS-delivered bundle shape directly.
 */
fun remoteMessageFromBundleForTest(bundle: Bundle): RemoteMessage =
    RemoteMessage(bundle)
