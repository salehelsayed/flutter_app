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
        case "encryptContactRequest":
            runOnBackground({ BridgeEncryptContactRequest(args ?? "") }, result: result)
        case "decryptContactRequest":
            runOnBackground({ BridgeDecryptContactRequest(args ?? "") }, result: result)

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

        // Relay
        case "relayReconnect":
            runOnBackground({ BridgeRelayReconnect() }, result: result)
        case "relayProbe":
            runOnBackground({ BridgeRelayProbe(args ?? "") }, result: result)

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
            runOnBackground({ BridgeInboxRetrieveWithParams(args ?? "") }, result: result)
        case "inboxRegisterToken":
            runOnBackground({ BridgeInboxRegisterToken(args ?? "") }, result: result)

        // Media
        case "mediaUpload":
            runOnBackground({ BridgeMediaUpload(args ?? "") }, result: result)
        case "mediaDownload":
            runOnBackground({ BridgeMediaDownload(args ?? "") }, result: result)
        case "mediaDelete":
            runOnBackground({ BridgeMediaDelete(args ?? "") }, result: result)
        case "mediaList":
            runOnBackground({ BridgeMediaList(args ?? "") }, result: result)

        // Profile
        case "profileUpload":
            runOnBackground({ BridgeProfileUpload(args ?? "") }, result: result)
        case "profileDownload":
            runOnBackground({ BridgeProfileDownload(args ?? "") }, result: result)

        // Groups
        case "generateGroupKey":
            runOnBackground({ BridgeGenerateGroupKey() }, result: result)
        case "groupCreate":
            runOnBackground({ BridgeGroupCreate(args ?? "") }, result: result)
        case "groupJoinTopic":
            runOnBackground({ BridgeGroupJoinTopic(args ?? "") }, result: result)
        case "groupLeaveTopic":
            runOnBackground({ BridgeGroupLeaveTopic(args ?? "") }, result: result)
        case "groupPublish":
            runOnBackground({ BridgeGroupPublish(args ?? "") }, result: result)
        case "groupPublishReaction":
            runOnBackground({ BridgeGroupPublishReaction(args ?? "") }, result: result)
        case "groupUpdateConfig":
            runOnBackground({ BridgeGroupUpdateConfig(args ?? "") }, result: result)
        case "groupRotateKey":
            runOnBackground({ BridgeGroupRotateKey(args ?? "") }, result: result)
        case "groupUpdateKey":
            runOnBackground({ BridgeGroupUpdateKey(args ?? "") }, result: result)
        case "groupEncryptMessage":
            runOnBackground({ BridgeGroupEncryptMessage(args ?? "") }, result: result)
        case "groupDecryptMessage":
            runOnBackground({ BridgeGroupDecryptMessage(args ?? "") }, result: result)
        case "groupInboxStore":
            runOnBackground({ BridgeGroupInboxStore(args ?? "") }, result: result)
        case "groupInboxRetrieve":
            runOnBackground({ BridgeGroupInboxRetrieve(args ?? "") }, result: result)
        case "groupInboxRetrieveCursor":
            runOnBackground({ BridgeGroupInboxRetrieveCursor(args ?? "") }, result: result)
        case "groupAcknowledgeRecovery":
            runOnBackground({ BridgeGroupAcknowledgeRecovery() }, result: result)

        default:
            result(FlutterMethodNotImplemented)
        }
    }
}

// MARK: - FlutterStreamHandler (EventChannel)
extension GoBridge: FlutterStreamHandler {
    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        NSLog("[GoBridge] onListen: eventSink registered")
        self.eventSink = events
        return nil
    }

    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        NSLog("[GoBridge] onCancel: eventSink cleared")
        self.eventSink = nil
        return nil
    }
}

// MARK: - BridgeEventCallback (Go → Swift push events)
extension GoBridge: BridgeEventCallbackProtocol {
    func onEvent(_ jsonString: String?) {
        guard let json = jsonString else { return }
        let hasSink = self.eventSink != nil
        if !hasSink {
            NSLog("[GoBridge] onEvent: DROPPED (no sink) event=%@", String(json.prefix(80)))
            return
        }
        DispatchQueue.main.async { [weak self] in
            guard let sink = self?.eventSink else {
                NSLog("[GoBridge] onEvent: DROPPED (sink gone) event=%@", String(json.prefix(80)))
                return
            }
            sink(json)
        }
    }
}
#endif
