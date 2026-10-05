// Fixture-only channel adapter. It calls the production registry and kernel
// owner guard; it neither implements another lock nor accesses account data.
import Flutter
import UIKit
import Darwin

func logGroupMediaNativeProof(_ message: String) { print(message) }

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var admission = true
  private var tasks = [UIBackgroundTaskIdentifier]()
  private let registry = CriticalTaskRegistry.shared
  private var channel: FlutterMethodChannel?

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    let channel = FlutterMethodChannel(name: "com.mknoon/go_bridge", binaryMessenger: engineBridge.applicationRegistrar.messenger())
    self.channel = channel
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else { return result(nil) }
      switch call.method {
      case "notificationLockBegin":
        let task = self.admission ? self.registry.beginIfLive(withName: "fixture.notificationLock") : nil
        if let task { self.tasks.append(task) }
        result(task?.rawValue)
      case "notificationLockIsActive":
        result(self.registry.isLive(UIBackgroundTaskIdentifier(rawValue: call.arguments as! Int)))
      case "notificationLockEnd":
        self.registry.end(UIBackgroundTaskIdentifier(rawValue: call.arguments as! Int)); result(nil)
      case "notificationLockOwnerBegin": result(IosNotificationAsyncOwner.begin(token: call.arguments as! String))
      case "notificationLockOwnerIsAlive": result(IosNotificationAsyncOwner.isAlive(call.arguments as! [String: Any]))
      case "notificationLockOwnerEnd": IosNotificationAsyncOwner.end(token: call.arguments as! String); result(nil)
      case "fixtureAdmission": self.admission = call.arguments as! Bool; result(nil)
      case "fixtureDirectory":
        result(FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
          .appendingPathComponent("NotificationLockFixture").path)
      case "fixtureProbe":
        let path = call.arguments as! String
        let fd = open(path, O_RDWR)
        let available = fd >= 0 && flock(fd, LOCK_EX | LOCK_NB) == 0
        let permitted = available && IosNotificationAsyncOwner.permitsNativeEntry(directory: URL(fileURLWithPath: path).deletingLastPathComponent())
        if available { _ = flock(fd, LOCK_UN) }
        if fd >= 0 { close(fd) }
        result(["lockFree": available, "nativeEntryPermitted": permitted,
          "grants": self.tasks.filter { self.registry.isLive($0) }.count])
      default: result(FlutterMethodNotImplemented)
      }
    }
  }
}
