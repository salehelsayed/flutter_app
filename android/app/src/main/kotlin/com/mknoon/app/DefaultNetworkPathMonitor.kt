package com.mknoon.app

import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.os.Build
import java.util.concurrent.ScheduledThreadPoolExecutor
import java.util.concurrent.TimeUnit

/**
 * Watches the process default network and reports each new usable path to the
 * owned Go node as one epoch (SE-42 D27: Wi-Fi to LTE with no "none" between
 * left the node on a stalled relay connection).
 *
 * Identity is the [Network] object the system hands out, so a Wi-Fi to Wi-Fi
 * change counts and a transport-type list is not needed. The first network
 * seen after registration is a seed, not a switch. Only INTERNET + VALIDATED
 * counts as usable; losing a network sends nothing. Delivery runs on the
 * monitor's own thread through [Sender], which the bridge fences by owner
 * token. A path the stopped node refused (`not_started`) stays owed and is
 * re-sent once [nodeStarted] reports a start. The monitor never starts a
 * node or takes runtime ownership.
 *
 * Every state change that makes pending work void bumps a revision. A
 * delivery carries the revision it was scheduled under and sends nothing when
 * it ran too late (its timer had already fired when VALIDATED was lost), and
 * the sender asks [Sender.send]'s `stillCurrent` again right before the Go
 * call, after the runtime-executor hop.
 */
