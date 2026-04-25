import XCTest

final class NotificationServiceConfigurationTests: XCTestCase {
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
}
