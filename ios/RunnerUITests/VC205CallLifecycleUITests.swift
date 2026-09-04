import XCTest

private enum VC205BootstrapError: LocalizedError {
  case appDidNotReachForeground
  case missingAccessibleButton(String)
  case missingEnvironmentValue(String)
  case missingQrEditor
  case missingIdentity
  case unrecognizedAppState
  case pairingConfirmationMissing

  var errorDescription: String? {
    switch self {
    case .appDidNotReachForeground:
      return "Expected the authorized app to be running in the foreground"
    case let .missingAccessibleButton(label):
      return "Expected accessible button '\(label)'"
    case let .missingEnvironmentValue(key):
      return "Missing required UI-test environment value: \(key)"
    case .missingQrEditor:
      return "Expected the debug QR paste editor"
    case .missingIdentity:
      return "The authorized iPhone app no longer has its prepared identity"
    case .unrecognizedAppState:
      return "The authorized app did not reach a recognized pairing entry"
    case .pairingConfirmationMissing:
      return "Expected the contact pairing confirmation"
    }
  }
}

final class VC205CallLifecycleUITests: XCTestCase {
  private let defaultBundleIdentifier = "com.mknoon.app"

  override func setUpWithError() throws {
    continueAfterFailure = false
    executionTimeAllowance = 360
  }

  /// Pairs the existing authorized iPhone app state with the caller contact
  /// required by the VC2-05 physical lifecycle campaign. The contact payload
  /// is read only by this test and is never printed or attached by the harness.
  func testBootstrapTrustedContactFromQR() throws {
    let environment = ProcessInfo.processInfo.environment
    let contactQR = try requiredContactQR(in: environment)
    let bundleIdentifier = configuredBundleIdentifier(in: environment)

    let app = XCUIApplication(bundleIdentifier: bundleIdentifier)
    app.terminate()
    let readyMarker = "MKNOON_VC205_XCUI_READY waiting_for_flutter_host"
    NSLog("%@", readyMarker)
    fputs("\(readyMarker)\n", stdout)
    fflush(stdout)
    guard app.wait(for: .runningForeground, timeout: 180) else {
      throw VC205BootstrapError.appDidNotReachForeground
    }

    try awaitRecognizedPairingEntry(in: app)

    if !tapButtonIfPresent("Paste QR Data", in: app, timeout: 2) {
      if !tapButtonIfPresent("Scan a friend's code", in: app, timeout: 2) {
        if !accessibleElementExists("Open settings", in: app, timeout: 2) {
          try tapButton("Orbit", in: app)
        }
        try tapButton("Open settings", in: app)
        try tapButton("Scan", in: app, scrollAttempts: 3)
      }
      settleCameraPermissionIfPresent(in: app)
      try tapButton("Paste QR Data", in: app)
    }
    try enter(contactQR: contactQR, in: app)
    try tapButton("Submit", in: app)

    let added = app.staticTexts["Added to your circle!"].firstMatch
    let alreadyAdded = app.staticTexts["Already in your circle!"].firstMatch
    let outcome = XCTNSPredicateExpectation(
      predicate: NSPredicate { _, _ in added.exists || alreadyAdded.exists },
      object: nil
    )
    guard XCTWaiter.wait(for: [outcome], timeout: 90) == .completed else {
      throw VC205BootstrapError.pairingConfirmationMissing
    }

    if added.exists {
      try tapButton("OK", in: app)
    } else {
      try tapButton("Got it", in: app)
    }
  }

  /// Taps the call affordance in an app that was already launched by Flutter
  /// tooling. This deliberately never launches, activates, or terminates the
  /// app because an iOS debug Flutter process must keep its tooling attachment.
  func testTapStartVoiceCallOnAlreadyRunningApp() throws {
    let environment = ProcessInfo.processInfo.environment
    let bundleIdentifier = configuredBundleIdentifier(in: environment)
    let app = XCUIApplication(bundleIdentifier: bundleIdentifier)

    guard app.wait(for: .runningForeground, timeout: 30) else {
      throw VC205BootstrapError.appDidNotReachForeground
    }

    try tapButton("Start voice call", in: app, timeout: 30)
    let marker = "MKNOON_VC205_XCUI_CALL_TAPPED"
    NSLog("%@", marker)
    fputs("\(marker)\n", stdout)
    fflush(stdout)
  }

  /// Answers a CallKit sheet that is already being presented by iOS. The
  /// application remains under Flutter tooling; this test touches only the
  /// system-owned call surface.
  func testAnswerAlreadyPresentedSystemCall() throws {
    let systemHosts = [
      XCUIApplication(bundleIdentifier: "com.apple.InCallService"),
      XCUIApplication(bundleIdentifier: "com.apple.springboard"),
      XCUIApplication(bundleIdentifier: "com.apple.TelephonyUI"),
    ]

    for host in systemHosts {
      if let answer = accessibleElement("Answer", in: host, timeout: 10) {
        answer.tap()
        let marker = "MKNOON_VC205_XCUI_SYSTEM_CALL_ANSWERED"
        NSLog("%@", marker)
        fputs("\(marker)\n", stdout)
        fflush(stdout)
        return
      }
    }

    throw VC205BootstrapError.missingAccessibleButton("Answer")
  }

