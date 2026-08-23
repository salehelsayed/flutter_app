import CryptoKit
import Foundation
import UserNotifications
import XCTest

@testable import Runner

final class IosNotificationRecoveryTests: XCTestCase {
  func testTC397GroupDeliveredInventoryClassifiesExactSources() throws {
    func hash(_ value: String) -> String {
      SHA256.hash(data: Data(value.utf8))
        .map { String(format: "%02x", $0) }.joined()
    }
    func localPayload(kind: String, event: String) throws -> String {
      let data = try JSONSerialization.data(withJSONObject: [
        "v": 1,
        "route": "group:group-397",
        "conversation": "group:group-397",
        "content": [
          "v": 1,
          "kind": kind,
          "event": event,
          "generation": "generation-397",
        ],
      ])
      return "mknoon-conversation-card-v1:"
        + data.base64EncodedString()
          .replacingOccurrences(of: "+", with: "-")
          .replacingOccurrences(of: "/", with: "_")
          .replacingOccurrences(of: "=", with: "")
    }
    let messageExpected = IosGroupNotificationExpectedHashes(
      phase: .message,
      groupIdSha256: hash("group-397"),
      eventIdSha256: hash("message-397"),
      targetMessageIdSha256: hash("target-397")
    )
    let reactionExpected = IosGroupNotificationExpectedHashes(
      phase: .reaction,
      groupIdSha256: hash("group-397"),
      eventIdSha256: hash("reaction-397"),
      targetMessageIdSha256: hash("target-397")
    )

    XCTAssertEqual(
      IosGroupNotificationSourceClassifier.classify(
        triggerOrigin: .remote,
        userInfo: [
          "type": "group_message",
          "groupId": "group-397",
          "message_id": "message-397",
        ],
        title: "Plan 397 group",
        body: "Plan 397 message",
        expected: messageExpected
      ),
      .usefulProviderRich
    )
    XCTAssertEqual(
      IosGroupNotificationSourceClassifier.classify(
        triggerOrigin: .remote,
        userInfo: [
          "type": "group_reaction",
          "action": "add",
          "groupId": "group-397",
          "event_id": "reaction-397",
          "target_message_id": "target-397",
        ],
        title: "Plan 397 group",
        body: "Alice reacted",
        expected: reactionExpected
      ),
      .usefulProviderRich
    )
    XCTAssertEqual(
      IosGroupNotificationSourceClassifier.classify(
        triggerOrigin: .local,
        userInfo: [
          "NotificationId": 397,
          "payload": try localPayload(kind: "message", event: "message-397"),
        ],
        title: "Plan 397 group",
        body: "Plan 397 message",
        expected: messageExpected
      ),
      .flutterLocal
    )
    XCTAssertEqual(
      IosGroupNotificationSourceClassifier.classify(
        triggerOrigin: .local,
        userInfo: [
          "NotificationId": 398,
          "payload": try localPayload(kind: "reaction", event: "reaction-397"),
        ],
        title: "Plan 397 group",
        body: "Alice reacted",
        expected: reactionExpected
      ),
      .flutterLocal
    )
    XCTAssertEqual(
      IosGroupNotificationSourceClassifier.classify(
        triggerOrigin: .remote,
        userInfo: [
          "type": "group_reaction",
          "action": "add",
          "groupId": "group-397",
          "event_id": "reaction-397",
          "target_message_id": "wrong-target",
        ],
        title: "Plan 397 group",
        body: "Alice reacted",
        expected: reactionExpected
      ),
      .unknown
    )
    XCTAssertNil(
      IosGroupNotificationSourceClassifier.classify(
        triggerOrigin: .remote,
        userInfo: [
          "type": "group_message",
          "groupId": "group-397",
          "message_id": "another-message",
        ],
        title: "Other",
        body: "Other",
        expected: messageExpected
      )
    )
    XCTAssertNotEqual(
      IosGroupNotificationSourceClassifier.classify(
        triggerOrigin: .local,
        userInfo: [
          "type": "group_message",
          "groupId": "group-397",
          "message_id": "message-397",
        ],
        title: "Forged provider",
        body: "Forged provider",
        expected: messageExpected
      ),
      .usefulProviderRich
    )
  }

  func testTC397GroupInventoryRequiresFullHorizonAndRejectsTransientLateLocalSibling() {
    func inventory(remote: Int, local: Int) -> Runner.IosGroupNotificationInventory {
      Runner.IosGroupNotificationInventory(
        matchingRemoteCount: remote,
        matchingLocalCount: local,
        matchingUsefulProviderCount: remote,
        matchingSanitizedProviderCount: 0,
        matchingFlutterLocalCount: local,
        matchingUnknownCount: 0,
        requestIdentifierSha256: (0..<(remote + local)).map {
          String(repeating: String(format: "%x", $0 + 1), count: 64)
        }
      )
    }
    let providerOnly = inventory(remote: 1, local: 0)
    let transientSibling = inventory(remote: 1, local: 1)
    var samples = [providerOnly, providerOnly, providerOnly, transientSibling]
      + Array(repeating: providerOnly, count: 12)
    let now = Date(timeIntervalSince1970: 1_900_000_000)
    var current = now
    var scheduled: [(TimeInterval, () -> Void)] = []
    var outcomes: [Runner.IosGroupNotificationFullHorizonOutcome] = []
    let sampler = Runner.IosGroupNotificationFullHorizonSampler(
      now: { current },
      scheduleAfter: { delay, action in scheduled.append((delay, action)) },
      fetchInventory: { callback in callback(samples.removeFirst()) }
    )

    sampler.start(
      deadline: now.addingTimeInterval(8),
      completion: { outcomes.append($0) }
    )
    XCTAssertTrue(outcomes.isEmpty, "three early equal samples must not complete")

    while let index = scheduled.indices
      .filter({ scheduled[$0].0 < 8 })
      .min(by: { scheduled[$0].0 < scheduled[$1].0 }) {
      let next = scheduled.remove(at: index)
      current = current.addingTimeInterval(next.0)
      next.1()
    }
    XCTAssertTrue(outcomes.isEmpty)
    let deadlineIndex = try! XCTUnwrap(
      scheduled.firstIndex(where: { $0.0 == 8 })
    )
    current = now.addingTimeInterval(8)
    scheduled.remove(at: deadlineIndex).1()

    XCTAssertEqual(outcomes.count, 1)
    XCTAssertEqual(outcomes[0].resultCode, .complete)
    XCTAssertEqual(outcomes[0].stableSampleCount, 3)
    XCTAssertTrue(outcomes[0].sampledThroughDeadline)
    XCTAssertTrue(outcomes[0].badSourceSeen)
    XCTAssertTrue(outcomes[0].duplicateSeen)
    XCTAssertEqual(outcomes[0].inventory, providerOnly)
  }

