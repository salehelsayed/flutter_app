import Foundation
import XCTest

private extension XCUIApplication {
  /// XCTest does not publish the process identifier in its Swift interface,
  /// but XCUIApplication exposes the scalar Objective-C getter at runtime.
  /// This test-only shim binds host observations to the exact receiver process
  /// that XCTest has proved is physically backgrounded.
  var processID: pid_t {
    guard responds(to: NSSelectorFromString("processID")) else {
      return 0
    }
    return (value(forKey: "processID") as? NSNumber)?.int32Value ?? 0
  }
}

final class GroupMediaBackgroundRecoveryUITests: XCTestCase {
  private let markerPrefix = "MKNOON_269_IOS_EVENT"
  private let dedicatedBundleId = "com.mknoon.sims.groupmedia269"

  override func setUpWithError() throws {
    continueAfterFailure = false
    executionTimeAllowance = 480
  }

  func testReceiverBackgroundRecovery() throws {
    let environment = ProcessInfo.processInfo.environment
    let bundleId = try requiredValue("MKNOON_269_APP_BUNDLE_ID", in: environment)
    let runId = try requiredValue("MKNOON_269_RUN_ID", in: environment)
    let phaseAReady = try requiredValue(
      "MKNOON_269_PHASE_A_READY_TEXT",
      in: environment
    )
    let phaseBReady = try requiredValue(
      "MKNOON_269_PHASE_B_READY_TEXT",
      in: environment
    )
    let phaseAEffect = try requiredValue(
      "MKNOON_269_PHASE_A_EFFECT_TEXT",
      in: environment
    )
    let phaseBEffect = try requiredValue(
      "MKNOON_269_PHASE_B_EFFECT_TEXT",
      in: environment
    )
    XCTAssertEqual(bundleId, dedicatedBundleId)
    XCTAssertNotEqual(bundleId, "com.mknoon.app")
    XCTAssertFalse(runId.contains("/"))

    let app = XCUIApplication(bundleIdentifier: bundleId)
    XCTAssertTrue(
      app.wait(for: .runningForeground, timeout: 30),
      "The host must launch the prepared receiver at its root before XCTest"
    )
    let phaseAProcessId = app.processID
    XCTAssertGreaterThan(phaseAProcessId, 0)

    prepareLocalNetworkPermission(for: app)
    emit("local_network_permission_ready")
    assertExactlyOneProofLabel(phaseAReady, in: app)
    emit("phase_a_ready")
    XCUIDevice.shared.press(.home)
    XCTAssertTrue(waitForBackground(app, timeout: 15))
    emitNativeHome(processId: phaseAProcessId)
    emit("phase_a_home")

    XCTAssertTrue(
      app.wait(for: .runningForeground, timeout: 180),
      "The host did not restore phase A after one normal background end"
    )
    assertExactlyOneProofLabel(phaseAEffect, in: app)
    emit("phase_a_effect_once")

    assertExactlyOneProofLabel(phaseBReady, in: app)
    emit("phase_b_ready")
    let phaseBProcessId = app.processID
    XCTAssertGreaterThan(phaseBProcessId, 0)
    XCTAssertEqual(phaseBProcessId, phaseAProcessId)
    XCUIDevice.shared.press(.home)
    XCTAssertTrue(waitForBackground(app, timeout: 15))
    emitNativeHome(processId: phaseBProcessId)
    emit("phase_b_home")

    XCTAssertTrue(
      app.wait(for: .notRunning, timeout: 180),
      "The host did not terminate the exact post-claim receiver process"
    )
    app.launchArguments = []
    app.launchEnvironment = [:]
    app.launch()
    XCTAssertTrue(
      app.wait(for: .runningForeground, timeout: 180),
      "The interrupted receiver did not relaunch at the application root"
    )
    emit("phase_b_relaunch_root_without_group")
    assertExactlyOneProofLabel(phaseBEffect, in: app)
    assertExactlyOneProofLabel(phaseAEffect, in: app)
    emit("phase_b_effect_once")
  }

  /// The dedicated Plan 269 bundle has independent TCC state. Its relay uses
  /// the host LAN, so the system Local Network decision must settle before the
  /// host starts the sender/receiver fixture. A missing prompt means this exact
  /// bundle was already decided; the app-side readiness gate then proves that
  /// the pre-existing decision really permits relay and inbox traffic.
  private func prepareLocalNetworkPermission(for app: XCUIApplication) {
    let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
    let localNetworkText = NSPredicate(
      format: "label CONTAINS[c] %@",
      "local network"
    )
    let appText = app.staticTexts.matching(localNetworkText).firstMatch
    let springboardText = springboard.staticTexts
      .matching(localNetworkText)
      .firstMatch
    let prompt = XCTNSPredicateExpectation(
      predicate: NSPredicate { _, _ in appText.exists || springboardText.exists },
      object: nil
    )
    guard XCTWaiter.wait(for: [prompt], timeout: 20) == .completed else {
      return
    }

    let appAllow = app.buttons["Allow"]
    let springboardAllow = springboard.buttons["Allow"]
    let allowButton = XCTNSPredicateExpectation(
      predicate: NSPredicate { _, _ in appAllow.exists || springboardAllow.exists },
      object: nil
    )
    guard XCTWaiter.wait(for: [allowButton], timeout: 5) == .completed else {
      XCTFail("The Local Network alert had no automatable Allow action")
      return
    }
    if appAllow.exists {
      appAllow.tap()
    } else {
      springboardAllow.tap()
    }

    let dismissed = XCTNSPredicateExpectation(
      predicate: NSPredicate { _, _ in !appText.exists && !springboardText.exists },
      object: nil
    )
    XCTAssertEqual(
      XCTWaiter.wait(for: [dismissed], timeout: 10),
      .completed,
      "The Local Network privacy decision did not settle"
    )
  }

  private func waitForBackground(
    _ app: XCUIApplication,
    timeout: TimeInterval
  ) -> Bool {
    let expectation = XCTNSPredicateExpectation(
      predicate: NSPredicate { _, _ in
        app.state == .runningBackground
          || app.state == .runningBackgroundSuspended
      },
      object: nil
    )
    return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
  }

  private func assertExactlyOneProofLabel(
    _ expectedText: String,
    in app: XCUIApplication
  ) {
    let matches = app.staticTexts.matching(
      NSPredicate(format: "label == %@", expectedText)
    )
    XCTAssertTrue(
      matches.firstMatch.waitForExistence(timeout: 120),
      "The expected group-media UI effect did not become visible"
    )
    XCTAssertEqual(
      matches.count,
      1,
      "The recovered group-media delivery produced a duplicate UI effect"
    )
  }

  private func requiredValue(
    _ key: String,
    in environment: [String: String]
  ) throws -> String {
    guard let value = environment[key]?.trimmingCharacters(
      in: .whitespacesAndNewlines
    ), !value.isEmpty, value.count <= 160 else {
      XCTFail("Missing bounded prebuilt-fixture value for \(key)")
      throw NSError(
        domain: "GroupMediaBackgroundRecoveryUITests",
        code: 1,
        userInfo: [NSLocalizedDescriptionKey: "Invalid fixture environment"]
      )
    }
    return value
  }

  private func emit(_ event: String) {
    NSLog("%@ %@", markerPrefix, event)
  }

  private func emitNativeHome(processId: pid_t) {
    NSLog("MKNOON_269_IOS_NATIVE event=home_background pid=%d", processId)
  }
}