  private func awaitRecognizedPairingEntry(in app: XCUIApplication) throws {
    let onboarding = app.buttons["I'm new here"].firstMatch
    let expectation = XCTNSPredicateExpectation(
      predicate: NSPredicate { _, _ in
        onboarding.exists
          || self.accessibleElementExists("Paste QR Data", in: app, timeout: 0)
          || self.accessibleElementExists(
            "Scan a friend's code",
            in: app,
            timeout: 0
          )
          || self.accessibleElementExists("Open settings", in: app, timeout: 0)
          || self.accessibleElementExists("Orbit", in: app, timeout: 0)
      },
      object: nil
    )
    guard XCTWaiter.wait(for: [expectation], timeout: 90) == .completed else {
      attachFailureScreenshot(named: "vc205-unrecognized-app-state", app: app)
      throw VC205BootstrapError.unrecognizedAppState
    }
    if onboarding.exists {
      attachFailureScreenshot(named: "vc205-missing-identity", app: app)
      throw VC205BootstrapError.missingIdentity
    }
  }

  private func enter(contactQR: String, in app: XCUIApplication) throws {
    let editor = app.textViews.firstMatch.exists
      ? app.textViews.firstMatch
      : app.textFields.firstMatch
    guard editor.waitForExistence(timeout: 10), editor.isHittable else {
      throw VC205BootstrapError.missingQrEditor
    }
    editor.tap()
    editor.typeText(contactQR)
  }

  private func requiredContactQR(
    in environment: [String: String]
  ) throws -> String {
    let key = "MKNOON_VC205_CONTACT_QR"
    guard let value = environment[key],
          !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw VC205BootstrapError.missingEnvironmentValue(key)
    }
    return value
  }

  private func configuredBundleIdentifier(
    in environment: [String: String]
  ) -> String {
    guard let configured = environment["MKNOON_VC205_APP_BUNDLE_ID"]?
      .trimmingCharacters(in: .whitespacesAndNewlines),
      !configured.isEmpty else {
      return defaultBundleIdentifier
    }
    return configured
  }

  private func tapButton(
    _ label: String,
    in app: XCUIApplication,
    timeout: TimeInterval = 30,
    scrollAttempts: Int = 0
  ) throws {
    for attempt in 0...scrollAttempts {
      let wait = attempt == 0 ? timeout : 2
      if let element = accessibleElement(label, in: app, timeout: wait) {
        element.tap()
        return
      }
      if attempt < scrollAttempts {
        app.swipeUp()
      }
    }
    throw VC205BootstrapError.missingAccessibleButton(label)
  }

  private func tapButtonIfPresent(
    _ label: String,
    in app: XCUIApplication,
    timeout: TimeInterval
  ) -> Bool {
    guard let element = accessibleElement(label, in: app, timeout: timeout) else {
      return false
    }
    element.tap()
    return true
  }

  private func accessibleElementExists(
    _ label: String,
    in app: XCUIApplication,
    timeout: TimeInterval
  ) -> Bool {
    accessibleElement(label, in: app, timeout: timeout) != nil
  }

  private func accessibleElement(
    _ label: String,
    in app: XCUIApplication,
    timeout: TimeInterval
  ) -> XCUIElement? {
    let button = app.buttons[label].firstMatch
    if button.waitForExistence(timeout: timeout), button.isHittable {
      return button
    }

    let labelOrValue = NSPredicate(
      format: "label == %@ OR value == %@",
      label,
      label
    )
    let fallback = app.descendants(matching: .any)
      .matching(labelOrValue)
      .firstMatch
    if fallback.waitForExistence(timeout: 1), fallback.isHittable {
      return fallback
    }
    return nil
  }

  private func settleCameraPermissionIfPresent(in app: XCUIApplication) {
    let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
    for host in [app, springboard] {
      let alert = host.alerts.firstMatch
      guard alert.waitForExistence(timeout: 2) else { continue }
      let cameraText = alert.staticTexts
        .matching(NSPredicate(format: "label CONTAINS[c] %@", "camera"))
        .firstMatch
      guard cameraText.exists else { continue }
      for label in ["Allow While Using App", "Allow"] {
        let action = alert.buttons[label].firstMatch
        if action.exists, action.isHittable {
          action.tap()
          return
        }
      }
    }
  }

  private func attachFailureScreenshot(named name: String, app: XCUIApplication) {
    let attachment = XCTAttachment(screenshot: app.screenshot())
    attachment.name = name
    attachment.lifetime = .keepAlways
    add(attachment)
  }
}
