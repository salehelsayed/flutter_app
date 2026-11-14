package com.mknoon.app.call

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel

/**
 * Read-only OS inputs for the video quality policy (U3j-QN).
 *
 * Nothing is registered or read until Dart listens, and Dart listens only
 * while video is enabled. Each event is one complete snapshot map:
 * `networkClass` ("unknown"/"wifi"/"cellular"/"other"), `lowDataMode` and
 * `metered` (Boolean or null when unknown) and `thermalState`
 * ("unknown"/"nominal"/"elevated"/"serious"/"critical"). It uses the
 * ACCESS_NETWORK_STATE permission the app already declares; nothing new.
 */
internal class MknoonCallVideoQualityEnvironment(
    private val context: Context,
    messenger: BinaryMessenger?,
) : EventChannel.StreamHandler {
    companion object {
        const val EVENT_CHANNEL = "mknoon/call_video_quality/events"
    }

    private val eventChannel = messenger?.let { EventChannel(it, EVENT_CHANNEL) }
    private val main = Handler(Looper.getMainLooper())
    private var observation: Observation? = null
    private var disposed = false

    init {
        eventChannel?.setStreamHandler(this)
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        if (disposed || events == null) return
        observation?.stop()
        observation = Observation(context.applicationContext, main, events).also { it.start() }
    }

    override fun onCancel(arguments: Any?) {
        observation?.stop()
        observation = null
    }

    fun dispose() {
        if (disposed) return
        disposed = true
        onCancel(null)
        eventChannel?.setStreamHandler(null)
    }

    /** One listen's registrations. After [stop] no callback can emit. */
    private class Observation(
        private val context: Context,
        private val main: Handler,
        private val events: EventChannel.EventSink,
    ) {
        private val connectivity =
            context.getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager
        private val power = context.getSystemService(Context.POWER_SERVICE) as? PowerManager
        @Volatile private var active = false
        private var network = MknoonVideoNetworkInputs.UNKNOWN
        private var networkCallback: ConnectivityManager.NetworkCallback? = null
        private var dataSaverReceiver: BroadcastReceiver? = null
        private var thermalListener: PowerManager.OnThermalStatusChangedListener? = null

        fun start() {
            active = true
            registerNetwork()
            registerDataSaver()
            registerThermal()
            emit()
        }

        fun stop() {
            if (!active) return
            active = false
            networkCallback?.let { cb -> runCatching { connectivity?.unregisterNetworkCallback(cb) } }
            networkCallback = null
            dataSaverReceiver?.let { r -> runCatching { context.unregisterReceiver(r) } }
            dataSaverReceiver = null
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                thermalListener?.let { l -> runCatching { power?.removeThermalStatusListener(l) } }
            }
            thermalListener = null
        }

        private fun registerNetwork() {
            val manager = connectivity ?: return
            val callback = object : ConnectivityManager.NetworkCallback() {
                override fun onCapabilitiesChanged(n: Network, caps: NetworkCapabilities) {
                    val inputs = MknoonVideoNetworkInputs(
                        wifi = caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI),
                        cellular = caps.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR),
                        vpn = caps.hasTransport(NetworkCapabilities.TRANSPORT_VPN),
                        notMetered = caps.hasCapability(
                            NetworkCapabilities.NET_CAPABILITY_NOT_METERED,
                        ) || temporarilyNotMetered(caps),
                    )
                    main.post { if (active) { network = inputs; emit() } }
                }

                override fun onLost(n: Network) {
                    main.post { if (active) { network = MknoonVideoNetworkInputs.UNKNOWN; emit() } }
                }
            }
            if (runCatching { manager.registerDefaultNetworkCallback(callback) }.isSuccess) {
                networkCallback = callback
            }
        }

        private fun temporarilyNotMetered(caps: NetworkCapabilities): Boolean =
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.R &&
                caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_TEMPORARILY_NOT_METERED)

        private fun registerDataSaver() {
            val receiver = object : BroadcastReceiver() {
                override fun onReceive(c: Context?, intent: Intent?) {
                    main.post { if (active) emit() }
                }
            }
            val filter = IntentFilter(ConnectivityManager.ACTION_RESTRICT_BACKGROUND_CHANGED)
            val ok = runCatching {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    context.registerReceiver(receiver, filter, Context.RECEIVER_NOT_EXPORTED)
                } else {
                    context.registerReceiver(receiver, filter)
                }
            }.isSuccess
            if (ok) dataSaverReceiver = receiver
        }

        private fun registerThermal() {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return
            val manager = power ?: return
            val listener = PowerManager.OnThermalStatusChangedListener {
                main.post { if (active) emit() }
            }
            if (runCatching { manager.addThermalStatusListener(listener) }.isSuccess) {
                thermalListener = listener
            }
        }

        private fun emit() {
            if (!active) return
            val dataSaver = runCatching { connectivity?.restrictBackgroundStatus }.getOrNull()
            val thermal = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                runCatching { power?.currentThermalStatus }.getOrNull()
            } else {
                null
            }
            events.success(
                MknoonVideoQualitySnapshot.build(network, dataSaver, thermal),
            )
        }
    }
}

/** Raw transport facts for the current default network. */
internal data class MknoonVideoNetworkInputs(
    val wifi: Boolean,
    val cellular: Boolean,
    val vpn: Boolean,
    val notMetered: Boolean?,
) {
    companion object {
        val UNKNOWN = MknoonVideoNetworkInputs(wifi = false, cellular = false, vpn = false, notMetered = null)
    }
}

/** Pure mapping from raw OS values to the Dart snapshot map. */
internal object MknoonVideoQualitySnapshot {
    fun build(network: MknoonVideoNetworkInputs, dataSaver: Int?, thermal: Int?): Map<String, Any?> =
        mapOf(
            "networkClass" to networkClass(network),
            "lowDataMode" to lowDataMode(dataSaver),
            "metered" to metered(network),
            "thermalState" to thermalState(thermal),
        )

    /** A VPN hides its underlying transport, so it stays unknown. */
    fun networkClass(network: MknoonVideoNetworkInputs): String = when {
        network.notMetered == null -> "unknown"
        network.vpn -> "unknown"
        network.wifi -> "wifi"
        network.cellular -> "cellular"
        else -> "other"
    }

    fun metered(network: MknoonVideoNetworkInputs): Boolean? = network.notMetered?.let { !it }

    /** Data Saver on counts even when this app is allowlisted. */
    fun lowDataMode(status: Int?): Boolean? = when (status) {
        ConnectivityManager.RESTRICT_BACKGROUND_STATUS_DISABLED -> false
        ConnectivityManager.RESTRICT_BACKGROUND_STATUS_WHITELISTED -> true
        ConnectivityManager.RESTRICT_BACKGROUND_STATUS_ENABLED -> true
        else -> null
    }

    fun thermalState(status: Int?): String = when (status) {
        PowerManager.THERMAL_STATUS_NONE -> "nominal"
        PowerManager.THERMAL_STATUS_LIGHT, PowerManager.THERMAL_STATUS_MODERATE -> "elevated"
        PowerManager.THERMAL_STATUS_SEVERE -> "serious"
        PowerManager.THERMAL_STATUS_CRITICAL,
        PowerManager.THERMAL_STATUS_EMERGENCY,
        PowerManager.THERMAL_STATUS_SHUTDOWN,
        -> "critical"
        else -> "unknown"
    }
}
