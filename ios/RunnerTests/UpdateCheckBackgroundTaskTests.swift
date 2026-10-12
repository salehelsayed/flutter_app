import Foundation
import UIKit
import UserNotifications
import XCTest

@testable import Runner

final class UpdateCheckBackgroundTaskTests: XCTestCase {
  private final class FakeTask: UpdateCheckRefreshTask {
    var expirationHandler: (() -> Void)?
    var completions: [Bool] = []

    func setTaskCompleted(success: Bool) {
      completions.append(success)
    }
  }

  private final class FakeScheduler: UpdateCheckTaskScheduling {
    var handler: ((UpdateCheckRefreshTask) -> Void)?
    var submitted: [(String, Date)] = []
    var cancelled: [String] = []
    var pending = false

    func register(identifier: String, handler: @escaping (UpdateCheckRefreshTask) -> Void) -> Bool {
      self.handler = handler
      return true
    }

    func submit(identifier: String, earliestBeginDate: Date) throws {
      submitted.append((identifier, earliestBeginDate))
    }

    func cancel(identifier: String) {
      cancelled.append(identifier)
    }

    func hasPendingRequest(identifier: String, completion: @escaping (Bool) -> Void) {
      completion(pending)
    }
  }

  /// configure(true) submits on the main queue after the pending check.
  private func drainMain() {
    let done = expectation(description: "main")
    DispatchQueue.main.async { done.fulfill() }
    wait(for: [done], timeout: 2)
  }

  private var defaults: UserDefaults!
  private var topics: [Bool] = []
  private var clock = Date(timeIntervalSince1970: 1_000_000)
  private let suite = "UpdateCheckBackgroundTaskTests"

  override func setUp() {
    super.setUp()
    defaults = UserDefaults(suiteName: suite)
    defaults.removePersistentDomain(forName: suite)
    topics = []
    clock = Date(timeIntervalSince1970: 1_000_000)
  }

  override func tearDown() {
    defaults.removePersistentDomain(forName: suite)
    super.tearDown()
  }

  private func coordinator(
    scheduler: FakeScheduler,
    budget: TimeInterval = 5,
    engineWait: TimeInterval = 5,
    inCall: Bool = false
  ) -> UpdateCheckBackgroundCoordinator {
    UpdateCheckBackgroundCoordinator(
      scheduler: scheduler,
      defaults: defaults,
      isInCall: { inCall },
      budget: budget,
      engineWait: engineWait,
      queue: .main,
      now: { [unowned self] in self.clock },
      setTopicSubscribed: { [unowned self] in self.topics.append($0) }
    )
  }

  func testGateCompletesExactlyOnce() {
    var calls: [Bool] = []
    let gate = UpdateCheckTaskCompletionGate { calls.append($0) }
    XCTAssertTrue(gate.finish(success: true))
    XCTAssertFalse(gate.finish(success: false))
    XCTAssertFalse(gate.finish(success: true))
    XCTAssertEqual(calls, [true])
    XCTAssertTrue(gate.isCompleted)
  }

  func testRegistersTheTaskIdentifierAndReschedulesEveryRun() throws {
    let scheduler = FakeScheduler()
    let subject = coordinator(scheduler: scheduler)
    XCTAssertTrue(subject.registerLaunchHandler())
    subject.configure(enabled: true)
    drainMain()
    XCTAssertEqual(scheduler.submitted.map(\.0), ["com.mknoon.app.update-check"])
    XCTAssertEqual(
      scheduler.submitted[0].1,
      Date(timeIntervalSince1970: 1_000_000 + 12 * 60 * 60)
    )

    subject.attach { _, _, reply in reply(["outcome": "noUpdate", "enabled": true]) }
    let task = FakeTask()
    try XCTUnwrap(scheduler.handler)(task)
    XCTAssertEqual(scheduler.submitted.count, 2, "every run submits the next request")
    XCTAssertEqual(task.completions, [true])
  }

