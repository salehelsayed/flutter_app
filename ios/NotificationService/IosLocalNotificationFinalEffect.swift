import CoreFoundation
import CryptoKit
import Darwin
import Foundation
import UserNotifications

#if DEBUG && canImport(Runner)
  @testable import Runner
#endif

struct IosLocalNotificationDeliveredInventory: Equatable {
  let querySucceeded: Bool
  let activeNotificationIds: Set<Int>
  let requestIdentifiersByNotificationId: [Int: Set<String>]

  static let unavailable = IosLocalNotificationDeliveredInventory(
    querySucceeded: false,
    activeNotificationIds: [],
    requestIdentifiersByNotificationId: [:]
  )
}

enum IosLocalNotificationFinalEffectDisposition: Equatable {
  /// The adapter invoked Apple's handler. The caller must do nothing else.
  case handled
  /// No native effect boundary was crossed. The caller must hand off the
  /// immutable original generic content through the mailbox-lease owner.
  case genericFallback
}

/// The NSE's deliberately narrow implementation of the Plan-372 v1 wire
/// authority. It neither initializes nor repairs the ledger and can mutate
/// only one exact RELAY_VERIFIED_UNACKED / IOS_NSE record.
final class IosLocalNotificationFinalEffect {
  static let directoryName = "NotificationConversationIds"
  static let ledgerFileName = "local_notification_ledger_v1.json"
  static let lockFileName = ".coordination.lock"
  static let ownerSuffix = ".owner"
  static let contentKindSuffix = ".content-kind"
  static let contentIntentSuffix = ".content-intent"

  private let directory: URL
  private let recoveryStore: IosNotificationRecoveryStore?
  private let currentOpaqueBinding: () -> String?
  private let readProjectionDocument: (String) -> String?
  private let readVisibility: () -> IosAppVisibilitySnapshotEnvelope?
  private let readDeliveredInventory: () -> IosLocalNotificationDeliveredInventory
  private let retireDeliveredRequests: ([String]) -> Void
  private let mutableContentCopy: (UNNotificationContent)
    -> UNMutableNotificationContent?
  private let now: () -> Date
  private let lockTimeoutMs: Int

  convenience init?(
    recoveryStore: IosNotificationRecoveryStore?,
    appGroupIdentifier: String = mknoonSharedAppGroupIdentifier,
    keyReader: PushKeyReading = KeychainPushKeyReader()
  ) {
    guard let root = FileManager.default.containerURL(
      forSecurityApplicationGroupIdentifier: appGroupIdentifier
    ) else {
      return nil
    }
    let visibilityStore = IosAppVisibilitySnapshotStore(directory: root)
    self.init(
      directory: root.appendingPathComponent(Self.directoryName),
      recoveryStore: recoveryStore,
      currentOpaqueBinding: {
        keyReader.readString(key: NseInboxCredential.bindingKey)
      },
      readProjectionDocument: { key in keyReader.readString(key: key) },
      readVisibility: {
        visibilityStore.readSnapshotForNse()
      },
      readDeliveredInventory: Self.productionInventory,
      retireDeliveredRequests: { identifiers in
        guard !identifiers.isEmpty else { return }
        UNUserNotificationCenter.current().removeDeliveredNotifications(
          withIdentifiers: identifiers
        )
      },
      mutableContentCopy: {
        $0.mutableCopy() as? UNMutableNotificationContent
      }
    )
  }

  init(
    directory: URL,
    recoveryStore: IosNotificationRecoveryStore?,
    currentOpaqueBinding: @escaping () -> String?,
    readProjectionDocument: @escaping (String) -> String?,
    readVisibility: @escaping () -> IosAppVisibilitySnapshotEnvelope?,
    readDeliveredInventory: @escaping () -> IosLocalNotificationDeliveredInventory,
    retireDeliveredRequests: @escaping ([String]) -> Void,
    mutableContentCopy: @escaping (UNNotificationContent)
      -> UNMutableNotificationContent? = {
        $0.mutableCopy() as? UNMutableNotificationContent
      },
    now: @escaping () -> Date = Date.init,
    lockTimeoutMs: Int = 150
  ) {
    self.directory = directory
    self.recoveryStore = recoveryStore
    self.currentOpaqueBinding = currentOpaqueBinding
    self.readProjectionDocument = readProjectionDocument
    self.readVisibility = readVisibility
    self.readDeliveredInventory = readDeliveredInventory
    self.retireDeliveredRequests = retireDeliveredRequests
    self.mutableContentCopy = mutableContentCopy
    self.now = now
    self.lockTimeoutMs = min(500, max(1, lockTimeoutMs))
  }

  func complete(
    candidate: NseInboxCandidate,
    lease: IosNotificationMailboxAlertLease,
    originalContent: UNNotificationContent,
    contentHandler: @escaping (UNNotificationContent) -> Void
  ) -> IosLocalNotificationFinalEffectDisposition {
    // Mutable-copy failure must not seed/claim any durable state. The caller
    // still owns the byte-equivalent immutable fallback.
    guard let enriched = mutableContentCopy(originalContent),
          Self.isCanonicalBinding(candidate.currentOpaqueBinding),
          Self.isDigest(candidate.eventCorrelation),
          Self.isDigest(candidate.conversationDigest),
          Self.allowedProducerKinds.contains(candidate.producerKind),
          Self.allowedContentKinds.contains(candidate.contentKind),
          Self.producerMatchesContentKind(candidate.producerKind, candidate.contentKind),
          Self.isDigest(candidate.transportProjectionDigest),
          candidate.conversationKey ==
            candidate.conversationKey.trimmingCharacters(
              in: .whitespacesAndNewlines
            ),
          !candidate.conversationKey.isEmpty,
          candidate.conversationKey.utf8.count <= 4_096,
          currentOpaqueBinding() == candidate.currentOpaqueBinding,
          Self.sha256(readProjectionDocument(
            NseInboxCredential.projectionKey
          ) ?? "") == candidate.transportProjectionDigest,
          authorityDocumentsMatch(candidate),
          recoveryStore?.mailboxAlertLeaseMatches(
            lease,
            accountPeerId: candidate.recoveryIdentity.accountPeerId,
            opaqueBinding: candidate.currentOpaqueBinding
          ) == true,
          Self.visibilityEvaluation(
            readVisibility(),
            conversationDigest: candidate.conversationDigest
          ) != nil else {
      return .genericFallback
    }

    // Inventory is an awaited OS fact and therefore must be collected before
    // the shared ledger flock. A failed query may reuse an exact existing owner
    // but can never allocate a new numeric id or prove publishing recovery.
    let inventory = readDeliveredInventory()
    let lockURL = directory.appendingPathComponent(Self.lockFileName)
    guard Self.isExistingDirectory(directory),
          Self.isRegularFile(lockURL) else {
      return .genericFallback
    }
    let descriptor = open(lockURL.path, O_RDWR | O_CLOEXEC)
    guard descriptor >= 0 else { return .genericFallback }
    defer {
      _ = flock(descriptor, LOCK_UN)
      close(descriptor)
    }
    guard Self.takeBoundedExclusiveLock(
      descriptor,
      timeoutMs: lockTimeoutMs
    ) else {
      return .genericFallback
    }

    return runLockHeld(
      candidate: candidate,
      lease: lease,
      content: enriched,
      inventory: inventory,
      contentHandler: contentHandler
    )
  }

