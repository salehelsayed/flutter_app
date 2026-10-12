import Foundation
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
  private let suite = "UpdateCheckBackgroundTaskTests"

  override func setUp() {
    super.setUp()
    defaults = UserDefaults(suiteName: suite)
    defaults.removePersistentDomain(forName: suite)
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
      now: { Date(timeIntervalSince1970: 1_000_000) }
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
}