  func testExpiryCompletesOnceAndALateReplyDoesNothing() throws {
    let scheduler = FakeScheduler()
    let subject = coordinator(scheduler: scheduler)
    subject.registerLaunchHandler()
    var pendingReply: ((Any?) -> Void)?
    subject.attach { _, _, reply in pendingReply = reply }
    let task = FakeTask()
    try XCTUnwrap(scheduler.handler)(task)

    try XCTUnwrap(task.expirationHandler)()
    XCTAssertEqual(task.completions, [false])
    try XCTUnwrap(pendingReply)(["outcome": "notified", "enabled": true])
    try XCTUnwrap(task.expirationHandler)()
    XCTAssertEqual(task.completions, [false], "setTaskCompleted exactly once")
  }

  func testTheNativeBudgetCompletesTheTaskWhenDartNeverAnswers() throws {
    let scheduler = FakeScheduler()
    let subject = coordinator(scheduler: scheduler, budget: 0.05)
    subject.registerLaunchHandler()
    subject.attach { _, _, _ in }
    let task = FakeTask()
    try XCTUnwrap(scheduler.handler)(task)

    let done = expectation(description: "budget")
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { done.fulfill() }
    wait(for: [done], timeout: 2)
    XCTAssertEqual(task.completions, [false])
  }

  func testARunBeforeTheEngineExistsWaitsForItAndSendsTheCallState() throws {
    let scheduler = FakeScheduler()
    let subject = coordinator(scheduler: scheduler, inCall: true)
    subject.registerLaunchHandler()
    let task = FakeTask()
    try XCTUnwrap(scheduler.handler)(task)
    XCTAssertEqual(task.completions, [])

    var sent: [String: Any]?
    subject.attach { method, arguments, reply in
      XCTAssertEqual(method, "run")
      sent = arguments as? [String: Any]
      reply(["outcome": "inCall", "enabled": true])
    }
    XCTAssertEqual(sent?["inCall"] as? Bool, true)
    XCTAssertEqual(sent?["budgetMs"] as? Int, 22_000)
    XCTAssertEqual(task.completions, [true])
  }

  func testF6ConfigureDoesNotPushAPendingRequestBack() {
    let scheduler = FakeScheduler()
    let subject = coordinator(scheduler: scheduler)
    scheduler.pending = true
    // A daily user: every launch calls configure(true).
    for _ in 0..<5 { subject.configure(enabled: true) }
    drainMain()
    XCTAssertTrue(scheduler.submitted.isEmpty, "a pending request keeps its date")

    scheduler.pending = false
    subject.configure(enabled: true)
    drainMain()
    XCTAssertEqual(scheduler.submitted.count, 1)
  }

  func testF7NoEngineCompletesFalseEarlyAndDropsTheQueuedRun() throws {
    let scheduler = FakeScheduler()
    let subject = coordinator(scheduler: scheduler, budget: 5, engineWait: 0.05)
    subject.registerLaunchHandler()
    let task = FakeTask()
    try XCTUnwrap(scheduler.handler)(task)

    let waited = expectation(description: "engine wait")
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { waited.fulfill() }
    wait(for: [waited], timeout: 2)
    XCTAssertEqual(task.completions, [false], "completed early, once")

    // The engine comes up later: the dropped run must not fire.
    var calls: [String] = []
    subject.attach { method, _, _ in calls.append(method) }
    XCTAssertTrue(calls.isEmpty)
    XCTAssertEqual(task.completions, [false])
  }

  func testKillSwitchOffCancelsAndStopsRescheduling() throws {
    let scheduler = FakeScheduler()
    let subject = coordinator(scheduler: scheduler)
    subject.registerLaunchHandler()
    subject.configure(enabled: false)
    XCTAssertEqual(scheduler.cancelled, ["com.mknoon.app.update-check"])
    XCTAssertTrue(scheduler.submitted.isEmpty)

    subject.attach { _, _, reply in reply(["outcome": "disabled", "enabled": false]) }
    let task = FakeTask()
    try XCTUnwrap(scheduler.handler)(task)
    XCTAssertTrue(scheduler.submitted.isEmpty)
    XCTAssertEqual(scheduler.cancelled.count, 2)
    XCTAssertEqual(task.completions, [true])
  }