  private func runLockHeld(
    candidate: NseInboxCandidate,
    lease: IosNotificationMailboxAlertLease,
    content: UNMutableNotificationContent,
    inventory: IosLocalNotificationDeliveredInventory,
    contentHandler: (UNNotificationContent) -> Void
  ) -> IosLocalNotificationFinalEffectDisposition {
    guard currentOpaqueBinding() == candidate.currentOpaqueBinding,
          recoveryStore?.mailboxAlertLeaseMatches(
            lease,
            accountPeerId: candidate.recoveryIdentity.accountPeerId,
            opaqueBinding: candidate.currentOpaqueBinding
          ) == true,
          var ledger = loadLedger(),
          ledger.opaqueBinding == candidate.currentOpaqueBinding,
          !ledger.claimsSuspended else {
      return .genericFallback
    }

    let owner = Self.sha256(candidate.conversationKey)
    var record = ledger.records[candidate.eventCorrelation]
    let notificationId: Int
    if let incumbent = record {
      guard let incumbentId = incumbent.notificationId,
            hasExactOwnerLockHeld(
              notificationId: incumbentId,
              owner: owner
            ) else {
        return .genericFallback
      }
      notificationId = incumbentId
    } else {
      guard let allocated = resolveNotificationIdLockHeld(
        normalizedConversationKey: candidate.conversationKey,
        owner: owner,
        inventory: inventory
      ) else {
        return .genericFallback
      }
      notificationId = allocated
    }
    let generation = "ledger:\(candidate.eventCorrelation)"
    let metadata = ContentMetadata(
      kind: candidate.contentKind,
      event: candidate.eventCorrelation,
      generation: generation
    )

    var recoveredPriorClaim = false
    if record == nil {
      guard ledger.records.count < 512,
            !ledger.records.values.contains(where: { other in
              other.conversationDigest == candidate.conversationDigest &&
                other.notificationId == notificationId &&
                (other.effectPhase == "CLAIMED" ||
                  other.effectPhase == "PUBLISHING")
            }),
            ledger.storeRevision < Int64.max else {
        return .genericFallback
      }
      let instant = canonicalNow(after: nil)
      let seeded = LedgerRecord(
        eventCorrelation: candidate.eventCorrelation,
        conversationDigest: candidate.conversationDigest,
        producerKind: candidate.producerKind,
        sourceCustody: "RELAY_VERIFIED_UNACKED",
        readState: "UNREAD",
        presentationState: "NOT_EVALUATED",
        presentationOwner: "IOS_NSE",
        notificationId: notificationId,
        contentGeneration: generation,
        lastEvaluatedLifecycle: "UNKNOWN",
        visibilityRevision: nil,
        lifecycleGeneration: nil,
        effectPhase: "READY",
        attemptKind: nil,
        effectToken: nil,
        revision: 1,
        createdAtUtc: instant,
        updatedAtUtc: instant,
        terminalAtUtc: nil,
        settledAtUtc: nil
      )
      guard seeded.isValid else { return .genericFallback }
      ledger.records[candidate.eventCorrelation] = seeded
      ledger.storeRevision += 1
      guard commitLedger(ledger),
            let reloaded = loadLedger(),
            reloaded.storeRevision == ledger.storeRevision,
            reloaded.records[candidate.eventCorrelation] == seeded else {
        return .genericFallback
      }
      ledger = reloaded
      record = seeded
    }

    guard var current = record,
          current.matches(
            candidate: candidate,
            notificationId: notificationId,
            contentGeneration: generation
          ) else {
      return .genericFallback
    }

    if (current.effectPhase == "CLAIMED" ||
        current.effectPhase == "PUBLISHING"),
       let attemptKind = current.attemptKind,
       Self.dartOwnedRemoteAdoptionAttemptKinds.contains(attemptKind) {
      return finishAmbiguousPublishing(
        candidate: candidate,
        lease: lease,
        content: content,
        contentHandler: contentHandler
      )
    }

    switch current.effectPhase {
    case "EFFECT_TERMINAL":
      let passive = trustedPassiveContent(
        candidate: candidate,
        from: content,
        targetNotificationId: notificationId
      )
      contentHandler(passive)
      _ = recoveryStore?.retireMailboxAlertLease(
        token: lease.token,
        generation: lease.generation,
        sequence: lease.sequence
      )
      return .handled
    case "SETTLED":
      return .genericFallback
    case "PUBLISHING":
      return recoverPublishingLockHeld(
        candidate: candidate,
        lease: lease,
        content: content,
        ledger: &ledger,
        record: &current,
        metadata: metadata,
        inventory: inventory,
        contentHandler: contentHandler
      )
    case "CLAIMED":
      guard Self.recoveryHorizonReached(
        current.updatedAtUtc,
        now: now(),
        seconds: 60
      ) else {
        return finishAmbiguousPublishing(
          candidate: candidate,
          lease: lease,
          content: content,
          contentHandler: contentHandler
        )
      }
      recoveredPriorClaim = true
    case "READY":
      guard !ledger.records.values.contains(where: { other in
        other.eventCorrelation != current.eventCorrelation &&
          other.conversationDigest == current.conversationDigest &&
          other.notificationId == current.notificationId &&
          (other.effectPhase == "CLAIMED" || other.effectPhase == "PUBLISHING")
      }) else {
        return .genericFallback
      }
      let token = Self.randomDigest()
      guard transition(
        ledger: &ledger,
        record: &current,
        mutate: { next in
          next.effectPhase = "CLAIMED"
          next.attemptKind = "POST_OR_UPDATE"
          next.effectToken = token
        }
      ) else {
        return .genericFallback
      }
    default:
      return .genericFallback
    }

    var preparedURL: URL?
    defer {
      if let preparedURL { try? FileManager.default.removeItem(at: preparedURL) }
    }
    guard ensureContentIntent(
            notificationId: notificationId,
            binding: candidate.currentOpaqueBinding,
            metadata: metadata
          ),
          let prepared = prepareContentMetadata(
            notificationId: notificationId,
            metadata: metadata
          ) else {
      return .genericFallback
    }
    preparedURL = prepared
    guard transition(
      ledger: &ledger,
      record: &current,
      mutate: { next in next.effectPhase = "PUBLISHING" }
    ) else {
      return .genericFallback
    }

    guard armAttempt(
            "CANCEL",
            ledger: &ledger,
            record: &current
          ) else {
      return finishAmbiguousPublishing(
        candidate: candidate,
        lease: lease,
        content: content,
        targetNotificationId: notificationId,
        contentHandler: contentHandler
      )
    }
    guard activateContent(
      notificationId: notificationId,
      binding: candidate.currentOpaqueBinding,
      metadata: metadata,
      prepared: prepared,
      inventory: inventory,
      authorizeCancellation: { intent, previous, identifiers in
        self.authorizeCancellationLockHeld(
          candidate: candidate,
          lease: lease,
          ledger: &ledger,
          record: &current,
          expectedIntent: intent,
          expectedMetadata: previous,
          identifiers: identifiers
        )
      }
    ) else {
      return finishAmbiguousPublishing(
        candidate: candidate,
        lease: lease,
        content: content,
        targetNotificationId: notificationId,
        contentHandler: contentHandler
      )
    }
    preparedURL = nil
    guard armAttempt(
            "POST_OR_UPDATE",
            ledger: &ledger,
            record: &current
          ),
          deleteContentIntent(notificationId: notificationId) else {
      return finishAmbiguousPublishing(
        candidate: candidate,
        lease: lease,
        content: content,
        targetNotificationId: notificationId,
        contentHandler: contentHandler
      )
    }

    return finishPublishingLockHeld(
      candidate: candidate,
      lease: lease,
      content: content,
      ledger: &ledger,
      record: &current,
      metadata: metadata,
      forceSilent: recoveredPriorClaim,
      forcedPresentation: nil,
      setPassiveTarget: true,
      contentHandler: contentHandler
    )
  }

