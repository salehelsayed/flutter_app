// ios/RunnerTests/GoBridgeCriticalTaskTests.swift

import Flutter
import ObjectiveC
import SQLCipher
import UIKit
import XCTest
import sqflite_sqlcipher
@testable import Runner

final class GoBridgeActivityReporterContractTests: XCTestCase {
    func testWeeklyMarkKindsCrossTheRealRequestCodecUnchanged() throws {
        for kinds in [["group"], ["active", "chat", "call", "group"]] {
            let encodedKinds = try JSONSerialization.data(withJSONObject: kinds)
            let raw = String(request(op: "markWeekly").dropLast()) +
                ",\"week\":\"2026-W47\",\"kinds\":" +
                String(decoding: encodedKinds, as: UTF8.self) + "}"
            let fields = try decoded(raw)
            XCTAssertEqual(fields["week"] as? String, "2026-W47")
            XCTAssertEqual(fields["kinds"] as? [String], kinds)
            XCTAssertEqual(Set(fields.keys), requiredKeys.union(["week", "kinds"]))
            let forwarded = try JSONSerialization.data(withJSONObject: fields)
            let reparsed = try decoded(String(decoding: forwarded, as: UTF8.self))
            XCTAssertEqual(fields as NSDictionary, reparsed as NSDictionary)
        }
    }

    func testWeeklyMarkUsesTheExistingOwnerRevisionShapeGuard() throws {
        var fields = try decoded(request(op: "markWeekly"))
        fields["week"] = "2026-W47"
        fields["kinds"] = ["group"]
        let original = fields as NSDictionary
        XCTAssertEqual(GoBridge.activityMarkRevision(fields), 1)
        XCTAssertEqual(fields as NSDictionary, original)
    }

    func testFeatureUseKeepsItsFencedOccurrenceAndRejectsEngagementKinds() throws {
        let start = String(request(op: "markFeatureUse").dropLast())
        let time: Int64 = 1_794_902_400_123
        let fields = try decoded(start + ",\"occurredAtUnixMillis\":\(time),\"kinds\":[\"view_3d\"]}")
        XCTAssertEqual(fields["occurredAtUnixMillis"] as? Int64, time)
        XCTAssertEqual(fields["kinds"] as? [String], ["view_3d"])
        XCTAssertEqual(GoBridge.activityMarkRevision(fields), 1)
        assertRejected(start + ",\"kinds\":[\"view_3d\"]}")
        assertRejected(start + ",\"occurredAtUnixMillis\":\(time),\"kinds\":[\"active\"]}")
    }

    func testMarkAcceptsZeroOccurrenceUnchanged() throws {
        try assertOccurrenceUnchanged(0)
    }

    func testMarkAcceptsCurrentMillisOccurrenceUnchanged() throws {
        try assertOccurrenceUnchanged(1_794_902_400_123)
    }

    func testMarkAcceptsAboveDoublePrecisionOccurrenceUnchanged() throws {
        try assertOccurrenceUnchanged(9_007_199_254_740_993)
    }

    func testMarkAcceptsInt64MaxOccurrenceUnchanged() throws {
        try assertOccurrenceUnchanged(Int64.max)
    }

    func testLegacyMarkAndFlushKeepExactlySixFields() throws {
        for op in ["mark", "flush"] {
            let fields = try decoded(request(op: op))
            XCTAssertEqual(GoBridge.activityMarkRevision(fields), 1)
            XCTAssertEqual(Set(fields.keys), requiredKeys)
            let forwarded = try JSONSerialization.data(withJSONObject: fields)
            let reparsed = try decoded(String(decoding: forwarded, as: UTF8.self))
            XCTAssertEqual(fields as NSDictionary, reparsed as NSDictionary)
        }
    }

    func testEveryRequiredFieldRemainsRequiredWithAndWithoutOccurrence() throws {
        let timestamps: [String?] = [nil, "0"]
        for timestamp in timestamps {
            for missing in requiredKeys {
                var fields = try decoded(request(timestamp: timestamp))
                fields.removeValue(forKey: missing)
                XCTAssertNil(GoBridge.activityMarkRevision(fields), "Missing \(missing), occurrence=\(String(describing: timestamp))")
            }
        }
    }

    func testUnknownFieldRemainsRejectedWithoutOccurrence() {
        assertRejected(String(request().dropLast()) + ",\"unknown\":0}")
    }

    func testUnknownFieldRemainsRejectedWithOccurrence() {
        assertRejected(String(request(timestamp: "0").dropLast()) + ",\"unknown\":0}")
    }

    func testFlushRejectsOccurrenceIncludingZero() {
        for timestamp in ["0", "1794902400123", "9223372036854775807"] {
            assertRejected(request(op: "flush", timestamp: timestamp))
        }
    }