  func testOnlyUpdateRemindersOpenTheStoreAndNeverWithAPayloadUrl() {
    let scheduler = FakeScheduler()
    let subject = coordinator(scheduler: scheduler)
    var calls: [(String, Any?)] = []
    subject.attach { method, arguments, _ in calls.append((method, arguments)) }

    XCTAssertFalse(subject.handleNotificationResponse(userInfo: ["payload": "x"]))
    XCTAssertTrue(
      subject.handleNotificationResponse(
        userInfo: ["mknoon_update_check": "hard", "url": "https://evil.example"]
      )
    )
    XCTAssertEqual(calls.count, 1)
    XCTAssertEqual(calls[0].0, "openStore")
    XCTAssertNil(calls[0].1)
  }

  func testFixedIdentifiersAndNoPrompt() {
    XCTAssertEqual(
      UpdateCheckBackgroundCoordinator.notificationIdentifier(kind: "soft"),
      "mknoon.update_check.soft"
    )
    XCTAssertEqual(
      UpdateCheckBackgroundCoordinator.notificationIdentifier(kind: "hard"),
      "mknoon.update_check.hard"
    )
    XCTAssertNil(UpdateCheckBackgroundCoordinator.notificationIdentifier(kind: "url"))
    XCTAssertFalse(UpdateCheckBackgroundCoordinator.mayPost(.notDetermined))
    XCTAssertFalse(UpdateCheckBackgroundCoordinator.mayPost(.denied))
    XCTAssertTrue(UpdateCheckBackgroundCoordinator.mayPost(.authorized))
  }

  // MARK: SE-41 T4b check-now push

  private func pushUserInfo(_ extra: [AnyHashable: Any] = [:]) -> [AnyHashable: Any] {
    var info: [AnyHashable: Any] = [
      "type": "update_check",
      "aps": ["content-available": 1],
      "gcm.message_id": "1",
      "google.c.sender.id": "2",
      "from": "/topics/update_check",
    ]
    info.merge(extra) { _, new in new }
    return info
  }

  func testT4bTheKillSwitchDrivesTheUpdateCheckTopic() {
    let subject = coordinator(scheduler: FakeScheduler())
    subject.configure(enabled: true)
    subject.configure(enabled: false)
    XCTAssertEqual(topics, [true, false])
    XCTAssertEqual(UpdateCheckBackgroundCoordinator.pushTopic, "update_check")
  }

  func testT4bExactPushRunsTheSameTriggerAndCompletesOnce() {
    let subject = coordinator(scheduler: FakeScheduler())
    subject.configure(enabled: true)
    var sent: (String, [String: Any]?)?
    var pendingReply: ((Any?) -> Void)?
    subject.attach { method, arguments, reply in
      sent = (method, arguments as? [String: Any])
      pendingReply = reply
    }
    var results: [UIBackgroundFetchResult] = []
    XCTAssertTrue(subject.handleRemotePush(userInfo: pushUserInfo()) { results.append($0) })
    XCTAssertEqual(sent?.0, "run")
    XCTAssertEqual(sent?.1?["reason"] as? String, "ios_push")
    XCTAssertEqual(results, [])
    pendingReply?(["outcome": "noUpdate", "enabled": true])
    pendingReply?(["outcome": "noUpdate", "enabled": true])
    XCTAssertEqual(results, [.newData], "fetchCompletionHandler exactly once")
  }

  func testT4bAlertModeShapeIsAlsoACheck() {
    let alert: [String: Any] = [
      "content-available": 1,
      "alert": ["title-loc-key": "UPDATE_CHECK_ALERT_TITLE", "loc-key": "UPDATE_CHECK_ALERT_BODY"],
    ]
    XCTAssertTrue(
      UpdateCheckBackgroundCoordinator.isExactUpdateCheckPush(pushUserInfo(["aps": alert]))
    )
  }

