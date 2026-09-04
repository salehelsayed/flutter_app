import XCTest

final class NotificationServiceConfigurationTests: XCTestCase {
  func testIosLocalNotificationFinalEffectRunnerImportIsRunnerTestsOnly() throws {
    try assertRunnerTestImportIsRunnerTestsOnly(
      in: "NotificationService/IosLocalNotificationFinalEffect.swift"
    )
  }

  func testNseInboxCandidateAdapterRunnerImportIsRunnerTestsOnly() throws {
    try assertRunnerTestImportIsRunnerTestsOnly(
      in: "NotificationService/NseInboxCandidateAdapter.swift"
    )
  }

  func testRunnerImportCompilationConditionIsRunnerTestsDebugOnly() throws {
    let root = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
    let project = try String(
      contentsOf: root.appendingPathComponent(
        "Runner.xcodeproj/project.pbxproj"
      ),
      encoding: .utf8
    )
    let markerSettings = project
      .components(separatedBy: .newlines)
      .filter {
        $0.contains("SWIFT_ACTIVE_COMPILATION_CONDITIONS") &&
          $0.contains("MKNOON_RUNNER_TESTS")
      }
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

    XCTAssertEqual(
      markerSettings,
      [
        "SWIFT_ACTIVE_COMPILATION_CONDITIONS = \"DEBUG MKNOON_RUNNER_TESTS $(inherited)\";"
      ],
      "the Runner test import marker must exist only in RunnerTests Debug"
    )
  }

  func testRunnerAndNotificationServiceEntitlementsShareAppGroupAndKeychainGroup() throws {
    let root = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()

    let runner = try loadPlist(root.appendingPathComponent("Runner/Runner.entitlements"))
    let service = try loadPlist(root.appendingPathComponent("NotificationService/NotificationService.entitlements"))

    XCTAssertEqual(
      runner["com.apple.security.application-groups"] as? [String],
      ["group.com.mknoon.app.share"]
    )
    XCTAssertEqual(
      service["com.apple.security.application-groups"] as? [String],
      ["group.com.mknoon.app.share"]
    )
    XCTAssertEqual(
      runner["keychain-access-groups"] as? [String],
      ["$(AppIdentifierPrefix)group.com.mknoon.app.share"]
    )
    XCTAssertEqual(
      service["keychain-access-groups"] as? [String],
      ["$(AppIdentifierPrefix)group.com.mknoon.app.share"]
    )
  }

  func testNotificationServiceInfoPlistUsesUserNotificationsServicePoint() throws {
    let root = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
    let info = try loadPlist(root.appendingPathComponent("NotificationService/Info.plist"))
    let extensionInfo = try XCTUnwrap(info["NSExtension"] as? [String: Any])

    XCTAssertEqual(
      extensionInfo["NSExtensionPointIdentifier"] as? String,
      "com.apple.usernotifications.service"
    )
  }

  private func loadPlist(_ url: URL) throws -> [String: Any] {
    let data = try Data(contentsOf: url)
    let object = try PropertyListSerialization.propertyList(
      from: data,
      options: [],
      format: nil
    )
    return try XCTUnwrap(object as? [String: Any])
  }

  private func assertRunnerTestImportIsRunnerTestsOnly(
    in relativePath: String,
    file: StaticString = #filePath,
    line: UInt = #line
  ) throws {
    let root = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
    let source = try String(
      contentsOf: root.appendingPathComponent(relativePath),
      encoding: .utf8
    )
    let expected = "#if DEBUG && MKNOON_RUNNER_TESTS && canImport(Runner)\n  @testable import Runner\n#endif"

    XCTAssertEqual(
      source.components(separatedBy: "@testable import Runner").count - 1,
      1,
      "\(relativePath) must contain exactly one Runner test import",
      file: file,
      line: line
    )
    XCTAssertTrue(
      source.contains(expected),
      "\(relativePath) must make the Runner import unreachable outside Debug RunnerTests",
      file: file,
      line: line
    )
  }
}
