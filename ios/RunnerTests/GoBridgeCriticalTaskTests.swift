// ios/RunnerTests/GoBridgeCriticalTaskTests.swift

import XCTest
@testable import Runner

final class GoBridgeCriticalTaskTests: XCTestCase {

    // --- Test 1: bgBegin returns a non-empty task ID string ---
    func test_bgBegin_returnsTaskIdString() {
        let bridge = makeBridge()
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
    }

    // --- Test 2: bgEnd accepts a valid task ID without crashing ---
    func test_bgEnd_acceptsTaskIdFromBgBegin() {
        let bridge = makeBridge()
        var taskIdStr: String?

        // Step 1: acquire a task handle
        let beginCall = FlutterMethodCall(methodName: "bgBegin", arguments: nil)
        let beginExp = expectation(description: "bgBegin returned")
        bridge.handleMethodCall(beginCall) { result in
            taskIdStr = result as? String
            beginExp.fulfill()
        }
        waitForExpectations(timeout: 2)

        guard let id = taskIdStr, !id.isEmpty else {
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
    }

    // --- Test 3: bgEnd with invalid/empty task ID does not crash ---
    func test_bgEnd_handlesInvalidTaskIdGracefully() {
        let bridge = makeBridge()
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
    }

    // --- Test 4: multiple bgBegin calls each return distinct task IDs ---
    func test_multipleBgBegin_returnDistinctIds() {
        let bridge = makeBridge()
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
    }

    // MARK: - Helpers

    private func makeBridge() -> GoBridge {
        return GoBridge(messenger: MockFlutterBinaryMessenger())
    }
}

// MARK: - Test doubles

final class MockFlutterBinaryMessenger: NSObject, FlutterBinaryMessenger {
    func send(onChannel channel: String, message: Data?) {}
    func send(onChannel channel: String, message: Data?, binaryReply callback: FlutterBinaryReply?) {}
    func setMessageHandlerOnChannel(_ channel: String, binaryMessageHandler handler: FlutterBinaryMessageHandler?) -> FlutterBinaryMessengerConnection { return 0 }
    func cleanUpConnection(_ connection: FlutterBinaryMessengerConnection) {}
}
