#if canImport(GoMknoon)
import Flutter
import GoMknoon
import UIKit

/// Small UIApplication seam used by the process-wide critical-task registry.
/// Tests inject a deterministic manager instead of asking the simulator OS for
/// background execution time.
protocol BackgroundTaskManaging: AnyObject {
    func beginBackgroundTask(
        withName taskName: String?,
        expirationHandler handler: (() -> Void)?
    ) -> UIBackgroundTaskIdentifier

    func endBackgroundTask(_ identifier: UIBackgroundTaskIdentifier)

    var backgroundTimeRemaining: TimeInterval { get }
}

extension UIApplication: BackgroundTaskManaging {}

/// Owns every live Dart-initiated iOS background task in this process.
///
/// A task ID is removed while holding `lock` before the underlying manager is
/// asked to end it. Consequently, native expiration and a concurrent/late Dart
/// `bgEnd` have exactly one winner. Tests inject an isolated registry; the
/// default bridge initializer uses the UIApplication-backed shared registry.
final class CriticalTaskRegistry {
    static let shared = CriticalTaskRegistry(
        backgroundTaskManager: UIApplication.shared
    )

    private final class PendingTask {
        var identifier: UIBackgroundTaskIdentifier?
        var expirationRequested = false
        var completed = false
    }

    private let backgroundTaskManager: BackgroundTaskManaging
    private let processIdentifier: () -> Int32
    private let eventLogger: (String) -> Void
    private let lock = NSLock()
    private var liveTasks: [Int: PendingTask] = [:]

    init(
        backgroundTaskManager: BackgroundTaskManaging,
        processIdentifier: @escaping () -> Int32 = {
            ProcessInfo.processInfo.processIdentifier
        },
        eventLogger: @escaping (String) -> Void = { message in
            logGroupMediaNativeProof(message)
        }
    ) {
        self.backgroundTaskManager = backgroundTaskManager
        self.processIdentifier = processIdentifier
        self.eventLogger = eventLogger
    }

    var backgroundTimeRemaining: TimeInterval {
        backgroundTaskManager.backgroundTimeRemaining
    }

    @discardableResult
    func begin(withName taskName: String) -> UIBackgroundTaskIdentifier {
        let pendingTask = PendingTask()
        let taskId = backgroundTaskManager.beginBackgroundTask(
            withName: taskName
        ) { [weak self, pendingTask] in
            self?.expire(pendingTask)
        }

        var expirationWonBeforeRegistration = false
        lock.lock()
        pendingTask.identifier = taskId
        if taskId == .invalid {
            pendingTask.completed = true
        } else if pendingTask.expirationRequested {
            pendingTask.completed = true
            expirationWonBeforeRegistration = true
        } else {
            liveTasks[taskId.rawValue] = pendingTask
        }
        lock.unlock()

        if expirationWonBeforeRegistration {
            eventLogger(
                "[GoBridge] BG_TASK_EXPIRED — ending task before suspension " +
                    "pid=\(processIdentifier())"
            )
            backgroundTaskManager.endBackgroundTask(taskId)
        }
        return taskId
    }

    func end(_ taskId: UIBackgroundTaskIdentifier) {
        guard taskId != .invalid else { return }

        var ownsTerminalEnd = false
        lock.lock()
        if let pendingTask = liveTasks.removeValue(forKey: taskId.rawValue),
           !pendingTask.completed {
            pendingTask.completed = true
            ownsTerminalEnd = true
        }
        lock.unlock()

        if ownsTerminalEnd {
            backgroundTaskManager.endBackgroundTask(taskId)
            eventLogger(
                "[GoBridge] BG_TASK_ENDED taskId=\(taskId.rawValue) " +
                    "terminal=normal pid=\(processIdentifier())"
            )
        }
    }

