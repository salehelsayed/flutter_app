import XCTest

final class NotificationTapUITests: XCTestCase {
  private let readyMarker = "MKNOON_APNS_TAP_READY"

  override func setUpWithError() throws {
    continueAfterFailure = false
  }

  func testNotificationTap() throws {
    try performNotificationTap(mode: "warm")
  }

  func testColdNotificationTap() throws {
    try performNotificationTap(mode: "cold")
  }

  private func performNotificationTap(mode: String) throws {
    let bundleId = ProcessInfo.processInfo.environment["MKNOON_APNS_TAP_APP_BUNDLE_ID"] ?? "com.mknoon.app"
    let title = ProcessInfo.processInfo.environment["MKNOON_APNS_TAP_EXPECTED_TITLE"] ?? "New Message"
    let postTapWait = TimeInterval(ProcessInfo.processInfo.environment["MKNOON_APNS_TAP_POST_TAP_WAIT_SECONDS"] ?? "5") ?? 5

    let app = XCUIApplication(bundleIdentifier: bundleId)
    let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")

    switch mode {
    case "cold":
      XCUIDevice.shared.press(.home)
      print("\(readyMarker) mode=cold title=\(title)")
    default:
      app.terminate()
      app.launch()
      allowNotificationPromptIfPresent(in: springboard)
      XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30))
      XCUIDevice.shared.press(.home)
      XCTAssertTrue(springboard.wait(for: .runningForeground, timeout: 10))
      print("\(readyMarker) mode=warm title=\(title)")
    }

    XCTAssertTrue(
      tapNotification(title: title, springboard: springboard),
      "Could not find a Springboard notification titled \(title)"
    )
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

  private func tapNotification(title: String, springboard: XCUIApplication) -> Bool {
    if tapVisibleNotification(title: title, springboard: springboard, timeout: 20) {
      return true
    }

    if tapVisibleNotificationChrome(springboard: springboard, timeout: 25) {
      return true
    }

    openNotificationCenter(from: springboard)
    if tapVisibleNotification(title: title, springboard: springboard, timeout: 15) {
      return true
    }

    return tapVisibleNotificationChrome(springboard: springboard, timeout: 5)
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
      let matches = springboard.descendants(matching: .any).matching(predicate)
      let count = min(matches.count, 20)
      if count > 0 {
        for index in 0..<count {
          let element = matches.element(boundBy: index)
          if element.exists && element.isHittable {
            element.tap()
            return true
          }
          if element.exists {
            element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            return true
          }
        }
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
      let count = min(matches.count, 10)
      if count > 0 {
        for index in 0..<count {
          let element = matches.element(boundBy: index)
          if element.exists && !element.frame.isEmpty {
            if element.isHittable {
              element.tap()
              return true
            }
            element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            return true
          }
        }
      }
      RunLoop.current.run(until: Date().addingTimeInterval(0.5))
    }

    return false
  }

  private func openNotificationCenter(from springboard: XCUIApplication) {
    let top = springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.01))
    let center = springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.65))
    top.press(forDuration: 0.1, thenDragTo: center)
    RunLoop.current.run(until: Date().addingTimeInterval(1))
  }
}