  func testAtomicClaimsReopenAndCountOnePendingEventAcrossDuplicates() throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let stores = (0..<4).map { _ in
      IosNotificationRecoveryStore(directory: directory)
    }
    let identity = ordinaryIdentity(eventId: "event-1")

    let outcomes = LockedArray<IosNotificationRecoveryClaim>()
    DispatchQueue.concurrentPerform(iterations: 12) { index in
      outcomes.append(stores[index % stores.count].claimPrepared(
        requestIdentifier: "request-\(index)",
        identity: identity
      ))
    }

    XCTAssertEqual(outcomes.values.filter { $0 == .unique }.count, 1)
    XCTAssertEqual(outcomes.values.filter { $0 == .duplicate }.count, 11)
    XCTAssertEqual(stores[0].desiredBadgeSnapshot()?.count, 1)
    let reopened = IosNotificationRecoveryStore(directory: directory)
    XCTAssertTrue(reopened.containsRequestForTesting("request-0"))
    XCTAssertEqual(reopened.desiredBadgeSnapshot()?.count, 1)
  }

  func testUnknownSchemaIsPreservedWhileRunnerQuarantinesOnlyCorruptV1()
    throws
  {
    let unknownDirectory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: unknownDirectory) }
    let unknownURL = unknownDirectory.appendingPathComponent(
      "ios_notification_recovery_v1.json"
    )
    let unknownBytes = Data(#"{"version":2,"future":"keep-me"}"#.utf8)
    try unknownBytes.write(to: unknownURL)
    let unknownStore = IosNotificationRecoveryStore(directory: unknownDirectory)

    XCTAssertEqual(
      unknownStore.claimPrepared(
        requestIdentifier: "request",
        identity: ordinaryIdentity(eventId: "event")
      ),
      .unsupportedSchema
    )
    XCTAssertNil(unknownStore.beginReconciliation(accountPeerId: "self"))
    XCTAssertEqual(try Data(contentsOf: unknownURL), unknownBytes)

    let corruptDirectory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: corruptDirectory) }
    try Data(#"{"version":1,"broken""#.utf8).write(
      to: corruptDirectory.appendingPathComponent(
        "ios_notification_recovery_v1.json"
      )
    )
    let corruptStore = IosNotificationRecoveryStore(directory: corruptDirectory)
    XCTAssertEqual(
      corruptStore.claimPrepared(
        requestIdentifier: "request",
        identity: ordinaryIdentity(eventId: "event")
      ),
      .corruptState
    )
    XCTAssertNotNil(corruptStore.beginReconciliation(accountPeerId: "self"))
    let names = try FileManager.default.contentsOfDirectory(
      atPath: corruptDirectory.path
    )
    XCTAssertTrue(names.contains { $0.hasPrefix("ios_notification_recovery_corrupt_") })
  }

  func testCapacityRejectsNewClaimWithoutEvictingOwnedRow() throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = IosNotificationRecoveryStore(directory: directory, maxRows: 1)
    XCTAssertEqual(store.claimPrepared(
      requestIdentifier: "owned",
      identity: ordinaryIdentity(eventId: "owned-event")
    ), .unique)

    XCTAssertEqual(store.claimPrepared(
      requestIdentifier: "overflow",
      identity: ordinaryIdentity(eventId: "overflow-event")
    ), .capacityExceeded)
    XCTAssertTrue(store.containsRequestForTesting("owned"))
    XCTAssertFalse(store.containsRequestForTesting("overflow"))
    XCTAssertEqual(store.desiredBadgeSnapshot()?.count, 1)
  }

  func testAccountFenceRejectsLateOldAccountCommitAndNseClaim() throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = IosNotificationRecoveryStore(directory: directory)
    let first = try XCTUnwrap(
      store.beginReconciliation(accountPeerId: "account-a")
    )
    XCTAssertEqual(
      store.claimPrepared(
        requestIdentifier: "a-request",
        identity: ordinaryIdentity(account: "account-a", eventId: "a-event")
      ),
      .unique
    )
    _ = try XCTUnwrap(store.beginReconciliation(accountPeerId: "account-b"))

    XCTAssertFalse(store.commitCanonicalState(
      accountPeerId: "account-a",
      generation: first.generation,
      watermark: first.watermark,
      canonicalBadgeCount: 0,
      identities: []
    ))
    XCTAssertEqual(
      store.claimPrepared(
        requestIdentifier: "late-a",
        identity: ordinaryIdentity(account: "account-a", eventId: "late")
      ),
      .accountMismatch
    )
  }

  func testClearAccountSuspendsNseClaimsUntilNextAccountBegin() throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = IosNotificationRecoveryStore(directory: directory)
    _ = try XCTUnwrap(
      store.beginReconciliation(accountPeerId: "account-a")
    )
    XCTAssertEqual(store.claimPrepared(
      requestIdentifier: "before-clear",
      identity: ordinaryIdentity(account: "account-a", eventId: "event-a")
    ), .unique)

    XCTAssertNotNil(store.clearAccount())
    XCTAssertEqual(store.claimPrepared(
      requestIdentifier: "late-after-clear",
      identity: ordinaryIdentity(account: "account-a", eventId: "late-a")
    ), .accountMismatch)

    _ = try XCTUnwrap(
      store.beginReconciliation(accountPeerId: "account-b")
    )
    XCTAssertEqual(store.claimPrepared(
      requestIdentifier: "after-next-begin",
      identity: ordinaryIdentity(account: "account-b", eventId: "event-b")
    ), .unique)
  }

  func testPreDeliveryAbsenceRemainsButObservedDismissalPrunes() throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = IosNotificationRecoveryStore(directory: directory)
    XCTAssertEqual(
      store.claimPrepared(
        requestIdentifier: "not-yet-delivered",
        identity: ordinaryIdentity(eventId: "event")
      ),
      .unique
    )
    let begin = try XCTUnwrap(
      store.beginReconciliation(accountPeerId: "account-self")
    )
    XCTAssertTrue(store.commitCanonicalState(
      accountPeerId: "account-self",
      generation: begin.generation,
      watermark: begin.watermark,
      canonicalBadgeCount: 0,
      identities: []
    ))
    _ = store.pruneObservedAbsent(
      remainingDeliveredIdentifiers: [],
      watermark: begin.watermark
    )
    XCTAssertTrue(store.containsRequestForTesting("not-yet-delivered"))

    XCTAssertTrue(store.markDelivered(["not-yet-delivered"]))
    _ = store.pruneObservedAbsent(
      remainingDeliveredIdentifiers: [],
      watermark: begin.watermark
    )
    XCTAssertFalse(store.containsRequestForTesting("not-yet-delivered"))
  }

  func testPreparedAbsentCommitDoesNotIssueRemovalCall() throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = IosNotificationRecoveryStore(directory: directory)
    XCTAssertEqual(store.claimPrepared(
      requestIdentifier: "pre-handler",
      identity: ordinaryIdentity(eventId: "event")
    ), .unique)
    let center = MemoryRecoveryCenter(inventories: [[], []])
    let coordinator = IosNotificationRecoveryCoordinator(
      store: store,
      center: center,
      badgeWriter: RecordingBadgeWriter()
    )
    let begin = try XCTUnwrap(
      coordinator.beginReconciliation(accountPeerId: "account-self")
    )
    let completed = expectation(description: "commit")
    coordinator.commitReconciliation(
      token: begin.token,
      watermark: begin.watermark,
      accountPeerId: "account-self",
      canonicalStateComplete: true,
      canonicalBadgeCount: 0,
      identities: []
    ) { ok in
      XCTAssertTrue(ok)
      completed.fulfill()
    }
    wait(for: [completed], timeout: 2)

    XCTAssertTrue(center.removals.isEmpty)
    XCTAssertTrue(store.containsRequestForTesting("pre-handler"))
  }

  func testTC395ExactGroupInviteRetirementIsSurgicalAndIdempotent() throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let groupId = "group-target"
    let inviteId = "invite-target"
    let exactLocalPayload =
      "group_invite:\(groupId)|message:\(inviteId)"
    let rawDeliveredRows: [(String, [AnyHashable: Any])] = [
      (
        "provider-exact-a",
        [
          "type": "group_invite",
          "groupId": groupId,
          "message_id": inviteId,
        ]
      ),
      (
        "provider-exact-b",
        [
          "type": "group_invite",
          "groupId": groupId,
          "message_id": inviteId,
          "gcm.message_id": "provider-copy-b",
        ]
      ),
      (
        "local-exact",
        ["NotificationId": 395, "payload": exactLocalPayload]
      ),
      (
        "newer-same-group",
        [
          "type": "group_invite",
          "groupId": groupId,
          "message_id": "invite-newer",
        ]
      ),
      (
        "same-invite-another-group",
        [
          "type": "group_invite",
          "groupId": "group-other",
          "message_id": inviteId,
        ]
      ),
      (
        "ordinary-group",
        [
          "type": "group_message",
          "groupId": groupId,
          "message_id": inviteId,
        ]
      ),
      (
        "ordinary-direct",
        ["type": "new_message", "message_id": inviteId]
      ),
      (
        "provider-missing-type",
        ["groupId": groupId, "message_id": inviteId]
      ),
      (
        "provider-missing-group",
        ["type": "group_invite", "message_id": inviteId]
      ),
      (
        "provider-missing-invite",
        ["type": "group_invite", "groupId": groupId]
      ),
      (
        "provider-nested-only",
        [
          "data": [
            "type": "group_invite",
            "groupId": groupId,
            "message_id": inviteId,
          ]
        ]
      ),
      (
        "provider-substring",
        [
          "type": "group_invite_copy",
          "groupId": groupId,
          "message_id": inviteId,
        ]
      ),
      (
        "provider-edge-whitespace",
        [
          "type": "group_invite",
          "groupId": " \(groupId)",
          "message_id": inviteId,
        ]
      ),
      ("local-missing-id", ["payload": exactLocalPayload]),
      (
        "local-malformed-id",
        ["NotificationId": "395", "payload": exactLocalPayload]
      ),
      (
        "local-newer-same-group",
        [
          "NotificationId": 396,
          "payload": "group_invite:\(groupId)|message:invite-newer",
        ]
      ),
      (
        "local-substring",
        ["NotificationId": 397, "payload": "\(exactLocalPayload)-copy"]
      ),
      (
        "local-provider-triplet-wrong-payload",
        [
          "NotificationId": 398,
          "payload": "group_invite:group-other|message:\(inviteId)",
          "type": "group_invite",
          "groupId": groupId,
          "message_id": inviteId,
        ]
      ),
    ]
    let snapshots = rawDeliveredRows.map { row in
      IosDeliveredNotificationSnapshot(
        requestIdentifier: row.0,
        userInfo: row.1
      )
    }
    let center = MutableSnapshotRecoveryCenter(snapshots: snapshots)
    let coordinator = IosNotificationRecoveryCoordinator(
      store: IosNotificationRecoveryStore(directory: directory),
      center: center,
      badgeWriter: RecordingBadgeWriter()
    )

    let first = expectation(description: "first exact retirement")
    coordinator.retireGroupInvite(
      groupId: groupId,
      inviteId: inviteId
    ) { ok in
      XCTAssertTrue(ok)
      first.fulfill()
    }
    wait(for: [first], timeout: 2)

    let exactIdentifiers: Set<String> = [
      "provider-exact-a",
      "provider-exact-b",
      "local-exact",
    ]
    XCTAssertEqual(center.removals.map { Set($0) }, [exactIdentifiers])
    XCTAssertEqual(
      center.currentIdentifiers,
      Set(rawDeliveredRows.map { $0.0 }).subtracting(exactIdentifiers)
    )
    XCTAssertEqual(center.snapshotInventoryCount, 2)

    let second = expectation(description: "idempotent exact retirement")
    coordinator.retireGroupInvite(
      groupId: groupId,
      inviteId: inviteId
    ) { ok in
      XCTAssertTrue(ok)
      second.fulfill()
    }
    wait(for: [second], timeout: 2)

    XCTAssertEqual(center.removals.map { Set($0) }, [exactIdentifiers])
    XCTAssertEqual(center.snapshotInventoryCount, 4)
  }

  func testCoordinatorWatermarkPreservesLaterAndUnrelatedDeliveredIds() throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = IosNotificationRecoveryStore(directory: directory)
    XCTAssertEqual(store.claimPrepared(
      requestIdentifier: "owned-before",
      identity: ordinaryIdentity(eventId: "event-before")
    ), .unique)
    let center = MemoryRecoveryCenter(inventories: [
      ["owned-before", "owned-later", "unrelated"],
      ["owned-later", "unrelated"],
    ])
    let badge = RecordingBadgeWriter()
    let coordinator = IosNotificationRecoveryCoordinator(
      store: store,
      center: center,
      badgeWriter: badge
    )
    let begin = try XCTUnwrap(
      coordinator.beginReconciliation(accountPeerId: "account-self")
    )
    XCTAssertEqual(store.claimPrepared(
      requestIdentifier: "owned-later",
      identity: ordinaryIdentity(eventId: "event-later")
    ), .unique)

    let completed = expectation(description: "commit")
    coordinator.commitReconciliation(
      token: begin.token,
      watermark: begin.watermark,
      accountPeerId: "account-self",
      canonicalStateComplete: true,
      canonicalBadgeCount: 0,
      identities: []
    ) { ok in
      XCTAssertTrue(ok)
      completed.fulfill()
    }
    wait(for: [completed], timeout: 2)

    XCTAssertEqual(center.removals, [["owned-before"]])
    XCTAssertFalse(store.containsRequestForTesting("owned-before"))
    XCTAssertTrue(store.containsRequestForTesting("owned-later"))
    XCTAssertEqual(badge.calls, 1)
  }

  func testIncompleteCommitConsumesTokenWithoutChangingRecoveryState() throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = IosNotificationRecoveryStore(directory: directory)
    _ = store.claimPrepared(
      requestIdentifier: "pending",
      identity: ordinaryIdentity(eventId: "pending-event")
    )
    let center = MemoryRecoveryCenter(inventories: [])
    let badge = RecordingBadgeWriter()
    let coordinator = IosNotificationRecoveryCoordinator(
      store: store,
      center: center,
      badgeWriter: badge
    )
    let begin = try XCTUnwrap(
      coordinator.beginReconciliation(accountPeerId: "account-self")
    )
    let completed = expectation(description: "incomplete accepted")
    coordinator.commitReconciliation(
      token: begin.token,
      watermark: begin.watermark,
      accountPeerId: "account-self",
      canonicalStateComplete: false,
      canonicalBadgeCount: 999,
      identities: []
    ) { ok in
      XCTAssertTrue(ok)
      completed.fulfill()
    }
    wait(for: [completed], timeout: 2)

    XCTAssertEqual(store.desiredBadgeSnapshot()?.count, 1)
    XCTAssertTrue(store.containsRequestForTesting("pending"))
    XCTAssertTrue(center.removals.isEmpty)
    XCTAssertEqual(badge.calls, 0)

    let replay = expectation(description: "token consumed")
    coordinator.commitReconciliation(
      token: begin.token,
      watermark: begin.watermark,
      accountPeerId: "account-self",
      canonicalStateComplete: false,
      canonicalBadgeCount: 0,
      identities: []
    ) { ok in
      XCTAssertFalse(ok)
      replay.fulfill()
    }
    wait(for: [replay], timeout: 2)
  }

  func testConcurrentIncompleteCommitConsumesTokenExactlyOnce() throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = IosNotificationRecoveryStore(directory: directory)
    let coordinator = IosNotificationRecoveryCoordinator(
      store: store,
      center: MemoryRecoveryCenter(inventories: []),
      badgeWriter: RecordingBadgeWriter()
    )
    let begin = try XCTUnwrap(
      coordinator.beginReconciliation(accountPeerId: "account-self")
    )
    let outcomes = LockedArray<Bool>()
    DispatchQueue.concurrentPerform(iterations: 2) { _ in
      coordinator.commitReconciliation(
        token: begin.token,
        watermark: begin.watermark,
        accountPeerId: "account-self",
        canonicalStateComplete: false,
        canonicalBadgeCount: 0,
        identities: []
      ) { outcomes.append($0) }
    }

    XCTAssertEqual(outcomes.values.filter { $0 }.count, 1)
    XCTAssertEqual(outcomes.values.filter { !$0 }.count, 1)
  }

  func testIncompleteCommitRejectsSessionAfterExternalAccountCutover() throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = IosNotificationRecoveryStore(directory: directory)
    let coordinator = IosNotificationRecoveryCoordinator(
      store: store,
      center: MemoryRecoveryCenter(inventories: []),
      badgeWriter: RecordingBadgeWriter()
    )
    let begin = try XCTUnwrap(
      coordinator.beginReconciliation(accountPeerId: "account-a")
    )
    _ = try XCTUnwrap(
      store.beginReconciliation(accountPeerId: "account-b")
    )

    let completed = expectation(description: "stale incomplete rejected")
    coordinator.commitReconciliation(
      token: begin.token,
      watermark: begin.watermark,
      accountPeerId: "account-a",
      canonicalStateComplete: false,
      canonicalBadgeCount: 0,
      identities: []
    ) { ok in
      XCTAssertFalse(ok)
      completed.fulfill()
    }
    wait(for: [completed], timeout: 2)
  }

  func testForegroundSuppressionDropsOnlyCustodyAndKeepsPendingBadge() throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = IosNotificationRecoveryStore(directory: directory)
    _ = store.claimPrepared(
      requestIdentifier: "foreground",
      identity: ordinaryIdentity(eventId: "event")
    )
    XCTAssertTrue(store.markForegroundSuppressed(
      requestIdentifier: "foreground"
    ))
    XCTAssertFalse(store.containsRequestForTesting("foreground"))
    XCTAssertEqual(store.desiredBadgeSnapshot()?.count, 1)
  }

  func testForegroundSuppressedReplayIsDuplicateAndCountNeutral() throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = IosNotificationRecoveryStore(directory: directory)
    let identity = ordinaryIdentity(eventId: "event")
    XCTAssertEqual(store.claimPrepared(
      requestIdentifier: "foreground",
      identity: identity
    ), .unique)
    XCTAssertTrue(store.markForegroundSuppressed(
      requestIdentifier: "foreground"
    ))

    XCTAssertEqual(store.claimPrepared(
      requestIdentifier: "replay",
      identity: identity
    ), .duplicate)
    XCTAssertEqual(store.desiredBadgeSnapshot()?.count, 1)
  }

  func testForegroundSuppressionFencesAlreadyConsumedReconciliation() throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = IosNotificationRecoveryStore(directory: directory)
    XCTAssertEqual(store.claimPrepared(
      requestIdentifier: "foreground",
      identity: ordinaryIdentity(eventId: "event")
    ), .unique)
    let inventoryRequested = expectation(description: "inventory requested")
    let center = SuspendedRecoveryCenter(requested: inventoryRequested)
    let coordinator = IosNotificationRecoveryCoordinator(
      store: store,
      center: center,
      badgeWriter: RecordingBadgeWriter()
    )
    let begin = try XCTUnwrap(
      coordinator.beginReconciliation(accountPeerId: "account-self")
    )
    let completed = expectation(description: "stale commit rejected")

    coordinator.commitReconciliation(
      token: begin.token,
      watermark: begin.watermark,
      accountPeerId: "account-self",
      canonicalStateComplete: true,
      canonicalBadgeCount: 0,
      identities: []
    ) { ok in
      XCTAssertFalse(ok)
      completed.fulfill()
    }
    wait(for: [inventoryRequested], timeout: 2)

    coordinator.markForegroundSuppressed(requestIdentifier: "foreground")
    center.resume(with: [])

    wait(for: [completed], timeout: 2)
    XCTAssertFalse(store.containsRequestForTesting("foreground"))
    XCTAssertEqual(store.desiredBadgeSnapshot()?.count, 1)
  }

  func testObservedPrunedReactionReplayRemainsDuplicateAndCountNeutral()
    throws
  {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = IosNotificationRecoveryStore(directory: directory)
    let identity = IosNotificationRecoveryIdentity(
      accountPeerId: "account-self",
      lane: .direct,
      conversationId: "peer-alice",
      eventId: "reaction-event",
      kind: .reaction
    )
    XCTAssertEqual(store.claimPrepared(
      requestIdentifier: "first-reaction",
      identity: identity
    ), .unique)
    XCTAssertTrue(store.markDelivered(["first-reaction"]))
    XCTAssertTrue(store.pruneObservedAbsent(
      remainingDeliveredIdentifiers: [],
      watermark: UInt64.max
    ))

    XCTAssertEqual(store.claimPrepared(
      requestIdentifier: "reaction-replay",
      identity: identity
    ), .duplicate)
    XCTAssertEqual(store.desiredBadgeSnapshot()?.count, 0)
  }

  func testSameEventIdInDifferentConversationsRemainsUnique() throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = IosNotificationRecoveryStore(directory: directory)
    XCTAssertEqual(store.claimPrepared(
      requestIdentifier: "alice",
      identity: ordinaryIdentity(
        conversation: "peer-alice",
        eventId: "shared-event-id"
      )
    ), .unique)
    XCTAssertEqual(store.claimPrepared(
      requestIdentifier: "bob",
      identity: ordinaryIdentity(
        conversation: "peer-bob",
        eventId: "shared-event-id"
      )
    ), .unique)
    XCTAssertEqual(store.desiredBadgeSnapshot()?.count, 2)
  }

  func testCanonicalCommitDeduplicatesMatchingPostWatermarkPendingEvent()
    throws
  {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = IosNotificationRecoveryStore(directory: directory)
    let begin = try XCTUnwrap(
      store.beginReconciliation(accountPeerId: "account-self")
    )
    XCTAssertEqual(store.claimPrepared(
      requestIdentifier: "post-watermark",
      identity: ordinaryIdentity(eventId: "canonical-event")
    ), .unique)

    XCTAssertTrue(store.commitCanonicalState(
      accountPeerId: "account-self",
      generation: begin.generation,
      watermark: begin.watermark,
      canonicalBadgeCount: 1,
      identities: [
        IosNotificationCanonicalIdentity(
          lane: .direct,
          conversationId: "peer-alice",
          eventId: "canonical-event"
        ),
      ]
    ))
    XCTAssertEqual(store.desiredBadgeSnapshot()?.count, 1)
    XCTAssertTrue(store.containsRequestForTesting("post-watermark"))
  }

  func testCanonicalCommitPreservesUnresolvedPostWatermarkPendingEvent()
    throws
  {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = IosNotificationRecoveryStore(directory: directory)
    let begin = try XCTUnwrap(
      store.beginReconciliation(accountPeerId: "account-self")
    )
    XCTAssertEqual(store.claimPrepared(
      requestIdentifier: "post-watermark",
      identity: ordinaryIdentity(eventId: "pending-event")
    ), .unique)

    XCTAssertTrue(store.commitCanonicalState(
      accountPeerId: "account-self",
      generation: begin.generation,
      watermark: begin.watermark,
      canonicalBadgeCount: 0,
      identities: []
    ))
    XCTAssertEqual(store.desiredBadgeSnapshot()?.count, 1)
    XCTAssertTrue(store.containsRequestForTesting("post-watermark"))
  }

  func testCanonicalCommitAbsorbsOldPendingButPreservesPostWatermarkPending()
    throws
  {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = IosNotificationRecoveryStore(directory: directory)
    _ = store.claimPrepared(
      requestIdentifier: "old",
      identity: ordinaryIdentity(eventId: "old-event")
    )
    let begin = try XCTUnwrap(
      store.beginReconciliation(accountPeerId: "account-self")
    )
    _ = store.claimPrepared(
      requestIdentifier: "later",
      identity: ordinaryIdentity(eventId: "later-event")
    )
    XCTAssertTrue(store.commitCanonicalState(
      accountPeerId: "account-self",
      generation: begin.generation,
      watermark: begin.watermark,
      canonicalBadgeCount: 1,
      identities: [
        IosNotificationCanonicalIdentity(
          lane: .direct,
          conversationId: "peer-alice",
          eventId: "old-event"
        ),
      ]
    ))
    XCTAssertEqual(store.desiredBadgeSnapshot()?.count, 2)
    XCTAssertTrue(store.containsRequestForTesting("later"))
  }

  func testIdentityFreeOrdinaryAndReactionRetireOnlyAtConversationZero()
    throws
  {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = IosNotificationRecoveryStore(directory: directory)
    XCTAssertEqual(store.claimPrepared(
      requestIdentifier: "identity-free",
      identity: ordinaryIdentity(eventId: nil)
    ), .unique)
    XCTAssertEqual(store.claimPrepared(
      requestIdentifier: "reaction",
      identity: IosNotificationRecoveryIdentity(
        accountPeerId: "account-self",
        lane: .direct,
        conversationId: "peer-alice",
        eventId: "reaction-event",
        kind: .reaction
      )
    ), .unique)
    XCTAssertTrue(store.markDelivered(["identity-free", "reaction"]))

    let nonempty = try XCTUnwrap(
      store.beginReconciliation(accountPeerId: "account-self")
    )
    XCTAssertTrue(store.commitCanonicalState(
      accountPeerId: "account-self",
      generation: nonempty.generation,
      watermark: nonempty.watermark,
      canonicalBadgeCount: 1,
      identities: [
        IosNotificationCanonicalIdentity(
          lane: .direct,
          conversationId: "peer-alice",
          eventId: "some-unread-event"
        ),
      ]
    ))
    XCTAssertTrue(
      store.removalCandidates(watermark: nonempty.watermark).isEmpty
    )

    let empty = try XCTUnwrap(
      store.beginReconciliation(accountPeerId: "account-self")
    )
    XCTAssertTrue(store.commitCanonicalState(
      accountPeerId: "account-self",
      generation: empty.generation,
      watermark: empty.watermark,
      canonicalBadgeCount: 0,
      identities: []
    ))
    XCTAssertEqual(
      Set(store.removalCandidates(watermark: empty.watermark)),
      ["identity-free", "reaction"]
    )
  }

  func testCanonicalReplayAfterCustodyPruneIsDuplicateAndDoesNotDoubleBadge()
    throws
  {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    // Disable the recent-claim tombstone in this test so the assertion is
    // causally owned by canonical unread replay memory.
    let store = IosNotificationRecoveryStore(
      directory: directory,
      maxRecentEvents: 0
    )
    let identity = ordinaryIdentity(eventId: "canonical-event")
    XCTAssertEqual(store.claimPrepared(
      requestIdentifier: "first-request",
      identity: identity
    ), .unique)
    let begin = try XCTUnwrap(
      store.beginReconciliation(accountPeerId: "account-self")
    )
    XCTAssertTrue(store.commitCanonicalState(
      accountPeerId: "account-self",
      generation: begin.generation,
      watermark: begin.watermark,
      canonicalBadgeCount: 1,
      identities: [
        IosNotificationCanonicalIdentity(
          lane: .direct,
          conversationId: "peer-alice",
          eventId: "canonical-event"
        ),
      ]
    ))
    XCTAssertTrue(store.markDelivered(["first-request"]))
    XCTAssertTrue(store.pruneObservedAbsent(
      remainingDeliveredIdentifiers: [],
      watermark: begin.watermark
    ))
    XCTAssertFalse(store.containsRequestForTesting("first-request"))

    XCTAssertEqual(store.claimPrepared(
      requestIdentifier: "replayed-request",
      identity: identity
    ), .duplicate)
    XCTAssertEqual(store.desiredBadgeSnapshot()?.count, 1)
  }

  func testRetiredOrdinaryReplayRemainsDuplicateAfterPendingAndCustodyClear()
    throws
  {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = IosNotificationRecoveryStore(directory: directory)
    let identity = ordinaryIdentity(eventId: "read-event")
    XCTAssertEqual(store.claimPrepared(
      requestIdentifier: "first-request",
      identity: identity
    ), .unique)
    let begin = try XCTUnwrap(
      store.beginReconciliation(accountPeerId: "account-self")
    )
    XCTAssertTrue(store.commitCanonicalState(
      accountPeerId: "account-self",
      generation: begin.generation,
      watermark: begin.watermark,
      canonicalBadgeCount: 0,
      identities: []
    ))
    XCTAssertTrue(store.markDelivered(["first-request"]))
    XCTAssertTrue(store.pruneObservedAbsent(
      remainingDeliveredIdentifiers: [],
      watermark: begin.watermark
    ))

    XCTAssertEqual(store.claimPrepared(
      requestIdentifier: "late-replay",
      identity: identity
    ), .duplicate)
    XCTAssertEqual(store.desiredBadgeSnapshot()?.count, 0)
  }

  func testApplyingAuthorizedPreviewAlwaysClearsProviderBadge() {
    let content = UNMutableNotificationContent()
    content.badge = 99
    applyNotificationPreviewResult(
      NotificationPreviewResult(
        title: "Trusted title",
        body: "Trusted body",
        threadIdentifier: nil,
        didDecrypt: true,
        reason: "chat"
      ),
      to: content
    )

    XCTAssertNil(content.badge)
  }

  func testSerializedBadgeWriterRereadsAfterInFlightStateChange() throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = IosNotificationRecoveryStore(directory: directory)
    _ = store.claimPrepared(
      requestIdentifier: "first",
      identity: ordinaryIdentity(eventId: "first")
    )
    let firstWrite = expectation(description: "first badge write")
    let repairedWrite = expectation(description: "repaired badge write")
    let recorder = BadgeSetterRecorder(
      firstExpectation: firstWrite,
      secondExpectation: repairedWrite
    )
    let writer = IosNotificationSerializedBadgeWriter(
      store: store,
      setter: recorder.set
    )
    writer.requestWrite()
    wait(for: [firstWrite], timeout: 2)

    _ = store.claimPrepared(
      requestIdentifier: "second",
      identity: ordinaryIdentity(eventId: "second")
    )
    recorder.completeFirst()
    wait(for: [repairedWrite], timeout: 2)
    XCTAssertEqual(recorder.counts, [1, 2])
    recorder.completeLast()
  }

  func testLegacyBadgeWriterUsesInjectedMainThreadFallback() throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = IosNotificationRecoveryStore(directory: directory)
    _ = store.claimPrepared(
      requestIdentifier: "request",
      identity: ordinaryIdentity(eventId: "event")
    )
    let wrote = expectation(description: "legacy badge")
    let writer = IosNotificationLegacyBadgeWriter(
      store: store,
      setter: { count in
        XCTAssertTrue(Thread.isMainThread)
        XCTAssertEqual(count, 1)
        wrote.fulfill()
      }
    )
    writer.requestWrite()
    wait(for: [wrote], timeout: 2)
  }

  func testProductionHandoffSeamClaimsBeforeHandlerAndCommitsAfter() {
    let events = LockedArray<String>()
    let store = OrderedHandoffStore(events: events)
    let orchestrator = IosNotificationRecoveryHandoffOrchestrator(store: store)
    let content = UNMutableNotificationContent()

    let disposition = orchestrator.handoff(
      requestIdentifier: "request",
      identity: ordinaryIdentity(eventId: "event"),
      content: content,
      prepareContent: { _ in events.append("prepare-content") },
      beforeContentHandler: { _ in events.append("enqueue-badge") },
      contentHandler: { _ in events.append("handler") }
    )

    XCTAssertEqual(disposition, .unique)
    XCTAssertEqual(events.values, [
      "claim-prepared",
      "prepare-content",
      "enqueue-badge",
      "handler",
      "mark-committed",
    ])
  }

  private func ordinaryIdentity(
    account: String = "account-self",
    conversation: String = "peer-alice",
    eventId: String?
  ) -> IosNotificationRecoveryIdentity {
    IosNotificationRecoveryIdentity(
      accountPeerId: account,
      lane: .direct,
      conversationId: conversation,
      eventId: eventId,
      kind: .ordinary
    )
  }

  private func temporaryDirectory() throws -> URL {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      "ios-notification-recovery-tests-\(UUID().uuidString)",
      isDirectory: true
    )
    try FileManager.default.createDirectory(
      at: directory,
      withIntermediateDirectories: true
    )
    return directory
  }
}