    private func expire(_ pendingTask: PendingTask) {
        var taskIdToEnd: UIBackgroundTaskIdentifier?
        lock.lock()
        if !pendingTask.completed {
            if let taskId = pendingTask.identifier {
                if taskId != .invalid,
                   liveTasks[taskId.rawValue] === pendingTask {
                    liveTasks.removeValue(forKey: taskId.rawValue)
                    pendingTask.completed = true
                    taskIdToEnd = taskId
                }
            } else {
                // Defend against a manager invoking expiration before its begin
                // call returns the task ID. `begin` completes the terminal end.
                pendingTask.expirationRequested = true
            }
        }
        lock.unlock()

        if let taskIdToEnd {
            eventLogger(
                "[GoBridge] BG_TASK_EXPIRED — ending task before suspension " +
                    "pid=\(processIdentifier())"
            )
            backgroundTaskManager.endBackgroundTask(taskIdToEnd)
        }
    }
}

/// Bridges Flutter MethodChannel/EventChannel to the Go native library.
///
/// MethodChannel `com.mknoon/go_bridge` handles request/response calls.
/// EventChannel `com.mknoon/go_bridge_events` streams push events from Go.
class GoBridge: NSObject {
    private let appDiagnosticBridge: MknoonAppDiagnosticBridge
    private let methodChannel: FlutterMethodChannel
    private let eventChannel: FlutterEventChannel
    private var eventSink: FlutterEventSink?
    private var pendingEvents: [String] = []
    private let pendingEventsLock = NSLock()
    private let maxPendingEvents = 256
    private let criticalTaskRegistry: CriticalTaskRegistry

    init(
        messenger: FlutterBinaryMessenger,
        criticalTaskRegistry: CriticalTaskRegistry = .shared
    ) {
        self.criticalTaskRegistry = criticalTaskRegistry
        appDiagnosticBridge = MknoonAppDiagnosticBridge(messenger: messenger)
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
        MknoonAppDiagnostics.shared.record("startup", "bridge", "ok", "bootstrap", values: ["phase": "bridge_initialized"])

        // Initialize the Go singleton with our event callback
        BridgeInitialize(self)
    }

    private func runOnBackground(_ work: @escaping () -> Any?, method: String = "", result: @escaping FlutterResult) {
        #if DEBUG
        // FDC-S5 (M1): stamp when the call was handed to the background queue so
        // the closure below can report how long it waited for a dispatch slot —
        // the thread-pool serialization signal under concurrent warm/probe work.
        let receivedAt = DispatchTime.now()
        #endif
        DispatchQueue.global(qos: .userInitiated).async {
            #if DEBUG
            if !method.isEmpty {
                let waitMs = Double(DispatchTime.now().uptimeNanoseconds - receivedAt.uptimeNanoseconds) / 1_000_000.0
                self.emitDispatchTiming(method: method, queueWaitMs: waitMs)
            }
            #endif
            let value = work()
            DispatchQueue.main.async {
                result(value)
            }
        }
    }

