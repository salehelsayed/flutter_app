import Foundation
import XCTest

@testable import Runner

final class IosCallConfigurationTests: XCTestCase {
  func testRunnerHasVoipAudioAndExistingBackgroundModes() throws {
    let root = repositoryRoot()
    let info = try loadPlist(root.appendingPathComponent("Runner/Info.plist"))
    let modes = try XCTUnwrap(info["UIBackgroundModes"] as? [String])
    XCTAssertEqual(Set(modes), ["audio", "fetch", "remote-notification", "voip"])
    let microphone = try XCTUnwrap(info["NSMicrophoneUsageDescription"] as? String)
    XCTAssertTrue(microphone.localizedCaseInsensitiveContains("call"))
    XCTAssertTrue(microphone.localizedCaseInsensitiveContains("voice message"))
  }

  func testRunnerPrivacyManifestDeclaresLinkedNontrackingVoipDeviceIdentifier() throws {
    let root = repositoryRoot()
    let runner = try loadPlist(root.appendingPathComponent("Runner/PrivacyInfo.xcprivacy"))
    let rows = try XCTUnwrap(runner["NSPrivacyCollectedDataTypes"] as? [[String: Any]])
    XCTAssertEqual(rows.count, 1)
    let row = try XCTUnwrap(rows.first)
    XCTAssertEqual(row["NSPrivacyCollectedDataType"] as? String, "NSPrivacyCollectedDataTypeDeviceID")
    XCTAssertEqual(row["NSPrivacyCollectedDataTypeLinked"] as? Bool, true)
    XCTAssertEqual(row["NSPrivacyCollectedDataTypeTracking"] as? Bool, false)
    XCTAssertEqual(
      row["NSPrivacyCollectedDataTypePurposes"] as? [String],
      ["NSPrivacyCollectedDataTypePurposeAppFunctionality"]
    )

    let service = try loadPlist(
      root.appendingPathComponent("NotificationService/PrivacyInfo.xcprivacy")
    )
    XCTAssertEqual(
      try XCTUnwrap(service["NSPrivacyCollectedDataTypes"] as? [[String: Any]]).count,
      0
    )
  }

  func testRunnerAloneOwnsVoipEntryPointAndPushEntitlement() throws {
    let root = repositoryRoot()
    let runner = try loadPlist(root.appendingPathComponent("Runner/Runner.entitlements"))
    XCTAssertEqual(
      runner["aps-environment"] as? String,
      "$(MKNOON_VOIP_ENVIRONMENT)"
    )
    let info = try loadPlist(root.appendingPathComponent("Runner/Info.plist"))
    XCTAssertEqual(
      info["MknoonVoipEnvironment"] as? String,
      "$(MKNOON_VOIP_ENVIRONMENT)"
    )
    let project = try String(
      contentsOf: root.appendingPathComponent("Runner.xcodeproj/project.pbxproj"),
      encoding: .utf8
    )
    XCTAssertEqual(
      project.components(separatedBy: "MKNOON_VOIP_ENVIRONMENT = development;").count - 1,
      2
    )
    XCTAssertEqual(
      project.components(separatedBy: "MKNOON_VOIP_ENVIRONMENT = production;").count - 1,
      1
    )
    XCTAssertEqual(
      project.components(
        separatedBy: "\"CODE_SIGN_IDENTITY[sdk=iphoneos*]\" = \"iPhone Developer\";"
      ).count - 1,
      2,
      "Debug and Profile must preserve development signing"
    )
    XCTAssertFalse(
      project.contains(
        "\"CODE_SIGN_IDENTITY[sdk=iphoneos*]\" = \"Apple Distribution\";"
      ),
      "Automatic archive/export signing must not inherit a conflicting manual distribution identity"
    )

    let nseInfo = try loadPlist(root.appendingPathComponent("NotificationService/Info.plist"))
    XCTAssertNil(nseInfo["UIBackgroundModes"])
    let extensionInfo = try XCTUnwrap(nseInfo["NSExtension"] as? [String: Any])
    XCTAssertEqual(
      extensionInfo["NSExtensionPointIdentifier"] as? String,
      "com.apple.usernotifications.service"
    )
    let nseSource = try String(
      contentsOf: root.appendingPathComponent("NotificationService/NotificationService.swift"),
      encoding: .utf8
    )
    XCTAssertFalse(nseSource.contains("PKPushRegistry"))
    XCTAssertFalse(nseSource.contains("CXProvider"))
  }