  private func recoverPublishingLockHeld(
    candidate: NseInboxCandidate,
    lease: IosNotificationMailboxAlertLease,
    content: UNMutableNotificationContent,
    ledger: inout LedgerEnvelope,
    record: inout LedgerRecord,
    metadata: ContentMetadata,
    inventory: IosLocalNotificationDeliveredInventory,
    contentHandler: (UNNotificationContent) -> Void
  ) -> IosLocalNotificationFinalEffectDisposition {
    let notificationId = record.notificationId!
    if let intent = readContentIntent(notificationId: notificationId) {
      guard intent.binding == candidate.currentOpaqueBinding,
            intent.nextDigest == metadata.digest,
            record.attemptKind == "POST_OR_UPDATE" ||
              record.attemptKind == "CANCEL" else {
        return finishAmbiguousPublishing(
          candidate: candidate,
          lease: lease,
          content: content,
          targetNotificationId: notificationId,
          contentHandler: contentHandler
        )
      }
      if record.attemptKind == "POST_OR_UPDATE" {
        guard armAttempt("CANCEL", ledger: &ledger, record: &record) else {
          return finishAmbiguousPublishing(
            candidate: candidate,
            lease: lease,
            content: content,
            targetNotificationId: notificationId,
            contentHandler: contentHandler
          )
        }
      }
      guard activateContent(
        notificationId: notificationId,
        binding: candidate.currentOpaqueBinding,
        metadata: metadata,
        prepared: nil,
        inventory: inventory,
        authorizeCancellation: { intent, previous, identifiers in
          self.authorizeCancellationLockHeld(
            candidate: candidate,
            lease: lease,
            ledger: &ledger,
            record: &record,
            expectedIntent: intent,
            expectedMetadata: previous,
            identifiers: identifiers
          )
        }
      ),
      armAttempt("POST_OR_UPDATE", ledger: &ledger, record: &record),
      deleteContentIntent(notificationId: notificationId) else {
        return finishAmbiguousPublishing(
          candidate: candidate,
          lease: lease,
          content: content,
          targetNotificationId: notificationId,
          contentHandler: contentHandler
        )
      }
    } else if readContentMetadata(notificationId: notificationId) != metadata {
      return finishAmbiguousPublishing(
        candidate: candidate,
        lease: lease,
        content: content,
        targetNotificationId: notificationId,
        contentHandler: contentHandler
      )
    }

    let horizonReached = Self.recoveryHorizonReached(
      record.updatedAtUtc,
      now: now(),
      seconds: 65
    )
    if !inventory.querySucceeded && !horizonReached {
      return finishAmbiguousPublishing(
        candidate: candidate,
        lease: lease,
        content: content,
        targetNotificationId: notificationId,
        contentHandler: contentHandler
      )
    }

    let exactActive = inventory.querySucceeded &&
      inventory.activeNotificationIds.contains(notificationId)
    if candidate.policy == .suppressedPolicy && exactActive {
      guard let identifiers =
              inventory.requestIdentifiersByNotificationId[notificationId],
            !identifiers.isEmpty,
            authorizeCancellationLockHeld(
              candidate: candidate,
              lease: lease,
              ledger: &ledger,
              record: &record,
              expectedIntent: nil,
              expectedMetadata: metadata,
              identifiers: Array(identifiers)
            ) else {
        return finishAmbiguousPublishing(
          candidate: candidate,
          lease: lease,
          content: content,
          targetNotificationId: notificationId,
          contentHandler: contentHandler
        )
      }
    }

    // An exact active id proves the prior post and terminals without another
    // enriched/audible effect. A proven absent id (or an aged unknown) permits
    // only a same-id passive repair. Apple still receives one passive
    // completion because this extension has no filtering entitlement.
    return finishPublishingLockHeld(
      candidate: candidate,
      lease: lease,
      content: content,
      ledger: &ledger,
      record: &record,
      metadata: metadata,
      forceSilent: true,
      forcedPresentation:
        exactActive && candidate.policy == .eligible ? "OS_POSTED" : nil,
      setPassiveTarget: true,
      contentHandler: contentHandler
    )
  }

  private func finishPublishingLockHeld(
    candidate: NseInboxCandidate,
    lease: IosNotificationMailboxAlertLease,
    content: UNMutableNotificationContent,
    ledger: inout LedgerEnvelope,
    record: inout LedgerRecord,
    metadata: ContentMetadata,
    forceSilent: Bool,
    forcedPresentation: String?,
    setPassiveTarget: Bool = false,
    contentHandler: (UNNotificationContent) -> Void
  ) -> IosLocalNotificationFinalEffectDisposition {
    // Persist the compatibility lease before the final authority barrier.
    // Once the following binding/visibility/ledger/metadata reads finish,
    // there is no intervening lock or I/O before Apple's handler.
    guard recoveryStore?.markMailboxAlertLeasePublishing(
      token: lease.token,
      generation: lease.generation,
      sequence: lease.sequence
    ) == true else {
      contentHandler(trustedPassiveContent(
        candidate: candidate,
        from: content,
        targetNotificationId: record.notificationId
      ))
      return .handled
    }
    guard currentOpaqueBinding() == candidate.currentOpaqueBinding,
          Self.sha256(readProjectionDocument(
            NseInboxCredential.projectionKey
          ) ?? "") == candidate.transportProjectionDigest,
          authorityDocumentsMatch(candidate),
          let visibility = Self.visibilityEvaluation(
            readVisibility(),
            conversationDigest: candidate.conversationDigest
          ),
          let reloaded = loadLedger(),
          reloaded.storeRevision == ledger.storeRevision,
          reloaded.records[candidate.eventCorrelation] == record,
          readContentMetadata(notificationId: record.notificationId!) == metadata
    else {
      contentHandler(trustedPassiveContent(
        candidate: candidate,
        from: content,
        targetNotificationId: record.notificationId
      ))
      return .handled
    }
    ledger = reloaded

    let presentation: String
    if let forcedPresentation {
      presentation = forcedPresentation
    } else if candidate.policy == .suppressedPolicy {
      presentation = "SUPPRESSED_POLICY"
    } else if visibility.sameVisibleConversation {
      presentation = "IN_CHAT"
    } else {
      presentation = "OS_POSTED"
    }
    let audible = presentation == "OS_POSTED" && !forceSilent
    let outbound: UNMutableNotificationContent
    if audible {
      applyNotificationPreviewResult(candidate.preview, to: content)
      content.badge = nil
      if #available(iOS 15.0, *) {
        content.targetContentIdentifier = String(record.notificationId!)
      }
      outbound = content
    } else {
      outbound = trustedPassiveContent(
        candidate: candidate,
        from: content,
        targetNotificationId: setPassiveTarget ? record.notificationId : nil
      )
    }