  func testT4bOtherShapesFallThroughUntouched() {
    let subject = coordinator(scheduler: FakeScheduler())
    subject.configure(enabled: true)
    var calls = 0
    subject.attach { _, _, _ in calls += 1 }
    let shapes: [[AnyHashable: Any]] = [
      pushUserInfo(["x": "1"]),
      pushUserInfo(["url": "https://evil.example"]),
      pushUserInfo(["type": "update_check "]),
      pushUserInfo(["type": "Update_check"]),
      pushUserInfo(["aps": ["content-available": 0]]),
      pushUserInfo(["aps": ["alert": "hi"]]),
      ["type": "update_check"],
      ["v": "1", "w": "1", "aps": ["content-available": 1]],
    ]
    for (index, shape) in shapes.enumerated() {
      var completed = false
      XCTAssertFalse(
        subject.handleRemotePush(userInfo: shape) { _ in completed = true },
        "shape \(index) must fall through"
      )
      XCTAssertFalse(completed, "shape \(index) completion stays with the caller")
    }
    XCTAssertEqual(calls, 0)
  }

  func testT4bAtMostOnePushTriggeredCheckPerHour() {
    let subject = coordinator(scheduler: FakeScheduler())
    subject.configure(enabled: true)
    var runs = 0
    subject.attach { _, _, reply in
      runs += 1
      reply(["outcome": "noUpdate", "enabled": true])
    }
    var results: [UIBackgroundFetchResult] = []
    XCTAssertTrue(subject.handleRemotePush(userInfo: pushUserInfo()) { results.append($0) })
    clock = clock.addingTimeInterval(59 * 60)
    XCTAssertTrue(subject.handleRemotePush(userInfo: pushUserInfo()) { results.append($0) })
    clock = clock.addingTimeInterval(60)
    XCTAssertTrue(subject.handleRemotePush(userInfo: pushUserInfo()) { results.append($0) })
    clock = clock.addingTimeInterval(-10 * 60)
    XCTAssertTrue(subject.handleRemotePush(userInfo: pushUserInfo()) { results.append($0) })
    XCTAssertEqual(runs, 3, "the 59-minute push is skipped; a clock that went back frees the slot")
    XCTAssertEqual(results, [.newData, .noData, .newData, .newData])
  }

  func testT4bKillSwitchOffCompletesWithoutRunning() {
    let subject = coordinator(scheduler: FakeScheduler())
    subject.configure(enabled: false)
    var runs = 0
    subject.attach { _, _, _ in runs += 1 }
    var results: [UIBackgroundFetchResult] = []
    XCTAssertTrue(subject.handleRemotePush(userInfo: pushUserInfo()) { results.append($0) })
    XCTAssertEqual(runs, 0)
    XCTAssertEqual(results, [.noData])
  }

  func testT4bTheBudgetCompletesThePushWhenDartNeverAnswers() {
    let subject = coordinator(scheduler: FakeScheduler(), budget: 0.05)
    subject.configure(enabled: true)
    subject.attach { _, _, _ in }
    var results: [UIBackgroundFetchResult] = []
    XCTAssertTrue(subject.handleRemotePush(userInfo: pushUserInfo()) { results.append($0) })
    let done = expectation(description: "budget")
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { done.fulfill() }
    wait(for: [done], timeout: 2)
    XCTAssertEqual(results, [.failed])
  }

  func testT4bDiagnosticKeyNamesNeverIncludeValues() {
    let names = UpdateCheckBackgroundCoordinator.keyNames(
      pushUserInfo(["secret": "value-must-not-appear"])
    )
    XCTAssertEqual(
      names,
      "[aps,from,gcm.message_id,google.c.sender.id,secret,type] aps=[content-available]"
    )
    XCTAssertFalse(names.contains("value-must-not-appear"))
  }
}
