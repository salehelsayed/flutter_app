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
        BridgeInitialize(self)
    }

    private func runOnBackground(_ work: @escaping () -> Any?, result: @escaping FlutterResult) {
        DispatchQueue.global(qos: .userInitiated).async {
            let value = work()
            DispatchQueue.main.async {
                result(value)
            }
        }
    }

    private func handleMethodCall(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        let args = call.arguments as? String

        switch call.method {
        // Identity
        case "generateIdentity":
            runOnBackground({ BridgeGenerateIdentity() }, result: result)
        case "restoreIdentity":
            runOnBackground({ BridgeRestoreIdentity(args ?? "") }, result: result)

        // Crypto
        case "mlKemKeygen":
            runOnBackground({ BridgeMlKemKeygen() }, result: result)
        case "encryptMessage":
            runOnBackground({ BridgeEncryptMessage(args ?? "") }, result: result)
        case "decryptMessage":
            runOnBackground({ BridgeDecryptMessage(args ?? "") }, result: result)
        case "signPayload":
            runOnBackground({ BridgeSignPayload(args ?? "") }, result: result)
        case "verifyPayload":
            runOnBackground({ BridgeVerifyPayload(args ?? "") }, result: result)

        // Node lifecycle
        case "startNode":
            runOnBackground({ BridgeStartNode(args ?? "") }, result: result)
        case "stopNode":
            runOnBackground({ BridgeStopNode() }, result: result)
        case "nodeStatus":
            runOnBackground({ BridgeNodeStatus() }, result: result)

        // Rendezvous
        case "rendezvousRegister":
            runOnBackground({ BridgeRendezvousRegister(args ?? "") }, result: result)
        case "rendezvousDiscover":
            runOnBackground({ BridgeRendezvousDiscover(args ?? "") }, result: result)

        // Peer operations
        case "dialPeer":
            runOnBackground({ BridgeDialPeer(args ?? "") }, result: result)
        case "disconnectPeer":
            runOnBackground({ BridgeDisconnectPeer(args ?? "") }, result: result)
        case "sendMessage":
            runOnBackground({ BridgeSendMessage(args ?? "") }, result: result)

        // Inbox
        case "inboxStore":
            runOnBackground({ BridgeInboxStore(args ?? "") }, result: result)
        case "inboxRetrieve":
            runOnBackground({ BridgeInboxRetrieve() }, result: result)
        case "inboxRegisterToken":
            runOnBackground({ BridgeInboxRegisterToken(args ?? "") }, result: result)

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

// MARK: - BridgeEventCallback (Go → Swift push events)
extension GoBridge: BridgeEventCallbackProtocol {
    func onEvent(_ jsonString: String?) {
        guard let json = jsonString else { return }
        DispatchQueue.main.async { [weak self] in
            self?.eventSink?(json)
        }
    }
}
#endif