    #if DEBUG
    /// FDC-S5 (M1): surface the bridge dispatch queue-wait on the same EventChannel
    /// Go push events use, so the Dart client (bridge:dispatch_timing raw passthrough)
    /// folds it into FLOW logs alongside BRIDGE_CALL_TIMING {bridgeMs}. The iOS bridge
    /// dispatches on DispatchQueue.global(qos:.userInitiated) — a *concurrent* queue —
    /// so this should read ~0 unless the thread pool is saturated; that is exactly the
    /// number the deferred two-device M1 run is looking for. DEBUG-only: zero release cost.
    private func emitDispatchTiming(method: String, queueWaitMs: Double) {
        let payload: [String: Any] = [
            "event": "bridge:dispatch_timing",
            "data": ["method": method, "queueWaitMs": queueWaitMs],
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let json = String(data: data, encoding: .utf8) else { return }
        self.onEvent(json)
    }
    #endif

    func handleMethodCall(_ call: FlutterMethodCall, result rawResult: @escaping FlutterResult) {
        let result = MknoonAppDiagnostics.shared.wrapBridge(call.method, arguments: call.arguments, result: rawResult)
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
        case "migrationSessionEncap":
            runOnBackground({ BridgeMigrationSessionEncap(args ?? "") }, result: result)
        case "migrationSessionDecap":
            runOnBackground({ BridgeMigrationSessionDecap(args ?? "") }, result: result)
        case "migrationChunkEncrypt":
            runOnBackground({ BridgeMigrationChunkEncrypt(args ?? "") }, result: result)
        case "migrationChunkDecrypt":
            runOnBackground({ BridgeMigrationChunkDecrypt(args ?? "") }, result: result)

        // Node lifecycle
        case "startNode":
            runOnBackground({ BridgeStartNode(args ?? "") }, result: result)
        case "stopNode":
            runOnBackground({ BridgeStopNode() }, result: result)
        case "nodeStatus":
            runOnBackground({ BridgeNodeStatus() }, method: "nodeStatus", result: result)

        // Rendezvous
        case "rendezvousRegister":
            runOnBackground({ BridgeRendezvousRegister(args ?? "") }, result: result)
        case "rendezvousUnregister":
            runOnBackground({ BridgeRendezvousUnregister(args ?? "") }, result: result)
        case "rendezvousDiscover":
            runOnBackground({ BridgeRendezvousDiscover(args ?? "") }, method: "rendezvousDiscover", result: result)

        // Relay
        case "relayReconnect":
            runOnBackground({ BridgeRelayReconnect() }, result: result)
        case "relayProbe":
            runOnBackground({ BridgeRelayProbe(args ?? "") }, method: "relayProbe", result: result)
        case "relayTurnCredentialsV1":
            runOnBackground({ BridgeTurnCredentialsV1() }, result: result)
        case "turnCredentialsWithDiagnosticsV1", "relayTurnCredentialsWithDiagnosticsV1":
            runOnBackground({ BridgeTurnCredentialsWithDiagnosticsV1(args ?? "") }, result: result)
        case "callDiagnosticsV1":
            runOnBackground({ BridgeCallDiagnosticsV1(args ?? "") }, result: result)
        case "appDiagnosticsV1":
            runOnBackground({ BridgeAppDiagnosticsV1(args ?? "") }, result: result)
        // Presence (FDC-08/09)
        case "relayPresenceGet":
            runOnBackground({ BridgePresenceGet(args ?? "") }, result: result)
        case "relayPresenceSet":
            runOnBackground({ BridgePresenceSet(args ?? "") }, result: result)

        // Dedicated call-control relay and capability authority. These
        // commands never traverse the durable chat inbox/outbox paths.
        case "callStoreV1":
            runOnBackground({ BridgeCallStoreV1(args ?? "") }, result: result)
        case "callRetrieveV1":
            runOnBackground({ BridgeCallRetrieveV1(args ?? "") }, result: result)
        case "callAckV1":
            runOnBackground({ BridgeCallAckV1(args ?? "") }, result: result)
        case "callCancelV1":
            runOnBackground({ BridgeCallCancelV1(args ?? "") }, result: result)
        case "callEndpointSetV1":
            runOnBackground({ BridgeCallEndpointSetV1(args ?? "") }, result: result)
        case "callEndpointGetV1":
            runOnBackground({ BridgeCallEndpointGetV1(args ?? "") }, result: result)
        case "callEndpointRevokeV1":
            runOnBackground({ BridgeCallEndpointRevokeV1(args ?? "") }, result: result)
        case "callWakeHandleSetV1":
            runOnBackground({ BridgeCallWakeHandleSetV1(args ?? "") }, result: result)
        case "callWakeHandleRevokeV1":
            runOnBackground({ BridgeCallWakeHandleRevokeV1(args ?? "") }, result: result)
        case "callTokenSetV1":
            runOnBackground({ BridgeCallTokenSetV1(args ?? "") }, result: result)
        case "callTokenRevokeV1":
            runOnBackground({ BridgeCallTokenRevokeV1(args ?? "") }, result: result)

        // Peer operations
        case "dialPeer":
            runOnBackground({ BridgeDialPeer(args ?? "") }, method: "dialPeer", result: result)
        // 183: active-chat keepalive liveness probe (libp2p ping).
        case "peerPing":
            runOnBackground({ BridgePeerPing(args ?? "") }, method: "peerPing", result: result)
        case "disconnectPeer":
            runOnBackground({ BridgeDisconnectPeer(args ?? "") }, result: result)
        case "sendMessage":
            runOnBackground({ BridgeSendMessage(args ?? "") }, method: "sendMessage", result: result)
        case "confirmDirectMessage":
            runOnBackground({ BridgeConfirmDirectMessage(args ?? "") }, result: result)
        // LAN-direct dial (FDC-11)
        case "lanPeerFound":
            runOnBackground({ BridgeHandleLANPeerFound(args ?? "") }, result: result)

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
        case "inboxUnregisterToken":
            runOnBackground({ BridgeInboxUnregisterToken(args ?? "") }, result: result)
        // Wake-token registration (FDC-09 §12)
        case "inboxRegisterWakeTokens":
            runOnBackground({ BridgeRegisterWakeTokens(args ?? "") }, result: result)

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
        // 1:1 media over libp2p LAN (FDC-15)
        case "mediaLanSend":
            runOnBackground({ BridgeMediaLANSend(args ?? "") }, result: result)

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
            let taskId = criticalTaskRegistry.begin(withName: "mknoon.sendMessage")
            if taskId == .invalid {
                logGroupMediaNativeProof(
                    "[GoBridge] BG_TASK_REFUSED — OS would not grant background time " +
                        "pid=\(ProcessInfo.processInfo.processIdentifier)"
                )
                result("")  // empty string signals Dart that no task was granted
            } else {
                // FDC-S4 (Method step 1): log the ACTUAL OS-granted background
                // budget right after the assertion is taken, so the device
                // measurement reads the real per-OS grant rather than the
                // folklore "~30s". backgroundTimeRemaining MUST be read on the
                // main thread (this case already runs on main); the OS may
                // report .greatestFiniteMagnitude until the app is fully
                // backgrounded, which the parser treats as "unbounded".
                let remainingSec = criticalTaskRegistry.backgroundTimeRemaining
                logGroupMediaNativeProof(
                    "[GoBridge] BG_TASK_GRANTED taskId=\(taskId.rawValue) " +
                        "backgroundTimeRemainingSec=\(String(format: "%.1f", remainingSec)) " +
                        "pid=\(ProcessInfo.processInfo.processIdentifier)"
                )
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
                criticalTaskRegistry.end(taskId)
            }
            result(nil)

        case "bgGrantProbe":
            // FDC-S4 measurement scaffolding (measurement builds only). Take a
            // background assertion, read the OS-granted backgroundTimeRemaining
            // on the main thread, release immediately, and RETURN the seconds to
            // Dart so the value rides the reliable Flutter [FLOW] log channel —
            // native os_log buffers while the process is truly suspended, but the
            // Flutter channel streams, so this is the robust way to capture the
            // real grant from a genuine home-swipe background.
            var probeTask = UIApplication.shared.beginBackgroundTask(withName: "mknoon.grantProbe") {}
            let remaining = UIApplication.shared.backgroundTimeRemaining
            NSLog("[GoBridge] BG_GRANT_PROBE backgroundTimeRemainingSec=%.1f", remaining)
            if probeTask != .invalid {
                UIApplication.shared.endBackgroundTask(probeTask)
                probeTask = .invalid
            }
            result(String(format: "%.1f", remaining))

        case "bgTimeRemaining":
            // FDC-S4 measurement: read-only backgroundTimeRemaining (no assertion
            // management — the caller holds the assertion). Used for the DELAYED
            // read: backgroundTimeRemaining is the DBL_MAX sentinel at
            // didEnterBackground and only arms the finite countdown a beat later,
            // so the Dart probe holds an assertion, waits ~1.5s in the background,
            // then calls this to capture the real finite grant.
            let timeRemaining = UIApplication.shared.backgroundTimeRemaining
            NSLog("[GoBridge] BG_TIME_REMAINING backgroundTimeRemainingSec=%.1f", timeRemaining)
            result(String(format: "%.1f", timeRemaining))

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
        NSLog(
            "[GoBridge] onEvent: BUFFERED (%@) eventLength=%d",
            reason,
            json.utf8.count
        )
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