    // Apple's irreversible handoff and its terminal CAS intentionally remain
    // inside the shared flock. A crash between them leaves PUBLISHING, whose
    // only repair path above is silent.
    contentHandler(outbound)
    let terminalAt = canonicalNow(after: record.updatedAtUtc)
    let terminalized = transition(
      ledger: &ledger,
      record: &record,
      mutate: { next in
        next.presentationState = presentation
        next.lastEvaluatedLifecycle = visibility.lifecycle
        next.visibilityRevision = visibility.revision
        next.lifecycleGeneration = visibility.lifecycleGeneration
        next.effectPhase = "EFFECT_TERMINAL"
        next.attemptKind = nil
        next.effectToken = nil
        next.updatedAtUtc = terminalAt
        next.terminalAtUtc = terminalAt
      },
      setTimestamp: false
    )
    if terminalized {
      if presentation != "OS_POSTED" {
        _ = deleteContentMetadata(notificationId: record.notificationId!)
      }
      _ = recoveryStore?.retireMailboxAlertLease(
        token: lease.token,
        generation: lease.generation,
        sequence: lease.sequence
      )
    }
    return .handled
  }

  private func finishAmbiguousPublishing(
    candidate: NseInboxCandidate,
    lease: IosNotificationMailboxAlertLease,
    content: UNMutableNotificationContent,
    targetNotificationId: Int? = nil,
    contentHandler: (UNNotificationContent) -> Void
  ) -> IosLocalNotificationFinalEffectDisposition {
    _ = recoveryStore?.markMailboxAlertLeasePublishing(
      token: lease.token,
      generation: lease.generation,
      sequence: lease.sequence
    )
    contentHandler(trustedPassiveContent(
      candidate: candidate,
      from: content,
      targetNotificationId: targetNotificationId
    ))
    return .handled
  }

  private func trustedPassiveContent(
    candidate _: NseInboxCandidate,
    from content: UNMutableNotificationContent,
    targetNotificationId: Int? = nil
  ) -> UNMutableNotificationContent {
    // This is an authenticated no-effect completion, not a second preview.
    // Reuse the incumbent terminal sanitizer so stale/ambiguous authority can
    // never disclose candidate text. The stable id is restored only after the
    // sanitizer because it intentionally clears targetContentIdentifier.
    sanitizeNotificationContentForUnresolvedExpiry(content)
    if #available(iOS 15.0, *) {
      content.interruptionLevel = .passive
      content.targetContentIdentifier = targetNotificationId.map(String.init)
    }
    return content
  }

  private func authorityDocumentsMatch(_ candidate: NseInboxCandidate) -> Bool {
    let required: Set<String>
    switch candidate.producerKind {
    case "direct_message":
      required = [PushSharedKeyNames.directReactionContacts]
    case "direct_reaction":
      required = [
        PushSharedKeyNames.directReactionContacts,
        PushSharedKeyNames.directReactionAuthoredTargets,
      ]
    case "group_message":
      required = [PushSharedKeyNames.groupReactionContexts]
    case "group_reaction":
      required = [
        PushSharedKeyNames.groupReactionContexts,
        PushSharedKeyNames.groupReactionAuthoredTargets,
        PushSharedKeyNames.groupReactionLatestStates,
      ]
    default:
      return false
    }
    guard Set(candidate.authorityProjectionDigests.keys) == required,
          required.isSubset(of: Self.allowedAuthorityProjectionKeys) else {
      return false
    }
    for key in required {
      guard let expected = candidate.authorityProjectionDigests[key],
            Self.isDigest(expected),
            Self.sha256(readProjectionDocument(key) ?? "") == expected else {
        return false
      }
    }
    return true
  }

  private func transition(
    ledger: inout LedgerEnvelope,
    record: inout LedgerRecord,
    mutate: (inout LedgerRecord) -> Void,
    setTimestamp: Bool = true
  ) -> Bool {
    guard ledger.storeRevision < Int64.max,
          record.revision < Int64.max,
          ledger.records[record.eventCorrelation] == record else {
      return false
    }
    let previous = record
    var next = record
    mutate(&next)
    next.revision += 1
    if setTimestamp {
      next.updatedAtUtc = canonicalNow(after: previous.updatedAtUtc)
    }
    guard next.isValid,
          Self.isAuthorizedTransition(from: previous, to: next) else {
      return false
    }
    ledger.storeRevision += 1
    ledger.records[next.eventCorrelation] = next
    guard commitLedger(ledger),
          let reloaded = loadLedger(),
          reloaded.storeRevision == ledger.storeRevision,
          reloaded.records[next.eventCorrelation] == next else {
      return false
    }
    ledger = reloaded
    record = next
    return true
  }

  private func armAttempt(
    _ attempt: String,
    ledger: inout LedgerEnvelope,
    record: inout LedgerRecord
  ) -> Bool {
    guard record.effectPhase == "PUBLISHING",
          (attempt == "CANCEL" || attempt == "POST_OR_UPDATE") else {
      return false
    }
    if record.attemptKind == attempt { return true }
    return transition(ledger: &ledger, record: &record) { next in
      next.attemptKind = attempt
    }
  }

  private func hasExactOwnerLockHeld(
    notificationId: Int,
    owner: String
  ) -> Bool {
    guard let names = try? FileManager.default.contentsOfDirectory(
      atPath: directory.path
    ) else {
      return false
    }
    return names.contains { name in
      guard Self.ownerFileNotificationId(name) == notificationId else {
        return false
      }
      let url = directory.appendingPathComponent(name)
      guard Self.isRegularFile(url),
            let data = try? Data(contentsOf: url),
            data.count <= 512,
            let value = String(data: data, encoding: .utf8) else {
        return false
      }
      return value.trimmingCharacters(in: .whitespacesAndNewlines) == owner
    }
  }

  private func resolveNotificationIdLockHeld(
    normalizedConversationKey: String,
    owner: String,
    inventory: IosLocalNotificationDeliveredInventory
  ) -> Int? {
    guard let names = try? FileManager.default.contentsOfDirectory(
      atPath: directory.path
    ) else {
      return nil
    }
    var occupied = Set<Int>()
    var exactOwners: [Int] = []
    for name in names {
      guard let id = Self.ownerFileNotificationId(name) else { continue }
      occupied.insert(id)
      let url = directory.appendingPathComponent(name)
      if Self.isRegularFile(url),
         let data = try? Data(contentsOf: url),
         data.count <= 512,
         let value = String(data: data, encoding: .utf8),
         value.trimmingCharacters(in: .whitespacesAndNewlines) == owner {
        exactOwners.append(id)
      }
    }
    let primary = Self.notificationId(
      digest: SHA256.hash(data: Data(normalizedConversationKey.utf8))
    )
    if exactOwners.contains(primary) { return primary }
    if let existing = exactOwners.min() { return existing }
    guard inventory.querySucceeded else { return nil }

    for active in inventory.activeNotificationIds.sorted()
    where !occupied.contains(active) {
      guard publishSidecar(
        Data("opaque-active".utf8),
        to: directory.appendingPathComponent("\(active)\(Self.ownerSuffix)"),
        replacing: false
      ) else {
        return nil
      }
      occupied.insert(active)
    }
    for probe in 0..<128 {
      let candidate: Int
      if probe == 0 {
        candidate = primary
      } else {
        candidate = Self.notificationId(
          digest: SHA256.hash(
            data: Data(
              "mknoon-notification-id-v1:\(owner):\(probe)".utf8
            )
          )
        )
      }
      if occupied.contains(candidate) { continue }
      guard publishSidecar(
        Data(owner.utf8),
        to: directory.appendingPathComponent("\(candidate)\(Self.ownerSuffix)"),
        replacing: false
      ) else {
        return nil
      }
      return candidate
    }
    return nil
  }

  private func ensureContentIntent(
    notificationId: Int,
    binding: String,
    metadata: ContentMetadata
  ) -> Bool {
    let url = contentIntentURL(notificationId)
    if let current = readContentIntent(notificationId: notificationId),
       current.binding == binding,
       current.nextDigest == metadata.digest {
      return true
    }
    if !Self.isAbsentOrRegularFile(url) {
      return false
    }
    let previous = readContentMetadata(notificationId: notificationId)?.digest
    let intent = ContentIntent(
      binding: binding,
      previousDigest: previous,
      nextDigest: metadata.digest
    )
    return publishSidecar(intent.data, to: url, replacing: true)
  }

  private func prepareContentMetadata(
    notificationId: Int,
    metadata: ContentMetadata
  ) -> URL? {
    let target = contentMetadataURL(notificationId)
    guard Self.isAbsentOrRegularFile(target) else {
      return nil
    }
    return writeTemporary(
      metadata.data,
      prefix: ".\(notificationId)-content"
    )
  }

  private func activateContent(
    notificationId: Int,
    binding: String,
    metadata: ContentMetadata,
    prepared: URL?,
    inventory: IosLocalNotificationDeliveredInventory,
    authorizeCancellation: (
      ContentIntent,
      ContentMetadata?,
      [String]
    ) -> Bool
  ) -> Bool {
    let currentMetadata = readContentMetadata(notificationId: notificationId)
    if currentMetadata == metadata {
      return true
    }
    // Replacing an incumbent marker is inseparable from proving/cancelling
    // delivered cards for the same stable id. Unknown inventory cannot grant
    // that mutation authority.
    guard inventory.querySucceeded else { return false }
    guard let intent = readContentIntent(notificationId: notificationId),
          intent.binding == binding,
          intent.nextDigest == metadata.digest,
          intent.previousDigest ==
            currentMetadata?.digest else {
      return false
    }
    let exactPrepared = prepared ?? prepareContentMetadata(
      notificationId: notificationId,
      metadata: metadata
    )
    guard let exactPrepared else { return false }
    let ownsPrepared = prepared == nil
    defer {
      if ownsPrepared { try? FileManager.default.removeItem(at: exactPrepared) }
    }
    let identifiers = inventory.requestIdentifiersByNotificationId[
      notificationId
    ].map(Array.init) ?? []
    guard !inventory.activeNotificationIds.contains(notificationId) ||
      !identifiers.isEmpty else {
      return false
    }
    // Cancellation is an OS effect, so the caller must cross the same current
    // authority/revision boundary used for publication before it can run.
    // The marker is activated only after that effect; a crash at either edge
    // leaves the intent durable and recovery repeats only exact-id work.
    guard authorizeCancellation(intent, currentMetadata, identifiers) else {
      return false
    }
    let target = contentMetadataURL(notificationId)
    guard rename(exactPrepared.path, target.path) == 0,
          Self.syncDirectory(directory),
          readContentMetadata(notificationId: notificationId) == metadata else {
      return false
    }
    return true
  }

  private func authorizeCancellationLockHeld(
    candidate: NseInboxCandidate,
    lease: IosNotificationMailboxAlertLease,
    ledger: inout LedgerEnvelope,
    record: inout LedgerRecord,
    expectedIntent: ContentIntent?,
    expectedMetadata: ContentMetadata?,
    identifiers: [String]
  ) -> Bool {
    guard recoveryStore?.markMailboxAlertLeasePublishing(
      token: lease.token,
      generation: lease.generation,
      sequence: lease.sequence
    ) == true,
    currentOpaqueBinding() == candidate.currentOpaqueBinding,
    Self.sha256(readProjectionDocument(
      NseInboxCredential.projectionKey
    ) ?? "") == candidate.transportProjectionDigest,
    authorityDocumentsMatch(candidate),
    let reloaded = loadLedger(),
    reloaded.storeRevision == ledger.storeRevision,
    reloaded.records[candidate.eventCorrelation] == record,
    readContentIntent(notificationId: record.notificationId!) ==
      expectedIntent,
    readContentMetadata(notificationId: record.notificationId!) ==
      expectedMetadata else {
      return false
    }
    ledger = reloaded
    let exactIdentifiers = Array(Set(identifiers)).sorted()
    if !exactIdentifiers.isEmpty {
      retireDeliveredRequests(exactIdentifiers)
    }
    return true
  }

  private func readContentMetadata(notificationId: Int) -> ContentMetadata? {
    let url = contentMetadataURL(notificationId)
    guard Self.isRegularFile(url),
          let data = try? Data(contentsOf: url),
          data.count <= 2_048 else {
      return nil
    }
    return ContentMetadata.decode(data)
  }

  private func readContentIntent(notificationId: Int) -> ContentIntent? {
    let url = contentIntentURL(notificationId)
    guard Self.isRegularFile(url),
          let data = try? Data(contentsOf: url),
          data.count <= 2_048 else {
      return nil
    }
    return ContentIntent.decode(data)
  }

  private func deleteContentIntent(notificationId: Int) -> Bool {
    let url = contentIntentURL(notificationId)
    guard Self.isAbsentOrRegularFile(url) else {
      return false
    }
    if Self.pathExists(url), unlink(url.path) != 0 {
      return false
    }
    return Self.syncDirectory(directory)
  }

  private func deleteContentMetadata(notificationId: Int) -> Bool {
    let url = contentMetadataURL(notificationId)
    guard Self.isAbsentOrRegularFile(url) else {
      return false
    }
    if Self.pathExists(url), unlink(url.path) != 0 {
      return false
    }
    return Self.syncDirectory(directory)
  }

  private func contentMetadataURL(_ id: Int) -> URL {
    directory.appendingPathComponent("\(id)\(Self.contentKindSuffix)")
  }

  private func contentIntentURL(_ id: Int) -> URL {
    directory.appendingPathComponent("\(id)\(Self.contentIntentSuffix)")
  }

  private func loadLedger() -> LedgerEnvelope? {
    let url = directory.appendingPathComponent(Self.ledgerFileName)
    guard Self.isRegularFile(url),
          let attributes = try? FileManager.default.attributesOfItem(
            atPath: url.path
          ),
          let size = attributes[.size] as? NSNumber,
          size.intValue <= 4 * 1_024 * 1_024,
          let data = try? Data(contentsOf: url) else {
      return nil
    }
    return LedgerEnvelope.decode(data)
  }

  private func commitLedger(_ ledger: LedgerEnvelope) -> Bool {
    guard ledger.isValid,
          let data = ledger.data,
          let temporary = writeTemporary(data, prefix: ".ledger") else {
      return false
    }
    defer { try? FileManager.default.removeItem(at: temporary) }
    let target = directory.appendingPathComponent(Self.ledgerFileName)
    guard Self.isRegularFile(target),
          rename(temporary.path, target.path) == 0,
          Self.syncDirectory(directory) else {
      return false
    }
    return true
  }

  private func writeTemporary(_ data: Data, prefix: String) -> URL? {
    guard data.count <= 4 * 1_024 * 1_024 else { return nil }
    let url = directory.appendingPathComponent(
      "\(prefix)-\(UUID().uuidString).tmp"
    )
    let descriptor = open(
      url.path,
      O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC,
      S_IRUSR | S_IWUSR
    )
    guard descriptor >= 0 else { return nil }
    var success = false
    defer {
      close(descriptor)
      if !success { _ = unlink(url.path) }
    }
    let wrote = data.withUnsafeBytes { raw -> Bool in
      guard let base = raw.baseAddress else { return data.isEmpty }
      var offset = 0
      while offset < data.count {
        let count = Darwin.write(
          descriptor,
          base.advanced(by: offset),
          data.count - offset
        )
        if count <= 0 { return false }
        offset += count
      }
      return true
    }
    guard wrote, fsync(descriptor) == 0 else { return nil }
    success = true
    return url
  }

  private func publishSidecar(
    _ data: Data,
    to target: URL,
    replacing: Bool
  ) -> Bool {
    if Self.pathExists(target) {
      guard replacing, Self.isRegularFile(target) else { return false }
    } else if !Self.isAbsentOrRegularFile(target) {
      return false
    }
    guard let temporary = writeTemporary(
      data,
      prefix: ".\(target.lastPathComponent)"
    ) else {
      return false
    }
    defer { try? FileManager.default.removeItem(at: temporary) }
    if !replacing && Self.pathExists(target) {
      return false
    }
    guard rename(temporary.path, target.path) == 0,
          Self.syncDirectory(directory) else {
      return false
    }
    return true
  }

  private func canonicalNow(after previous: String?) -> String {
    var value = Self.canonicalTimestamp(now())
    if let previous,
       let previousDate = Self.canonicalDate(previous),
       let valueDate = Self.canonicalDate(value),
       valueDate < previousDate {
      value = previous
    }
    return value
  }

  private static func productionInventory()
    -> IosLocalNotificationDeliveredInventory {
    let semaphore = DispatchSemaphore(value: 0)
    let lock = NSLock()
    var result = IosLocalNotificationDeliveredInventory.unavailable
    UNUserNotificationCenter.current().getDeliveredNotifications { values in
      var ids = Set<Int>()
      var requests: [Int: Set<String>] = [:]
      if values.count <= 4_096 {
        for value in values {
          var resolved: Int?
          if #available(iOS 15.0, *),
             let target = value.request.content.targetContentIdentifier {
            resolved = exactNotificationId(
              target
            )
          }
          if resolved == nil {
            resolved = exactNotificationId(value.request.identifier)
          }
          guard let id = resolved else { continue }
          ids.insert(id)
          let identifier = value.request.identifier
          if identifier.utf8.count <= 512,
             !identifier.isEmpty,
             identifier == identifier.trimmingCharacters(
               in: .whitespacesAndNewlines
             ) {
            requests[id, default: []].insert(identifier)
          }
        }
        lock.lock()
        result = IosLocalNotificationDeliveredInventory(
          querySucceeded: true,
          activeNotificationIds: ids,
          requestIdentifiersByNotificationId: requests
        )
        lock.unlock()
      }
      semaphore.signal()
    }
    guard semaphore.wait(timeout: .now() + .milliseconds(150)) == .success
    else {
      return .unavailable
    }
    lock.lock()
    defer { lock.unlock() }
    return result
  }

  private static func exactNotificationId(_ raw: String) -> Int? {
    guard !raw.isEmpty,
          raw.utf8.allSatisfy({ (48...57).contains($0) }),
          let value = Int(raw),
          (0...0x7fffffff).contains(value),
          String(value) == raw else {
      return nil
    }
    return value
  }

  private static func visibilityEvaluation(
    _ envelope: IosAppVisibilitySnapshotEnvelope?,
    conversationDigest: String
  ) -> VisibilityEvaluation? {
    guard let envelope,
          envelope.snapshot.isStructurallyValid,
          envelope.snapshot.bootSession == envelope.context.currentBootSession,
          envelope.context.currentMonotonicMs >=
            envelope.snapshot.updatedMonotonicMs,
          envelope.context.currentMonotonicMs -
            envelope.snapshot.updatedMonotonicMs <
              IosAppVisibilitySnapshotV1.freshnessLimitMs else {
      return nil
    }
    return VisibilityEvaluation(
      sameVisibleConversation:
        envelope.snapshot.lifecycle == .foregroundActive &&
          envelope.snapshot.visibleConversationDigest == conversationDigest,
      lifecycle: envelope.snapshot.lifecycle.rawValue,
      revision: envelope.snapshot.revision,
      lifecycleGeneration: envelope.snapshot.lifecycleGeneration
    )
  }

  private static func isAuthorizedTransition(
    from: LedgerRecord,
    to: LedgerRecord
  ) -> Bool {
    guard from.sameImmutableIdentity(as: to),
          to.revision == from.revision + 1,
          let fromUpdated = canonicalDate(from.updatedAtUtc),
          let toUpdated = canonicalDate(to.updatedAtUtc),
          toUpdated >= fromUpdated,
          from.sourceCustody == to.sourceCustody,
          from.presentationState == to.presentationState ||
            (from.effectPhase == "PUBLISHING" &&
              to.effectPhase == "EFFECT_TERMINAL") else {
      return false
    }
    switch (from.effectPhase, to.effectPhase) {
    case ("READY", "CLAIMED"):
      return to.attemptKind == "POST_OR_UPDATE" && to.effectToken != nil
    case ("CLAIMED", "PUBLISHING"):
      return from.attemptKind == to.attemptKind &&
        from.effectToken == to.effectToken
    case ("PUBLISHING", "PUBLISHING"):
      return from.effectToken == to.effectToken &&
        ((from.attemptKind == "POST_OR_UPDATE" && to.attemptKind == "CANCEL") ||
          (from.attemptKind == "CANCEL" &&
            to.attemptKind == "POST_OR_UPDATE") ||
          from.attemptKind == to.attemptKind)
    case ("PUBLISHING", "EFFECT_TERMINAL"):
      return to.attemptKind == nil && to.effectToken == nil
    default:
      return false
    }
  }

  private static func recoveryHorizonReached(
    _ timestamp: String,
    now: Date,
    seconds: TimeInterval
  ) -> Bool {
    guard let date = canonicalDate(timestamp) else { return false }
    return now >= date.addingTimeInterval(seconds)
  }

  private static func canonicalTimestamp(_ value: Date) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'"
    return formatter.string(from: value)
  }

  fileprivate static func canonicalDate(_ value: String) -> Date? {
    guard value.range(
      of: #"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{3}|\.\d{6})Z$"#,
      options: .regularExpression
    ) != nil else {
      return nil
    }
    let fractionStart = value.index(value.startIndex, offsetBy: 20)
    let fractionEnd = value.index(before: value.endIndex)
    let fractionText = String(value[fractionStart..<fractionEnd])
    guard let fraction = Int(fractionText) else { return nil }
    let microseconds = fractionText.count == 3 ? fraction * 1_000 : fraction
    let wholeSeconds = String(value.prefix(19)) + "Z"
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    guard let date = formatter.date(from: wholeSeconds) else { return nil }
    return date.addingTimeInterval(Double(microseconds) / 1_000_000)
  }

  private static func takeBoundedExclusiveLock(
    _ descriptor: Int32,
    timeoutMs: Int
  ) -> Bool {
    let deadline = DispatchTime.now().uptimeNanoseconds +
      UInt64(timeoutMs) * 1_000_000
    repeat {
      if flock(descriptor, LOCK_EX | LOCK_NB) == 0 { return true }
      if errno != EWOULDBLOCK && errno != EAGAIN { return false }
      usleep(2_000)
    } while DispatchTime.now().uptimeNanoseconds < deadline
    return false
  }

  private static func isExistingDirectory(_ url: URL) -> Bool {
    var info = stat()
    guard lstat(url.path, &info) == 0 else { return false }
    return (info.st_mode & S_IFMT) == S_IFDIR
  }

  private static func isRegularFile(_ url: URL) -> Bool {
    var info = stat()
    guard lstat(url.path, &info) == 0 else { return false }
    return (info.st_mode & S_IFMT) == S_IFREG
  }

  /// `FileManager.fileExists` follows symlinks and reports a dangling symlink
  /// as absent. Plan-372 sidecar authority is lstat-based: only true absence
  /// or an incumbent regular file is a writable target.
  private static func isAbsentOrRegularFile(_ url: URL) -> Bool {
    var info = stat()
    if lstat(url.path, &info) == 0 {
      return (info.st_mode & S_IFMT) == S_IFREG
    }
    return errno == ENOENT
  }

  private static func pathExists(_ url: URL) -> Bool {
    var info = stat()
    return lstat(url.path, &info) == 0
  }

  private static func syncDirectory(_ url: URL) -> Bool {
    let descriptor = open(url.path, O_RDONLY | O_CLOEXEC)
    guard descriptor >= 0 else { return false }
    defer { close(descriptor) }
    return fsync(descriptor) == 0
  }

  private static func ownerFileNotificationId(_ name: String) -> Int? {
    guard name.hasSuffix(ownerSuffix) else { return nil }
    let stem = String(name.dropLast(ownerSuffix.count))
    guard !stem.isEmpty,
          stem.utf8.allSatisfy({ (48...57).contains($0) }),
          let value = Int(stem),
          (0...0x7fffffff).contains(value) else {
      return nil
    }
    return value
  }

  private static func notificationId<D: Digest>(digest: D) -> Int {
    let bytes = Array(digest)
    let value = UInt32(bytes[0]) << 24 |
      UInt32(bytes[1]) << 16 |
      UInt32(bytes[2]) << 8 |
      UInt32(bytes[3])
    return Int(value & 0x7fffffff)
  }

  private static func sha256(_ value: String) -> String {
    SHA256.hash(data: Data(value.utf8)).map {
      String(format: "%02x", $0)
    }.joined()
  }

  private static func randomDigest() -> String {
    sha256(UUID().uuidString + ":" + UUID().uuidString)
  }

  fileprivate static func isDigest(_ value: String) -> Bool {
    value.utf8.count == 64 && value.utf8.allSatisfy {
      (48...57).contains($0) || (97...102).contains($0)
    }
  }

  fileprivate static func isCanonicalBinding(_ value: String) -> Bool {
    value.utf8.count == 67 && value.hasPrefix("v1:") &&
      isDigest(String(value.dropFirst(3)))
  }

  fileprivate static func strictInt64(_ raw: Any?) -> Int64? {
    guard let number = raw as? NSNumber,
          CFGetTypeID(number) != CFBooleanGetTypeID(),
          !CFNumberIsFloatType(number) else {
      return nil
    }
    return Int64(number.stringValue)
  }

  fileprivate static func exactBool(_ raw: Any?) -> Bool? {
    guard let number = raw as? NSNumber,
          CFGetTypeID(number) == CFBooleanGetTypeID() else {
      return nil
    }
    return number.boolValue
  }

  private static func producerMatchesContentKind(
    _ producer: String,
    _ kind: String
  ) -> Bool {
    (producer.hasSuffix("_message") && kind == "message") ||
      (producer.hasSuffix("_reaction") && kind == "reaction")
  }

  fileprivate static let allowedProducerKinds: Set<String> = [
    "direct_message", "direct_reaction", "group_message", "group_reaction",
  ]
  fileprivate static let allowedContentKinds: Set<String> = ["message", "reaction"]
  fileprivate static let dartOwnedRemoteAdoptionAttemptKinds: Set<String> = [
    "ADOPT_EXISTING_REMOTE", "CANCEL_LOCAL_FOR_REMOTE_ADOPTION",
  ]
  private static let allowedAuthorityProjectionKeys: Set<String> = [
    PushSharedKeyNames.directReactionContacts,
    PushSharedKeyNames.directReactionAuthoredTargets,
    PushSharedKeyNames.groupReactionContexts,
    PushSharedKeyNames.groupReactionAuthoredTargets,
    PushSharedKeyNames.groupReactionLatestStates,
  ]
}

