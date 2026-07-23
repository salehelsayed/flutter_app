// ios/RunnerTests/GoBridgeCriticalTaskTests.swift

import XCTest
@testable import Runner

final class GoBridgeCriticalTaskTests: XCTestCase {

    // --- Test 1: bgBegin returns a non-empty task ID string ---
    func test_bgBegin_returnsTaskIdString() {
        let manager = FakeBackgroundTaskManager()
        let bridge = makeBridge(manager: manager)
        let call = FlutterMethodCall(methodName: "bgBegin", arguments: nil)
        let expectation = expectation(description: "result returned")

        bridge.handleMethodCall(call) { result in
            guard let taskIdStr = result as? String, !taskIdStr.isEmpty else {
                XCTFail("bgBegin must return a non-empty task ID string, got: \(String(describing: result))")
                expectation.fulfill()
                return
            }
            // The returned string must be parseable as a UInt (raw task handle).
            XCTAssertNotNil(UInt(taskIdStr),
                "Task ID must be a decimal integer, got: \(taskIdStr)")
            expectation.fulfill()
        }

        waitForExpectations(timeout: 2)
        XCTAssertEqual(manager.begunTaskNames, ["mknoon.sendMessage"])
        XCTAssertTrue(manager.endedTaskIds.isEmpty)
    }

    // --- Test 2: bgEnd accepts a valid task ID without crashing ---
    func test_bgEnd_acceptsTaskIdFromBgBegin() {
        let manager = FakeBackgroundTaskManager()
        let bridge = makeBridge(manager: manager)
        var taskIdStr: String?

        // Step 1: acquire a task handle
        let beginCall = FlutterMethodCall(methodName: "bgBegin", arguments: nil)
        let beginExp = expectation(description: "bgBegin returned")
        bridge.handleMethodCall(beginCall) { result in
            taskIdStr = result as? String
            beginExp.fulfill()
        }
        waitForExpectations(timeout: 2)

        guard let id = taskIdStr, !id.isEmpty, let rawTaskId = Int(id) else {
            XCTFail("bgBegin did not return a task ID")
            return
        }

        // Step 2: end the task — must not crash or throw
        let payload = "{\"taskId\":\"\(id)\"}"
        let endCall = FlutterMethodCall(methodName: "bgEnd", arguments: payload)
        let endExp = expectation(description: "bgEnd returned")
        bridge.handleMethodCall(endCall) { result in
            // bgEnd returns nil on success
            endExp.fulfill()
        }
        waitForExpectations(timeout: 2)

        XCTAssertEqual(manager.endedTaskIds.map(\.rawValue), [rawTaskId])
    }

    // --- Test 3: bgEnd with invalid/empty task ID does not crash ---
    func test_bgEnd_handlesInvalidTaskIdGracefully() {
        let manager = FakeBackgroundTaskManager()
        let bridge = makeBridge(manager: manager)
        let invalidPayloads: [String?] = [
            nil,
            "",
            "{}",
            "{\"taskId\":\"\"}",
            "{\"taskId\":\"not-a-number\"}",
        ]

        for (i, args) in invalidPayloads.enumerated() {
            let call = FlutterMethodCall(methodName: "bgEnd", arguments: args)
            let exp = expectation(description: "bgEnd-invalid-\(i)")
            bridge.handleMethodCall(call) { _ in exp.fulfill() }
            waitForExpectations(timeout: 1)
        }
        // If we reach here without crashing, the test passes.
        XCTAssertTrue(manager.endedTaskIds.isEmpty)
    }

    // --- Test 4: multiple bgBegin calls each return distinct task IDs ---
    func test_multipleBgBegin_returnDistinctIds() {
        let manager = FakeBackgroundTaskManager()
        let bridge = makeBridge(manager: manager)
        var ids = Set<String>()

        for i in 0..<3 {
            let call = FlutterMethodCall(methodName: "bgBegin", arguments: nil)
            let exp = expectation(description: "bgBegin-\(i)")
            bridge.handleMethodCall(call) { result in
                if let id = result as? String, !id.isEmpty {
                    ids.insert(id)
                }
                exp.fulfill()
            }
            waitForExpectations(timeout: 1)
        }

        XCTAssertEqual(ids.count, 3,
            "Three bgBegin calls must produce three distinct task IDs")

        // Cleanup: end all tasks
        for id in ids {
            let payload = "{\"taskId\":\"\(id)\"}"
            let call = FlutterMethodCall(methodName: "bgEnd", arguments: payload)
            let exp = expectation(description: "cleanup-\(id)")
            bridge.handleMethodCall(call) { _ in exp.fulfill() }
            waitForExpectations(timeout: 1)
        }

        XCTAssertEqual(manager.endedTaskIds.count, 3)
        XCTAssertEqual(Set(manager.endedTaskIds.map { String($0.rawValue) }), ids)
    }

