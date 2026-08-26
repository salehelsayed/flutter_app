import XCTest

final class NotificationServiceConfigurationTests: XCTestCase {
  func testIosLocalNotificationFinalEffectRunnerImportIsDebugOnly() throws {
    try assertRunnerTestImportIsDebugOnly(
      in: "NotificationService/IosLocalNotificationFinalEffect.swift"
    )
  }

  func testNseInboxCandidateAdapterRunnerImportIsDebugOnly() throws {
    try assertRunnerTestImportIsDebugOnly(
      in: "NotificationService/NseInboxCandidateAdapter.swift"
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

  private func assertRunnerTestImportIsDebugOnly(
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
    let expected = "#if DEBUG && canImport(Runner)\n  @testable import Runner\n#endif"

    XCTAssertEqual(
      source.components(separatedBy: "@testable import Runner").count - 1,
      1,
      "\(relativePath) must contain exactly one Runner test import",
      file: file,
      line: line
    )
    XCTAssertTrue(
      source.contains(expected),
      "\(relativePath) must make the Runner test import unreachable outside DEBUG",
      file: file,
      line: line
    )
  }
}