private struct VisibilityEvaluation {
  let sameVisibleConversation: Bool
  let lifecycle: String
  let revision: Int64
  let lifecycleGeneration: Int64
}

private struct ContentMetadata: Equatable {
  let kind: String
  let event: String
  let generation: String

  var data: Data {
    Data(
      "{\"v\":1,\"kind\":\"\(kind)\",\"event\":\"\(event)\",\"generation\":\"\(generation)\"}".utf8
    )
  }

  var digest: String {
    SHA256.hash(
      data: Data("mknoon-content-activation-intent-v1\0".utf8) + data
    ).map { String(format: "%02x", $0) }.joined()
  }

  static func decode(_ data: Data) -> ContentMetadata? {
    guard let root = try? JSONSerialization.jsonObject(with: data),
          let value = root as? [String: Any],
          Set(value.keys) == ["v", "kind", "event", "generation"],
          IosLocalNotificationFinalEffect.strictInt64(value["v"]) == 1,
          let kind = value["kind"] as? String,
          IosLocalNotificationFinalEffect.allowedContentKinds.contains(kind),
          let event = value["event"] as? String,
          IosLocalNotificationFinalEffect.isDigest(event),
          let generation = value["generation"] as? String,
          generation == "ledger:\(event)" else {
      return nil
    }
    return ContentMetadata(kind: kind, event: event, generation: generation)
  }
}