private final class LockedArray<Element>: @unchecked Sendable {
  private let lock = NSLock()
  private var storage: [Element] = []

  var values: [Element] {
    lock.lock()
    defer { lock.unlock() }
    return storage
  }

  func append(_ value: Element) {
    lock.lock()
    storage.append(value)
    lock.unlock()
  }
}

private final class MemoryRecoveryCenter: IosNotificationRecoveryCenter,
  @unchecked Sendable {
  private let lock = NSLock()
  private var inventories: [Set<String>]
  private(set) var removals: [[String]] = []

  init(inventories: [Set<String>]) {
    self.inventories = inventories
  }

  func getDeliveredRequestIdentifiers(
    completionHandler: @escaping @Sendable (Set<String>) -> Void
  ) {
    lock.lock()
    let value = inventories.isEmpty ? [] : inventories.removeFirst()
    lock.unlock()
    completionHandler(value)
  }

  func getDeliveredNotificationSnapshots(
    completionHandler:
      @escaping @Sendable ([IosDeliveredNotificationSnapshot]) -> Void
  ) {
    completionHandler([])
  }

  func removeDeliveredNotifications(withIdentifiers identifiers: [String]) {
    lock.lock()
    removals.append(identifiers)
    lock.unlock()
  }
}

private final class SuspendedRecoveryCenter: IosNotificationRecoveryCenter,
  @unchecked Sendable {
  private let lock = NSLock()
  private let requested: XCTestExpectation
  private var completion: (@Sendable (Set<String>) -> Void)?

  init(requested: XCTestExpectation) {
    self.requested = requested
  }

  func getDeliveredRequestIdentifiers(
    completionHandler: @escaping @Sendable (Set<String>) -> Void
  ) {
    lock.lock()
    completion = completionHandler
    lock.unlock()
    requested.fulfill()
  }

  func getDeliveredNotificationSnapshots(
    completionHandler:
      @escaping @Sendable ([IosDeliveredNotificationSnapshot]) -> Void
  ) {
    completionHandler([])
  }

  func removeDeliveredNotifications(withIdentifiers identifiers: [String]) {}

  func resume(with identifiers: Set<String>) {
    lock.lock()
    let completion = completion
    self.completion = nil
    lock.unlock()
    completion?(identifiers)
  }
}

