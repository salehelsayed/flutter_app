import Foundation
import UIKit
import UserNotifications

protocol IosNotificationRecoveryCenter: AnyObject {
  func getDeliveredRequestIdentifiers(
    completionHandler: @escaping @Sendable (Set<String>) -> Void
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
    return BeginResponse(token: token, watermark: begin.watermark)
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
}
