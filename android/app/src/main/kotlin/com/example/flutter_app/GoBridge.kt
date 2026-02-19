package com.example.flutter_app

import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import gomknoon.Bridge as GoMknoon
import gomknoon.EventCallback as GoEventCallback

/**
 * Bridges Flutter MethodChannel/EventChannel to the Go native library.
 *
 * MethodChannel `com.mknoon/go_bridge` handles request/response calls.
 * EventChannel `com.mknoon/go_bridge_events` streams push events from Go.
 */
class GoBridge(flutterEngine: FlutterEngine) : MethodChannel.MethodCallHandler,
    EventChannel.StreamHandler, GoEventCallback {

    private val methodChannel = MethodChannel(
        flutterEngine.dartExecutor.binaryMessenger,
        "com.mknoon/go_bridge"
    )
    private val eventChannel = EventChannel(
        flutterEngine.dartExecutor.binaryMessenger,
        "com.mknoon/go_bridge_events"
    )
    private var eventSink: EventChannel.EventSink? = null
    private val executor = java.util.concurrent.Executors.newCachedThreadPool()
    private val mainHandler = android.os.Handler(android.os.Looper.getMainLooper())

    init {
        methodChannel.setMethodCallHandler(this)
        eventChannel.setStreamHandler(this)

        // Initialize the Go singleton with our event callback
        GoMknoon.initialize(this)
    }

    private fun runOnBackground(work: () -> Any?, result: MethodChannel.Result) {
        executor.execute {
            try {
                val value = work()
                mainHandler.post { result.success(value) }
            } catch (e: Exception) {
                mainHandler.post { result.error("GO_ERROR", e.message, null) }
            }
        }
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        val args = call.arguments as? String

        when (call.method) {
            // Identity
            "generateIdentity" -> runOnBackground({ GoMknoon.generateIdentity() }, result)
            "restoreIdentity" -> runOnBackground({ GoMknoon.restoreIdentity(args ?: "") }, result)

            // Crypto
            "mlKemKeygen" -> runOnBackground({ GoMknoon.mlKemKeygen() }, result)
            "encryptMessage" -> runOnBackground({ GoMknoon.encryptMessage(args ?: "") }, result)
            "decryptMessage" -> runOnBackground({ GoMknoon.decryptMessage(args ?: "") }, result)
            "signPayload" -> runOnBackground({ GoMknoon.signPayload(args ?: "") }, result)
            "verifyPayload" -> runOnBackground({ GoMknoon.verifyPayload(args ?: "") }, result)

            // Node lifecycle
            "startNode" -> runOnBackground({ GoMknoon.startNode(args ?: "") }, result)
            "stopNode" -> runOnBackground({ GoMknoon.stopNode() }, result)
            "nodeStatus" -> runOnBackground({ GoMknoon.nodeStatus() }, result)

            // Rendezvous
            "rendezvousRegister" -> runOnBackground({ GoMknoon.rendezvousRegister(args ?: "") }, result)
            "rendezvousDiscover" -> runOnBackground({ GoMknoon.rendezvousDiscover(args ?: "") }, result)

            // Peer operations
            "dialPeer" -> runOnBackground({ GoMknoon.dialPeer(args ?: "") }, result)
            "disconnectPeer" -> runOnBackground({ GoMknoon.disconnectPeer(args ?: "") }, result)
            "sendMessage" -> runOnBackground({ GoMknoon.sendMessage(args ?: "") }, result)

            // Inbox
            "inboxStore" -> runOnBackground({ GoMknoon.inboxStore(args ?: "") }, result)
            "inboxRetrieve" -> runOnBackground({ GoMknoon.inboxRetrieve() }, result)
            "inboxRegisterToken" -> runOnBackground({ GoMknoon.inboxRegisterToken(args ?: "") }, result)

            else -> result.notImplemented()
        }
    }

    // EventChannel.StreamHandler
    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }

    // GoEventCallback — Go → Kotlin push events
    override fun onEvent(jsonString: String?) {
        jsonString?.let { json ->
            android.os.Handler(android.os.Looper.getMainLooper()).post {
                eventSink?.success(json)
            }
        }
    }
}