private struct ContentIntent: Equatable {
  let binding: String
  let previousDigest: String?
  let nextDigest: String

  var data: Data {
    let previous = previousDigest.map { "\"\($0)\"" } ?? "null"
    return Data(
      "{\"v\":1,\"opaqueBinding\":\"\(binding)\",\"previousDigest\":\(previous),\"nextDigest\":\"\(nextDigest)\"}".utf8
    )
  }

  static func decode(_ data: Data) -> ContentIntent? {
    guard let root = try? JSONSerialization.jsonObject(with: data),
          let value = root as? [String: Any],
          Set(value.keys) == [
            "v", "opaqueBinding", "previousDigest", "nextDigest",
          ],
          IosLocalNotificationFinalEffect.strictInt64(value["v"]) == 1,
          let binding = value["opaqueBinding"] as? String,
          IosLocalNotificationFinalEffect.isCanonicalBinding(binding),
          let next = value["nextDigest"] as? String,
          IosLocalNotificationFinalEffect.isDigest(next) else {
      return nil
    }
    let previous: String?
    if value["previousDigest"] is NSNull {
      previous = nil
    } else {
      guard let exact = value["previousDigest"] as? String,
            IosLocalNotificationFinalEffect.isDigest(exact) else {
        return nil
      }
      previous = exact
    }
    return ContentIntent(
      binding: binding,
      previousDigest: previous,
      nextDigest: next
    )
  }
}

