import CryptoKit
import Foundation
import UIKit
import UserNotifications

struct IosDirectNotificationInventory: Equatable, Sendable {
  static let stableSampleTarget = 3
  static let stableSampleIntervalMilliseconds = 500
  static let settleDelayMilliseconds = 3_000
  static let observationDeadlineMilliseconds = 8_000

  let matchingRemoteCount: Int
  let matchingLocalCount: Int
  let matchingUsefulProviderCount: Int
  let matchingSanitizedProviderCount: Int
  let matchingFlutterLocalCount: Int
  let matchingUnknownCount: Int
  let requestIdentifierSha256: [String]

  var matchingTotalCount: Int {
    matchingUsefulProviderCount + matchingSanitizedProviderCount
      + matchingFlutterLocalCount + matchingUnknownCount
  }

  static let empty = IosDirectNotificationInventory(
    matchingRemoteCount: 0,
    matchingLocalCount: 0,
    matchingUsefulProviderCount: 0,
    matchingSanitizedProviderCount: 0,
    matchingFlutterLocalCount: 0,
    matchingUnknownCount: 0,
    requestIdentifierSha256: []
  )

  static func project(
    _ notifications: [UNNotification],
    expectedPeerId: String,
    expectedMessageId: String
  ) -> IosDirectNotificationInventory {
    var remote = 0
    var local = 0
    var useful = 0
    var sanitized = 0
    var flutterLocal = 0
    var unknown = 0
    var requestHashes: [String] = []
    for notification in notifications.prefix(8) {
      let request = notification.request
      let isRemote = request.trigger is UNPushNotificationTrigger
      if isRemote { remote += 1 } else { local += 1 }
      switch IosDirectNotificationSourceClassifier.classify(
        trigger: request.trigger,
        userInfo: request.content.userInfo,
        title: request.content.title,
        body: request.content.body,
        expectedPeerId: expectedPeerId,
        expectedMessageId: expectedMessageId
      ) {
      case .usefulProviderRich:
        useful += 1
      case .sanitizedProviderRich:
        sanitized += 1
      case .flutterLocal:
        flutterLocal += 1
      case .unknown:
        unknown += 1
      }
      requestHashes.append(sha256(request.identifier))
    }
    return IosDirectNotificationInventory(
      matchingRemoteCount: remote,
      matchingLocalCount: local,
      matchingUsefulProviderCount: useful,
      matchingSanitizedProviderCount: sanitized,
      matchingFlutterLocalCount: flutterLocal,
      matchingUnknownCount: unknown,
      requestIdentifierSha256: requestHashes.sorted()
    )
  }

  private static func sha256(_ value: String) -> String {
    SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
  }
}

struct IosGroupDeliveredNotificationProjection: @unchecked Sendable {
  let requestIdentifier: String
  let triggerOrigin: IosDirectNotificationTriggerOrigin
  let userInfo: [AnyHashable: Any]
  let title: String
  let body: String

  init(
    requestIdentifier: String,
    triggerOrigin: IosDirectNotificationTriggerOrigin,
    userInfo: [AnyHashable: Any],
    title: String,
    body: String
  ) {
    self.requestIdentifier = requestIdentifier
    self.triggerOrigin = triggerOrigin
    self.userInfo = userInfo
    self.title = title
    self.body = body
  }

  init(_ notification: UNNotification) {
    let request = notification.request
    self.init(
      requestIdentifier: request.identifier,
      triggerOrigin: request.trigger is UNPushNotificationTrigger
        ? .remote
        : .local,
      userInfo: request.content.userInfo,
      title: request.content.title,
      body: request.content.body
    )
  }
}

struct IosGroupNotificationDiagnosticRecord: Equatable, Sendable {
  let requestIdentifierSha256: String
  let triggerOrigin: IosDirectNotificationTriggerOrigin
  let sourceClass: IosDirectNotificationSource
  let reason: IosGroupNotificationDiagnosticReason
  let expectedCollapseIdentifierMatch: Bool
  let dispatchClaim: IosGroupNotificationDispatchClaim
  let dispatchCorrelationSha256: String?
  let claimedCollapseIdentifierSha256: String?
  let providerMessageIdSha256: String?

