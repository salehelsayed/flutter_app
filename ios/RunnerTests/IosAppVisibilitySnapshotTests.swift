import Foundation
import XCTest

@testable import Runner

final class IosAppVisibilitySnapshotTests: XCTestCase {
  func testTC37106AtomicSnapshotLifecycleAndPrivacyContract() throws {
    let fixture = try loadFixture()
    XCTAssertEqual(
      fixture.schemaVersion,
      IosAppVisibilitySnapshotV1.supportedSchemaVersion
    )
    XCTAssertEqual(
      fixture.freshnessWindowMs,
      IosAppVisibilitySnapshotV1.freshnessLimitMs
    )

    for vector in fixture.digestVectors {
      let lane = try XCTUnwrap(IosAppVisibilityLane(rawValue: vector.lane))
      XCTAssertEqual(
        IosAppVisibilityDigest.normalizedConversationIdentifier(
          lane: lane,
          conversationIdentifier: vector.input
        ),
        vector.normalizedId,
        vector.name
      )
      XCTAssertEqual(
        IosAppVisibilityDigest.canonicalPreimage(
          lane: lane,
          conversationIdentifier: vector.input
        )?.hexString,
        vector.preimageHex,
        vector.name
      )
      XCTAssertEqual(
        IosAppVisibilityDigest.digest(
          lane: lane,
          conversationIdentifier: vector.input
        ),
        vector.digest,
        vector.name
      )
    }
    for vector in fixture.invalidConversationVectors {
      let lane = try XCTUnwrap(IosAppVisibilityLane(rawValue: vector.lane))
      XCTAssertNil(
        IosAppVisibilityDigest.digest(
          lane: lane,
          conversationIdentifier: vector.input
        ),
        vector.name
      )
    }
    for vector in fixture.predicateVectors {
      XCTAssertEqual(
        vector.snapshot.isEligibleForSuppression(
          expectedConversationDigest: vector.expectedConversationDigest,
          currentBootSession: vector.currentBootSession,
          currentMonotonicMs: vector.currentMonotonicMs
        ),
        vector.maySuppress,
        vector.name
      )
    }
    for vector in try loadInvalidSnapshotVectors() {
      let data = try JSONSerialization.data(withJSONObject: vector.snapshot)
      let decoded = try? JSONDecoder().decode(
        IosAppVisibilitySnapshotV1.self,
        from: data
      )
      XCTAssertFalse(decoded?.isStructurallyValid ?? false, vector.name)
    }
    let unavailableBoot = IosAppVisibilitySnapshotV1(
      revision: 1,
      lifecycleGeneration: 1,
      lifecycle: .foregroundActive,
      visibleConversationDigest: fixture.digestVectors[0].digest,
      updatedMonotonicMs: 1,
      bootSession: "unavailable"
    )
    XCTAssertFalse(unavailableBoot.isStructurallyValid)
    XCTAssertFalse(unavailableBoot.isEligibleForSuppression(
      expectedConversationDigest: fixture.digestVectors[0].digest,
      currentBootSession: "unavailable",
      currentMonotonicMs: 2
    ))

    var now: Int64 = 100
    let boot = "ios:42:7"
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = makeStore(directory: directory, boot: { boot }, now: { now })
    XCTAssertTrue(store.recordColdStart())
    now = 101
    XCTAssertTrue(store.transitionLifecycle(to: .foregroundActive))
    let active = try XCTUnwrap(store.readSnapshot()).snapshot
    now = 102
    let published = store.publishVisibleConversation(
      digest: fixture.digestVectors[0].digest,
      lifecycleGeneration: active.lifecycleGeneration
    )
    XCTAssertTrue(published.committed)
    XCTAssertEqual(
      published.snapshot?.visibleConversationDigest,
      fixture.digestVectors[0].digest
    )
    XCTAssertEqual(
      Set(published.methodChannelMap.keys),
      [
        "committed",
        "snapshot",
        "currentMonotonicMs",
        "currentBootSession",
      ]
    )
    XCTAssertEqual(
      Set(try XCTUnwrap(
        published.methodChannelMap["snapshot"] as? [String: Any]
      ).keys),
      [
        "schemaVersion",
        "revision",
        "lifecycleGeneration",
        "lifecycle",
        "visibleConversationDigest",
        "updatedMonotonicMs",
        "bootSession",
      ]
    )
    let failedPublicationMap = IosAppVisibilityPublishResult(
      committed: false,
      snapshot: nil,
      context: nil
    ).methodChannelMap
    XCTAssertEqual(failedPublicationMap["committed"] as? Bool, false)
    XCTAssertTrue(failedPublicationMap["snapshot"] is NSNull)
    XCTAssertEqual(failedPublicationMap["currentMonotonicMs"] as? Int64, 0)
    XCTAssertEqual(
      failedPublicationMap["currentBootSession"] as? String,
      "unavailable"
    )

    let stateURL = directory.appendingPathComponent(
      IosAppVisibilitySnapshotStore.stateFileName
    )
    let lockURL = directory.appendingPathComponent(
      IosAppVisibilitySnapshotStore.lockFileName
    )
    XCTAssertTrue(FileManager.default.fileExists(atPath: stateURL.path))
    XCTAssertTrue(FileManager.default.fileExists(atPath: lockURL.path))
    assertCompleteUntilFirstUserAuthenticationProtection(
      try FileManager.default.attributesOfItem(atPath: stateURL.path)
    )
    XCTAssertEqual(
      try stateURL.resourceValues(forKeys: [.isExcludedFromBackupKey])
        .isExcludedFromBackup,
      true
    )

    let incumbentBytes = try Data(contentsOf: stateURL)
    now = 103
    let preRenameFailure = makeStore(
      directory: directory,
      boot: { boot },
      now: { now },
      fault: { $0 == .beforeRename }
    )
    XCTAssertFalse(preRenameFailure.transitionLifecycle(to: .background))
    XCTAssertEqual(try Data(contentsOf: stateURL), incumbentBytes)
    XCTAssertNil(preRenameFailure.readSnapshot())
    let reopenedIncumbent = makeStore(
      directory: directory,
      boot: { boot },
      now: { now }
    )
    XCTAssertEqual(
      reopenedIncumbent.readSnapshot()?.snapshot.visibleConversationDigest,
      fixture.digestVectors[0].digest
    )

    let postRenameDirectory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: postRenameDirectory) }
    now = 200
    let postRenameSeed = makeStore(
      directory: postRenameDirectory,
      boot: { boot },
      now: { now }
    )
    XCTAssertTrue(postRenameSeed.recordColdStart())
    now = 201
    XCTAssertTrue(postRenameSeed.transitionLifecycle(to: .foregroundActive))
    now = 202
    let postRenameFailure = makeStore(
      directory: postRenameDirectory,
      boot: { boot },
      now: { now },
      fault: { $0 == .afterRenameBeforeDirectorySync }
    )
    XCTAssertFalse(postRenameFailure.transitionLifecycle(to: .background))
    XCTAssertNil(postRenameFailure.readSnapshot())
    let reopenedRenamed = makeStore(
      directory: postRenameDirectory,
      boot: { boot },
      now: { now }
    )
    XCTAssertEqual(
      reopenedRenamed.readSnapshot()?.snapshot.lifecycle,
      .background
    )
    XCTAssertNil(
      makeStore(
        directory: postRenameDirectory,
        boot: { nil },
        now: { now }
      ).readSnapshot()
    )
    XCTAssertNil(
      makeStore(
        directory: postRenameDirectory,
        boot: { boot },
        now: { nil }
      ).readSnapshot()
    )

    let futureDirectory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: futureDirectory) }
    let futureURL = futureDirectory.appendingPathComponent(
      IosAppVisibilitySnapshotStore.stateFileName
    )
    let futureBytes = Data(#"{"schemaVersion":2,"future":"keep"}"#.utf8)
    try futureBytes.write(to: futureURL)
    let futureStore = makeStore(
      directory: futureDirectory,
      boot: { boot },
      now: { now }
    )
    XCTAssertFalse(futureStore.recordColdStart())
    XCTAssertEqual(try Data(contentsOf: futureURL), futureBytes)

    let unsupportedBoundsDirectory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: unsupportedBoundsDirectory) }
    let unsupportedBoundsURL = unsupportedBoundsDirectory.appendingPathComponent(
      IosAppVisibilitySnapshotStore.stateFileName
    )
    let overflowVector = try XCTUnwrap(
      try loadInvalidSnapshotVectors().first { $0.name == "revision_overflow" }
    )
    let unsupportedBoundsBytes = try JSONSerialization.data(
      withJSONObject: overflowVector.snapshot,
      options: [.sortedKeys]
    )
    try unsupportedBoundsBytes.write(to: unsupportedBoundsURL)
    let unsupportedBoundsStore = makeStore(
      directory: unsupportedBoundsDirectory,
      boot: { boot },
      now: { now }
    )
    XCTAssertFalse(unsupportedBoundsStore.recordColdStart())
    XCTAssertEqual(
      try Data(contentsOf: unsupportedBoundsURL),
      unsupportedBoundsBytes
    )

    try assertPrivacyManifest(
      at: try XCTUnwrap(Bundle.main.url(
        forResource: "PrivacyInfo",
        withExtension: "xcprivacy"
      )),
      expectedReasons: [
        "NSPrivacyAccessedAPICategorySystemBootTime": ["35F9.1"],
        "NSPrivacyAccessedAPICategoryDiskSpace": ["E174.1"],
      ],
      expectsVoipDeviceIdentifier: true
    )
    try assertPrivacyManifest(
      at: Bundle.main.bundleURL.appendingPathComponent(
        "PlugIns/NotificationService.appex/PrivacyInfo.xcprivacy"
      ),
      expectedReasons: [
        "NSPrivacyAccessedAPICategorySystemBootTime": ["35F9.1"],
        "NSPrivacyAccessedAPICategoryFileTimestamp": ["C617.1"],
      ],
      expectsVoipDeviceIdentifier: false
    )
  }

  func testTC37106DuplicateUIApplicationAndUISceneActiveDoesNotClearInterleavedRouteCAS()
    throws
  {
    var now: Int64 = 1_000
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = makeStore(
      directory: directory,
      boot: { "ios:77:11" },
      now: { now }
    )
    let coordinator = IosAppVisibilityCoordinator(store: store)
    coordinator.start(observeSystemNotifications: false)
    defer { coordinator.stop() }

    now = 1_001
    coordinator.handleApplicationLifecycleForTesting(.foregroundActive)
    let active = try XCTUnwrap(coordinator.readSnapshot()).snapshot
    let digest = try XCTUnwrap(IosAppVisibilityDigest.digest(
      lane: .direct,
      conversationIdentifier: "peer-A"
    ))
    now = 1_002
    XCTAssertTrue(coordinator.publishVisibleConversation(
      digest: digest,
      lifecycleGeneration: active.lifecycleGeneration
    ).committed)
    let routed = try XCTUnwrap(coordinator.readSnapshot()).snapshot

    now = 1_003
    coordinator.handleSceneLifecycleForTesting(.foregroundActive)
    let afterDuplicateActive = try XCTUnwrap(
      coordinator.readSnapshot()
    ).snapshot
    XCTAssertEqual(afterDuplicateActive, routed)
    XCTAssertEqual(afterDuplicateActive.visibleConversationDigest, digest)

    now = 1_004
    coordinator.handleApplicationLifecycleForTesting(.inactive)
    let inactive = try XCTUnwrap(coordinator.readSnapshot()).snapshot
    XCTAssertEqual(inactive.visibleConversationDigest, nil)
    XCTAssertEqual(
      inactive.lifecycleGeneration,
      routed.lifecycleGeneration + 1
    )

    now = 1_005
    coordinator.handleSceneLifecycleForTesting(.inactive)
    XCTAssertEqual(
      try XCTUnwrap(coordinator.readSnapshot()).snapshot,
      inactive
    )
    let staleRoute = coordinator.publishVisibleConversation(
      digest: digest,
      lifecycleGeneration: routed.lifecycleGeneration
    )
    XCTAssertFalse(staleRoute.committed)
    XCTAssertEqual(staleRoute.snapshot?.lifecycle, .inactive)
    XCTAssertNil(staleRoute.snapshot?.visibleConversationDigest)
  }

  private func loadFixture() throws -> VisibilityFixture {
    try JSONDecoder().decode(
      VisibilityFixture.self,
      from: Data(contentsOf: fixtureURL)
    )
  }

  private func loadInvalidSnapshotVectors() throws -> [InvalidSnapshotVector] {
    let object = try JSONSerialization.jsonObject(
      with: Data(contentsOf: fixtureURL)
    )
    let root = try XCTUnwrap(object as? [String: Any])
    let values = try XCTUnwrap(root["invalidSnapshotVectors"] as? [[String: Any]])
    return try values.map { value in
      InvalidSnapshotVector(
        name: try XCTUnwrap(value["name"] as? String),
        snapshot: try XCTUnwrap(value["snapshot"] as? [String: Any])
      )
    }
  }

  private var repositoryRoot: URL {
    URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
  }

  private var fixtureURL: URL {
    Bundle(for: IosAppVisibilitySnapshotTests.self).url(
      forResource: "app_visibility_snapshot_v1",
      withExtension: "json"
    ) ?? repositoryRoot.appendingPathComponent(
      "test/shared/fixtures/app_visibility_snapshot_v1.json"
    )
  }

  private func makeStore(
    directory: URL,
    boot: @escaping () -> String?,
    now: @escaping () -> Int64?,
    fault: @escaping (IosAppVisibilityCommitFaultPoint) -> Bool = { _ in false }
  ) -> IosAppVisibilitySnapshotStore {
    IosAppVisibilitySnapshotStore(
      directory: directory,
      bootSessionProvider: boot,
      monotonicMsProvider: now,
      commitFault: fault
    )
  }

  private func temporaryDirectory() throws -> URL {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      "ios-app-visibility-\(UUID().uuidString)",
      isDirectory: true
    )
    try FileManager.default.createDirectory(
      at: directory,
      withIntermediateDirectories: true
    )
    return directory
  }

  private func assertPrivacyManifest(
    at url: URL,
    expectedReasons: [String: Set<String>],
    expectsVoipDeviceIdentifier: Bool
  ) throws {
    let data = try Data(contentsOf: url)
    let plist = try PropertyListSerialization.propertyList(
      from: data,
      options: [],
      format: nil
    )
    let root = try XCTUnwrap(plist as? [String: Any])
    XCTAssertEqual(root["NSPrivacyTracking"] as? Bool, false)
    let rows = try XCTUnwrap(
      root["NSPrivacyAccessedAPITypes"] as? [[String: Any]]
    )
    var actual: [String: Set<String>] = [:]
    for row in rows {
      let category = try XCTUnwrap(
        row["NSPrivacyAccessedAPIType"] as? String
      )
      let reasons = try XCTUnwrap(
        row["NSPrivacyAccessedAPITypeReasons"] as? [String]
      )
      actual[category] = Set(reasons)
    }
    XCTAssertEqual(actual, expectedReasons)

    let collected = try XCTUnwrap(
      root["NSPrivacyCollectedDataTypes"] as? [[String: Any]]
    )
    if expectsVoipDeviceIdentifier {
      XCTAssertEqual(collected.count, 1)
      let row = try XCTUnwrap(collected.first)
      XCTAssertEqual(
        row["NSPrivacyCollectedDataType"] as? String,
        "NSPrivacyCollectedDataTypeDeviceID"
      )
      XCTAssertEqual(row["NSPrivacyCollectedDataTypeLinked"] as? Bool, true)
      XCTAssertEqual(row["NSPrivacyCollectedDataTypeTracking"] as? Bool, false)
      XCTAssertEqual(
        row["NSPrivacyCollectedDataTypePurposes"] as? [String],
        ["NSPrivacyCollectedDataTypePurposeAppFunctionality"]
      )
    } else {
      XCTAssertTrue(collected.isEmpty)
    }
  }

  private func assertCompleteUntilFirstUserAuthenticationProtection(
    _ attributes: [FileAttributeKey: Any],
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    let protection = attributes[.protectionKey] as? FileProtectionType
#if targetEnvironment(simulator)
    XCTAssertTrue(
      protection == nil || protection == .completeUntilFirstUserAuthentication,
      "The simulator may omit file-protection metadata, but must not report a weaker class.",
      file: file,
      line: line
    )
#else
    XCTAssertEqual(
      protection,
      .completeUntilFirstUserAuthentication,
      file: file,
      line: line
    )
#endif
  }
}

private struct VisibilityFixture: Decodable {
  let schemaVersion: Int64
  let freshnessWindowMs: Int64
  let digestVectors: [DigestVector]
  let invalidConversationVectors: [InvalidConversationVector]
  let predicateVectors: [PredicateVector]
}

private struct DigestVector: Decodable {
  let name: String
  let lane: String
  let input: String
  let normalizedId: String
  let preimageHex: String
  let digest: String
}

private struct InvalidConversationVector: Decodable {
  let name: String
  let lane: String
  let input: String
}

private struct PredicateVector: Decodable {
  let name: String
  let snapshot: IosAppVisibilitySnapshotV1
  let currentMonotonicMs: Int64
  let currentBootSession: String
  let expectedConversationDigest: String
  let maySuppress: Bool
}

private struct InvalidSnapshotVector {
  let name: String
  let snapshot: [String: Any]
}

private extension Data {
  var hexString: String {
    map { String(format: "%02x", $0) }.joined()
  }
}
