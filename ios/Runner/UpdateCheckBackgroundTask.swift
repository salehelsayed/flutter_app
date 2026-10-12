import BackgroundTasks
import CallKit
import Flutter
import Foundation
import UserNotifications

/// SE-41 T4a: calls a BG task's completion exactly once, whichever comes
/// first: the Dart reply, the expiration handler or the native budget.
final class UpdateCheckTaskCompletionGate {
  private let lock = NSLock()
  private var completed = false
  private let complete: (Bool) -> Void

  init(complete: @escaping (Bool) -> Void) {
    self.complete = complete
  }

  var isCompleted: Bool {
    lock.lock()
    defer { lock.unlock() }
    return completed
  }

  /// Returns false when the task was already completed.
  @discardableResult
  func finish(success: Bool) -> Bool {
    lock.lock()
    if completed {
      lock.unlock()
      return false
    }
    completed = true
    lock.unlock()
    complete(success)
    return true
  }
}

/// The part of BGAppRefreshTask the coordinator uses (tests fake it).
protocol UpdateCheckRefreshTask: AnyObject {
  var expirationHandler: (() -> Void)? { get set }
  func setTaskCompleted(success: Bool)
}

extension BGAppRefreshTask: UpdateCheckRefreshTask {}

protocol UpdateCheckTaskScheduling {
  func register(identifier: String, handler: @escaping (UpdateCheckRefreshTask) -> Void) -> Bool
  func submit(identifier: String, earliestBeginDate: Date) throws
  func cancel(identifier: String)
}

struct SystemUpdateCheckTaskScheduler: UpdateCheckTaskScheduling {
  func register(identifier: String, handler: @escaping (UpdateCheckRefreshTask) -> Void) -> Bool {
    BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: .main) { task in
      guard let refresh = task as? BGAppRefreshTask else {
        task.setTaskCompleted(success: false)
        return
      }
      handler(refresh)
    }
  }

  func submit(identifier: String, earliestBeginDate: Date) throws {
    let request = BGAppRefreshTaskRequest(identifier: identifier)
    request.earliestBeginDate = earliestBeginDate
    try BGTaskScheduler.shared.submit(request)
  }

  func cancel(identifier: String) {
    BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: identifier)
  }
}

/// SE-41 T4a: the iOS background update check.
///
/// - The BG app refresh task runs in the normal main engine (D1). It is
///   forwarded to ONE Dart trigger, `run` on `mknoon/update_check_background`
///   (UpdateCheckBackgroundHost). A run asked for before the engine exists
///   waits for [attach]; it never starts a second engine.
/// - Every run submits the next request (earliest begin about 12 h) while
///   the kill switch is on, and completes the task exactly once.
/// - `configure` from Dart schedules (switch on) or cancels (switch off).
/// - `notify` posts the reminder with a fixed identifier per kind. It never
///   asks for permission; not allowed means nothing is posted.
/// - A tap on the reminder calls Dart `openStore`, which opens the built-in
///   App Store page. Nothing from the notification reaches the URL.
///
/// Limits (docs/release/se41-update-check-background.md): iOS runs the task
/// at its own discretion and never after the user force-quits the app.
final class UpdateCheckBackgroundCoordinator {
  static let taskIdentifier = "com.mknoon.app.update-check"
  static let channelName = "mknoon/update_check_background"
  static let refreshInterval: TimeInterval = 12 * 60 * 60
  static let nativeBudget: TimeInterval = 25
  static let dartBudgetMs = 22_000
  static let enabledDefaultsKey = "se41.updateCheck.backgroundEnabled"
  static let notificationKindKey = "mknoon_update_check"

  typealias DartInvoker = (_ method: String, _ arguments: Any?, _ reply: @escaping (Any?) -> Void) -> Void

  private let scheduler: UpdateCheckTaskScheduling
  private let defaults: UserDefaults
  private let isInCall: () -> Bool
  private let budget: TimeInterval
  private let queue: DispatchQueue
  private let now: () -> Date
  private var channel: FlutterMethodChannel?
  private var invoker: DartInvoker?
  private var pending: [(DartInvoker) -> Void] = []

  init(
    scheduler: UpdateCheckTaskScheduling = SystemUpdateCheckTaskScheduler(),
    defaults: UserDefaults = .standard,
    isInCall: @escaping () -> Bool = UpdateCheckBackgroundCoordinator.systemHasCall,
    budget: TimeInterval = UpdateCheckBackgroundCoordinator.nativeBudget,
    queue: DispatchQueue = .main,
    now: @escaping () -> Date = Date.init
  ) {
    self.scheduler = scheduler
    self.defaults = defaults
    self.isInCall = isInCall
    self.budget = budget
    self.queue = queue
    self.now = now
  }

  /// Any call on the device, ringing or active (CallKit covers ours too).
  static func systemHasCall() -> Bool {
    CXCallObserver().calls.contains { !$0.hasEnded }
  }

  /// Call before didFinishLaunching returns.
  @discardableResult
  func registerLaunchHandler() -> Bool {
    scheduler.register(identifier: Self.taskIdentifier) { [weak self] task in
      guard let self else {
        task.setTaskCompleted(success: false)
        return
      }
      self.handle(task: task)
    }
  }

