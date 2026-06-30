package com.mknoon.app

import android.content.Context
import android.net.wifi.WifiManager
import android.os.Handler
import android.os.Looper
import android.util.Log
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.net.Inet4Address
import java.net.InetAddress
import java.net.NetworkInterface
import javax.jmdns.JmDNS
import javax.jmdns.ServiceInfo

/**
 * 180: native Android mDNS resolver (jmDNS) for the Pixel→iPhone discovery wall.
 *
 * Upstream bonsoir_android (NsdManager / Android-12+ MdnsServiceTypeClient)
 * intermittently never fires `onServiceFound` for an iPhone's `_mknoon._tcp`
 * service because its `.local`-hostname SRV target's A record isn't reliably
 * attached (`serviceBecomesComplete:FALSE`). jmDNS binds to the WiFi interface
 * and does its own PTR→SRV→TXT→A resolution, holding a `WifiManager.MulticastLock`
 * so the WiFi chip delivers multicast (the Dart `RawDatagramSocket` path was
 * device-falsified — it can't set the outgoing multicast interface). Resolved
 * peers (numeric host + TXT) are streamed to Dart over an EventChannel and feed
 * `BonsoirDiscoveryService._commitResolvedPeer`. Android-only.
 *
 * MethodChannel `mknoon/mdns_resolver` (start/stop) + EventChannel
 * `mknoon/mdns_resolver/events`. All jmDNS I/O runs off the main thread; events
 * are posted back to the main thread (EventChannel requires it).
 */
class MdnsResolver(private val context: Context) : EventChannel.StreamHandler {
    private val mainHandler = Handler(Looper.getMainLooper())

    private var eventSink: EventChannel.EventSink? = null
    private var jmdns: JmDNS? = null
    private var multicastLock: WifiManager.MulticastLock? = null
    private var pollThread: Thread? = null

    @Volatile
    private var running = false

    @Volatile
    private var serviceType: String = "_mknoon._tcp.local."

    private companion object {
        const val TAG = "MdnsResolver"
    }

    fun onMethodCall(
        method: String,
        serviceTypeArg: String?,
        result: MethodChannel.Result,
    ) {
        when (method) {
            "start" -> {
                serviceTypeArg?.let { serviceType = normalizeType(it) }
                start()
                result.success(null)
            }
            "stop" -> {
                stop()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    // jmDNS needs the FULLY-qualified type `_mknoon._tcp.local.`. The Dart side
    // passes bonsoir's `_mknoon._tcp`, so append the `.local.` domain.
    private fun normalizeType(type: String): String {
        val base = type.removeSuffix(".")
        return if (base.endsWith(".local")) "$base." else "$base.local."
    }

    private fun start() {
        if (running) return
        running = true
        val thread = Thread {
            try {
                val wifi = context.applicationContext
                    .getSystemService(Context.WIFI_SERVICE) as WifiManager
                multicastLock = wifi.createMulticastLock("mknoon-jmdns").apply {
                    setReferenceCounted(false)
                    acquire()
                }
                // Binding jmDNS to the WiFi interface IPv4 is what lets multicast
                // SEND+RECEIVE work on Android (the IP_MULTICAST_IF the Dart socket
                // could not set).
                val addr = wifiInetAddress()
                val dns = JmDNS.create(addr, "mknoon-android")
                jmdns = dns
                Log.i(TAG, "jmdns up on $addr, polling $serviceType")
                // Active query loop: dns.list() sends the PTR query and BLOCKS
                // until the SRV/TXT/A are resolved (more reliable on Android than
                // the passive ServiceListener). Re-issued periodically so a peer
                // that appears/heals is picked up (the spec's periodic re-query).
                while (running) {
                    try {
                        // list() returns from the jmDNS cache once resolved, so a
                        // short timeout suffices after the first round. Re-issued
                        // every ~10s to keep peers fresh (under the 30s LocalPeer
                        // TTL) without churning the discoveredPeers stream.
                        val infos = dns.list(serviceType, 2000)
                        for (info in infos) emit(info)
                    } catch (loopError: Exception) {
                        Log.w(TAG, "list error: ${loopError.message}")
                    }
                    if (running) Thread.sleep(8000)
                }
            } catch (error: Exception) {
                Log.e(TAG, "start failed", error)
                mainHandler.post {
                    eventSink?.error("mdns_start_failed", error.message, null)
                }
            }
        }
        pollThread = thread
        thread.isDaemon = true
        thread.start()
    }

    private fun stop() {
        running = false
        pollThread?.interrupt()
        pollThread = null
        val dns = jmdns
        jmdns = null
        Thread {
            try {
                dns?.close()
            } catch (_: Exception) {
            }
            try {
                multicastLock?.let { if (it.isHeld) it.release() }
            } catch (_: Exception) {
            }
            multicastLock = null
        }.also { it.isDaemon = true }.start()
    }

    private fun emit(info: ServiceInfo) {
        val host = info.inet4Addresses.firstOrNull()?.hostAddress ?: return
        val peerId = info.getPropertyString("peerId") ?: return
        val attributes = HashMap<String, String>()
        val names = info.propertyNames
        while (names.hasMoreElements()) {
            val key = names.nextElement()
            info.getPropertyString(key)?.let { attributes[key] = it }
        }
        val payload = hashMapOf<String, Any>(
            "peerId" to peerId,
            "host" to host,
            "port" to info.port,
            "attributes" to attributes,
        )
        mainHandler.post { eventSink?.success(payload) }
    }

    /** The device's WiFi-interface IPv4 (site-local, non-loopback). */
    private fun wifiInetAddress(): InetAddress {
        try {
            for (ni in NetworkInterface.getNetworkInterfaces()) {
                if (!ni.isUp || ni.isLoopback) continue
                for (address in ni.inetAddresses) {
                    if (address is Inet4Address && address.isSiteLocalAddress) {
                        return address
                    }
                }
            }
        } catch (_: Exception) {
        }
        return InetAddress.getLocalHost()
    }

    // EventChannel.StreamHandler
    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }
}