  init(
    requestIdentifierSha256: String,
    triggerOrigin: IosDirectNotificationTriggerOrigin,
    sourceClass: IosDirectNotificationSource,
    reason: IosGroupNotificationDiagnosticReason,
    expectedCollapseIdentifierMatch: Bool,
    dispatchClaim: IosGroupNotificationDispatchClaim,
    dispatchCorrelationSha256: String? = nil,
    claimedCollapseIdentifierSha256: String? = nil,
    providerMessageIdSha256: String? = nil
  ) {
    self.requestIdentifierSha256 = requestIdentifierSha256
    self.triggerOrigin = triggerOrigin
    self.sourceClass = sourceClass
    self.reason = reason
    self.expectedCollapseIdentifierMatch = expectedCollapseIdentifierMatch
    self.dispatchClaim = dispatchClaim
    self.dispatchCorrelationSha256 = dispatchCorrelationSha256
    self.claimedCollapseIdentifierSha256 =
      claimedCollapseIdentifierSha256
    self.providerMessageIdSha256 = providerMessageIdSha256
  }

  var isClosedAndConsistent: Bool {
    guard Self.isSha256(requestIdentifierSha256),
          Self.isOptionalSha256(dispatchCorrelationSha256),
          Self.isOptionalSha256(claimedCollapseIdentifierSha256),
          Self.isOptionalSha256(providerMessageIdSha256) else {
      return false
    }
    switch (triggerOrigin, sourceClass, reason) {
    case (.remote, .usefulProviderRich, .exactUseful),
         (.remote, .sanitizedProviderRich, .exactSanitized),
         (.local, .flutterLocal, .exactFlutterLocal),
         (.remote, .unknown, .missingOrInvalidType),
         (.remote, .unknown, .groupHashMismatch),
         (.remote, .unknown, .partialContent),
         (.remote, .unknown, .unclassifiedRemote),
         (.local, .unknown, .groupHashMismatch),
         (.local, .unknown, .unclassifiedLocal):
      return true
    default:
      return false
    }
  }

  var jsonObject: [String: Any] {
    [
      "requestIdentifierSha256": requestIdentifierSha256,
      "triggerOrigin": triggerOrigin.rawValue,
      "sourceClass": diagnosticSourceClass,
      "reason": reason.rawValue,
      "expectedCollapseIdentifierMatch": expectedCollapseIdentifierMatch,
      "dispatchClaim": dispatchClaim.rawValue,
      "dispatchCorrelationSha256": dispatchCorrelationSha256 ?? NSNull(),
      "claimedCollapseIdentifierSha256":
        claimedCollapseIdentifierSha256 ?? NSNull(),
      "providerMessageIdSha256": providerMessageIdSha256 ?? NSNull(),
    ]
  }

  private var diagnosticSourceClass: String {
    switch sourceClass {
    case .usefulProviderRich: return "usefulProviderRich"
    case .sanitizedProviderRich: return "sanitizedProviderRich"
    case .flutterLocal: return "flutterLocal"
    case .unknown: return "unknown"
    }
  }

  private static func isSha256(_ value: String) -> Bool {
    value.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil
  }

  private static func isOptionalSha256(_ value: String?) -> Bool {
    guard let value else { return true }
    return isSha256(value)
  }
}

struct IosGroupNotificationInventory: Equatable, Sendable {
  static let stableSampleTarget = 3
  static let stableSampleIntervalMilliseconds = 500
  static let observationDeadlineMilliseconds = 8_000

  let matchingRemoteCount: Int
  let matchingLocalCount: Int
  let matchingUsefulProviderCount: Int
  let matchingSanitizedProviderCount: Int
  let matchingFlutterLocalCount: Int
  let matchingUnknownCount: Int
  let requestIdentifierSha256: [String]
  let diagnosticRecords: [IosGroupNotificationDiagnosticRecord]
  let diagnosticOverflow: Bool
  let diagnosticConflict: Bool