  func attach(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: Self.channelName, binaryMessenger: messenger)
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handle(call: call, result: result) ?? result(FlutterMethodNotImplemented)
    }
    self.channel = channel
    attach { method, arguments, reply in
      channel.invokeMethod(method, arguments: arguments) { reply($0) }
    }
  }

  func attach(invoker: @escaping DartInvoker) {
    self.invoker = invoker
    let waiting = pending
    pending.removeAll()
    waiting.forEach { $0(invoker) }
  }

  func handle(task: UpdateCheckRefreshTask) {
    if isEnabled { scheduleNext() }
    let gate = UpdateCheckTaskCompletionGate { success in
      task.setTaskCompleted(success: success)
    }
    task.expirationHandler = {
      NSLog("[SE41_UPDATE_CHECK] bg_task expired")
      gate.finish(success: false)
    }
    queue.asyncAfter(deadline: .now() + budget) {
      if gate.finish(success: false) {
        NSLog("[SE41_UPDATE_CHECK] bg_task budget_exhausted")
      }
    }
    NSLog("[SE41_UPDATE_CHECK] bg_task started")
    runInDart(reason: "ios_bg_app_refresh") { result in
      let outcome = result?["outcome"] as? String ?? "no_reply"
      if gate.finish(success: result != nil) {
        NSLog("[SE41_UPDATE_CHECK] bg_task completed outcome=%@", outcome)
      }
    }
  }

  func runInDart(reason: String, completion: @escaping ([String: Any]?) -> Void) {
    let arguments: [String: Any] = [
      "reason": reason,
      "budgetMs": Self.dartBudgetMs,
      "inCall": isInCall(),
    ]
    withInvoker { invoke in
      invoke("run", arguments) { [weak self] reply in
        let result = reply as? [String: Any]
        if result?["enabled"] as? Bool == false { self?.configure(enabled: false) }
        completion(result)
      }
    }
  }

  var isEnabled: Bool { defaults.bool(forKey: Self.enabledDefaultsKey) }

  func configure(enabled: Bool) {
    defaults.set(enabled, forKey: Self.enabledDefaultsKey)
    if enabled {
      scheduleNext()
    } else {
      scheduler.cancel(identifier: Self.taskIdentifier)
    }
  }

  func scheduleNext() {
    do {
      try scheduler.submit(
        identifier: Self.taskIdentifier,
        earliestBeginDate: now().addingTimeInterval(Self.refreshInterval)
      )
    } catch {
      // Simulator, Background App Refresh off, or too many pending requests.
      NSLog("[SE41_UPDATE_CHECK] bg_task submit_failed %@", String(describing: error))
    }
  }

  /// True when the response belongs to an update reminder; it is then handled.
  func handleNotificationResponse(userInfo: [AnyHashable: Any]) -> Bool {
    guard userInfo[Self.notificationKindKey] is String else { return false }
    withInvoker { invoke in invoke("openStore", nil) { _ in } }
    return true
  }

  static func notificationIdentifier(kind: String) -> String? {
    switch kind {
    case "soft", "hard": return "mknoon.update_check.\(kind)"
    default: return nil
    }
  }

  private func withInvoker(_ work: @escaping (DartInvoker) -> Void) {
    if let invoker {
      work(invoker)
    } else {
      pending.append(work)
    }
  }

  private func handle(call: FlutterMethodCall, result: @escaping FlutterResult) {
    let arguments = call.arguments as? [String: Any]
    switch call.method {
    case "configure":
      guard let enabled = arguments?["enabled"] as? Bool else {
        result(FlutterError(code: "bad_args", message: "enabled is required", details: nil))
        return
      }
      configure(enabled: enabled)
      result(nil)
    case "notify":
      guard
        let kind = arguments?["kind"] as? String,
        let identifier = Self.notificationIdentifier(kind: kind),
        let title = arguments?["title"] as? String, !title.isEmpty,
        let body = arguments?["body"] as? String, !body.isEmpty
      else {
        result(false)
        return
      }
      post(identifier: identifier, kind: kind, title: title, body: body) { posted in
        DispatchQueue.main.async { result(posted) }
      }
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func post(
    identifier: String,
    kind: String,
    title: String,
    body: String,
    completion: @escaping (Bool) -> Void
  ) {
    let center = UNUserNotificationCenter.current()
    center.getNotificationSettings { settings in
      guard Self.mayPost(settings.authorizationStatus) else {
        completion(false)
        return
      }
      let content = UNMutableNotificationContent()
      content.title = title
      content.body = body
      content.sound = .default
      content.userInfo = [Self.notificationKindKey: kind]
      // Same identifier per kind: a reminder replaces the previous one.
      let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
      center.add(request) { error in completion(error == nil) }
    }
  }

  /// Never asks: only an existing grant counts.
  static func mayPost(_ status: UNAuthorizationStatus) -> Bool {
    switch status {
    case .authorized, .provisional, .ephemeral: return true
    default: return false
    }
  }
}
