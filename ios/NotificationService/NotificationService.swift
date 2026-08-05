import Foundation
import UserNotifications

final class NotificationService: UNNotificationServiceExtension {
  private let completionGate = NotificationServiceCompletionGate()
  private var contentHandler: ((UNNotificationContent) -> Void)?
  private var bestAttemptContent: UNNotificationContent?
  private var resolvedPreview: NotificationPreviewResult?
  private var requestIdentifier: String?
  private let previewEventEmitter = LogPushPreviewEventEmitter()
  private lazy var notificationRecoveryStore = IosNotificationRecoveryStore()
  private lazy var notificationRecoveryHandoff =
    IosNotificationRecoveryHandoffOrchestrator(
      store: notificationRecoveryStore
    )
  private lazy var notificationRecoveryBadgeWriter:
    IosNotificationBadgeWriting? = {
      guard #available(iOS 16.0, *),
            let notificationRecoveryStore else {
        return nil
      }
      return IosNotificationSerializedBadgeWriter(
        store: notificationRecoveryStore,
        setter: { count, completion in
          UNUserNotificationCenter.current().setBadgeCount(
            count,
            withCompletionHandler: completion
          )
        }
      )
    }()
  private lazy var previewResolver = NotificationPreviewResolver(
    keyReader: KeychainPushKeyReader(),
    decryptor: BridgePushDecryptor(),
    // The shared handoff orchestrator owns the production uniqueness claim so
    // there is no crash window between the old resolver-only claim and exact
    // Apple request custody. The resolver injection remains as a test seam.
    dedupeStore: nil,
    toneLeaseStore: AppGroupNotificationToneLeaseStore(),
    eventEmitter: previewEventEmitter
  )
  private lazy var recentRemoteShownMarkerStore = RecentRemoteShownMarkerStore()
  private lazy var pushEnvelopeStore = AppGroupPushEnvelopeStore()

  override func didReceive(
    _ request: UNNotificationRequest,
    withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void
  ) {
    let mutableContent: UNMutableNotificationContent
    if let copy = request.content.mutableCopy() as? UNMutableNotificationContent {
      mutableContent = copy
    } else {
      // Keep only routing if the system content unexpectedly cannot be copied;
      // this still lets resolution authorize trusted copy and guarantees the
      // unresolved expiry path has mutable metadata it can fully sanitize.
      mutableContent = UNMutableNotificationContent()
      mutableContent.userInfo = request.content.userInfo
    }
    let generation = completionGate.reset { _ in
      self.contentHandler = contentHandler
      bestAttemptContent = mutableContent
      resolvedPreview = nil
      requestIdentifier = request.identifier
    }

    let envelopeStaged = pushEnvelopeStore?.stage(
      userInfo: mutableContent.userInfo
    ) ?? false
    previewEventEmitter.emit(
      event: "PUSH_NSE_ENVELOPE_STAGED",
      details: ["success": envelopeStaged ? "true" : "false"]
    )

    let preview = previewResolver.resolve(
      userInfo: mutableContent.userInfo,
      fallbackTitle: mutableContent.title,
      fallbackBody: mutableContent.body,
      fallbackThreadIdentifier: mutableContent.threadIdentifier
    )
    guard publish(preview: preview, generation: generation) else {
      return
    }
    finish(generation: generation)
  }

  override func serviceExtensionTimeWillExpire() {
    previewEventEmitter.emit(
      event: "PUSH_NSE_TIMEOUT",
      details: ["reason": "service_extension_time_will_expire"]
    )
    guard let generation = completionGate.currentGeneration() else { return }
    finish(generation: generation, expiry: true)
  }

  private func publish(
    preview: NotificationPreviewResult,
    generation: NotificationServiceCompletionGeneration
  ) -> Bool {
    let published = completionGate.publish(generation: generation) {
      resolvedPreview = preview
    }
    guard published else {
      if let reservation = preview.toneReservation,
         !reservation.release() {
        previewEventEmitter.emit(
          event: "PUSH_NSE_TONE_RELEASE_FAILED",
          details: ["kind": "preview_publish_lost"]
        )
      }
      return false
    }
    return true
  }

  private func finish(
    generation: NotificationServiceCompletionGeneration,
    expiry: Bool = false
  ) {
    var handler: ((UNNotificationContent) -> Void)?
    var content: UNNotificationContent?
    var preview: NotificationPreviewResult?
    var claimedRequestIdentifier: String?
    let claimed = completionGate.claim(generation: generation) {
      handler = contentHandler
      content = bestAttemptContent
      preview = resolvedPreview
      contentHandler = nil
      bestAttemptContent = nil
      resolvedPreview = nil
      claimedRequestIdentifier = requestIdentifier
      requestIdentifier = nil
    }
    guard claimed, let handler, let content else {
      return
    }

    var didApplyPreview = false
    var recoveryDisposition: IosNotificationRecoveryHandoffDisposition =
      .untracked
    let badgeWriter = notificationRecoveryBadgeWriter
    notificationRecoveryHandoff.handoff(
      requestIdentifier: claimedRequestIdentifier ?? "",
      identity: preview?.recoveryIdentity,
      content: content,
      prepareContent: { [weak self] disposition in
        recoveryDisposition = disposition
        guard let mutableContent = content as? UNMutableNotificationContent else {
          return
        }
        switch disposition {
        case .rejected:
          sanitizeNotificationContentForUnresolvedExpiry(mutableContent)
          didApplyPreview = false
        case .duplicate
          where preview?.recoveryIdentity?.kind == .ordinary:
          // Without the filtering entitlement this is privacy clearing, not a
          // claim that iOS will suppress delivery.
          sanitizeNotificationContentForUnresolvedExpiry(mutableContent)
          didApplyPreview = false
        default:
          didApplyPreview = applyOrSanitizeNotificationPreviewResult(
            preview,
            to: mutableContent
          )
          if disposition == .duplicate,
             preview?.recoveryIdentity?.kind == .reaction {
            mutableContent.sound = nil
            if #available(iOS 15.0, *) {
              mutableContent.interruptionLevel = .passive
            }
          }
        }
        // Belt-and-suspenders for every branch, including future preview
        // applicators: APNs badge payloads never escape this extension.
        mutableContent.badge = nil
        if didApplyPreview {
          self?.recentRemoteShownMarkerStore?.mark(
            userInfo: mutableContent.userInfo
          )
        }
        self?.previewEventEmitter.emit(
          event: "PUSH_NSE_CONTENT_HANDOFF",
          details: ["authorized": didApplyPreview ? "true" : "false"]
        )
      },
      beforeContentHandler: { disposition in
        if disposition == .unique || disposition == .duplicate {
          // Submission is queued before Apple's handoff so extension teardown
          // cannot lose it, but the handler never waits for the async writer.
          badgeWriter?.requestWrite()
        }
      },
      contentHandler: handler
    )
    let toneReservation = preview?.toneReservation
    if didApplyPreview &&
       recoveryDisposition != .duplicate &&
       preview?.markAsShown == true {
      if let toneReservation, !toneReservation.commit(now: Date()) {
        previewEventEmitter.emit(
          event: "PUSH_NSE_TONE_COMMIT_FAILED",
          details: ["kind": preview?.reason ?? "unknown"]
        )
      }
    } else if let toneReservation,
              !toneReservation.release() {
      previewEventEmitter.emit(
        event: "PUSH_NSE_TONE_RELEASE_FAILED",
        details: [
          "kind": expiry
            ? "extension_expired"
            : preview?.reason ?? "not_displayed",
        ]
      )
    }
  }
}