private struct LedgerEnvelope {
  var storeRevision: Int64
  let opaqueBinding: String
  let claimsSuspended: Bool
  var records: [String: LedgerRecord]

  var isValid: Bool {
    storeRevision > 0 &&
      IosLocalNotificationFinalEffect.isCanonicalBinding(opaqueBinding) &&
      records.count <= 512 && records.allSatisfy {
        $0.key == $0.value.eventCorrelation && $0.value.isValid
      }
  }

  var data: Data? {
    guard isValid else { return nil }
    return try? JSONSerialization.data(
      withJSONObject: [
        "schemaVersion": 1,
        "storeRevision": storeRevision,
        "opaqueBinding": opaqueBinding,
        "claimsSuspended": claimsSuspended,
        "records": records.mapValues(\.json),
      ],
      options: [.sortedKeys, .withoutEscapingSlashes]
    )
  }

  static func decode(_ data: Data) -> LedgerEnvelope? {
    guard let root = try? JSONSerialization.jsonObject(with: data),
          let value = root as? [String: Any],
          Set(value.keys) == [
            "schemaVersion", "storeRevision", "opaqueBinding",
            "claimsSuspended", "records",
          ],
          IosLocalNotificationFinalEffect.strictInt64(
            value["schemaVersion"]
          ) == 1,
          let revision = IosLocalNotificationFinalEffect.strictInt64(
            value["storeRevision"]
          ),
          revision > 0,
          let binding = value["opaqueBinding"] as? String,
          let suspended = IosLocalNotificationFinalEffect.exactBool(
            value["claimsSuspended"]
          ),
          let rawRecords = value["records"] as? [String: Any],
          rawRecords.count <= 512 else {
      return nil
    }
    var records: [String: LedgerRecord] = [:]
    for (key, raw) in rawRecords {
      guard let record = LedgerRecord.decode(raw),
            record.eventCorrelation == key else {
        return nil
      }
      records[key] = record
    }
    let result = LedgerEnvelope(
      storeRevision: revision,
      opaqueBinding: binding,
      claimsSuspended: suspended,
      records: records
    )
    return result.isValid ? result : nil
  }
}

private struct LedgerRecord: Equatable {
  let eventCorrelation: String
  let conversationDigest: String
  let producerKind: String
  let sourceCustody: String
  var readState: String
  var presentationState: String
  let presentationOwner: String
  let notificationId: Int?
  let contentGeneration: String?
  var lastEvaluatedLifecycle: String
  var visibilityRevision: Int64?
  var lifecycleGeneration: Int64?
  var effectPhase: String
  var attemptKind: String?
  var effectToken: String?
  var revision: Int64
  let createdAtUtc: String
  var updatedAtUtc: String
  var terminalAtUtc: String?
  var settledAtUtc: String?