    func testMalformedOccurrenceValuesRemainRejected() {
        for timestamp in ["null", "true", "false", "\"0\"", "-1", "0.0", "1.5", "1e3", "9223372036854775808", "[]", "{}"] {
            assertRejected(request(timestamp: timestamp))
        }
    }

    func testDuplicateOccurrenceNamesAndDecodedAliasesRemainRejected() {
        let timestamped = String(request(timestamp: "0").dropLast())
        for duplicate in ["occurredAtUnixMillis", #"\u006fccurredAtUnixMillis"#] {
            XCTAssertNil(GoBridge.activityFields(timestamped + ",\"\(duplicate)\":1}"))
        }
    }

    func testRevisionRetainsItsOriginalPositiveSafeIntegerBounds() throws {
        for op in ["mark", "flush"] {
            XCTAssertEqual(GoBridge.activityMarkRevision(try decoded(request(op: op, revision: "9007199254740991"))), 9_007_199_254_740_991)
            for revision in ["0", "9007199254740992", "9223372036854775807", "-1", "true", "\"1\"", "1.0"] {
                assertRejected(request(op: op, revision: revision))
            }
        }
    }

    func testDuplicateRequiredNamesAndDecodedAliasesRemainRejected() {
        for duplicate in ["revision", #"\u0072evision"#] {
            XCTAssertNil(GoBridge.activityFields(String(request().dropLast()) + ",\"\(duplicate)\":1}"))
        }
    }

