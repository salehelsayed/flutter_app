import UserNotifications

final class NotificationService: UNNotificationServiceExtension {
  private var contentHandler: ((UNNotificationContent) -> Void)?
  private var bestAttemptContent: UNMutableNotificationContent?
  private let previewEventEmitter = LogPushPreviewEventEmitter()
  private lazy var previewResolver = NotificationPreviewResolver(
    keyReader: KeychainPushKeyReader(),
    decryptor: BridgePushDecryptor(),
    dedupeStore: AppGroupPushDedupeStore(),
    eventEmitter: previewEventEmitter
  )
  private lazy var recentRemoteShownMarkerStore = RecentRemoteShownMarkerStore()

  override func didReceive(
    _ request: UNNotificationRequest,
    withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void
  ) {
    self.contentHandler = contentHandler
    bestAttemptContent = (request.content.mutableCopy() as? UNMutableNotificationContent)

    guard let bestAttemptContent else {
      contentHandler(request.content)
      return
    }

    let preview = previewResolver.resolve(
      userInfo: bestAttemptContent.userInfo,
      fallbackTitle: bestAttemptContent.title,
      fallbackBody: bestAttemptContent.body,
      fallbackThreadIdentifier: bestAttemptContent.threadIdentifier
    )
    bestAttemptContent.title = preview.title
    bestAttemptContent.body = preview.body
    if let threadIdentifier = preview.threadIdentifier {
      bestAttemptContent.threadIdentifier = threadIdentifier
    }
    if preview.suppress {
      // 04-P0 SI-1 NSE: muted group — deliver silently (no sound, passive) so it
      // does not buzz or banner; it lands quietly in Notification Center. iOS
      // will not let the NSE fully drop an alert push, so this is the achievable
      // "honor mute" on the out-of-process path.
      bestAttemptContent.sound = nil
      if #available(iOS 15.0, *) {
        bestAttemptContent.interruptionLevel = .passive
      }
    }
    // 04-P0 SI-5: record that the NSE actually surfaced this push into the
    // shared app-group container so a duplicate Dart-side banner is suppressed
    // even if iOS never schedules the Dart isolate for this FCM copy. Skip the
    // marker when the preview is suppressed (muted group): nothing was surfaced
    // to dedupe against, and the Dart `isMuted` gate never consumes such a
    // marker — writing one only orphans an inode that accumulates until the next
    // cold-start prune.
    if !preview.suppress {
      recentRemoteShownMarkerStore?.mark(userInfo: bestAttemptContent.userInfo)
    }

    contentHandler(bestAttemptContent)
  }

  override func serviceExtensionTimeWillExpire() {
    previewEventEmitter.emit(
      event: "PUSH_NSE_TIMEOUT",
      details: ["reason": "service_extension_time_will_expire"]
    )
    if let contentHandler, let bestAttemptContent {
      contentHandler(bestAttemptContent)
    }
  }
}