  init(
    matchingRemoteCount: Int,
    matchingLocalCount: Int,
    matchingUsefulProviderCount: Int,
    matchingSanitizedProviderCount: Int,
    matchingFlutterLocalCount: Int,
    matchingUnknownCount: Int,
    requestIdentifierSha256: [String],
    diagnosticRecords: [IosGroupNotificationDiagnosticRecord] = [],
    diagnosticOverflow: Bool = false,
    diagnosticConflict: Bool = false
  ) {
    self.matchingRemoteCount = matchingRemoteCount
    self.matchingLocalCount = matchingLocalCount
    self.matchingUsefulProviderCount = matchingUsefulProviderCount
    self.matchingSanitizedProviderCount = matchingSanitizedProviderCount
    self.matchingFlutterLocalCount = matchingFlutterLocalCount
    self.matchingUnknownCount = matchingUnknownCount
    self.requestIdentifierSha256 = requestIdentifierSha256
    self.diagnosticRecords = diagnosticRecords
    self.diagnosticOverflow = diagnosticOverflow
    self.diagnosticConflict = diagnosticConflict
  }

  var matchingTotalCount: Int {
    matchingUsefulProviderCount + matchingSanitizedProviderCount
      + matchingFlutterLocalCount + matchingUnknownCount
  }

  static let empty = IosGroupNotificationInventory(
    matchingRemoteCount: 0,
    matchingLocalCount: 0,
    matchingUsefulProviderCount: 0,
    matchingSanitizedProviderCount: 0,
    matchingFlutterLocalCount: 0,
    matchingUnknownCount: 0,
    requestIdentifierSha256: [],
    diagnosticRecords: [],
    diagnosticOverflow: false,
    diagnosticConflict: false
  )

  static func project(
    _ notifications: [UNNotification],
    expected: IosGroupNotificationExpectedHashes
  ) -> IosGroupNotificationInventory {
    project(notifications.map(IosGroupDeliveredNotificationProjection.init), expected: expected)
  }

  static func project(
    _ notifications: [IosGroupDeliveredNotificationProjection],
    expected: IosGroupNotificationExpectedHashes
  ) -> IosGroupNotificationInventory {
    var recordsByHash: [String: IosGroupNotificationDiagnosticRecord] = [:]
    var overflow = false
    var conflict = false
    for notification in notifications {
      guard let classification = IosGroupNotificationSourceClassifier.diagnose(
        triggerOrigin: notification.triggerOrigin,
        userInfo: notification.userInfo,
        title: notification.title,
        body: notification.body,
        expected: expected
      ) else { continue }
      let requestHash = sha256(notification.requestIdentifier)
      let provenance = IosGroupNotificationSourceClassifier.provenanceHashes(
        userInfo: notification.userInfo
      )
      let record = IosGroupNotificationDiagnosticRecord(
        requestIdentifierSha256: requestHash,
        triggerOrigin: classification.triggerOrigin,
        sourceClass: classification.sourceClass,
        reason: classification.reason,
        expectedCollapseIdentifierMatch:
          requestHash == expected.expectedCollapseIdentifierSha256,
        dispatchClaim: classification.dispatchClaim,
        dispatchCorrelationSha256:
          provenance.dispatchCorrelationSha256,
        claimedCollapseIdentifierSha256:
          provenance.claimedCollapseIdentifierSha256,
        providerMessageIdSha256: provenance.providerMessageIdSha256
      )
      if let existing = recordsByHash[requestHash] {
        if existing != record { conflict = true }
        continue
      }
      guard recordsByHash.count < 8 else {
        overflow = true
        continue
      }
      recordsByHash[requestHash] = record
    }
    let records = recordsByHash.values.sorted {
      $0.requestIdentifierSha256 < $1.requestIdentifierSha256
    }
    let remote = records.filter { $0.triggerOrigin == .remote }.count
    let local = records.filter { $0.triggerOrigin == .local }.count
    let useful = records.filter { $0.sourceClass == .usefulProviderRich }.count
    let sanitized = records.filter {
      $0.sourceClass == .sanitizedProviderRich
    }.count
    let flutterLocal = records.filter { $0.sourceClass == .flutterLocal }.count
    let unknown = records.filter { $0.sourceClass == .unknown }.count
    return IosGroupNotificationInventory(
      matchingRemoteCount: remote,
      matchingLocalCount: local,
      matchingUsefulProviderCount: useful,
      matchingSanitizedProviderCount: sanitized,
      matchingFlutterLocalCount: flutterLocal,
      matchingUnknownCount: unknown,
      requestIdentifierSha256: records.map(\.requestIdentifierSha256),
      diagnosticRecords: records,
      diagnosticOverflow: overflow,
      diagnosticConflict: conflict
    )
  }