    func testWeeklyMarkRejectsInvalidWeekAndKinds() {
        let rejected: [(week: String, kinds: String, codecRejects: Bool)] = [
            ("2026-W00", #"["group"]"#, false),
            ("2026-W54", #"["group"]"#, false),
            ("2026-W47", "[]", false),
            ("2026-W47", #"["group","group"]"#, false),
            ("2026-W47", #"["unknown"]"#, false),
            ("2026-W47", "[1]", true),
            ("2026-W47", #"[["group"]]"#, true),
            ("2026-W47", #"["active","chat","call","group","group"]"#, true),
        ]
        for sample in rejected {
            let raw = String(request(op: "markWeekly").dropLast()) +
                ",\"week\":\"\(sample.week)\",\"kinds\":\(sample.kinds)}"
            if sample.codecRejects {
                XCTAssertNil(GoBridge.activityFields(raw))
            } else {
                assertRejected(raw)
            }
        }
    }

    func testWeeklyProjectionAcceptsAnEmptyCalendarReceipt() throws {
        let weekly = weeklyReceipt()
        let answer = try validatedAnswer(op: "weeklyProjection", field: "weekly", value: weekly)
        XCTAssertEqual(answer["ok"] as? Bool, true)
        XCTAssertEqual((answer["data"] as? NSDictionary)?["weekly"] as? NSDictionary, weekly as NSDictionary)
    }

    func testWeeklyProjectionPreservesDSTRangesAndAcknowledgements() throws {
        for hours: Int64 in [167, 169] {
            var weekly = weeklyReceipt()
            weekly["endUnixMillis"] = Int64(1_794_902_400_000) + hours * 3_600_000
            weekly["kinds"] = ["active", "chat", "call", "group"]
            weekly["acknowledged"] = [["relayPeerId": "public-test-relay", "kinds": ["chat", "group"]]]
            let answer = try validatedAnswer(op: "weeklyProjection", field: "weekly", value: weekly)
            XCTAssertEqual(answer["ok"] as? Bool, true)
            XCTAssertEqual((answer["data"] as? NSDictionary)?["weekly"] as? NSDictionary, weekly as NSDictionary)
        }
    }

    func testWeeklyMarkReturnsItsBooleanAcceptanceReceipt() throws {
        for accepted in [true, false] {
            let answer = try validatedAnswer(op: "markWeekly", field: "accepted", value: accepted)
            XCTAssertEqual(answer["ok"] as? Bool, true)
            XCTAssertEqual((answer["data"] as? [String: Any])?["accepted"] as? Bool, accepted)
        }
    }

    func testLegacyBooleanReceiptsKeepTheirExistingShapes() throws {
        for (op, field) in [("configure", "configured"), ("mark", "accepted"), ("flush", "queued")] {
            for value in [true, false] {
                let answer = try validatedAnswer(op: op, field: field, value: value)
                XCTAssertEqual(answer["ok"] as? Bool, true)
                let data = try XCTUnwrap(answer["data"] as? [String: Any])
                XCTAssertEqual(Set(data.keys), [field, "revision", "consentEpoch"])
                XCTAssertEqual(data[field] as? Bool, value)
            }
        }
    }

    func testWeeklyProjectionRejectsMalformedNestedReceipts() throws {
        var samples: [[String: Any]] = []
        for value in [true, 1.5, Int64(9_007_199_254_740_992), "0"] as [Any] {
            var weekly = weeklyReceipt(); weekly["startUnixMillis"] = value; samples.append(weekly)
        }
        for (key, value) in [
            ("week", "2026-W00"), ("week", "2026-W54"),
            ("endUnixMillis", 0), ("extra", true),
            ("kinds", ["chat", "chat"]), ("kinds", ["unknown"]),
            ("acknowledged", [["relayPeerId": "", "kinds": ["chat"]]]),
            ("acknowledged", [["relayPeerId": "relay", "kinds": []]]),
            ("acknowledged", Array(repeating: ["relayPeerId": "relay", "kinds": ["chat"]] as [String: Any], count: 65)),
        ] as [(String, Any)] {
            var weekly = weeklyReceipt(); weekly[key] = value; samples.append(weekly)
        }
        var missing = weeklyReceipt(); missing.removeValue(forKey: "week"); samples.append(missing)
        for weekly in samples {
            XCTAssertEqual(try validatedAnswer(op: "weeklyProjection", field: "weekly", value: weekly)["ok"] as? Bool, false)
        }
    }

    func testWeeklyReceiptsRejectStaleNativeRevisionAndEpoch() throws {
        for (revision, epoch) in [(Int64(2), Int64(7)), (Int64(1), Int64(8))] {
            for (op, field, value) in [
                ("weeklyProjection", "weekly", weeklyReceipt()), ("markWeekly", "accepted", true),
            ] as [(String, String, Any)] {
                XCTAssertEqual(try validatedAnswer(op: op, field: field, value: value, revision: revision, epoch: epoch)["ok"] as? Bool, false)
            }
        }
    }

    func testWeeklyProjectionPreservesSignedSafeCalendarBoundaries() throws {
        let maximum: Int64 = 9_007_199_254_740_991
        let ranges: [(Int64, Int64)] = [(-maximum, -maximum + 1000), (-1000, 0), (0, 1000), (maximum - 1000, maximum)]
        for (start, end) in ranges {
            var weekly = weeklyReceipt()
            weekly["startUnixMillis"] = start
            weekly["endUnixMillis"] = end
            let answer = try validatedAnswer(op: "weeklyProjection", field: "weekly", value: weekly)
            XCTAssertEqual(answer["ok"] as? Bool, true)
            XCTAssertEqual((answer["data"] as? NSDictionary)?["weekly"] as? NSDictionary, weekly as NSDictionary)
        }
    }

    private func weeklyReceipt() -> [String: Any] {
        ["week": "2026-W47", "startUnixMillis": Int64(1_794_902_400_000),
         "endUnixMillis": Int64(1_795_507_200_000), "kinds": [String](),
         "acknowledged": [[String: Any]]()]
    }

    private func validatedAnswer(op: String, field: String, value: Any, revision: Int64 = 1, epoch: Int64 = 7) throws -> [String: Any] {
        let raw = try JSONSerialization.data(withJSONObject: ["ok": true, "data": [
            "revision": revision, "consentEpoch": epoch, field: value,
        ]])
        let fence = MknoonActiveIdentityReporterFence(revision: 1, consentEpoch: 7,
            profileBinding: "v1:" + String(repeating: "a", count: 64), accountPeerID: "public-test-account")
        let result = GoBridge.activityAnswer(String(decoding: raw, as: UTF8.self), fence: fence, op: op)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: Data(result.utf8)) as? [String: Any])
    }

    private func assertOccurrenceUnchanged(_ timestamp: Int64) throws {
        let fields = try decoded(request(timestamp: String(timestamp)))
        let revision = GoBridge.activityMarkRevision(fields)
        XCTAssertEqual(revision, 1, "A valid mark occurrence must pass the real handler's shape guard")
        guard revision == 1 else { return }
        XCTAssertEqual(fields["occurredAtUnixMillis"] as? Int64, timestamp)
        XCTAssertEqual(Set(fields.keys), requiredKeys.union(["occurredAtUnixMillis"]))
        let forwarded = try JSONSerialization.data(withJSONObject: fields)
        let reparsed = try decoded(String(decoding: forwarded, as: UTF8.self))
        XCTAssertEqual(reparsed["occurredAtUnixMillis"] as? Int64, timestamp)
        XCTAssertEqual(fields as NSDictionary, reparsed as NSDictionary)
    }

    private func assertRejected(_ raw: String) {
        if let fields = GoBridge.activityFields(raw) {
            XCTAssertNil(GoBridge.activityMarkRevision(fields), "Must reject \(raw)")
        }
    }

    private func decoded(_ raw: String) throws -> [String: Any] {
        try XCTUnwrap(GoBridge.activityFields(raw), "Canonical fixture must parse: \(raw)")
    }

    private func request(op: String = "mark", timestamp: String? = nil, revision: String = "1") -> String {
        "{\"version\":1,\"op\":\"\(op)\",\"revision\":\(revision),\"consentEpoch\":1," +
            "\"profileBinding\":\"v1:\(String(repeating: "a", count: 64))\",\"accountPeerId\":\"12D3KooWJsEmQWn5WGGn9AZX79emq3RkGNx2ihFwWzZAqbiUQGMF\"" +
            (timestamp.map { ",\"occurredAtUnixMillis\":\($0)" } ?? "") + "}"
    }

    private let requiredKeys: Set<String> = ["version", "op", "revision", "consentEpoch", "profileBinding", "accountPeerId"]
}

final class GoBridgeCriticalTaskTests: XCTestCase {

    @MainActor
    func testTranslatorCompletionMarkerSurvivesAssertionExpiryOrRefusal() {
        let scenarios = [
            (wasBackgrounded: true, refuses: false, expires: false),
            (wasBackgrounded: true, refuses: false, expires: true),
            (wasBackgrounded: true, refuses: true, expires: false),
            (wasBackgrounded: false, refuses: false, expires: false),
        ]
        for scenario in scenarios {
            let manager = FakeBackgroundTaskManager(refuseBegins: scenario.refuses)
            let window = TranslatorVerificationWindow(
                registry: CriticalTaskRegistry(backgroundTaskManager: manager)
            )
            let taskId = "translator"
            let assertion = UIBackgroundTaskIdentifier(rawValue: 100)

            window.recordCompletion(taskId: taskId, wasBackgrounded: scenario.wasBackgrounded)
            window.recordCompletion(taskId: taskId, wasBackgrounded: !scenario.wasBackgrounded)
            XCTAssertEqual(manager.begunTaskNames, ["mknoon.translatorVerification"])
            window.finish(taskId: "other-task")
            XCTAssertTrue(manager.endedTaskIds.isEmpty)
            XCTAssertEqual(window.wasBackgrounded(taskId: taskId), scenario.wasBackgrounded)
            XCTAssertFalse(window.wasBackgrounded(taskId: "other-task"))

            if scenario.expires {
                manager.expire(assertion)
            }
            XCTAssertEqual(window.wasBackgrounded(taskId: taskId), scenario.wasBackgrounded)
            window.finish(taskId: taskId)
            XCTAssertFalse(window.wasBackgrounded(taskId: taskId))
            XCTAssertEqual(manager.endedTaskIds, scenario.refuses ? [] : [assertion])
        }
    }

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

    func test_notificationLockNestedLeasesEndIndependentlyExactlyOnce() {
        let manager = FakeBackgroundTaskManager()
        let bridge = makeBridge(manager: manager)
        let first = invoke(bridge, "notificationLockBegin") as? Int
        let second = invoke(bridge, "notificationLockBegin") as? Int

        XCTAssertEqual(first, 100)
        XCTAssertEqual(second, 101)
        XCTAssertEqual(manager.begunTaskNames, [
            "mknoon.notificationLock", "mknoon.notificationLock",
        ])
        XCTAssertTrue(manager.endedTaskIds.isEmpty)
        _ = invoke(bridge, "notificationLockEnd", arguments: second)
        XCTAssertEqual(manager.endedTaskIds.map(\.rawValue), [101])
        _ = invoke(bridge, "notificationLockEnd", arguments: first)
        _ = invoke(bridge, "notificationLockEnd", arguments: second)
        XCTAssertEqual(manager.endedTaskIds.map(\.rawValue), [101, 100])
    }

    func test_notificationLockRefusalDoesNotAdmitAnInvalidLease() {
        let manager = FakeBackgroundTaskManager(refuseBegins: true)
        let bridge = makeBridge(manager: manager)

        XCTAssertNil(invoke(bridge, "notificationLockBegin"))
        XCTAssertEqual(manager.begunTaskNames, ["mknoon.notificationLock"])
        XCTAssertTrue(manager.endedTaskIds.isEmpty)
    }

    func test_notificationLockExpiryDuringRegistrationDoesNotAdmitAStaleLease() {
        let manager = FakeBackgroundTaskManager(expireBeforeBeginReturns: true)
        let bridge = makeBridge(manager: manager)

        XCTAssertNil(invoke(bridge, "notificationLockBegin"))
        XCTAssertEqual(manager.endedTaskIds.map(\.rawValue), [100])
        _ = invoke(bridge, "notificationLockEnd", arguments: 100)
        XCTAssertEqual(manager.endedTaskIds.map(\.rawValue), [100])
    }

    func test_notificationLockExpiryThenLateReleaseEndsOnlyOnce() {
        let manager = FakeBackgroundTaskManager()
        let bridge = makeBridge(manager: manager)
        let taskId = invoke(bridge, "notificationLockBegin") as? Int
        XCTAssertEqual(taskId, 100)

        manager.expire(UIBackgroundTaskIdentifier(rawValue: 100))
        XCTAssertEqual(manager.endedTaskIds.map(\.rawValue), [100])
        _ = invoke(bridge, "notificationLockEnd", arguments: taskId)
        XCTAssertEqual(manager.endedTaskIds.map(\.rawValue), [100])
    }

    func test_notificationLockLivenessTracksExpiryEndAndUnknownHandles() {
        let manager = FakeBackgroundTaskManager()
        let bridge = makeBridge(manager: manager)
        let first = invoke(bridge, "notificationLockBegin") as? Int
        let second = invoke(bridge, "notificationLockBegin") as? Int
        XCTAssertEqual(invoke(bridge, "notificationLockIsActive", arguments: first) as? Bool, true)
        XCTAssertEqual(invoke(bridge, "notificationLockIsActive", arguments: second) as? Bool, true)
        manager.expire(UIBackgroundTaskIdentifier(rawValue: 100))
        XCTAssertEqual(invoke(bridge, "notificationLockIsActive", arguments: first) as? Bool, false)
        XCTAssertEqual(invoke(bridge, "notificationLockIsActive", arguments: second) as? Bool, true)
        _ = invoke(bridge, "notificationLockEnd", arguments: second)
        XCTAssertEqual(invoke(bridge, "notificationLockIsActive", arguments: second) as? Bool, false)
        XCTAssertEqual(invoke(bridge, "notificationLockIsActive", arguments: 999) as? Bool, false)
        XCTAssertEqual(invoke(bridge, "notificationLockIsActive") as? Bool, false)
        XCTAssertEqual(manager.endedTaskIds.map(\.rawValue), [100, 101])
    }

    func test_weeklyProjectionUsesTheRealHandlerOwnerFence() throws {
        try assertUnconfiguredWeeklyRequestIsStale(op: "weeklyProjection")
    }

    func test_markWeeklyUsesTheRealHandlerOwnerFence() throws {
        try assertUnconfiguredWeeklyRequestIsStale(op: "markWeekly")
    }

    private func assertUnconfiguredWeeklyRequestIsStale(op: String) throws {
        let bridge = makeBridge(manager: FakeBackgroundTaskManager())
        var fields: [String: Any] = ["version": 1, "op": op, "revision": 1, "consentEpoch": 7,
            "profileBinding": "v1:" + String(repeating: "a", count: 64), "accountPeerId": "public-test-account"]
        if op == "markWeekly" { fields["week"] = "2026-W47"; fields["kinds"] = ["group"] }
        let request = String(decoding: try JSONSerialization.data(withJSONObject: fields), as: UTF8.self)
        let raw = try XCTUnwrap(invoke(bridge, "activeIdentityReporterV1", arguments: request) as? String)
        let answer = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [String: Any])
        XCTAssertEqual(answer["ok"] as? Bool, false)
        XCTAssertEqual(answer["errorCode"] as? String, "ACTIVE_IDENTITY_REPORTER_STALE")
    }

    private func invoke(
        _ bridge: GoBridge,
        _ method: String,
        arguments: Any? = nil
    ) -> Any? {
        let returned = expectation(description: method)
        var value: Any?
        bridge.handleMethodCall(FlutterMethodCall(
            methodName: method, arguments: arguments
        )) { result in
            value = result
            returned.fulfill()
        }
        waitForExpectations(timeout: 1)
        return value
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


final class SqlCipherSuspensionTests: XCTestCase {
    @MainActor
    func testExpirationReleasesAnOpenWriteBeforeEndingTheGrant() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString, isDirectory: true
        )
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appendingPathComponent("suspension.db").path
        let password = "x'\(String(repeating: "ab", count: 32))'"

        let grants = try SqlCipherTestGrants()
        defer { grants.restore() }
        let plugin = SqfliteSqlCipherPlugin()
        let opened = try success(plugin, grants, "openDatabase", [
            "path": path, "password": password, "singleInstance": false,
        ])
        let id = try XCTUnwrap((opened as? [String: Any])?["id"] as? Int)
        defer { _ = try? success(plugin, grants, "closeDatabase", ["id": id]) }

        _ = try success(plugin, grants, "execute", [
            "id": id, "sql": "CREATE TABLE marker (id INTEGER PRIMARY KEY)",
        ])
        _ = try success(plugin, grants, "insert", [
            "id": id, "sql": "INSERT INTO marker VALUES (1)",
        ])

        var second: OpaquePointer?
        let openCode = SQLCipher.sqlite3_open_v2(path, &second, SQLCipher.SQLITE_OPEN_READWRITE, nil)
        defer { SQLCipher.sqlite3_close(second) }
        XCTAssertEqual(openCode, SQLCipher.SQLITE_OK)
        guard openCode == SQLCipher.SQLITE_OK else { return }
        let peer = try XCTUnwrap(second)
        XCTAssertEqual(
            SQLCipher.sqlite3_exec(peer, "PRAGMA key = \"\(password)\"", nil, nil, nil),
            SQLCipher.SQLITE_OK
        )
        XCTAssertEqual(try markers(on: peer), [1])
        XCTAssertEqual(writeLockStatus(on: peer), SQLCipher.SQLITE_OK)

        let begin = try success(plugin, grants, "execute", [
            "id": id, "sql": "BEGIN IMMEDIATE", "inTransaction": true, "transactionId": NSNull(),
        ])
        let token = (begin as? [String: Any])?["transactionId"] as? Int
        var write: [String: Any] = ["id": id, "sql": "INSERT INTO marker VALUES (2)"]
        write["transactionId"] = token
        _ = try success(plugin, grants, "insert", write)

        // Establish real lock contention on another handle before injecting expiration.
        let statusBeforeExpiration = writeLockStatus(on: peer)
        XCTAssertEqual(statusBeforeExpiration, SQLCipher.SQLITE_BUSY)
        guard statusBeforeExpiration == SQLCipher.SQLITE_BUSY else { return }
        guard grants.pending.count == 1, let (grant, expire) = grants.pending.first else {
            XCTFail("SQLCipher held an open write lock without a live background assertion")
            return
        }
        let expiredToken = try XCTUnwrap(token)

        let ended = expectation(description: "SQLCipher releases its write lock before ending its assertion")
        var statusAtEnd: Int32?
        grants.didEnd = { identifier in
            guard identifier == grant else { return }
            statusAtEnd = self.writeLockStatus(on: peer)
            ended.fulfill()
        }
        expire()
        wait(for: [ended], timeout: 3)
        grants.didEnd = nil
        XCTAssertEqual(statusAtEnd, SQLCipher.SQLITE_OK)
        XCTAssertEqual(grants.ended.filter { $0 == grant }.count, 1)
        XCTAssertEqual(try markers(on: peer), [1])

        let lateWrite = try invoke(plugin, grants, "insert", [
            "id": id, "sql": "INSERT INTO marker VALUES (3)", "transactionId": expiredToken,
        ])
        XCTAssertEqual((lateWrite as? FlutterError)?.code, "sqlite_error")
        XCTAssertEqual((lateWrite as? FlutterError)?.message, "transaction_aborted")
        XCTAssertEqual(try markers(on: peer), [1])

        let fresh = try success(plugin, grants, "execute", [
            "id": id, "sql": "BEGIN IMMEDIATE", "inTransaction": true, "transactionId": NSNull(),
        ])
        let freshToken = try XCTUnwrap((fresh as? [String: Any])?["transactionId"] as? Int)
        XCTAssertNotEqual(freshToken, expiredToken)
        _ = try success(plugin, grants, "insert", [
            "id": id, "sql": "INSERT INTO marker VALUES (4)", "transactionId": freshToken,
        ])
        let lateCommit = try invoke(plugin, grants, "execute", [
            "id": id, "sql": "COMMIT", "inTransaction": false, "transactionId": expiredToken,
        ])
        XCTAssertEqual((lateCommit as? FlutterError)?.message, "transaction_aborted")
        XCTAssertEqual(writeLockStatus(on: peer), SQLCipher.SQLITE_BUSY)
        _ = try success(plugin, grants, "execute", [
            "id": id, "sql": "COMMIT", "inTransaction": false, "transactionId": freshToken,
        ])
        XCTAssertEqual(try markers(on: peer), [1, 4])
    }

    @MainActor
    func testCancelledCommitReleasesTheWriteBeforeEndingTheGrant() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString, isDirectory: true
        )
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appendingPathComponent("contention.db").path
        let password = "x'\(String(repeating: "cd", count: 32))'"

        let grants = try SqlCipherTestGrants()
        defer { grants.restore() }
        let plugin = SqfliteSqlCipherPlugin()
        let opened = try success(plugin, grants, "openDatabase", [
            "path": path, "password": password, "singleInstance": false,
        ])
        let id = try XCTUnwrap((opened as? [String: Any])?["id"] as? Int)
        defer { _ = try? success(plugin, grants, "closeDatabase", ["id": id]) }
        _ = try success(plugin, grants, "query", [
            "id": id, "sql": "PRAGMA journal_mode = DELETE",
        ])
        _ = try success(plugin, grants, "query", [
            "id": id, "sql": "PRAGMA busy_timeout = 5000",
        ])
        _ = try success(plugin, grants, "execute", [
            "id": id, "sql": "CREATE TABLE marker (id INTEGER PRIMARY KEY)",
        ])
        _ = try success(plugin, grants, "insert", [
            "id": id, "sql": "INSERT INTO marker VALUES (1)",
        ])

        let reader = try openFixtureConnection(path: path, password: password)
        defer { SQLCipher.sqlite3_close(reader) }
        let probe = try openFixtureConnection(path: path, password: password)
        defer { SQLCipher.sqlite3_close(probe) }

        let began = try success(plugin, grants, "execute", [
            "id": id, "sql": "BEGIN IMMEDIATE", "inTransaction": true, "transactionId": NSNull(),
        ])
        let token = try XCTUnwrap((began as? [String: Any])?["transactionId"] as? Int)
        _ = try success(plugin, grants, "insert", [
            "id": id, "sql": "INSERT INTO marker VALUES (2)", "transactionId": token,
        ])
        XCTAssertEqual(SQLCipher.sqlite3_exec(reader, "BEGIN", nil, nil, nil), SQLCipher.SQLITE_OK)
        defer { _ = SQLCipher.sqlite3_exec(reader, "ROLLBACK", nil, nil, nil) }
        XCTAssertEqual(try markers(on: reader), [1])
        XCTAssertEqual(try markers(on: probe), [1])
        let (grant, expire) = try XCTUnwrap(grants.pending.first)

        let commitDone = expectation(description: "the pending COMMIT replies")
        var commitReply: Any?
        grants.capture {
            plugin.handle(FlutterMethodCall(methodName: "execute", arguments: [
                "id": id, "sql": "COMMIT", "inTransaction": false, "transactionId": token,
            ]), result: {
                commitReply = $0
                commitDone.fulfill()
            })
        }
        defer {
            // Release the independent reader before waiting, even on a failed
            // assertion. The plugin handle stays open until its call returns.
            _ = SQLCipher.sqlite3_exec(reader, "ROLLBACK", nil, nil, nil)
            wait(for: [commitDone], timeout: 3)
        }

        let blocked = DispatchTime.now() + .seconds(2)
        var probeStatus = SQLCipher.SQLITE_OK
        while DispatchTime.now() < blocked {
            probeStatus = SQLCipher.sqlite3_exec(probe, "SELECT id FROM marker", nil, nil, nil)
            if probeStatus != SQLCipher.SQLITE_OK { break }
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.005))
        }
        XCTAssertEqual(probeStatus, SQLCipher.SQLITE_BUSY)
        guard probeStatus == SQLCipher.SQLITE_BUSY else { return }

