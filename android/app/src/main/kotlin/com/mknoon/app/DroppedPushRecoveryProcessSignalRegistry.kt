package com.mknoon.app

import android.os.Handler
import android.os.Looper

/**
 * One process-local acceleration route from native recovery ingress to the
 * already-running foreground Flutter owner.
 *
 * The durable native marker and WorkManager request remain authoritative. A
 * missing, replaced, or disposed registration simply drops this hint; a later
 * lifecycle poll or the headless worker still owns recovery. Registrations are
 * identity-qualified so disposal of an older Activity cannot revoke a newer
 * engine, and delivery is marshalled onto Android's platform thread before the
 * MethodChannel is invoked.
 */
internal object DroppedPushRecoveryProcessSignalRegistry {
    internal class Registration internal constructor(
        internal val signal: (Long) -> Unit,
    )

    private val lock = Any()
    private val mainHandler = Handler(Looper.getMainLooper())
    private var current: Registration? = null

    fun register(signal: (Long) -> Unit): Registration {
        val registration = Registration(signal)
        synchronized(lock) {
            current = registration
        }
        return registration
    }

    fun unregister(registration: Registration) {
        synchronized(lock) {
            if (current === registration) {
                current = null
            }
        }
    }

    /** Returns whether a live foreground registration accepted the hint. */
    fun signal(generation: Long): Boolean {
        if (generation <= 0L) return false
        val registration = synchronized(lock) { current } ?: return false
        val delivery = Runnable {
            val stillCurrent = synchronized(lock) { current === registration }
            if (stillCurrent) {
                registration.signal(generation)
            }
        }
        if (Looper.myLooper() == Looper.getMainLooper()) {
            delivery.run()
        } else {
            mainHandler.post(delivery)
        }
        return true
    }
}
