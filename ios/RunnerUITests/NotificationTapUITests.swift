import Foundation
import XCTest

final class NotificationTapUITests: XCTestCase {
  private let readyMarker = "MKNOON_APNS_TAP_READY"

  override func setUpWithError() throws {
    continueAfterFailure = false
    executionTimeAllowance = 120
  }

  func testNotificationTap() throws {
    try performNotificationTap(mode: "warm")
  }

  func testColdNotificationTap() throws {
    try performNotificationTap(mode: "cold")
  }

  func testPrepareWarmNotificationTap() throws {
    try prepareWarmNotificationTap()
  }

  func testTapExistingNotification() throws {
    try tapExistingNotification(waitForHostPush: false)
  }

  private func performNotificationTap(mode: String) throws {
    switch mode {
    case "cold":
      prepareColdNotificationTap()
    default:
      try prepareWarmNotificationTap()
    }

    try tapExistingNotification(waitForHostPush: true)
  }

  private func prepareWarmNotificationTap() throws {
    let bundleId = ProcessInfo.processInfo.environment["MKNOON_APNS_TAP_APP_BUNDLE_ID"] ?? "com.mknoon.app"
    let title = configuredValue(
      environmentName: "MKNOON_APNS_TAP_EXPECTED_TITLE",
      configKey: "expectedTitle"
    ) ?? "New Message"
    let preBackgroundWait = TimeInterval(
      configuredValue(
        environmentName: "MKNOON_APNS_TAP_PRE_BACKGROUND_WAIT_SECONDS",
        configKey: "preBackgroundWaitSeconds"
      ) ?? "8"
    ) ?? 8
    let app = XCUIApplication(bundleIdentifier: bundleId)
    let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")

    app.terminate()
    app.launch()
    allowNotificationPromptIfPresent(in: springboard)
    XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30))
    RunLoop.current.run(until: Date().addingTimeInterval(preBackgroundWait))
    XCUIDevice.shared.press(.home)
    XCTAssertTrue(springboard.wait(for: .runningForeground, timeout: 10))
    unlockSpringboardIfNeeded(springboard)
    settleOnSpringboard()
    emitReadyMarker(mode: "warm", title: title)
  }

  private func prepareColdNotificationTap() {
    let title = configuredValue(
      environmentName: "MKNOON_APNS_TAP_EXPECTED_TITLE",
      configKey: "expectedTitle"
    ) ?? "New Message"

    XCUIDevice.shared.press(.home)
    settleOnSpringboard()
    emitReadyMarker(mode: "cold", title: title)
  }

  private func tapExistingNotification(waitForHostPush: Bool) throws {
    let bundleId = ProcessInfo.processInfo.environment["MKNOON_APNS_TAP_APP_BUNDLE_ID"] ?? "com.mknoon.app"
    let title = configuredValue(
      environmentName: "MKNOON_APNS_TAP_EXPECTED_TITLE",
      configKey: "expectedTitle"
    ) ?? "New Message"
    let postTapWait = TimeInterval(ProcessInfo.processInfo.environment["MKNOON_APNS_TAP_POST_TAP_WAIT_SECONDS"] ?? "5") ?? 5
    let app = XCUIApplication(bundleIdentifier: bundleId)
    let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")

    XCUIDevice.shared.press(.home)
    XCTAssertTrue(springboard.wait(for: .runningForeground, timeout: 10))
    settleOnSpringboard()

    if waitForHostPush {
      waitForHostPushInjection()
    }
    XCTAssertTrue(
      tapNotification(title: title, springboard: springboard),
      "Could not find a Springboard notification titled \(title)"
    )
    if !app.wait(for: .runningForeground, timeout: 8) {
      XCTAssertTrue(
        tapNotification(title: title, springboard: springboard),
        "Could not re-tap a Springboard notification titled \(title)"
      )
    }
    XCTAssertTrue(
      app.wait(for: .runningForeground, timeout: 30),
      "Expected notification tap to foreground \(bundleId)"
    )
    RunLoop.current.run(until: Date().addingTimeInterval(postTapWait))
  }

  private func allowNotificationPromptIfPresent(in springboard: XCUIApplication) {
    let allowButton = springboard.buttons["Allow"]
    if allowButton.waitForExistence(timeout: 3) {
      allowButton.tap()
      return
    }

    let allowPredicate = NSPredicate(
      format: "label CONTAINS[c] %@",
      "Allow"
    )
    let matchingButton = springboard.buttons.matching(allowPredicate).firstMatch
    if matchingButton.waitForExistence(timeout: 1) {
      matchingButton.tap()
    }
  }

  private func emitReadyMarker(mode: String, title: String) {
    let line = "\(readyMarker) mode=\(mode) title=\(title)"
    if let readyFile = configuredValue(
      environmentName: "MKNOON_APNS_TAP_READY_FILE",
      configKey: "readyFile"
    ) {
      try? line.write(
        toFile: readyFile,
        atomically: true,
        encoding: .utf8
      )
    }
    NSLog("%@", line)
    fputs("\(line)\n", stdout)
    fflush(stdout)
  }

  private func settleOnSpringboard() {
    RunLoop.current.run(until: Date().addingTimeInterval(1.5))
  }

  private func waitForHostPushInjection() {
    RunLoop.current.run(until: Date().addingTimeInterval(3))
  }

  private func unlockSpringboardIfNeeded(_ springboard: XCUIApplication) {
    let bottom = springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.92))
    let top = springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.20))
    bottom.press(forDuration: 0.05, thenDragTo: top)
    RunLoop.current.run(until: Date().addingTimeInterval(1))
  }

  private func configuredValue(
    environmentName: String,
    configKey: String
  ) -> String? {
    if let value = ProcessInfo.processInfo.environment[environmentName],
       !value.isEmpty {
      return value
    }
    return tapSmokeConfig()[configKey]
  }

  private func tapSmokeConfig() -> [String: String] {
    let explicitPath = ProcessInfo.processInfo.environment["MKNOON_APNS_TAP_CONFIG_FILE"]
    let configURL: URL
    if let explicitPath, !explicitPath.isEmpty {
      configURL = URL(fileURLWithPath: explicitPath)
    } else {
      configURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("build/ios-notification-tap-ui-smoke/current_tap_config.json")
    }

    guard let data = try? Data(contentsOf: configURL),
          let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
      return [:]
    }

    var config: [String: String] = [:]
    for (key, value) in object {
      if let stringValue = value as? String, !stringValue.isEmpty {
        config[key] = stringValue
      }
    }
    return config
  }

  private func tapNotification(title: String, springboard: XCUIApplication) -> Bool {
    if tapVisibleNotification(title: title, springboard: springboard, timeout: 8) {
      return true
    }

    if tapVisibleNotificationChrome(springboard: springboard, timeout: 5) {
      return true
    }

    openNotificationCenter(from: springboard)
    if tapVisibleNotification(title: title, springboard: springboard, timeout: 20) {
      return true
    }

    return tapVisibleNotificationChrome(springboard: springboard, timeout: 10)
  }

  private func tapVisibleNotification(
    title: String,
    springboard: XCUIApplication,
    timeout: TimeInterval
  ) -> Bool {
    let predicate = NSPredicate(
      format: "label CONTAINS[c] %@ OR value CONTAINS[c] %@ OR identifier CONTAINS[c] %@",
      title,
      title,
      title
    )
    let deadline = Date().addingTimeInterval(timeout)

    while Date() < deadline {
      if tapFirstMatch(springboard.staticTexts.matching(predicate), limit: 20) {
        return true
      }
      let matches = springboard.descendants(matching: .any).matching(predicate)
      if tapFirstMatch(matches, limit: 20) {
        return true
      }
      RunLoop.current.run(until: Date().addingTimeInterval(0.5))
    }

    return false
  }

  private func tapVisibleNotificationChrome(
    springboard: XCUIApplication,
    timeout: TimeInterval
  ) -> Bool {
    let predicate = NSPredicate(
      format: "identifier CONTAINS[c] %@ OR label CONTAINS[c] %@ OR value CONTAINS[c] %@",
      "NotificationShortLookView",
      "NotificationShortLookView",
      "NotificationShortLookView"
    )
    let deadline = Date().addingTimeInterval(timeout)

    while Date() < deadline {
      let matches = springboard.descendants(matching: .any).matching(predicate)
      if tapFirstMatch(matches, limit: 10) {
        return true
      }
      RunLoop.current.run(until: Date().addingTimeInterval(0.5))
    }

    return false
  }

  private func tapFirstMatch(_ matches: XCUIElementQuery, limit: Int) -> Bool {
    let count = min(matches.count, limit)
    if count == 0 {
      return false
    }

    for index in 0..<count {
      let element = matches.element(boundBy: index)
      if element.exists && !element.frame.isEmpty {
        let start = element.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.5))
        let end = element.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: end)
        return true
      }
    }

    return false
  }

  private func openNotificationCenter(from springboard: XCUIApplication) {
    let top = springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.01))
    let center = springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.75))
    top.press(forDuration: 0.1, thenDragTo: center)
    RunLoop.current.run(until: Date().addingTimeInterval(2))
  }
}
