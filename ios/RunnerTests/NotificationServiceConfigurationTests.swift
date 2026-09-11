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

  func testRunnerImportCompilationConditionIsRunnerTestsOnlyInEveryConfiguration() throws {
    let root = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
    let project = try XCTUnwrap(
      PropertyListSerialization.propertyList(
        from: Data(contentsOf: root.appendingPathComponent("Runner.xcodeproj/project.pbxproj")),
        options: [],
        format: nil
      ) as? [String: Any]
    )
    let objects = try XCTUnwrap(project["objects"] as? [String: [String: Any]])
    let target = try XCTUnwrap(objects.values.first {
      $0["isa"] as? String == "PBXNativeTarget" && $0["name"] as? String == "RunnerTests"
    })
    let listId = try XCTUnwrap(target["buildConfigurationList"] as? String)
    let configIds = try XCTUnwrap(objects[listId]?["buildConfigurations"] as? [String])
    XCTAssertEqual(Set(configIds.compactMap { objects[$0]?["name"] as? String }), ["Debug", "Release", "Profile"])
    for (id, object) in objects where object["isa"] as? String == "XCBuildConfiguration" {
      let settings = try XCTUnwrap(object["buildSettings"] as? [String: Any])
      let flags = settings["OTHER_SWIFT_FLAGS"] as? String ?? ""
      let conditions = settings["SWIFT_ACTIVE_COMPILATION_CONDITIONS"] as? String ?? ""
      if configIds.contains(id) {
        XCTAssertTrue(flags.contains("$(inherited)"))
        XCTAssertTrue(flags.split(separator: " ").contains("-DMKNOON_RUNNER_TESTS"))
        if object["name"] as? String != "Debug" {
          XCTAssertFalse(flags.split(separator: " ").contains("-DDEBUG"))
          XCTAssertFalse(conditions.split(separator: " ").contains("DEBUG"))
        }
      } else {
        XCTAssertFalse(flags.contains("MKNOON_RUNNER_TESTS"))
        XCTAssertFalse(conditions.contains("MKNOON_RUNNER_TESTS"))
      }
    }
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
    let expected = "#if MKNOON_RUNNER_TESTS && canImport(Runner)\n  @testable import Runner\n#endif"

    XCTAssertEqual(
      source.components(separatedBy: "@testable import Runner").count - 1,
      1,
      "\(relativePath) must contain exactly one Runner test import",
      file: file,
      line: line
    )
    XCTAssertTrue(
      source.contains(expected),
      "\(relativePath) must make the Runner import unreachable outside RunnerTests",
      file: file,
      line: line
    )
  }
}
