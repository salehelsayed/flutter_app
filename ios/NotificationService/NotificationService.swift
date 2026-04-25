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