private final class MutableSnapshotRecoveryCenter:
  IosNotificationRecoveryCenter, @unchecked Sendable {
  private let lock = NSLock()
  private var snapshots: [IosDeliveredNotificationSnapshot]
  private(set) var removals: [[String]] = []
  private(set) var snapshotInventoryCount = 0

  init(snapshots: [IosDeliveredNotificationSnapshot]) {
    self.snapshots = snapshots
  }

  var currentIdentifiers: Set<String> {
    lock.lock()
    defer { lock.unlock() }
    return Set(snapshots.map(\.requestIdentifier))
  }

  func getDeliveredRequestIdentifiers(
    completionHandler: @escaping @Sendable (Set<String>) -> Void
  ) {
    completionHandler(currentIdentifiers)
  }

  func getDeliveredNotificationSnapshots(
    completionHandler:
      @escaping @Sendable ([IosDeliveredNotificationSnapshot]) -> Void
  ) {
    lock.lock()
    snapshotInventoryCount += 1
    let value = snapshots
    lock.unlock()
    completionHandler(value)
  }

  func removeDeliveredNotifications(withIdentifiers identifiers: [String]) {
    lock.lock()
    removals.append(identifiers)
    let selected = Set(identifiers)
    snapshots.removeAll { selected.contains($0.requestIdentifier) }
    lock.unlock()
  }
}

