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
    private var pendingEvents: [String] = []
    private let pendingEventsLock = NSLock()
    private let maxPendingEvents = 256

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

    func handleMethodCall(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
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
        case "confirmDirectMessage":
            runOnBackground({ BridgeConfirmDirectMessage(args ?? "") }, result: result)

        // Inbox
        case "inboxStore":
            runOnBackground({ BridgeInboxStore(args ?? "") }, result: result)
        case "inboxRetrieve":
            runOnBackground({ BridgeInboxRetrieveWithParams(args ?? "") }, result: result)
        case "inboxRetrievePending":
            runOnBackground({ BridgeInboxRetrievePendingWithParams(args ?? "") }, result: result)
        case "inboxAck":
            runOnBackground({ BridgeInboxAck(args ?? "") }, result: result)
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
        case "blobKeygen":
            runOnBackground({ BridgeBlobKeygen(nil) }, result: result)
        case "blobEncrypt":
            runOnBackground({ BridgeBlobEncrypt(args ?? "") }, result: result)
        case "blobDecrypt":
            runOnBackground({ BridgeBlobDecrypt(args ?? "") }, result: result)

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
        case "groupSendReliable":
            runOnBackground({ BridgeGroupSendReliable(args ?? "") }, result: result)
        case "groupPublishReaction":
            runOnBackground({ BridgeGroupPublishReaction(args ?? "") }, result: result)
        case "groupUpdateConfig":
            runOnBackground({ BridgeGroupUpdateConfig(args ?? "") }, result: result)
        case "groupGenerateNextKey":
            runOnBackground({ BridgeGroupGenerateNextKey(args ?? "") }, result: result)
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

        // Background task (Dart-initiated)
        case "bgBegin":
            // Called synchronously on main thread — do NOT use runOnBackground.
            // UIApplication.beginBackgroundTask must run on main thread and return before
            // the app finishes transitioning to background.
            var taskId = UIBackgroundTaskIdentifier.invalid
            taskId = UIApplication.shared.beginBackgroundTask(withName: "mknoon.sendMessage") {
                // Expiration handler: iOS is about to force-suspend.
                NSLog("[GoBridge] BG_TASK_EXPIRED — ending task before suspension")
                if taskId != .invalid {
                    UIApplication.shared.endBackgroundTask(taskId)
                    taskId = .invalid
                }
            }
            if taskId == .invalid {
                NSLog("[GoBridge] BG_TASK_REFUSED — OS would not grant background time")
                result("")  // empty string signals Dart that no task was granted
            } else {
                NSLog("[GoBridge] bgBegin: taskId=%@", String(taskId.rawValue))
                result(String(taskId.rawValue))  // return raw handle as string
            }

        case "bgEnd":
            // Called synchronously on main thread — do NOT use runOnBackground.
            // args is a JSON string: {"taskId": "12345"} — because _CmdSpec('bgEnd', true)
            // serializes the payload map via jsonEncode before passing to invokeMethod.
            if let jsonStr = call.arguments as? String,
               let data = jsonStr.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let taskIdStr = json["taskId"] as? String,
               let rawVal = Int(taskIdStr),
               rawVal != UIBackgroundTaskIdentifier.invalid.rawValue {
                let taskId = UIBackgroundTaskIdentifier(rawValue: rawVal)
                UIApplication.shared.endBackgroundTask(taskId)
            }
            result(nil)

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
        flushPendingEvents()
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
            bufferEvent(json, reason: "no sink")
            return
        }
        DispatchQueue.main.async { [weak self] in
            guard let sink = self?.eventSink else {
                self?.bufferEvent(json, reason: "sink gone")
                return
            }
            sink(json)
        }
    }

    private func bufferEvent(_ json: String, reason: String) {
        pendingEventsLock.lock()
        if pendingEvents.count >= maxPendingEvents {
            pendingEvents.removeFirst()
            NSLog(
                "[GoBridge] bufferEvent: dropped oldest buffered event to keep queue <= %d",
                maxPendingEvents
            )
        }
        pendingEvents.append(json)
        pendingEventsLock.unlock()
        NSLog("[GoBridge] onEvent: BUFFERED (%@) event=%@", reason, String(json.prefix(80)))
    }

    private func flushPendingEvents() {
        DispatchQueue.main.async { [weak self] in
            guard let self, let sink = self.eventSink else { return }
            self.pendingEventsLock.lock()
            let snapshot = self.pendingEvents
            self.pendingEvents.removeAll(keepingCapacity: true)
            self.pendingEventsLock.unlock()
            if snapshot.isEmpty { return }
            NSLog("[GoBridge] flushPendingEvents: replaying %d buffered event(s)", snapshot.count)
            snapshot.forEach { sink($0) }
        }
    }
}
#endif
