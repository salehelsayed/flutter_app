package com.mknoon.app

import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import java.util.concurrent.Executors

/**
 * Reports when Android tears down the PREVIOUS default network (SE-42 D27).
 *
 * After Wi-Fi returns mid-call Android keeps the old cellular network alive
 * for its linger period, and a restarted call can still be using it. When
 * that network is finally lost, media dies there; this signal lets the call
 * restart at once instead of waiting for WebRTC to notice.
 *
 * [DefaultNetworkPathMonitor] tells this watcher which default network each
 * announced path belongs to ([pathAnnounced]). The default-network callback
 * does not report a non-default network's loss, so the watcher registers its
 * own narrow callback and acts only on the one previous network. A previous
 * network that becomes the default again, or a later switch, replaces what
 * is watched. One report per watched network, carrying the current epoch.
 */
internal class PreviousNetworkLossWatcher(
    private val connectivity: ConnectivityManager?,
    private val sink: Sink,
    private val dispatch: Dispatch = defaultDispatch(),
) : DefaultNetworkPathMonitor.PathObserver {
    fun interface Sink {
        fun previousPathLost(epoch: Long)
    }

    fun interface Dispatch {
        fun run(work: Runnable)
    }

    private val callback = object : ConnectivityManager.NetworkCallback() {
        override fun onLost(network: Network) = lost(network)
    }

    private val lock = Any()
    private var registered = false
    private var closed = false
    private var current: Network? = null
    private var currentEpoch = 0L
    private var previous: Network? = null

    /** Registers the loss callback. False when unsupported or refused. */
    fun start(): Boolean {
        val manager = connectivity ?: return false
        synchronized(lock) {
            if (closed || registered) return registered
            registered = try {
                manager.registerNetworkCallback(
                    NetworkRequest.Builder()
                        .addCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
                        .build(),
                    callback,
                )
                true
            } catch (_: RuntimeException) {
                false
            }
            return registered
        }
    }

    override fun pathAnnounced(network: Network, epoch: Long) {
        synchronized(lock) {
            if (closed) return
            if (network != current) previous = current
            current = network
            currentEpoch = epoch
        }
    }

    private fun lost(network: Network) {
        val epoch: Long
        synchronized(lock) {
            if (closed || network != previous || network == current || currentEpoch <= 0L) return
            previous = null
            epoch = currentEpoch
        }
        dispatch.run { sink.previousPathLost(epoch) }
    }

    /** Unregisters; later losses report nothing. Idempotent. */
    fun close() {
        val manager = connectivity
        synchronized(lock) {
            if (closed) return
            closed = true
            if (registered && manager != null) {
                try {
                    manager.unregisterNetworkCallback(callback)
                } catch (_: RuntimeException) {
                    // Already gone; nothing else owns this callback.
                }
            }
            registered = false
        }
    }

    companion object {
        const val EVENT = "network:previous_path_lost"

        private fun defaultDispatch(): Dispatch {
            val executor = Executors.newSingleThreadExecutor { runnable ->
                Thread(runnable, "mknoon-net-previous").apply { isDaemon = true }
            }
            return Dispatch { executor.execute(it) }
        }
    }
}
