import Foundation
import UserNotifications

final class NotificationService: UNNotificationServiceExtension {
  private let completionGate = NotificationServiceCompletionGate()
  private var contentHandler: ((UNNotificationContent) -> Void)?
  private var bestAttemptContent: UNNotificationContent?
  private var resolvedPreview: NotificationPreviewResult?
  private let previewEventEmitter = LogPushPreviewEventEmitter()
  private lazy var previewResolver = NotificationPreviewResolver(
    keyReader: KeychainPushKeyReader(),
    decryptor: BridgePushDecryptor(),
    dedupeStore: AppGroupPushDedupeStore(),
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
    }

    pushEnvelopeStore?.stage(userInfo: mutableContent.userInfo)

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
    let claimed = completionGate.claim(generation: generation) {
      handler = contentHandler
      content = bestAttemptContent
      preview = resolvedPreview
      contentHandler = nil
      bestAttemptContent = nil
      resolvedPreview = nil
    }
    guard claimed, let handler, let content else {
      return
    }

    var didApplyPreview = false
    if let mutableContent = content as? UNMutableNotificationContent {
      didApplyPreview = applyOrSanitizeNotificationPreviewResult(
        preview,
        to: mutableContent
      )
      if didApplyPreview {
        recentRemoteShownMarkerStore?.mark(userInfo: mutableContent.userInfo)
      }
    }
    handler(content)
    let toneReservation = preview?.toneReservation
    if didApplyPreview && preview?.markAsShown == true {
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