    func test_bgBegin_refusalReturnsEmptyAndNeverEndsInvalidTask() {
        let manager = FakeBackgroundTaskManager(refuseBegins: true)
        let bridge = makeBridge(manager: manager)
        let call = FlutterMethodCall(methodName: "bgBegin", arguments: nil)
        let exp = expectation(description: "bgBegin-refused")

        bridge.handleMethodCall(call) { result in
            XCTAssertEqual(result as? String, "")
            exp.fulfill()
        }

        waitForExpectations(timeout: 1)
        XCTAssertTrue(manager.endedTaskIds.isEmpty)
    }

    func test_expirationThenLateDartEndEndsNativeTaskExactlyOnce() {
        let manager = FakeBackgroundTaskManager()
        let bridge = makeBridge(manager: manager)
        var taskId = ""

        let beginExp = expectation(description: "bgBegin-expiring")
        bridge.handleMethodCall(
            FlutterMethodCall(methodName: "bgBegin", arguments: nil)
        ) { result in
            taskId = result as? String ?? ""
            beginExp.fulfill()
        }
        waitForExpectations(timeout: 1)

        guard let rawTaskId = Int(taskId) else {
            XCTFail("bgBegin did not return a task ID")
            return
        }

        manager.expire(UIBackgroundTaskIdentifier(rawValue: rawTaskId))
        XCTAssertEqual(manager.endedTaskIds.map(\.rawValue), [rawTaskId])

        let lateEndExp = expectation(description: "late-bgEnd")
        bridge.handleMethodCall(
            FlutterMethodCall(
                methodName: "bgEnd",
                arguments: "{\"taskId\":\"\(taskId)\"}"
            )
        ) { _ in
            lateEndExp.fulfill()
        }
        waitForExpectations(timeout: 1)

        XCTAssertEqual(
            manager.endedTaskIds.map(\.rawValue),
            [rawTaskId],
            "native expiration must own the terminal end; late Dart finally is a no-op"
        )
    }

    func test_terminalLogsIncludePidAndEachPathEndsExactlyOnce() {
        let expectedPid: Int32 = 42_269

        let normalManager = FakeBackgroundTaskManager()
        let normalLogs = CriticalTaskLogRecorder()
        let normalRegistry = makeRegistry(
            manager: normalManager,
            processIdentifier: expectedPid,
            logs: normalLogs
        )
        let normalTaskId = normalRegistry.begin(withName: "normal")
        normalRegistry.end(normalTaskId)
        normalRegistry.end(normalTaskId)

        XCTAssertEqual(normalManager.endedTaskIds, [normalTaskId])
        XCTAssertEqual(normalLogs.messages.count, 1)
        XCTAssertTrue(normalLogs.messages[0].contains("BG_TASK_ENDED"))
        XCTAssertTrue(normalLogs.messages[0].contains("terminal=normal"))
        XCTAssertTrue(normalLogs.messages[0].contains("pid=\(expectedPid)"))

        let registeredExpiryManager = FakeBackgroundTaskManager()
        let registeredExpiryLogs = CriticalTaskLogRecorder()
        let registeredExpiryRegistry = makeRegistry(
            manager: registeredExpiryManager,
            processIdentifier: expectedPid,
            logs: registeredExpiryLogs
        )
        let registeredExpiryTaskId = registeredExpiryRegistry.begin(
            withName: "registered-expiry"
        )
        registeredExpiryManager.expire(registeredExpiryTaskId)
        registeredExpiryRegistry.end(registeredExpiryTaskId)

        XCTAssertEqual(
            registeredExpiryManager.endedTaskIds,
            [registeredExpiryTaskId]
        )
        XCTAssertEqual(registeredExpiryLogs.messages.count, 1)
        XCTAssertTrue(
            registeredExpiryLogs.messages[0].contains("BG_TASK_EXPIRED")
        )
        XCTAssertTrue(
            registeredExpiryLogs.messages[0].contains("pid=\(expectedPid)")
        )

        let earlyExpiryManager = FakeBackgroundTaskManager(
            expireBeforeBeginReturns: true
        )
        let earlyExpiryLogs = CriticalTaskLogRecorder()
        let earlyExpiryRegistry = makeRegistry(
            manager: earlyExpiryManager,
            processIdentifier: expectedPid,
            logs: earlyExpiryLogs
        )
        let earlyExpiryTaskId = earlyExpiryRegistry.begin(
            withName: "early-expiry"
        )
        earlyExpiryRegistry.end(earlyExpiryTaskId)

        XCTAssertEqual(earlyExpiryManager.endedTaskIds, [earlyExpiryTaskId])
        XCTAssertEqual(earlyExpiryLogs.messages.count, 1)
        XCTAssertTrue(
            earlyExpiryLogs.messages[0].contains("BG_TASK_EXPIRED")
        )
        XCTAssertTrue(
            earlyExpiryLogs.messages[0].contains("pid=\(expectedPid)")
        )
    }