  var isValid: Bool {
    guard IosLocalNotificationFinalEffect.isDigest(eventCorrelation),
          IosLocalNotificationFinalEffect.isDigest(conversationDigest),
          IosLocalNotificationFinalEffect.allowedProducerKinds.contains(
            producerKind
          ),
          ["SQL_READY", "RELAY_VERIFIED_UNACKED"].contains(sourceCustody),
          ["UNREAD", "READ"].contains(readState),
          [
            "NOT_EVALUATED", "IN_CHAT", "OS_POSTED", "SUPPRESSED_POLICY",
            "CANCELLED",
          ].contains(presentationState),
          [
            "MAIN_APP", "IOS_NSE", "ANDROID_PUSH_SERVICE", "INBOX_RECONCILER",
          ].contains(presentationOwner),
          notificationId.map({ (0...0x7fffffff).contains($0) }) ?? true,
          contentGeneration.map(Self.isContentGeneration) ?? true,
          [
            "FOREGROUND_ACTIVE", "INACTIVE", "BACKGROUND", "UNKNOWN",
          ].contains(lastEvaluatedLifecycle),
          visibilityRevision.map({ $0 > 0 }) ?? true,
          lifecycleGeneration.map({ $0 > 0 }) ?? true,
          [
            "READY", "CLAIMED", "PUBLISHING", "EFFECT_TERMINAL", "SETTLED",
          ].contains(effectPhase),
          revision > 0,
          let created = IosLocalNotificationFinalEffect.canonicalDate(
            createdAtUtc
          ),
          let updated = IosLocalNotificationFinalEffect.canonicalDate(
            updatedAtUtc
          ),
          updated >= created else {
      return false
    }
    let requiresAttempt = effectPhase == "CLAIMED" || effectPhase == "PUBLISHING"
    guard requiresAttempt == (attemptKind != nil),
          requiresAttempt == (effectToken != nil),
          attemptKind.map({
            ["POST_OR_UPDATE", "CANCEL"].contains($0) ||
              IosLocalNotificationFinalEffect
                .dartOwnedRemoteAdoptionAttemptKinds.contains($0)
          }) ?? true,
          effectToken.map(IosLocalNotificationFinalEffect.isDigest) ?? true else {
      return false
    }
    if effectPhase == "READY" || effectPhase == "CLAIMED" ||
       effectPhase == "PUBLISHING" {
      guard terminalAtUtc == nil, settledAtUtc == nil else { return false }
    } else {
      guard presentationState != "NOT_EVALUATED",
            let terminalAtUtc,
            let terminal = IosLocalNotificationFinalEffect.canonicalDate(
              terminalAtUtc
            ),
            terminal >= created, terminal <= updated else {
        return false
      }
      if effectPhase == "EFFECT_TERMINAL" {
        guard settledAtUtc == nil else { return false }
      } else {
        guard sourceCustody != "RELAY_VERIFIED_UNACKED",
              let settledAtUtc,
              let settled = IosLocalNotificationFinalEffect.canonicalDate(
                settledAtUtc
              ),
              settled >= terminal, settled <= updated else {
          return false
        }
      }
    }
    return true
  }

  var json: [String: Any] {
    [
      "eventCorrelation": eventCorrelation,
      "conversationDigest": conversationDigest,
      "producerKind": producerKind,
      "sourceCustody": sourceCustody,
      "readState": readState,
      "presentationState": presentationState,
      "presentationOwner": presentationOwner,
      "notificationId": notificationId ?? NSNull(),
      "contentGeneration": contentGeneration ?? NSNull(),
      "lastEvaluatedLifecycle": lastEvaluatedLifecycle,
      "visibilityRevision": visibilityRevision ?? NSNull(),
      "lifecycleGeneration": lifecycleGeneration ?? NSNull(),
      "effectPhase": effectPhase,
      "attemptKind": attemptKind ?? NSNull(),
      "effectToken": effectToken ?? NSNull(),
      "revision": revision,
      "createdAtUtc": createdAtUtc,
      "updatedAtUtc": updatedAtUtc,
      "terminalAtUtc": terminalAtUtc ?? NSNull(),
      "settledAtUtc": settledAtUtc ?? NSNull(),
    ]
  }

  func sameImmutableIdentity(as other: LedgerRecord) -> Bool {
    eventCorrelation == other.eventCorrelation &&
      conversationDigest == other.conversationDigest &&
      producerKind == other.producerKind &&
      presentationOwner == other.presentationOwner &&
      notificationId == other.notificationId &&
      contentGeneration == other.contentGeneration &&
      createdAtUtc == other.createdAtUtc &&
      !(readState == "READ" && other.readState != "READ")
  }

  func matches(
    candidate: NseInboxCandidate,
    notificationId: Int,
    contentGeneration: String
  ) -> Bool {
    let base = eventCorrelation == candidate.eventCorrelation &&
      conversationDigest == candidate.conversationDigest &&
      producerKind == candidate.producerKind &&
      sourceCustody == "RELAY_VERIFIED_UNACKED" &&
      presentationOwner == "IOS_NSE" &&
      self.notificationId == notificationId &&
      self.contentGeneration == contentGeneration && effectPhase != "SETTLED"
    guard base else { return false }
    if effectPhase == "EFFECT_TERMINAL" { return true }
    return readState == "UNREAD" &&
      presentationState == "NOT_EVALUATED" &&
      lastEvaluatedLifecycle == "UNKNOWN" &&
      visibilityRevision == nil && lifecycleGeneration == nil &&
      terminalAtUtc == nil && settledAtUtc == nil
  }

  static func decode(_ raw: Any) -> LedgerRecord? {
    guard let value = raw as? [String: Any],
          Set(value.keys) == [
            "eventCorrelation", "conversationDigest", "producerKind",
            "sourceCustody", "readState", "presentationState",
            "presentationOwner", "notificationId", "contentGeneration",
            "lastEvaluatedLifecycle", "visibilityRevision",
            "lifecycleGeneration", "effectPhase", "attemptKind", "effectToken",
            "revision", "createdAtUtc", "updatedAtUtc", "terminalAtUtc",
            "settledAtUtc",
          ],
          let event = value["eventCorrelation"] as? String,
          let conversation = value["conversationDigest"] as? String,
          let producer = value["producerKind"] as? String,
          let custody = value["sourceCustody"] as? String,
          let read = value["readState"] as? String,
          let presentation = value["presentationState"] as? String,
          let owner = value["presentationOwner"] as? String,
          let lifecycle = value["lastEvaluatedLifecycle"] as? String,
          let phase = value["effectPhase"] as? String,
          let revision = IosLocalNotificationFinalEffect.strictInt64(
            value["revision"]
          ),
          let created = value["createdAtUtc"] as? String,
          let updated = value["updatedAtUtc"] as? String else {
      return nil
    }
    func nullableInt(_ key: String) -> Int64?? {
      if value[key] is NSNull { return .some(nil) }
      guard let exact = IosLocalNotificationFinalEffect.strictInt64(value[key])
      else { return nil }
      return .some(exact)
    }
    func nullableString(_ key: String) -> String?? {
      if value[key] is NSNull { return .some(nil) }
      guard let exact = value[key] as? String else { return nil }
      return .some(exact)
    }
    guard let rawId = nullableInt("notificationId"),
          let generation = nullableString("contentGeneration"),
          let visibility = nullableInt("visibilityRevision"),
          let lifecycleGeneration = nullableInt("lifecycleGeneration"),
          let attempt = nullableString("attemptKind"),
          let token = nullableString("effectToken"),
          let terminal = nullableString("terminalAtUtc"),
          let settled = nullableString("settledAtUtc"),
          rawId.map({ $0 <= Int64(Int.max) }) ?? true else {
      return nil
    }
    let result = LedgerRecord(
      eventCorrelation: event,
      conversationDigest: conversation,
      producerKind: producer,
      sourceCustody: custody,
      readState: read,
      presentationState: presentation,
      presentationOwner: owner,
      notificationId: rawId.map(Int.init),
      contentGeneration: generation,
      lastEvaluatedLifecycle: lifecycle,
      visibilityRevision: visibility,
      lifecycleGeneration: lifecycleGeneration,
      effectPhase: phase,
      attemptKind: attempt,
      effectToken: token,
      revision: revision,
      createdAtUtc: created,
      updatedAtUtc: updated,
      terminalAtUtc: terminal,
      settledAtUtc: settled
    )
    return result.isValid ? result : nil
  }

  private static func isContentGeneration(_ value: String) -> Bool {
    value.range(
      of: #"^[A-Za-z0-9._:-]{1,512}$"#,
      options: .regularExpression
    ) != nil
  }
}
