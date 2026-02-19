#if canImport(GoMknoon)
import Flutter
import GoMknoon

/// Bridges Flutter MethodChannel/EventChannel to the Go native library.
///
/// MethodChannel `com.mknoon/go_bridge` handles request/response calls.
/// EventChannel `com.mknoon/go_bridge_events` streams push events from Go.
class GoBridge: NSObject {
    private let methodChannel: FlutterMethodChannel
    private let eventChannel: FlutterEventChannel
    private var eventSink: FlutterEventSink?

    init(messenger: FlutterBinaryMessenger) {
        methodChannel = FlutterMethodChannel(
            name: "com.mknoon/go_bridge",
            binaryMessenger: messenger
        )
        eventChannel = FlutterEventChannel(
            name: "com.mknoon/go_bridge_events",
            binaryMessenger: messenger
        )
        super.init()

        methodChannel.setMethodCallHandler(handleMethodCall)
        eventChannel.setStreamHandler(self)

        // Initialize the Go singleton with our event callback
        GoMknoonInitialize(self)
    }

    private func handleMethodCall(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        let args = call.arguments as? String

        switch call.method {
        // Identity
        case "generateIdentity":
            result(GoMknoonGenerateIdentity())
        case "restoreIdentity":
            result(GoMknoonRestoreIdentity(args ?? ""))

        // Crypto
        case "mlKemKeygen":
            result(GoMknoonMlKemKeygen())
        case "encryptMessage":
            result(GoMknoonEncryptMessage(args ?? ""))
        case "decryptMessage":
            result(GoMknoonDecryptMessage(args ?? ""))
        case "signPayload":
            result(GoMknoonSignPayload(args ?? ""))
        case "verifyPayload":
            result(GoMknoonVerifyPayload(args ?? ""))

        // Node lifecycle
        case "startNode":
            result(GoMknoonStartNode(args ?? ""))
        case "stopNode":
            result(GoMknoonStopNode())
        case "nodeStatus":
            result(GoMknoonNodeStatus())

        // Rendezvous
        case "rendezvousRegister":
            result(GoMknoonRendezvousRegister(args ?? ""))
        case "rendezvousDiscover":
            result(GoMknoonRendezvousDiscover(args ?? ""))

        // Peer operations
        case "dialPeer":
            result(GoMknoonDialPeer(args ?? ""))
        case "disconnectPeer":
            result(GoMknoonDisconnectPeer(args ?? ""))
        case "sendMessage":
            result(GoMknoonSendMessage(args ?? ""))

        // Inbox
        case "inboxStore":
            result(GoMknoonInboxStore(args ?? ""))
        case "inboxRetrieve":
            result(GoMknoonInboxRetrieve())
        case "inboxRegisterToken":
            result(GoMknoonInboxRegisterToken(args ?? ""))

        default:
            result(FlutterMethodNotImplemented)
        }
    }
}

// MARK: - FlutterStreamHandler (EventChannel)
extension GoBridge: FlutterStreamHandler {
    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        self.eventSink = events
        return nil
    }

    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        self.eventSink = nil
        return nil
    }
}

// MARK: - GoMknoonEventCallbackProtocol (Go → Swift push events)
extension GoBridge: GoMknoonEventCallbackProtocol {
    func onEvent(_ jsonString: String?) {
        guard let json = jsonString else { return }
        DispatchQueue.main.async { [weak self] in
            self?.eventSink?(json)
        }
    }
}
#endif