        let ended = expectation(description: "the UIKit assertion ends")
        var statusAtEnd: Int32?
        grants.didEnd = { identifier in
            guard identifier == grant else { return }
            statusAtEnd = self.writeLockStatus(on: probe)
            ended.fulfill()
        }
        defer { grants.didEnd = nil }
        expire()
        wait(for: [ended], timeout: 3)

        XCTAssertEqual(
            statusAtEnd, SQLCipher.SQLITE_OK,
            "Ending the assertion must wait for the contended write lock to be released"
        )
        guard statusAtEnd == SQLCipher.SQLITE_OK else { return }
        XCTAssertEqual(try markers(on: probe), [1])
        // The wrapper schedules the COMMIT reply on main after native cleanup.
        // Release the read snapshot and let defer await the already-pending reply.
        _ = SQLCipher.sqlite3_exec(reader, "ROLLBACK", nil, nil, nil)
        let replyDeadline = DispatchTime.now() + .seconds(2)
        while commitReply == nil && DispatchTime.now() < replyDeadline {
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.005))
        }
        XCTAssertEqual((commitReply as? FlutterError)?.code, "sqlite_error")
    }

    private func openFixtureConnection(path: String, password: String) throws -> OpaquePointer {
        var connection: OpaquePointer?
        let opened = SQLCipher.sqlite3_open_v2(
            path, &connection, SQLCipher.SQLITE_OPEN_READWRITE, nil
        )
        guard opened == SQLCipher.SQLITE_OK, let connection else {
            SQLCipher.sqlite3_close(connection)
            throw ProbeFailure.statement
        }
        let keyed = SQLCipher.sqlite3_exec(
            connection, "PRAGMA key = \"\(password)\"", nil, nil, nil
        )
        guard keyed == SQLCipher.SQLITE_OK else {
            SQLCipher.sqlite3_close(connection)
            throw ProbeFailure.statement
        }
        return connection
    }

    private func writeLockStatus(on peer: OpaquePointer) -> Int32 {
        let status = SQLCipher.sqlite3_exec(peer, "BEGIN IMMEDIATE", nil, nil, nil)
        guard status == SQLCipher.SQLITE_OK else { return status }
        return SQLCipher.sqlite3_exec(peer, "ROLLBACK", nil, nil, nil)
    }

    private func markers(on peer: OpaquePointer) throws -> [Int64] {
        var statement: OpaquePointer?
        let status = SQLCipher.sqlite3_prepare_v2(
            peer, "SELECT id FROM marker ORDER BY id", -1, &statement, nil
        )
        defer { SQLCipher.sqlite3_finalize(statement) }
        XCTAssertEqual(status, SQLCipher.SQLITE_OK)
        guard status == SQLCipher.SQLITE_OK else { throw ProbeFailure.statement }
        var values = [Int64]()
        var step = SQLCipher.sqlite3_step(statement)
        while step == SQLCipher.SQLITE_ROW {
            values.append(SQLCipher.sqlite3_column_int64(statement, 0))
            step = SQLCipher.sqlite3_step(statement)
        }
        XCTAssertEqual(step, SQLCipher.SQLITE_DONE)
        return values
    }

    private enum ProbeFailure: Error {
        case statement, missingReply, unexpectedFlutterError
    }

    @MainActor
    private func success(
        _ plugin: FlutterPlugin, _ grants: SqlCipherTestGrants,
        _ method: String, _ arguments: [String: Any]
    ) throws -> Any? {
        let reply = try invoke(plugin, grants, method, arguments)
        if let error = reply as? FlutterError {
            XCTFail("\(method) unexpectedly returned \(error.code)")
            throw ProbeFailure.unexpectedFlutterError
        }
        return reply
    }

    @MainActor
    private func invoke(
        _ plugin: FlutterPlugin, _ grants: SqlCipherTestGrants,
        _ method: String, _ arguments: [String: Any]
    ) throws -> Any? {
        let returned = expectation(description: method)
        var reply: Any?
        grants.capture {
            plugin.handle?(FlutterMethodCall(methodName: method, arguments: arguments), result: {
                reply = $0
                returned.fulfill()
            })
        }
        guard XCTWaiter.wait(for: [returned], timeout: 3) == .completed else {
            XCTFail("SQLCipher \(method) did not return")
            throw ProbeFailure.missingReply
        }
        return reply
    }
}