  func testVoipSigningVerifierIsExecutableAndFailClosed() throws {
    let verifier = repositoryRoot()
      .deletingLastPathComponent()
      .appendingPathComponent("scripts/verify_ios_voip_signing.sh")
    XCTAssertTrue(FileManager.default.isExecutableFile(atPath: verifier.path))
    let source = try String(contentsOf: verifier, encoding: .utf8)
    XCTAssertTrue(source.contains("MknoonVoipEnvironment"))
    XCTAssertTrue(source.contains("aps-environment"))
    XCTAssertTrue(source.contains("codesign --verify --strict"))
    XCTAssertTrue(source.contains("codesign --display --entitlements"))
    XCTAssertTrue(source.contains("development|production"))
    XCTAssertTrue(source.contains("mktemp -d"))
    XCTAssertTrue(source.contains("trap cleanup EXIT"))
    XCTAssertTrue(source.contains(">/dev/null 2>&1"))
    XCTAssertFalse(source.contains("cat \"$entitlements_plist\""))
  }

  func testAppDelegatePreservesStandardNotificationsAndOwnsOneVoipRegistryAtImplicitEngineSeam() throws {
    let source = try String(
      contentsOf: repositoryRoot().appendingPathComponent("Runner/AppDelegate.swift"),
      encoding: .utf8
    )
    XCTAssertTrue(source.contains("didRegisterForRemoteNotificationsWithDeviceToken"))
    XCTAssertTrue(source.contains("Messaging.messaging().apnsToken = deviceToken"))
    XCTAssertTrue(source.contains("didFailToRegisterForRemoteNotificationsWithError"))
    XCTAssertTrue(source.contains("super.userNotificationCenter("))
    XCTAssertTrue(source.contains("func didInitializeImplicitFlutterEngine"))
    XCTAssertEqual(source.components(separatedBy: "private lazy var iosVoipPushRegistry").count - 1, 1)
    XCTAssertEqual(source.components(separatedBy: "iosVoipPushRegistry.start()").count - 1, 1)
    XCTAssertEqual(
      source.components(separatedBy: "private lazy var iosNativeCallCapability").count - 1,
      1
    )
    XCTAssertTrue(source.contains("capability: iosNativeCallCapability"))
    XCTAssertTrue(source.contains("iosVoipPushRegistry.applyCapability(enabled)"))
    XCTAssertEqual(
      source.components(separatedBy: "setupIosCallLifecycleBridges(messenger: messenger)").count - 1,
      1
    )
  }

  func testXcodeMembershipKeepsVoipAuthorityOutOfNotificationService() throws {
    let project = try String(
      contentsOf: repositoryRoot().appendingPathComponent("Runner.xcodeproj/project.pbxproj"),
      encoding: .utf8
    )
    for file in [
      "VoipPayloadParser.swift", "PendingNativeCallStore.swift",
      "OpaqueCallContactResolver.swift", "MknoonCallKitController.swift",
      "MknoonCallNativeBridge.swift", "MknoonVoipPushRegistry.swift",
    ] {
      XCTAssertTrue(project.contains("/* \(file) in Sources */"), file)
    }
    let notificationSources = try XCTUnwrap(
      project.range(of: "6F73B00973A0000000000001 /* Sources */")
    )
    let following = project[notificationSources.lowerBound...].prefix(600)
    XCTAssertFalse(following.contains("MknoonVoipPushRegistry.swift"))
    XCTAssertFalse(following.contains("MknoonCallKitController.swift"))
  }

  private func repositoryRoot() -> URL {
    URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
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
