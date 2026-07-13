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

  /// Plan 256 TC-14: cold-tap an already staged reaction notification and
  /// require a real conversation semantic from the app. The host staging
  /// controller owns APNs/NSE delivery and writes the existing tap config;
  /// this selector never accepts a manual tap or a route-only boolean.
  func testReactionNotificationTap() throws {
    let bundleId = ProcessInfo.processInfo.environment["MKNOON_APNS_TAP_APP_BUNDLE_ID"] ?? "com.mknoon.app"
    guard let expectedConversationLabel = configuredValue(
      environmentName: "MKNOON_REACTION_EXPECTED_CONVERSATION_LABEL",
      configKey: "expectedConversationLabel"
    ), !expectedConversationLabel.isEmpty else {
      XCTFail("Plan 256 reaction tap requires expectedConversationLabel in the staged tap config")
      return
    }

    let app = XCUIApplication(bundleIdentifier: bundleId)
    app.terminate()
    try tapExistingNotification(
      waitForHostPush: false,
      requireTitleMatchedNotification: true
    )

    let conversationMarker = "mknoon.conversation.\(expectedConversationLabel)"
    let rendered = app.descendants(matching: .any)
      .matching(identifier: conversationMarker)
      .firstMatch
    XCTAssertTrue(
      rendered.waitForExistence(timeout: 20),
      "Reaction notification tap did not render marker \(conversationMarker)"
    )
    NSLog("MKNOON_256_REACTION_TAP conversation_rendered=true cold_launch=true")
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
    XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30))
    // #21 fix: poll for the (late-appearing) notification-permission alert across
    // the pre-background window and grant it the moment it shows, instead of a
    // one-shot check that the prompt usually beats. Returns early once granted,
    // otherwise the poll itself doubles as the app-settle wait.
    allowNotificationPromptIfPresent(
      in: springboard,
      timeout: max(preBackgroundWait, 15)
    )
    RunLoop.current.run(until: Date().addingTimeInterval(2))
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

  private func tapExistingNotification(
    waitForHostPush: Bool,
    requireTitleMatchedNotification: Bool = false
  ) throws {
    let bundleId = ProcessInfo.processInfo.environment["MKNOON_APNS_TAP_APP_BUNDLE_ID"] ?? "com.mknoon.app"
    let title = configuredValue(
      environmentName: "MKNOON_APNS_TAP_EXPECTED_TITLE",
      configKey: "expectedTitle"
    ) ?? "New Message"
    let expectedBody = configuredValue(
      environmentName: "MKNOON_APNS_TAP_EXPECTED_BODY",
      configKey: "expectedBody"
    )
    let routeCategory = configuredValue(
      environmentName: "MKNOON_APNS_TAP_ROUTE_CATEGORY",
      configKey: "routeCategory"
    ) ?? "unspecified"
    let postTapWait = TimeInterval(ProcessInfo.processInfo.environment["MKNOON_APNS_TAP_POST_TAP_WAIT_SECONDS"] ?? "5") ?? 5
    let app = XCUIApplication(bundleIdentifier: bundleId)
    let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")

    XCUIDevice.shared.press(.home)
    XCTAssertTrue(springboard.wait(for: .runningForeground, timeout: 10))
    settleOnSpringboard()
    // #21: a permission alert can still be up over Springboard (granted late, or
    // raised after we backgrounded). Clear it before hunting the banner, else the
    // notification stays undelivered/untappable.
    allowNotificationPromptIfPresent(in: springboard, timeout: 3)

    if waitForHostPush {
      waitForHostPushInjection()
    }
    if let expectedBody {
      XCTAssertTrue(
        notificationTextExists(
          expectedBody,
          springboard: springboard,
          timeout: 8
        ) || {
          openNotificationCenter(from: springboard)
          return notificationTextExists(
            expectedBody,
            springboard: springboard,
            timeout: 12
          )
        }(),
        "Could not find expected Springboard notification body \(expectedBody)"
      )
      NSLog(
        "MKNOON_IOS_NOTIFICATION_PRESENTED title=%@ body=%@ routeCategory=%@",
        title,
        expectedBody,
        routeCategory
      )
    }
    XCTAssertTrue(
      tapNotification(
        title: title,
        springboard: springboard,
        allowGenericChromeFallback: !requireTitleMatchedNotification
      ),
      "Could not find a Springboard notification titled \(title)"
    )
    if !app.wait(for: .runningForeground, timeout: 8) {
      XCTAssertTrue(
        tapNotification(
          title: title,
          springboard: springboard,
          allowGenericChromeFallback: !requireTitleMatchedNotification
        ),
        "Could not re-tap a Springboard notification titled \(title)"
      )
    }
    XCTAssertTrue(
      app.wait(for: .runningForeground, timeout: 30),
      "Expected notification tap to foreground \(bundleId)"
    )
    RunLoop.current.run(until: Date().addingTimeInterval(postTapWait))
  }

  /// Grants the iOS "Would Like to Send You Notifications" permission alert.
  ///
  /// #21 fix: the alert appears several seconds AFTER `app.launch()` (the app
  /// requests authorization only once startup settles), so a one-shot check
  /// right after launch races — and loses to — the prompt, leaving it lingering
  /// over Springboard and blocking notification delivery. Poll across [timeout]
  /// and tap "Allow" the moment it appears. Returns true once granted.
  @discardableResult
  private func allowNotificationPromptIfPresent(
    in springboard: XCUIApplication,
    timeout: TimeInterval = 3
  ) -> Bool {
    let allowPredicate = NSPredicate(format: "label CONTAINS[c] %@", "Allow")
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
      let allowButton = springboard.buttons["Allow"]
      if allowButton.exists && allowButton.isHittable {
        allowButton.tap()
        return true
      }
      let matchingButton = springboard.buttons.matching(allowPredicate).firstMatch
      if matchingButton.exists && matchingButton.isHittable {
        matchingButton.tap()
        return true
      }
      RunLoop.current.run(until: Date().addingTimeInterval(0.5))
    }
    return false
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

  private func tapNotification(
    title: String,
    springboard: XCUIApplication,
    allowGenericChromeFallback: Bool = true
  ) -> Bool {
    if tapVisibleNotification(title: title, springboard: springboard, timeout: 8) {
      return true
    }

    if allowGenericChromeFallback &&
       tapVisibleNotificationChrome(springboard: springboard, timeout: 5) {
      return true
    }

    openNotificationCenter(from: springboard)
    if tapVisibleNotification(title: title, springboard: springboard, timeout: 20) {
      return true
    }

    return allowGenericChromeFallback &&
      tapVisibleNotificationChrome(springboard: springboard, timeout: 10)
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
      if tapFirstMatch(
        springboard.staticTexts.matching(predicate),
        limit: 20,
        springboard: springboard
      ) {
        return true
      }
      let matches = springboard.descendants(matching: .any).matching(predicate)
      if tapFirstMatch(matches, limit: 20, springboard: springboard) {
        return true
      }
      RunLoop.current.run(until: Date().addingTimeInterval(0.5))
    }

    return false
  }

  private func notificationTextExists(
    _ text: String,
    springboard: XCUIApplication,
    timeout: TimeInterval
  ) -> Bool {
    let predicate = NSPredicate(
      format: "label CONTAINS[c] %@ OR value CONTAINS[c] %@",
      text,
      text
    )
    let match = springboard.descendants(matching: .any)
      .matching(predicate)
      .firstMatch
    return match.waitForExistence(timeout: timeout)
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
      if tapFirstMatch(matches, limit: 10, springboard: springboard) {
        return true
      }
      RunLoop.current.run(until: Date().addingTimeInterval(0.5))
    }

    return false
  }

  private func tapFirstMatch(
    _ matches: XCUIElementQuery,
    limit: Int,
    springboard: XCUIApplication
  ) -> Bool {
    let count = min(matches.count, limit)
    if count == 0 {
      return false
    }

    for index in 0..<count {
      let element = matches.element(boundBy: index)
      if element.exists && element.isHittable && !element.frame.isEmpty {
        element.tap()
        // iOS 26 lock-screen notifications use a two-step activation: tapping
        // the title/card reveals a separate SpringBoard "Open" action. A
        // second title tap only reselects the card and never launches the app.
        // Prefer the action's accessibility identifier, then use an exact
        // button-role label/value fallback for localized SpringBoard variants.
        tapNotificationOpenActionIfPresent(in: springboard)
        return true
      }
    }

    return false
  }

  @discardableResult
  private func tapNotificationOpenActionIfPresent(
    in springboard: XCUIApplication,
    timeout: TimeInterval = 2
  ) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    let exactIdentifier = springboard.buttons
      .matching(identifier: "Open")
      .firstMatch
    let labelPredicate = NSPredicate(
      format: "label ==[c] %@ OR value ==[c] %@",
      "Open",
      "Open"
    )

    while Date() < deadline {
      if exactIdentifier.exists && exactIdentifier.isHittable {
        exactIdentifier.tap()
        NSLog("MKNOON_IOS_NOTIFICATION_OPEN_ACTION_TAPPED source=identifier")
        return true
      }
      let roleMatched = springboard.buttons.matching(labelPredicate).firstMatch
      if roleMatched.exists && roleMatched.isHittable {
        roleMatched.tap()
        NSLog("MKNOON_IOS_NOTIFICATION_OPEN_ACTION_TAPPED source=button_role")
        return true
      }
      RunLoop.current.run(until: Date().addingTimeInterval(0.2))
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