internal class DefaultNetworkPathMonitor(
    private val connectivity: ConnectivityManager?,
    private val sender: Sender,
    private val scheduler: Scheduler = ExecutorScheduler(),
    private val debounceMs: Long = DEFAULT_DEBOUNCE_MS,
    private val pathObserver: PathObserver? = null,
) {
    /**
     * Told which default network each announced path belongs to: the seed
     * as epoch 0, then every delivered epoch. Called outside the lock.
     */
    fun interface PathObserver {
        fun pathAnnounced(network: Network, epoch: Long)
    }

    /**
     * Delivers one epoch. Returns false when the runtime owner is no longer
     * active. [stillCurrent] must be asked right before the Go call: it is
     * false once the path changed again while the epoch waited for the
     * executor, and the epoch must then be dropped. [onAnswer] later receives
     * the node's reason word for this epoch ("none" when it was accepted); it
     * may run on any thread.
     */
    fun interface Sender {
        fun send(
            epoch: Long,
            usable: Boolean,
            stillCurrent: () -> Boolean,
            onAnswer: (reason: String) -> Unit,
        ): Boolean
    }

    /**
     * The owned node reports started. A path it refused as `not_started`
     * while stopped is owed to it now; a newer pending delivery carries it
     * instead. Connectivity never starts a node.
     */
    fun nodeStarted() {
        synchronized(lock) {
            if (closed) return
            startedSinceSend = true
            scheduleRedeliveryLocked()
        }
    }

    fun interface Cancellable {
        fun cancel()
    }

    interface Scheduler {
        fun schedule(delayMs: Long, work: Runnable): Cancellable
        fun shutdown()
    }

    private class ExecutorScheduler : Scheduler {
        private val executor = ScheduledThreadPoolExecutor(1) { runnable ->
            Thread(runnable, THREAD_NAME).apply { isDaemon = true }
        }.apply {
            removeOnCancelPolicy = true
            setKeepAliveTime(30, TimeUnit.SECONDS)
            allowCoreThreadTimeOut(true)
        }

        override fun schedule(delayMs: Long, work: Runnable): Cancellable {
            val future = executor.schedule(work, delayMs, TimeUnit.MILLISECONDS)
            return Cancellable { future.cancel(false) }
        }

        override fun shutdown() {
            executor.shutdownNow()
        }
    }

    private val callback = object : ConnectivityManager.NetworkCallback() {
        override fun onAvailable(network: Network) = available(network)

        override fun onCapabilitiesChanged(network: Network, networkCapabilities: NetworkCapabilities) =
            capabilities(network, networkCapabilities)

        override fun onLost(network: Network) = lost(network)
    }

    /** One default network plus whether it is usable. Equality is the dedupe key. */
    private data class PathKey(val network: Network, val usable: Boolean)

    private val lock = Any()
    private var registered = false
    private var closed = false

    /** The system's current default network; null while there is none. */
    private var current: Network? = null

    /** True until the first capabilities of the first default network are recorded. */
    private var seedPending = true

    /** The path last delivered (or seeded). Repeats of it send nothing. */
    private var announced: PathKey? = null
    private var pendingKey: PathKey? = null
    private var pendingDelivery: Cancellable? = null
    private var epoch = 0L

    /** Bumped whenever pending work becomes void; a delivery is valid only under its own revision. */
    private var revision = 0L

    /** The node answered not_started for the latest epoch, so that path is still owed. */
    private var awaitingStart = false

    /** A node start was reported after the latest epoch was sent. */
    private var startedSinceSend = false

    /** Registers the default-network callback. False when unsupported or refused. */
    fun start(): Boolean {
        val manager = connectivity ?: return false
        synchronized(lock) {
            if (closed || registered) return registered
            registered = try {
                manager.registerDefaultNetworkCallback(callback)
                true
            } catch (_: RuntimeException) {
                false
            }
            return registered
        }
    }

    /** Unregisters and drops any pending delivery. Idempotent. */
    fun close() {
        val manager = connectivity
        synchronized(lock) {
            if (closed) return
            closed = true
            cancelPendingLocked()
            if (registered && manager != null) {
                try {
                    manager.unregisterNetworkCallback(callback)
                } catch (_: RuntimeException) {
                    // Already gone; nothing else owns this callback.
                }
            }
            registered = false
        }
        scheduler.shutdown()
    }

    /** A new default network identity. Its usability arrives with its capabilities. */
    private fun available(network: Network) {
        synchronized(lock) {
            if (closed || network == current) return
            current = network
            cancelPendingLocked()
        }
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            // Before API 26 the follow-up onCapabilitiesChanged is not
            // guaranteed, so read the capabilities once ourselves.
            val snapshot = try {
                connectivity?.getNetworkCapabilities(network)
            } catch (_: RuntimeException) {
                null
            }
            if (snapshot != null) capabilities(network, snapshot)
        }
    }

    private fun capabilities(network: Network, capabilities: NetworkCapabilities) {
        var seeded = false
        synchronized(lock) {
            if (closed || network != current) return
            val key = PathKey(network, isUsable(capabilities))
            if (seedPending) {
                seedPending = false
                announced = key
                seeded = true
            } else if (!key.usable) {
                // Loss-only: nothing to deliver, and the same network counts
                // as a new path once it validates again.
                cancelPendingLocked()
                if (announced?.network == network) announced = null
            } else if (key != pendingKey && (key != announced || owedNowLocked())) {
                cancelPendingLocked()
                scheduleDeliveryLocked(key)
            }
        }
        if (seeded) pathObserver?.pathAnnounced(network, 0L)
    }

    /** Only the current default's loss matters; a stale loss of an old network is noise. */
    private fun lost(network: Network) {
        synchronized(lock) {
            if (closed || network != current) return
            current = null
            announced = null
            cancelPendingLocked()
        }
    }

    private fun deliver(key: PathKey, scheduledUnder: Long) {
        val epochToSend: Long
        val sentUnder: Long
        synchronized(lock) {
            if (pendingKey == key) {
                pendingKey = null
                pendingDelivery = null
            }
            // A timer that had already fired when its work became void
            // (VALIDATED lost, a new default, close) arrives here with a
            // stale revision and must neither announce nor send.
            if (closed || scheduledUnder != revision || key.network != current ||
                (announced == key && !owedNowLocked())
            ) {
                return
            }
            announced = key
            epochToSend = nextEpochLocked()
            sentUnder = revision
        }
        pathObserver?.pathAnnounced(key.network, epochToSend)
        // Off the system callback thread and outside the lock; the sender
        // hops onto the runtime owner's executor and drops stale owners.
        sender.send(
            epochToSend,
            key.usable,
            stillCurrent = { stillCurrent(key, sentUnder) },
            onAnswer = { reason -> answered(epochToSend, reason) },
        )
    }

    /**
     * Asked by the sender right before the Go call. A delivery the path
     * outran withdraws its announcement, so the same network's revalidation
     * is a fresh path and not a repeat.
     */
    private fun stillCurrent(key: PathKey, sentUnder: Long): Boolean {
        synchronized(lock) {
            if (!closed && sentUnder == revision) return true
            if (announced == key) announced = null
            return false
        }
    }

    /** Go's answer for one epoch. Only the latest epoch's `not_started` matters. */
    private fun answered(sentEpoch: Long, reason: String) {
        synchronized(lock) {
            if (closed || sentEpoch != epoch || reason != REASON_NOT_STARTED) return
            awaitingStart = true
            scheduleRedeliveryLocked()
        }
    }

    private fun nextEpochLocked(): Long {
        epoch += 1
        awaitingStart = false
        startedSinceSend = false
        return epoch
    }

    /** A refused path is owed once the node has started since that send. */
    private fun owedNowLocked(): Boolean = awaitingStart && startedSinceSend

    /** Schedules the owed path as a fresh epoch unless a newer delivery already carries it. */
    private fun scheduleRedeliveryLocked() {
        if (!owedNowLocked() || pendingKey != null) return
        val key = announced ?: return
        if (key.network != current || !key.usable) return
        scheduleDeliveryLocked(key)
    }

    private fun scheduleDeliveryLocked(key: PathKey) {
        val scheduledUnder = revision
        pendingKey = key
        pendingDelivery = scheduler.schedule(debounceMs) { deliver(key, scheduledUnder) }
    }

    /** Voids the pending delivery, including one whose timer already fired. */
    private fun cancelPendingLocked() {
        revision += 1
        pendingDelivery?.cancel()
        pendingDelivery = null
        pendingKey = null
    }

    companion object {
        const val DEFAULT_DEBOUNCE_MS = 150L
        const val THREAD_NAME = "mknoon-net-path"

        /** Go's answer for an epoch that reached a node which is not running. */
        const val REASON_NOT_STARTED = "not_started"

        fun isUsable(capabilities: NetworkCapabilities): Boolean =
            capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET) &&
                capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED)
    }
}
