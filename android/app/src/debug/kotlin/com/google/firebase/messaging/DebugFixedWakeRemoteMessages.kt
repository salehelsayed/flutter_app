package com.google.firebase.messaging

import android.os.Bundle

/**
 * Debug-proof access to the package-private [RemoteMessage] bundle
 * constructor. The device runner injects the exact OS-delivered fixed-wake
 * and rich-canary bundle shapes through the real production service so the
 * proof exercises the production classifier, not a parallel debug path.
 */
fun debugRemoteMessageFromBundle(bundle: Bundle): RemoteMessage =
    RemoteMessage(bundle)
