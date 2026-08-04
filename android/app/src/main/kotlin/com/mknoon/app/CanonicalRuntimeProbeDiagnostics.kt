package com.mknoon.app

import java.util.concurrent.atomic.AtomicInteger

/** Process-local counters consumed only by the debug H0 receiver. */
internal object CanonicalRuntimeProbeDiagnostics {
    private val activityLaunches = AtomicInteger(0)

    fun recordMainActivityLaunch() {
        activityLaunches.incrementAndGet()
    }

    fun mainActivityLaunchCount(): Int = activityLaunches.get()
}
