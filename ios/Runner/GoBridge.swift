import UIKit
import CoreFoundation

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

    /// Notification file-lock admission requires a currently live assertion.
    /// An expiration delivered before `begin` returns must not admit work with
    /// a handle that the registry has already ended. A later expiration still
    /// ends the OS assertion; callers retain their lock until their work exits.
    func beginIfLive(withName taskName: String) -> UIBackgroundTaskIdentifier? {
        let taskId = begin(withName: taskName)
        return isLive(taskId) ? taskId : nil
    }

    func isLive(_ taskId: UIBackgroundTaskIdentifier) -> Bool {
        lock.lock()
        let isLive = liveTasks[taskId.rawValue] != nil
        lock.unlock()
        return isLive
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

#if canImport(GoMknoon)
import Flutter
import GoMknoon

/// Bridges Flutter MethodChannel/EventChannel to the Go native library.
///
/// MethodChannel `com.mknoon/go_bridge` handles request/response calls.
/// EventChannel `com.mknoon/go_bridge_events` streams push events from Go.
class GoBridge: NSObject {
    private static let activityAdmission = MknoonActiveIdentityReporterAdmission { fence, enabled, preserve in
        var desired = activityFenceFields(fence)
        desired["enabled"] = enabled
        desired["preservePendingOnUnarm"] = preserve
        guard let data = try? JSONSerialization.data(withJSONObject: desired),
              let request = String(data: data, encoding: .utf8) else { return false }
        let published: String? = BridgePublishActiveIdentityReporterDesired(request)
        guard let raw = published, raw.utf8.count <= 16_384,
              let response = raw.data(using: .utf8),
              let answer = try? JSONSerialization.jsonObject(with: response) as? [String: Any],
              activityBool(answer["ok"]) == true, Set(answer.keys) == ["ok", "data"],
              let receipt = answer["data"] as? [String: Any], Set(receipt.keys) == ["revision", "consentEpoch"] else { return false }
        return activityInteger(receipt["revision"]) == fence.revision &&
            activityInteger(receipt["consentEpoch"]) == fence.consentEpoch
    }

    private static func activityFenceFields(_ fence: MknoonActiveIdentityReporterFence) -> [String: Any] {
        ["version": 1, "revision": fence.revision, "consentEpoch": fence.consentEpoch,
         "profileBinding": fence.profileBinding, "accountPeerId": fence.accountPeerID]
    }

    private static func activityInteger(_ value: Any?) -> Int64? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
              number.doubleValue >= 1, number.doubleValue <= 9_007_199_254_740_991,
              number.doubleValue.rounded() == number.doubleValue else { return nil }
        return number.int64Value
    }

    private static func activityBool(_ value: Any?) -> Bool? {
        guard let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() else { return nil }
        return number.boolValue
    }

    private static func activityError(_ code: String) -> String {
        let fixed: String
        switch code {
        case "INVALID_INPUT", "ACTIVE_IDENTITY_INVALID_REQUEST": fixed = "INVALID_INPUT"
        case "ACTIVE_IDENTITY_REPORTER_STALE": fixed = "ACTIVE_IDENTITY_REPORTER_STALE"
        default: fixed = "ACTIVE_IDENTITY_REPORTER_UNAVAILABLE"
        }
        return "{\"ok\":false,\"errorCode\":\"\(fixed)\"}"
    }

    // The local operation is bounded JSON; only kinds may be a string array. Decode names before
    // duplicate checks so escaped aliases cannot disappear during re-encoding.
    internal static func activityFields(_ raw: String?) -> [String: Any]? {
        guard let raw, raw.utf8.count <= 16_384, let data = raw.data(using: .utf8),
              (try? JSONSerialization.jsonObject(with: data)) is [String: Any] else { return nil }
        let bytes = Array(raw.utf8)
        var position = 0
        func space() {
            while position < bytes.count && [UInt8(9), 10, 13, 32].contains(bytes[position]) { position += 1 }
        }
        func string() -> String? {
            guard position < bytes.count, bytes[position] == 34 else { return nil }
            let start = position
            position += 1
            while position < bytes.count {
                if bytes[position] == 34 {
                    position += 1
                    return (try? JSONSerialization.jsonObject(with: Data(bytes[start..<position]), options: .fragmentsAllowed)) as? String
                }
                position += bytes[position] == 92 ? 2 : 1
            }
            return nil
        }
        space()
        guard position < bytes.count, bytes[position] == 123 else { return nil }
        position += 1
        var fields: [String: Any] = [:]
        space()
        if position < bytes.count && bytes[position] == 125 { position += 1; space(); return position == bytes.count ? fields : nil }
        while position < bytes.count {
            guard let key = string(), fields[key] == nil else { return nil }
            space()
            guard position < bytes.count, bytes[position] == 58 else { return nil }
            position += 1
            space()
            if position < bytes.count && bytes[position] == 34 {
                guard let value = string() else { return nil }
                fields[key] = value
            } else if position < bytes.count && bytes[position] == 91 {
                guard key == "kinds" else { return nil }
                position += 1
                space()
                var kinds: [String] = []
                if position < bytes.count && bytes[position] == 93 {
                    position += 1
                } else {
                    while true {
                        guard kinds.count < 4, let value = string() else { return nil }
                        kinds.append(value)
                        space()
                        guard position < bytes.count else { return nil }
                        if bytes[position] == 93 { position += 1; break }
                        guard bytes[position] == 44 else { return nil }
                        position += 1
                        space()
                    }
                }
                fields[key] = kinds
            } else {
                let start = position
                while position < bytes.count && bytes[position] != 44 && bytes[position] != 125 { position += 1 }
                let token = String(decoding: bytes[start..<position], as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
                if token == "true" { fields[key] = true }
                else if token == "false" { fields[key] = false }
                else {
                    guard !token.isEmpty, token.utf8.allSatisfy({ (48...57).contains($0) }),
                          token.count == 1 || token.first != "0", let number = Int64(token) else { return nil }
                    fields[key] = number
                }
            }
            space()
            guard position < bytes.count else { return nil }
            if bytes[position] == 125 { position += 1; space(); return position == bytes.count ? fields : nil }
            guard bytes[position] == 44 else { return nil }
            position += 1
            space()
        }
        return nil
    }

    internal static func activityMarkRevision(_ fields: [String: Any]) -> Int64? {
        var keys: Set<String> = ["version", "op", "revision", "consentEpoch", "profileBinding", "accountPeerId"]
        if fields["op"] as? String == "markWeekly" {
            guard let week = fields["week"] as? String, week.utf8.count == 8,
                  week.range(of: #"^[0-9]{4}-W(0[1-9]|[1-4][0-9]|5[0-3])$"#, options: .regularExpression) != nil,
                  let kinds = fields["kinds"] as? [String], !kinds.isEmpty, kinds.count <= 4,
                  Set(kinds).count == kinds.count,
                  kinds.allSatisfy({ ["active", "chat", "call", "group"].contains($0) }) else { return nil }
            keys.formUnion(["week", "kinds"])
        }
        if let occurrence = fields["occurredAtUnixMillis"] {
            guard fields["op"] as? String == "mark", type(of: occurrence) == Int64.self,
                  let timestamp = occurrence as? Int64, timestamp >= 0 else { return nil }
            keys.insert("occurredAtUnixMillis")
        }
        guard Set(fields.keys) == keys,
              let revision = activityInteger(fields["revision"]) else { return nil }
        return revision
    }

    private static func activityAnswer(_ raw: String?, fence: MknoonActiveIdentityReporterFence, op: String) -> String {
        guard let raw, raw.utf8.count <= 16_384, let bytes = raw.data(using: .utf8),
              let answer = try? JSONSerialization.jsonObject(with: bytes) as? [String: Any] else { return activityError("") }
        guard activityBool(answer["ok"]) == true else { return activityError(answer["errorCode"] as? String ?? "") }
        let field = op == "configure" ? "configured" : op == "mark" ? "accepted" : "queued"
        guard Set(answer.keys) == ["ok", "data"], let data = answer["data"] as? [String: Any],
              Set(data.keys) == Set([field, "revision", "consentEpoch"]),
              activityInteger(data["revision"]) == fence.revision,
              activityInteger(data["consentEpoch"]) == fence.consentEpoch,
              let value = activityBool(data[field]) else { return activityError("") }
        let receipt: [String: Any] = [field: value, "revision": fence.revision, "consentEpoch": fence.consentEpoch]
        let result: [String: Any] = ["ok": true, "data": receipt]
        guard let encoded = try? JSONSerialization.data(withJSONObject: result),
              let response = String(data: encoded, encoding: .utf8) else { return activityError("") }
        return response
    }
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
        appDiagnosticBridge.setActivityOwner(self)
        MknoonAppDiagnostics.shared.installActivityOwner(self, retirePrevious: {
            _ = Self.activityAdmission.unarmPreservingPending()
        }) { [weak self] epoch, enabled in
            guard let self else { return false }
            return MknoonAppDiagnostics.shared.withActivityOwner(self) {
                Self.activityAdmission.observeConsent(consentEpoch: epoch, enabled: enabled)
            } ?? false
        }
    }

    deinit {
        MknoonAppDiagnostics.shared.retireActivityOwner(self) { _ = Self.activityAdmission.unarmPreservingPending() }
    }

    private func activeActivityOwner() -> Bool {
        MknoonAppDiagnostics.shared.withActivityOwner(self) { true } == true
    }

    private func handleActivityReporter(_ raw: String?, result: @escaping FlutterResult) {
        guard activeActivityOwner() else { result(Self.activityError("")); return }
        guard var fields = Self.activityFields(raw), Self.activityInteger(fields["version"]) == 1,
              let op = fields["op"] as? String, let epoch = Self.activityInteger(fields["consentEpoch"]),
              let profile = fields["profileBinding"] as? String, let account = fields["accountPeerId"] as? String else {
            result(Self.activityError("INVALID_INPUT")); return
        }
        let fence: MknoonActiveIdentityReporterFence
        if op == "configure" {
            let keys: Set<String> = ["version", "op", "enabled", "consentEpoch", "profileBinding", "accountPeerId",
                "rootPrivateKeyBase64", "statePath", "preservePendingOnUnarm"]
            guard Set(fields.keys) == keys || Set(fields.keys) == keys.union(["revision"]),
                  fields["revision"] == nil || Self.activityInteger(fields["revision"]) != nil,
                  let enabled = Self.activityBool(fields["enabled"]), let root = fields["rootPrivateKeyBase64"] as? String,
                  fields["statePath"] is String, let preserve = Self.activityBool(fields["preservePendingOnUnarm"]) else {
                result(Self.activityError("INVALID_INPUT")); return
            }
            var entered = false
            let admitted = MknoonAppDiagnostics.shared.withActivityOwner(self) {
                entered = true
                return Self.activityAdmission.admitConfiguration(consentEpoch: epoch, enabled: enabled,
                    profileBinding: profile, accountPeerID: account, hasRootKey: !root.isEmpty,
                    preservePendingOnUnarm: preserve)
            } ?? nil
            guard let admitted else {
                result(Self.activityError(entered ? Self.activityAdmission.errorCode : "")); return
            }
            fence = admitted
            fields["revision"] = fence.revision
        } else if op == "mark" || op == "flush" {
            guard let revision = Self.activityMarkRevision(fields) else {
                result(Self.activityError("INVALID_INPUT")); return
            }
            fence = MknoonActiveIdentityReporterFence(revision: revision, consentEpoch: epoch,
                profileBinding: profile, accountPeerID: account)
            guard Self.activityAdmission.admitMark(fence) else { result(Self.activityError("ACTIVE_IDENTITY_REPORTER_STALE")); return }
        } else { result(Self.activityError("INVALID_INPUT")); return }
        guard let data = try? JSONSerialization.data(withJSONObject: fields), let request = String(data: data, encoding: .utf8) else {
            result(Self.activityError("INVALID_INPUT")); return
        }
        runOnBackground({ [weak self] in
            guard let self, self.activeActivityOwner(), Self.activityAdmission.isCurrent(fence),
                  op == "configure" || Self.activityAdmission.admitMark(fence) else {
                return Self.activityError("ACTIVE_IDENTITY_REPORTER_STALE")
            }
            return Self.activityAnswer(BridgeActiveIdentityReporterV1(request), fence: fence, op: op)
        }, result: { [weak self] value in
            guard let self, self.activeActivityOwner(), Self.activityAdmission.isCurrent(fence) else {
                result(Self.activityError("ACTIVE_IDENTITY_REPORTER_STALE")); return
            }
            result(value)
        })
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
        if call.method == "activeIdentityReporterV1" {
            handleActivityReporter(call.arguments as? String, result: rawResult)
            return
        }
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
        // SE-42 D27: call-media protection lease on the relay recovery broker.
        case "callMediaProtection":
            runOnBackground({ BridgeCallMediaProtection(args ?? "") }, result: result)
        case "relayTurnCredentialsV1":
            runOnBackground({ BridgeTurnCredentialsV1() }, result: result)
        case "turnCredentialsWithDiagnosticsV1", "relayTurnCredentialsWithDiagnosticsV1":
            runOnBackground({ BridgeTurnCredentialsWithDiagnosticsV1(args ?? "") }, result: result)
        case "callDiagnosticsV1":
            runOnBackground({ BridgeCallDiagnosticsV1(args ?? "") }, result: result)
        case "appDiagnosticsV1":
            runOnBackground({ BridgeAppDiagnosticsV1(args ?? "") }, result: result)
        case "stickerUsageV1":
            runOnBackground({ BridgeStickerUsageV1(args ?? "") }, result: result)
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

        // Notification ownership: acquire before flock, end after unlock. Keep
        // this admission contract separate from the existing send-task bridge.
        case "notificationLockBegin":
            let taskId = criticalTaskRegistry.beginIfLive(
                withName: "mknoon.notificationLock"
            )
            result(taskId?.rawValue)

        case "notificationLockEnd":
            if let rawValue = call.arguments as? Int {
                criticalTaskRegistry.end(
                    UIBackgroundTaskIdentifier(rawValue: rawValue)
                )
            }
            result(nil)

        case "notificationLockIsActive":
            if let rawValue = call.arguments as? Int {
                result(criticalTaskRegistry.isLive(
                    UIBackgroundTaskIdentifier(rawValue: rawValue)
                ))
            } else {
                result(false)
            }

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