@MainActor
private final class SqlCipherTestGrants {
    static var owner: SqlCipherTestGrants?

    private let begin: (Method, Method)
    private let end: (Method, Method)
    private var nextIdentifier = Int.max - 1_000
    private(set) var capturing = false
    private(set) var pending: [Int: () -> Void] = [:]
    private(set) var ended: [Int] = []
    var didEnd: ((Int) -> Void)?

    init() throws {
        XCTAssertNil(Self.owner)
        let cls = UIApplication.self
        begin = (
            try XCTUnwrap(class_getInstanceMethod(cls, NSSelectorFromString("beginBackgroundTaskWithName:expirationHandler:"))),
            try XCTUnwrap(class_getInstanceMethod(cls, #selector(UIApplication.bl49_begin(_:expirationHandler:))))
        )
        end = (
            try XCTUnwrap(class_getInstanceMethod(cls, NSSelectorFromString("endBackgroundTask:"))),
            try XCTUnwrap(class_getInstanceMethod(cls, #selector(UIApplication.bl49_end(_:))))
        )
        Self.owner = self
        method_exchangeImplementations(begin.0, begin.1)
        method_exchangeImplementations(end.0, end.1)
    }

    func capture(_ body: () -> Void) {
        capturing = true
        defer { capturing = false }
        body()
    }

    func start(_ expiration: (() -> Void)?) -> Int {
        let identifier = nextIdentifier
        nextIdentifier += 1
        pending[identifier] = expiration ?? {}
        return identifier
    }

    func finish(_ identifier: Int) -> Bool {
        if ended.contains(identifier) {
            XCTFail("SQLCipher ended the same background assertion twice")
            return true
        }
        guard pending.removeValue(forKey: identifier) != nil else { return false }
        ended.append(identifier)
        didEnd?(identifier)
        return true
    }

    func restore() {
        XCTAssertTrue(pending.isEmpty, "SQLCipher left a captured background assertion outstanding")
        method_exchangeImplementations(end.0, end.1)
        method_exchangeImplementations(begin.0, begin.1)
        Self.owner = nil
    }
}

private extension UIApplication {
    @objc(bl49_begin:expirationHandler:)
    dynamic func bl49_begin(_ name: String?, expirationHandler: (() -> Void)?) -> Int {
        if name == "mknoon.sqlcipher", let grants = SqlCipherTestGrants.owner, grants.capturing {
            return grants.start(expirationHandler)
        }
        // The exchange routes this selector to the original UIKit implementation.
        return bl49_begin(name, expirationHandler: expirationHandler)
    }

    @objc(bl49_end:)
    dynamic func bl49_end(_ identifier: Int) {
        if SqlCipherTestGrants.owner?.finish(identifier) == true { return }
        bl49_end(identifier)
    }
}