private final class RecordingBadgeWriter: IosNotificationBadgeWriting {
  private(set) var calls = 0
  func requestWrite() { calls += 1 }
}

private final class BadgeSetterRecorder: @unchecked Sendable {
  private let lock = NSLock()
  private var completions: [(Error?) -> Void] = []
  private var recordedCounts: [Int] = []
  private let firstExpectation: XCTestExpectation
  private let secondExpectation: XCTestExpectation

  init(
    firstExpectation: XCTestExpectation,
    secondExpectation: XCTestExpectation
  ) {
    self.firstExpectation = firstExpectation
    self.secondExpectation = secondExpectation
  }

  var counts: [Int] {
    lock.lock()
    defer { lock.unlock() }
    return recordedCounts
  }

  func set(_ count: Int, completion: @escaping (Error?) -> Void) {
    lock.lock()
    recordedCounts.append(count)
    completions.append(completion)
    let index = recordedCounts.count
    lock.unlock()
    if index == 1 { firstExpectation.fulfill() }
    if index == 2 { secondExpectation.fulfill() }
  }

  func completeFirst() {
    lock.lock()
    let completion = completions.removeFirst()
    lock.unlock()
    completion(nil)
  }

  func completeLast() {
    lock.lock()
    guard let completion = completions.last else {
      lock.unlock()
      return
    }
    completions.removeAll()
    lock.unlock()
    completion(nil)
  }
}

private final class OrderedHandoffStore: IosNotificationRecoveryHandoffStoring {
  private let events: LockedArray<String>
  init(events: LockedArray<String>) { self.events = events }

  func claimPrepared(
    requestIdentifier: String,
    identity: IosNotificationRecoveryIdentity
  ) -> IosNotificationRecoveryClaim {
    events.append("claim-prepared")
    return .unique
  }

  func markCommitted(requestIdentifier: String) -> Bool {
    events.append("mark-committed")
    return true
  }
}
