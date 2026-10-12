import BackgroundTasks
import CallKit
import FirebaseMessaging
import Flutter
import Foundation
import UIKit
import UserNotifications
import os.log

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
  func hasPendingRequest(identifier: String, completion: @escaping (Bool) -> Void)
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

  func hasPendingRequest(identifier: String, completion: @escaping (Bool) -> Void) {
    BGTaskScheduler.shared.getPendingTaskRequests { requests in
      completion(requests.contains { $0.identifier == identifier })
    }
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
/// T4b check-now push: while the kill switch is on the app is subscribed to
/// the FCM topic `update_check`. An exact `{"type":"update_check"}` push runs
/// the same Dart trigger (reason `ios_push`) at most once per hour and calls
/// the fetch completion handler exactly once within the native budget. It
/// shows nothing; an `--ios-alert` push is drawn by iOS from the fixed
/// Localizable.strings keys.
///
/// Limits (docs/release/se41-update-check-background.md): iOS runs the task
/// at its own discretion and never after the user force-quits the app.
final class UpdateCheckBackgroundCoordinator {
  static let taskIdentifier = "com.mknoon.app.update-check"
  static let channelName = "mknoon/update_check_background"
  static let refreshInterval: TimeInterval = 12 * 60 * 60
  static let nativeBudget: TimeInterval = 25
  static let dartBudgetMs = 22_000
  /// A run asked for before the Flutter engine exists waits this long, then
  /// completes false (T4a F7): under UIScene a background launch may never
  /// create the engine.
  static let engineWait: TimeInterval = 5
  static let enabledDefaultsKey = "se41.updateCheck.backgroundEnabled"
  static let notificationKindKey = "mknoon_update_check"
  static let pushTopic = "update_check"
  static let pushPayloadType = "update_check"
  static let pushMinInterval: TimeInterval = 60 * 60
  static let lastPushCheckDefaultsKey = "se41.updateCheck.lastPushCheckAt"

  typealias DartInvoker = (_ method: String, _ arguments: Any?, _ reply: @escaping (Any?) -> Void) -> Void

  private let scheduler: UpdateCheckTaskScheduling
  private let defaults: UserDefaults
  private let isInCall: () -> Bool
  private let budget: TimeInterval
  private let engineWait: TimeInterval
  private let queue: DispatchQueue
  private let now: () -> Date
  private let setTopicSubscribed: (Bool) -> Void
  private var channel: FlutterMethodChannel?
  private var invoker: DartInvoker?
  private var pending: [(id: UUID, work: (DartInvoker) -> Void)] = []

  init(
    scheduler: UpdateCheckTaskScheduling = SystemUpdateCheckTaskScheduler(),
    defaults: UserDefaults = .standard,
    isInCall: @escaping () -> Bool = UpdateCheckBackgroundCoordinator.systemHasCall,
    budget: TimeInterval = UpdateCheckBackgroundCoordinator.nativeBudget,
    engineWait: TimeInterval = UpdateCheckBackgroundCoordinator.engineWait,
    queue: DispatchQueue = .main,
    now: @escaping () -> Date = Date.init,
    setTopicSubscribed: @escaping (Bool) -> Void = UpdateCheckBackgroundCoordinator.setFirebaseTopic
  ) {
    self.scheduler = scheduler
    self.defaults = defaults
    self.isInCall = isInCall
    self.budget = budget
    self.engineWait = engineWait
    self.queue = queue
    self.now = now
    self.setTopicSubscribed = setTopicSubscribed
  }

  static func setFirebaseTopic(_ subscribed: Bool) {
    if subscribed {
      Messaging.messaging().subscribe(toTopic: pushTopic)
    } else {
      Messaging.messaging().unsubscribe(fromTopic: pushTopic)
    }
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
    waiting.forEach { $0.work(invoker) }
  }

  func handle(task: UpdateCheckRefreshTask) {
    if isEnabled { scheduleNext() }
    let gate = UpdateCheckTaskCompletionGate { success in
      task.setTaskCompleted(success: success)
    }
    task.expirationHandler = {
      Self.log("bg_task expired")
      gate.finish(success: false)
    }
    queue.asyncAfter(deadline: .now() + budget) {
      if gate.finish(success: false) {
        Self.log("bg_task budget_exhausted")
      }
    }
    Self.log("bg_task started")
    runGated(reason: "ios_bg_app_refresh", label: "bg_task", gate: gate)
  }

  /// T4b: true when [userInfo] is the exact check-now push; the completion
  /// handler is then called exactly once (within the native budget) and the
  /// caller must not forward the push. Anything else returns false untouched.
  func handleRemotePush(
    userInfo: [AnyHashable: Any],
    completion: @escaping (UIBackgroundFetchResult) -> Void
  ) -> Bool {
    guard Self.isExactUpdateCheckPush(userInfo) else {
      if userInfo["type"] != nil || Self.isContentAvailable(userInfo) {
        // Key names only, never values: shows why a push was not claimed.
        Self.log("push not matched keys=\(Self.keyNames(userInfo))")
      }
      return false
    }
    guard isEnabled, takePushSlot() else {
      Self.log("push skipped enabled=\(isEnabled)")
      completion(.noData)
      return true
    }
    let gate = UpdateCheckTaskCompletionGate { success in
      completion(success ? .newData : .failed)
    }
    queue.asyncAfter(deadline: .now() + budget) {
      if gate.finish(success: false) {
        Self.log("push budget_exhausted")
      }
    }
    Self.log("push started")
    runGated(reason: "ios_push", label: "push", gate: gate)
    return true
  }

  /// Exactly `{"type":"update_check"}` plus the keys APNs and FCM add
  /// (`aps`, `gcm.*`, `google.*`, `from`, `collapse_key`), with
  /// `content-available: 1`. An extra app field means it is not ours.
  static func isExactUpdateCheckPush(_ userInfo: [AnyHashable: Any]) -> Bool {
    guard
      let aps = userInfo["aps"] as? [String: Any],
      (aps["content-available"] as? NSNumber)?.intValue == 1
    else { return false }
    let keys = userInfo.keys.compactMap { $0 as? String }
    guard keys.count == userInfo.count else { return false }
    let appKeys = keys.filter { key in
      !(key == "aps" || key == "from" || key == "collapse_key"
        || key.hasPrefix("gcm.") || key.hasPrefix("google."))
    }
    return appKeys == ["type"] && userInfo["type"] as? String == pushPayloadType
  }

  static func isContentAvailable(_ userInfo: [AnyHashable: Any]) -> Bool {
    ((userInfo["aps"] as? [String: Any])?["content-available"] as? NSNumber)?.intValue == 1
  }

  /// Sorted top-level key names plus the aps key names, for diagnostics.
  static func keyNames(_ userInfo: [AnyHashable: Any]) -> String {
    let top = userInfo.keys.map { String(describing: $0) }.sorted()
    let aps = (userInfo["aps"] as? [String: Any])?.keys.sorted() ?? []
    return "[\(top.joined(separator: ","))] aps=[\(aps.joined(separator: ","))]"
  }

  /// Takes the hourly push slot if free. A clock that went back frees it.
  func takePushSlot() -> Bool {
    let nowSeconds = now().timeIntervalSince1970
    if let last = defaults.object(forKey: Self.lastPushCheckDefaultsKey) as? Double,
      nowSeconds >= last, nowSeconds - last < Self.pushMinInterval {
      return false
    }
    defaults.set(nowSeconds, forKey: Self.lastPushCheckDefaultsKey)
    return true
  }

  private func runGated(reason: String, label: String, gate: UpdateCheckTaskCompletionGate) {
    let queuedId = runInDart(reason: reason) { result in
      let outcome = result?["outcome"] as? String ?? "no_reply"
      if gate.finish(success: result != nil) {
        Self.log("\(label) completed outcome=\(outcome)")
      }
    }
    guard let queuedId else { return }
    queue.asyncAfter(deadline: .now() + engineWait) { [weak self] in
      guard let self, self.invoker == nil else { return }
      // Drop the queued run so it cannot fire later, after the task ended.
      self.pending.removeAll { $0.id == queuedId }
      Self.log("update-check: no engine")
      gate.finish(success: false)
    }
  }

  /// Returns the id of the queued work when no engine is attached yet.
  @discardableResult
  func runInDart(reason: String, completion: @escaping ([String: Any]?) -> Void) -> UUID? {
    let arguments: [String: Any] = [
      "reason": reason,
      "budgetMs": Self.dartBudgetMs,
      "inCall": isInCall(),
    ]
    return withInvoker { invoke in
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
    setTopicSubscribed(enabled)
    if enabled {
      // Every launch calls configure. Re-submitting would move the earliest
      // begin date 12 h ahead each time, so a daily user would never get a
      // run (T4a F6). Submit only when nothing is pending; each run still
      // reschedules itself at its start.
      scheduler.hasPendingRequest(identifier: Self.taskIdentifier) { [weak self] pending in
        guard !pending else { return }
        DispatchQueue.main.async { self?.scheduleNext() }
      }
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
      Self.log("bg_task submit_failed \(error.localizedDescription)")
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

  @discardableResult
  private func withInvoker(_ work: @escaping (DartInvoker) -> Void) -> UUID? {
    if let invoker {
      work(invoker)
      return nil
    }
    let id = UUID()
    pending.append((id: id, work: work))
    return id
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

  /// Public os_log: a release build hides NSLog text on the device. The text
  /// carries no user data, only the step and the outcome.
  static func log(_ message: String) {
    os_log("%{public}@", log: updateCheckLog, type: .default, "[SE41_UPDATE_CHECK] \(message)")
  }

  /// Own subsystem, like GoBridge's proof log, which shows its text in a
  /// release build's device syslog.
  private static let updateCheckLog = OSLog(subsystem: "com.mknoon.se41", category: "update-check")

  /// Never asks: only an existing grant counts.
  static func mayPost(_ status: UNAuthorizationStatus) -> Bool {
    switch status {
    case .authorized, .provisional, .ephemeral: return true
    default: return false
    }
  }
}
