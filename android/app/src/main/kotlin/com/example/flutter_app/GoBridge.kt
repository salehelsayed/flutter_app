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

    init {
        methodChannel.setMethodCallHandler(this)
        eventChannel.setStreamHandler(this)

        // Initialize the Go singleton with our event callback
        GoMknoon.initialize(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        val args = call.arguments as? String

        when (call.method) {
            // Identity
            "generateIdentity" -> result.success(GoMknoon.generateIdentity())
            "restoreIdentity" -> result.success(GoMknoon.restoreIdentity(args ?: ""))

            // Crypto
            "mlKemKeygen" -> result.success(GoMknoon.mlKemKeygen())
            "encryptMessage" -> result.success(GoMknoon.encryptMessage(args ?: ""))
            "decryptMessage" -> result.success(GoMknoon.decryptMessage(args ?: ""))
            "signPayload" -> result.success(GoMknoon.signPayload(args ?: ""))
            "verifyPayload" -> result.success(GoMknoon.verifyPayload(args ?: ""))

            // Node lifecycle
            "startNode" -> result.success(GoMknoon.startNode(args ?: ""))
            "stopNode" -> result.success(GoMknoon.stopNode())
            "nodeStatus" -> result.success(GoMknoon.nodeStatus())

            // Rendezvous
            "rendezvousRegister" -> result.success(GoMknoon.rendezvousRegister(args ?: ""))
            "rendezvousDiscover" -> result.success(GoMknoon.rendezvousDiscover(args ?: ""))

            // Peer operations
            "dialPeer" -> result.success(GoMknoon.dialPeer(args ?: ""))
            "disconnectPeer" -> result.success(GoMknoon.disconnectPeer(args ?: ""))
            "sendMessage" -> result.success(GoMknoon.sendMessage(args ?: ""))

            // Inbox
            "inboxStore" -> result.success(GoMknoon.inboxStore(args ?: ""))
            "inboxRetrieve" -> result.success(GoMknoon.inboxRetrieve())
            "inboxRegisterToken" -> result.success(GoMknoon.inboxRegisterToken(args ?: ""))

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