    // MARK: - Helpers

    private func makeBridge(manager: BackgroundTaskManaging) -> GoBridge {
        return GoBridge(
            messenger: MockFlutterBinaryMessenger(),
            criticalTaskRegistry: CriticalTaskRegistry(backgroundTaskManager: manager)
        )
    }

    private func makeRegistry(
        manager: BackgroundTaskManaging,
        processIdentifier: Int32,
        logs: CriticalTaskLogRecorder
    ) -> CriticalTaskRegistry {
        return CriticalTaskRegistry(
            backgroundTaskManager: manager,
            processIdentifier: { processIdentifier },
            eventLogger: { logs.record($0) }
        )
    }
}

// MARK: - Test doubles

final class MockFlutterBinaryMessenger: NSObject, FlutterBinaryMessenger {
    func send(onChannel channel: String, message: Data?) {}
    func send(onChannel channel: String, message: Data?, binaryReply callback: FlutterBinaryReply?) {}
    func setMessageHandlerOnChannel(_ channel: String, binaryMessageHandler handler: FlutterBinaryMessageHandler?) -> FlutterBinaryMessengerConnection { return 0 }
    func cleanUpConnection(_ connection: FlutterBinaryMessengerConnection) {}
}

final class CriticalTaskLogRecorder {
    private(set) var messages: [String] = []

    func record(_ message: String) {
        messages.append(message)
    }
}

final class FakeBackgroundTaskManager: BackgroundTaskManaging {
    private var nextRawTaskId = 100
    private var expirationHandlers: [UIBackgroundTaskIdentifier: () -> Void] = [:]
    private let refuseBegins: Bool
    private let expireBeforeBeginReturns: Bool

    private(set) var begunTaskNames: [String] = []
    private(set) var endedTaskIds: [UIBackgroundTaskIdentifier] = []
    var backgroundTimeRemaining: TimeInterval = 25

    init(
        refuseBegins: Bool = false,
        expireBeforeBeginReturns: Bool = false
    ) {
        self.refuseBegins = refuseBegins
        self.expireBeforeBeginReturns = expireBeforeBeginReturns
    }

    func beginBackgroundTask(
        withName taskName: String?,
        expirationHandler handler: (() -> Void)?
    ) -> UIBackgroundTaskIdentifier {
        begunTaskNames.append(taskName ?? "")
        guard !refuseBegins else { return .invalid }

        let taskId = UIBackgroundTaskIdentifier(rawValue: nextRawTaskId)
        nextRawTaskId += 1
        if expireBeforeBeginReturns {
            handler?()
        } else {
            expirationHandlers[taskId] = handler
        }
        return taskId
    }

    func endBackgroundTask(_ identifier: UIBackgroundTaskIdentifier) {
        endedTaskIds.append(identifier)
        expirationHandlers.removeValue(forKey: identifier)
    }

    func expire(_ identifier: UIBackgroundTaskIdentifier) {
        let expirationHandler = expirationHandlers[identifier]
        expirationHandler?()
    }
}
