// Fixture-only NSE observer. It uses the shared production guard under the
// same coordination flock and never initializes or mutates the ledger.
import Foundation
import Darwin
import UserNotifications

@objc(NotificationService)
final class NotificationService: UNNotificationServiceExtension {
  private let completionLock = NSLock()
  private var completion: ((UNNotificationContent) -> Void)?
  private var original: UNNotificationContent?

  override func didReceive(
    _ request: UNNotificationRequest,
    withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void
  ) {
    completionLock.lock()
    completion = contentHandler
    original = request.content
    completionLock.unlock()
    let content = request.content.mutableCopy() as! UNMutableNotificationContent
    content.title = "Notification lock boundary fixture"
    guard request.content.userInfo["fixture"] as? String == "notification-lock-v1",
          let probe = request.content.userInfo["probe"] as? String,
          probe.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil,
          let group = Bundle.main.object(forInfoDictionaryKey: "FixtureAppGroup") as? String,
          group == "group.com.mknoon.fixture.notificationLock",
          let root = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group)
    else {
      content.body = "FIXTURE_OR_GROUP_UNAVAILABLE"
      finish(content)
      return
    }
    let directory = root.appendingPathComponent("NotificationLockFixture")
    let fd = open(directory.appendingPathComponent(".coordination.lock").path, O_RDWR)
    let lockFree = fd >= 0 && flock(fd, LOCK_EX | LOCK_NB) == 0
    var permitted = false
    var seedRetained = false
    if lockFree {
      permitted = IosNotificationAsyncOwner.permitsNativeEntry(directory: directory)
      let ledger = directory.appendingPathComponent("local_notification_ledger_v1.json")
      if let bytes = try? Data(contentsOf: ledger),
         let envelope = try? JSONSerialization.jsonObject(with: bytes) as? [String: Any],
         let records = envelope["records"] as? [String: Any],
         let seed = records[String(repeating: "b", count: 64)] as? [String: Any] {
        seedRetained = seed["effectPhase"] as? String == "SETTLED"
      }
      _ = flock(fd, LOCK_UN)
    }
    if fd >= 0 { close(fd) }
    let state = fd < 0 ? "FIXTURE_NOT_READY"
      : !lockFree ? "KERNEL_BUSY" : permitted ? "AVAILABLE" : "RUNNER_LIVE_OR_UNCERTAIN"
    let receipt: [String: Any] = [
      "version": 1, "probe": probe, "state": state,
      "lockFree": lockFree, "nativeEntryPermitted": permitted,
      "seedRetained": seedRetained, "nsePid": Int(getpid())
    ]
    // Observation is written after unlocking; no protected state is changed.
    // CoreDevice permits fixture exports only below Documents/Library/tmp,
    // including App Group containers. Keep evidence in its own namespace.
    if let data = try? JSONSerialization.data(withJSONObject: receipt, options: [.sortedKeys]) {
      let evidence = root.appendingPathComponent("Documents/NotificationLockFixtureEvidence")
      do {
        try FileManager.default.createDirectory(at: evidence, withIntermediateDirectories: true)
        try data.write(to: evidence.appendingPathComponent("nse-probe-\(probe).json"), options: .atomic)
      } catch {
        content.body = "FIXTURE_EVIDENCE_WRITE_FAILED"
        finish(content)
        return
      }
    }
    content.body = "\(state); seed=\(seedRetained ? "RETAINED" : "MISSING")"
    finish(content)
  }

  override func serviceExtensionTimeWillExpire() {
    completionLock.lock()
    let content = original
    completionLock.unlock()
    if let content { finish(content) }
  }

  private func finish(_ content: UNNotificationContent) {
    completionLock.lock()
    let handler = completion
    completion = nil
    completionLock.unlock()
    handler?(content)
  }
}