  private static func sha256(_ value: String) -> String {
    SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
  }
}

/// Sendable, narrow projection of delivered notification content used only for
/// exact group-invite retirement. Raw `userInfo` never crosses the notification
/// center callback boundary.
struct IosDeliveredNotificationSnapshot: Equatable, Sendable {
  let requestIdentifier: String

  private let hasFlutterLocalNotificationId: Bool
  private let hasValidFlutterLocalNotificationId: Bool
  private let localPayload: String?
  private let providerType: String?
  private let providerGroupId: String?
  private let providerMessageId: String?

  init(requestIdentifier: String, userInfo: [AnyHashable: Any]) {
    self.requestIdentifier = requestIdentifier
    hasFlutterLocalNotificationId = userInfo.keys.contains("NotificationId")
    hasValidFlutterLocalNotificationId = Self.isValidFlutterNotificationId(
      userInfo["NotificationId"]
    )
    localPayload = userInfo["payload"] as? String
    providerType = userInfo["type"] as? String
    providerGroupId = userInfo["groupId"] as? String
    providerMessageId = userInfo["message_id"] as? String
  }

  func matchesGroupInvite(groupId: String, inviteId: String) -> Bool {
    guard !requestIdentifier.isEmpty else { return false }
    if hasFlutterLocalNotificationId {
      return hasValidFlutterLocalNotificationId &&
        localPayload == "group_invite:\(groupId)|message:\(inviteId)"
    }
    return providerType == "group_invite" &&
      providerGroupId == groupId &&
      providerMessageId == inviteId
  }

  private static func isValidFlutterNotificationId(_ value: Any?) -> Bool {
    guard let number = value as? NSNumber,
          CFGetTypeID(number) != CFBooleanGetTypeID(),
          number.doubleValue.isFinite,
          number.doubleValue.rounded() == number.doubleValue,
          number.int64Value >= 0,
          number.int64Value <= Int64(Int32.max) else {
      return false
    }
    return true
  }
}

protocol IosNotificationRecoveryCenter: AnyObject {
  func getDeliveredRequestIdentifiers(
    completionHandler: @escaping @Sendable (Set<String>) -> Void
  )
  func getDeliveredNotificationSnapshots(
    completionHandler:
      @escaping @Sendable ([IosDeliveredNotificationSnapshot]) -> Void
  )
  func removeDeliveredNotifications(withIdentifiers identifiers: [String])
}

extension UNUserNotificationCenter: IosNotificationRecoveryCenter {
  func getDeliveredRequestIdentifiers(
    completionHandler: @escaping @Sendable (Set<String>) -> Void
  ) {
    getDeliveredNotifications { notifications in
      completionHandler(Set(notifications.map(\.request.identifier)))
    }
  }

  func getDeliveredNotificationSnapshots(
    completionHandler:
      @escaping @Sendable ([IosDeliveredNotificationSnapshot]) -> Void
  ) {
    getDeliveredNotifications { notifications in
      completionHandler(notifications.map { notification in
        IosDeliveredNotificationSnapshot(
          requestIdentifier: notification.request.identifier,
          userInfo: notification.request.content.userInfo
        )
      })
    }
  }
}

final class IosNotificationLegacyBadgeWriter: IosNotificationBadgeWriting {
  private let store: IosNotificationRecoveryStore
  private let setter: (Int) -> Void

  init(
    store: IosNotificationRecoveryStore,
    setter: @escaping (Int) -> Void = { count in
      UIApplication.shared.applicationIconBadgeNumber = count
    }
  ) {
    self.store = store
    self.setter = setter
  }

  func requestWrite() {
    guard let snapshot = store.desiredBadgeSnapshot() else { return }
    DispatchQueue.main.async { [setter] in setter(snapshot.count) }
  }
}

final class IosNotificationRecoveryCoordinator {
  struct BeginResponse: Equatable {
    let token: String
    let watermark: UInt64
    let mailboxAlertLease: IosNotificationMailboxAlertLease?
  }

  private struct Session {
    let accountPeerId: String
    let generation: UInt64
    let watermark: UInt64
  }

  private let store: IosNotificationRecoveryStore
  private let center: IosNotificationRecoveryCenter
  private let badgeWriter: IosNotificationBadgeWriting
  private let sessionLock = NSLock()
  private var sessions: [String: Session] = [:]

