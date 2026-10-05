import Foundation
import Darwin

// Compiled with the unchanged shared Runner/NSE source, on the host. This proves
// process fencing and schema behavior, not signed App Group access or APNs.
@main
enum NotificationAsyncOwnerNativeTest {
  static func require(_ condition: @autoclosure () -> Bool, _ label: String) {
    guard condition() else { fatalError(label) }
  }

  static func main() throws {
    let token = String(repeating: "a", count: 64)
    if CommandLine.arguments.count == 3 {
      var owner = IosNotificationAsyncOwner.begin(token: token)!
      owner["version"] = 1
      owner["token"] = token
      try JSONSerialization.data(withJSONObject: owner).write(
        to: URL(fileURLWithPath: CommandLine.arguments[2]), options: .atomic)
      print("ready")
      fflush(stdout)
      _ = readLine()
      return
    }
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("notification-owner-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let marker = directory.appendingPathComponent(IosNotificationAsyncOwner.markerName)
    require(IosNotificationAsyncOwner.permitsNativeEntry(directory: directory), "absent marker")
    var owner = IosNotificationAsyncOwner.begin(token: token)!
    owner["version"] = 1
    owner["token"] = token
    try JSONSerialization.data(withJSONObject: owner).write(to: marker)
    require(!IosNotificationAsyncOwner.permitsNativeEntry(directory: directory), "live Runner token")
    IosNotificationAsyncOwner.end(token: token)
    require(IosNotificationAsyncOwner.permitsNativeEntry(directory: directory), "completed token")
    var malformed = owner
    malformed["version"] = true
    require(IosNotificationAsyncOwner.isAlive(malformed), "boolean is not schema version")
    malformed = owner
    malformed["pid"] = Double(getpid())
    require(IosNotificationAsyncOwner.isAlive(malformed), "floating PID is not authority")
    try Data("{\"version\":2}".utf8).write(to: marker)
    require(!IosNotificationAsyncOwner.permitsNativeEntry(directory: directory), "unknown schema")
    try FileManager.default.removeItem(at: marker)
    try FileManager.default.createSymbolicLink(at: marker, withDestinationURL: directory)
    require(!IosNotificationAsyncOwner.permitsNativeEntry(directory: directory), "symlink")
    try FileManager.default.removeItem(at: marker)

    let child = Process()
    child.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
    child.arguments = ["child", marker.path]
    let input = Pipe(), output = Pipe()
    child.standardInput = input; child.standardOutput = output
    try child.run()
    defer { if child.isRunning { child.terminate(); child.waitUntilExit() } }
    require(!output.fileHandleForReading.availableData.isEmpty, "child readiness")
    require(!IosNotificationAsyncOwner.permitsNativeEntry(directory: directory), "foreign live owner")
    kill(child.processIdentifier, SIGSTOP)
    require(!IosNotificationAsyncOwner.permitsNativeEntry(directory: directory), "suspended owner")
    kill(child.processIdentifier, SIGKILL)
    child.waitUntilExit()
    require(IosNotificationAsyncOwner.permitsNativeEntry(directory: directory), "dead process recovery")
    var reused = owner
    reused["processStart"] = "0:0"
    require(!IosNotificationAsyncOwner.isAlive(reused), "PID birth mismatch")
    print("PASS: missing/live/completed/malformed/symlink/foreign/suspended/dead/PID-birth owner fencing")
  }
}