  convenience init?() {
    guard let store = IosNotificationRecoveryStore() else { return nil }
    let badgeWriter: IosNotificationBadgeWriting
    if #available(iOS 16.0, *) {
      badgeWriter = IosNotificationSerializedBadgeWriter(
        store: store,
        setter: { count, completion in
          UNUserNotificationCenter.current().setBadgeCount(
            count,
            withCompletionHandler: completion
          )
        }
      )
    } else {
      // UIApplication is intentionally Runner-only. The NSE does not attempt
      // the unavailable/deprecated iOS 13-15 badge API.
      badgeWriter = IosNotificationLegacyBadgeWriter(store: store)
    }
    self.init(
      store: store,
      center: UNUserNotificationCenter.current(),
      badgeWriter: badgeWriter
    )
  }

  init(
    store: IosNotificationRecoveryStore,
    center: IosNotificationRecoveryCenter,
    badgeWriter: IosNotificationBadgeWriting
  ) {
    self.store = store
    self.center = center
    self.badgeWriter = badgeWriter
  }

  func beginReconciliation(accountPeerId: String) -> BeginResponse? {
    guard !accountPeerId.isEmpty else { return nil }
    // Keep the store generation advance and the in-memory token replacement in
    // one coordinator critical section. Two concurrent begins can never return
    // an older token after a newer token has already been installed.
    sessionLock.lock()
    defer { sessionLock.unlock() }
    guard let begin = store.beginReconciliation(accountPeerId: accountPeerId)
    else { return nil }
    let token = UUID().uuidString
    // The shared state has one active account and one generation. Every begin
    // supersedes every earlier in-process canonical read, including a read for
    // the prior account.
    sessions.removeAll()
    sessions[token] = Session(
      accountPeerId: accountPeerId,
      generation: begin.generation,
      watermark: begin.watermark
    )
    return BeginResponse(
      token: token,
      watermark: begin.watermark,
      mailboxAlertLease: begin.mailboxAlertLease
    )
  }

  /// Consumes only the lease paired with this still-live reconciliation
  /// session. The session itself remains available for the canonical commit.
  func consumeMailboxAlertLease(
    token: String,
    watermark: UInt64,
    generation: UInt64,
    sequence: UInt64
  ) -> Bool {
    sessionLock.lock()
    defer { sessionLock.unlock() }
    guard let session = sessions[token],
          session.watermark == watermark else {
      return false
    }
    return store.consumeMailboxAlertLease(
      accountPeerId: session.accountPeerId,
      generation: generation,
      sequence: sequence,
      watermark: watermark
    )
  }

  func commitReconciliation(
    token: String,
    watermark: UInt64,
    accountPeerId: String,
    canonicalStateComplete: Bool,
    canonicalBadgeCount: Int,
    identities: [IosNotificationCanonicalIdentity],
    completion: @escaping (Bool) -> Void
  ) {
    if canonicalStateComplete,
       (canonicalBadgeCount != identities.count ||
         Set(identities).count != identities.count) {
      completion(false)
      return
    }
    guard let session = consumeSession(
      token: token,
      watermark: watermark,
      accountPeerId: accountPeerId
    ) else {
      completion(false)
      return
    }
    if !canonicalStateComplete {
      // Dart explicitly closes the two-phase read as incomplete after a failed
      // ingress/drain. Consume the token but preserve every prior baseline,
      // pending event, and custody row for the next complete reconciliation.
      completion(store.validatesReconciliation(
        accountPeerId: accountPeerId,
        generation: session.generation,
        watermark: watermark
      ))
      return
    }
    reconcile(
      watermark: watermark,
      selectRetiredRows: { [store] in
        store.commitCanonicalState(
          accountPeerId: accountPeerId,
          generation: session.generation,
          watermark: watermark,
          canonicalBadgeCount: canonicalBadgeCount,
          identities: identities
        )
      },
      completion: completion
    )
  }

  func retireConversation(
    accountPeerId: String,
    lane: IosNotificationRecoveryLane,
    conversationId: String,
    completion: @escaping (Bool) -> Void
  ) {
    sessionLock.lock()
    guard let watermark = store.retireConversation(
      accountPeerId: accountPeerId,
      lane: lane,
      conversationId: conversationId
    ) else {
      sessionLock.unlock()
      completion(false)
      return
    }
    sessions.removeAll()
    sessionLock.unlock()
    reconcile(watermark: watermark, completion: completion)
  }

  /// Removes only delivered provider/local cards for this exact invite. This
  /// path is independent of the canonical message ledger because group invite
  /// cards are not canonical unread conversation events.
  func retireGroupInvite(
    groupId: String,
    inviteId: String,
    completion: @escaping (Bool) -> Void
  ) {
    guard Self.isStrictRetirementIdentifier(groupId),
          Self.isStrictRetirementIdentifier(inviteId) else {
      completion(false)
      return
    }
    center.getDeliveredNotificationSnapshots { [weak self] delivered in
      guard let self else {
        completion(false)
        return
      }
      let selected = Set(
        delivered.lazy
          .filter {
            $0.matchesGroupInvite(groupId: groupId, inviteId: inviteId)
          }
          .map(\.requestIdentifier)
      ).sorted()
      if !selected.isEmpty {
        self.center.removeDeliveredNotifications(withIdentifiers: selected)
      }
      self.center.getDeliveredNotificationSnapshots { remaining in
        completion(!remaining.contains { snapshot in
          snapshot.matchesGroupInvite(groupId: groupId, inviteId: inviteId)
        })
      }
    }
  }

  func clearAccount(completion: @escaping (Bool) -> Void) {
    sessionLock.lock()
    guard let watermark = store.clearAccount() else {
      sessionLock.unlock()
      completion(false)
      return
    }
    sessions.removeAll()
    sessionLock.unlock()
    reconcile(watermark: watermark, completion: completion)
  }

  func markForegroundSuppressed(requestIdentifier: String) {
    // Serialize the store generation fence with begin/token installation. A
    // begin after this block remains valid; every earlier session is removed.
    sessionLock.lock()
    let didSuppress = store.markForegroundSuppressed(
      requestIdentifier: requestIdentifier
    )
    if didSuppress { sessions.removeAll() }
    sessionLock.unlock()
    guard didSuppress else {
      return
    }
    badgeWriter.requestWrite()
  }

  private func reconcile(
    watermark: UInt64,
    selectRetiredRows: @escaping () -> Bool = { true },
    completion: @escaping (Bool) -> Void
  ) {
    center.getDeliveredRequestIdentifiers { [weak self] beforeIdentifiers in
      guard let self else {
        completion(false)
        return
      }
      _ = self.store.markDelivered(beforeIdentifiers)
      // An already-observed row absent from the initial inventory is a user
      // dismissal. A never-observed prepared row is deliberately retained.
      _ = self.store.pruneObservedAbsent(
        remainingDeliveredIdentifiers: beforeIdentifiers,
        watermark: watermark
      )
      guard selectRetiredRows() else {
        completion(false)
        return
      }
      let candidates = self.store.removalCandidates(watermark: watermark)
      if !candidates.isEmpty {
        self.center.removeDeliveredNotifications(withIdentifiers: candidates)
      }
      self.center.getDeliveredRequestIdentifiers { [weak self] remaining in
        guard let self else {
          completion(false)
          return
        }
        _ = self.store.pruneSelectedObservedAbsent(
          selectedIdentifiers: Set(candidates),
          remainingDeliveredIdentifiers: remaining,
          watermark: watermark
        )
        self.badgeWriter.requestWrite()
        completion(true)
      }
    }
  }

  private func consumeSession(
    token: String,
    watermark: UInt64,
    accountPeerId: String
  ) -> Session? {
    sessionLock.lock()
    defer { sessionLock.unlock() }
    guard let session = sessions[token],
          session.accountPeerId == accountPeerId,
          session.watermark == watermark else {
      return nil
    }
    sessions.removeValue(forKey: token)
    return session
  }

  private static func isStrictRetirementIdentifier(_ value: String) -> Bool {
    guard !value.isEmpty,
          value == value.trimmingCharacters(in: .whitespacesAndNewlines),
          value.lengthOfBytes(using: .utf8) <= 512 else {
      return false
    }
    return !value.unicodeScalars.contains { scalar in
      scalar.value < 0x20 || (scalar.value >= 0x7f && scalar.value <= 0x9f)
    }
  }
}
