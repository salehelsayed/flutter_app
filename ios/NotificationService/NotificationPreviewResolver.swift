import CryptoKit
import Darwin
import Foundation
import os.log
import Security
import UserNotifications

#if canImport(GoMknoon)
import GoMknoon
#endif

#if MKNOON_SIMS_GROUP_MEDIA_269
let mknoonSharedAppGroupIdentifier =
  "group.com.mknoon.sims.groupmedia269.share"
let mknoonSharedKeychainAccessGroupIdentifier =
  "397R9Q4WMX.group.com.mknoon.sims.groupmedia269.share"
#else
let mknoonSharedAppGroupIdentifier = "group.com.mknoon.app.share"
let mknoonSharedKeychainAccessGroupIdentifier =
  "397R9Q4WMX.group.com.mknoon.app.share"
#endif
let mknoonFlutterSecureStorageService = "flutter_secure_storage_service"

enum PushSharedKeyNames {
  static let identityMlKemSecretKey = "identity_ml_kem_secret_key"
  static let directReactionContacts = "direct_reaction_contacts_v1"
  static let directReactionAuthoredTargets = "direct_reaction_authored_targets_v1"
  static let groupReactionContexts = "group_reaction_contexts_v1"
  static let groupReactionAuthoredTargets =
    "group_reaction_authored_targets_v1"
  static let groupReactionLatestStates = "group_reaction_latest_states_v1"

  static func groupKey(groupId: String, keyEpoch: Int) -> String {
    "group_key:\(groupId):\(keyEpoch)"
  }

  // 04-P0 SI-1 NSE: the app mirrors a "group_muted:<groupId>" sentinel ("1")
  // into the shared Keychain so the out-of-process NSE can honor mute.
  static func groupMuted(groupId: String) -> String {
    "group_muted:\(groupId)"
  }
}

protocol PushKeyReading {
  func readString(key: String) -> String?
}

protocol PushPayloadDecrypting {
  func decryptOneToOne(
    secretKey: String,
    kem: String,
    ciphertext: String,
    nonce: String
  ) throws -> String

  func decryptGroup(
    groupKey: String,
    ciphertext: String,
    nonce: String
  ) throws -> String
}

protocol PushDedupeStoring {
  func claim(type: String, messageId: String) -> Bool
}

protocol PushToneLeaseStoring {
  func acquire(conversationId: String, now: Date) -> Bool
}

protocol PushToneReservation: AnyObject {
  func commit(now: Date) -> Bool
  func release() -> Bool
}

enum PushToneReservationOutcome {
  case reserved(PushToneReservation)
  case leaseHeld
  case storageUnavailable
}

protocol PushToneReservationStoring {
  func reserve(conversationId: String, now: Date) -> PushToneReservationOutcome
}

protocol PushPreviewEventEmitting {
  func emit(event: String, details: [String: String])
}

/// Owns the single completion claim shared by the NSE's normal and expiry
/// paths. The winning action runs while the gate is locked, so it can take and
/// clear handler/content state atomically; a losing action is never invoked.
struct NotificationServiceCompletionGeneration: Equatable {
  fileprivate let value: UInt64
}

final class NotificationServiceCompletionGate {
  private let lock = NSLock()
  private var didFinish = false
  private var generation: UInt64 = 0

  @discardableResult
  func reset(
    _ prepare: (NotificationServiceCompletionGeneration) -> Void
  ) -> NotificationServiceCompletionGeneration {
    lock.lock()
    generation &+= 1
    let token = NotificationServiceCompletionGeneration(value: generation)
    prepare(token)
    didFinish = false
    lock.unlock()
    return token
  }

  func currentGeneration() -> NotificationServiceCompletionGeneration? {
    lock.lock()
    defer { lock.unlock() }
    guard generation > 0 else { return nil }
    return NotificationServiceCompletionGeneration(value: generation)
  }

  @discardableResult
  func publish(
    generation token: NotificationServiceCompletionGeneration,
    _ publishState: () -> Void
  ) -> Bool {
    lock.lock()
    defer { lock.unlock() }
    guard !didFinish, token.value == generation else { return false }
    publishState()
    return true
  }

  @discardableResult
  func claim(
    generation token: NotificationServiceCompletionGeneration,
    _ takeState: () -> Void
  ) -> Bool {
    lock.lock()
    defer { lock.unlock() }
    guard !didFinish, token.value == generation else { return false }
    didFinish = true
    takeState()
    return true
  }
}

func sanitizeNotificationContentForUnresolvedExpiry(
  _ content: UNMutableNotificationContent
) {
  content.title = ""
  content.subtitle = ""
  content.body = ""
  content.attachments = []
  content.badge = nil
  content.sound = nil
  content.categoryIdentifier = ""
  content.threadIdentifier = ""
  content.summaryArgument = ""
  content.summaryArgumentCount = 0
  #if os(iOS)
  content.launchImageName = ""
  #endif
  if #available(iOS 15.0, *) {
    content.targetContentIdentifier = ""
    content.relevanceScore = 0
    content.interruptionLevel = .passive
  }
  if #available(iOS 16.0, *) {
    content.filterCriteria = ""
  }
}

func nsePublicProofPayload(
  event: String,
  details: [String: String]
) -> String? {
  let publicDetails: [String: String]
  switch event {
  case "PUSH_NSE_ENVELOPE_STAGED":
    if let success = details["success"],
       success == "true" || success == "false" {
      publicDetails = ["success": success]
    } else {
      publicDetails = ["success": "unknown"]
    }
  case "PUSH_NSE_CONTENT_HANDOFF":
    if let authorized = details["authorized"],
       authorized == "true" || authorized == "false" {
      publicDetails = ["authorized": authorized]
    } else {
      publicDetails = ["authorized": "unknown"]
    }
  case "PUSH_NSE_DECRYPT_OK", "PUSH_NSE_DECRYPT_FAIL", "PUSH_NSE_TIMEOUT":
    publicDetails = [:]
  default:
    return nil
  }
  let payload: [String: Any] = [
    "event": event,
    "details": publicDetails,
  ]
  guard let data = try? JSONSerialization.data(
    withJSONObject: payload,
    options: [.sortedKeys]
  ) else {
    return nil
  }
  return String(data: data, encoding: .utf8)
}

final class LogPushPreviewEventEmitter: PushPreviewEventEmitting {
  private static let proofLog = OSLog(
    subsystem: "com.mknoon.app.NotificationService",
    category: "nse-proof"
  )

  func emit(event: String, details: [String: String]) {
    let payload: [String: Any] = [
      "event": event,
      "details": details,
    ]
    guard let data = try? JSONSerialization.data(
      withJSONObject: payload,
      options: [.sortedKeys]
    ),
      let json = String(data: data, encoding: .utf8) else {
      return
    }
    if let publicProof = nsePublicProofPayload(event: event, details: details) {
      os_log(
        "[FLOW_PROOF] %{public}@",
        log: Self.proofLog,
        type: .info,
        publicProof
      )
    }
    NSLog("[FLOW] %@", json)
  }
}

struct NotificationPreviewResult {
  let title: String
  let body: String
  let threadIdentifier: String?
  let didDecrypt: Bool
  let reason: String
  // 04-P0 SI-1 NSE: a muted group keeps generic fallback content but asks
  // NotificationService to deliver it silently (no sound, passive — no banner).
  var suppress: Bool = false
  var markAsShown: Bool = true
  var categoryIdentifier: String? = nil
  var targetContentIdentifier: String? = nil
  var toneReservation: PushToneReservation? = nil
  var recoveryIdentity: IosNotificationRecoveryIdentity? = nil
}

/// Applies the resolver result at the real UserNotifications boundary. Relay
/// fallback payloads are intentionally silent, so a validated reaction must
/// explicitly restore the default sound. Rejected, duplicate, and burst-update
/// reaction results are suppressed by the resolver and always remain passive
/// and silent.
func applyNotificationPreviewResult(
  _ preview: NotificationPreviewResult,
  to content: UNMutableNotificationContent
) {
  // Provider-supplied relative badge arithmetic is never authoritative. Both
  // authorized and sanitized handoffs use the native absolute writer instead.
  content.badge = nil
  content.title = preview.title
  content.body = preview.body
  if let threadIdentifier = preview.threadIdentifier {
    content.threadIdentifier = threadIdentifier
  }
  if let categoryIdentifier = preview.categoryIdentifier {
    content.categoryIdentifier = categoryIdentifier
  }
  if #available(iOS 15.0, *),
     let targetContentIdentifier = preview.targetContentIdentifier {
    content.targetContentIdentifier = targetContentIdentifier
  }

  if preview.suppress {
    content.sound = nil
    if #available(iOS 15.0, *) {
      content.interruptionLevel = .passive
    }
    return
  }

  if preview.didDecrypt &&
    (preview.reason == "reaction" || preview.reason == "group_reaction") {
    content.sound = .default
    if #available(iOS 15.0, *) {
      content.interruptionLevel = .active
    }
  }
}

/// Applies only a resolver result explicitly authorized for handoff. Every
/// rejected, malformed, muted, or duplicate `markAsShown == false` result uses
/// the same full sanitizer as unresolved expiry, so provider-controlled visible
/// metadata cannot survive on the normal completion path either.
@discardableResult
func applyOrSanitizeNotificationPreviewResult(
  _ preview: NotificationPreviewResult?,
  to content: UNMutableNotificationContent
) -> Bool {
  guard let preview, preview.markAsShown else {
    sanitizeNotificationContentForUnresolvedExpiry(content)
    return false
  }
  applyNotificationPreviewResult(preview, to: content)
  return true
}

enum NotificationPreviewError: Error {
  case bridgeUnavailable
  case invalidBridgeInput
  case invalidBridgeResponse
  case bridgeFailure(String)
}

final class NotificationPreviewResolver {
  private let keyReader: PushKeyReading
  private let decryptor: PushPayloadDecrypting
  private let dedupeStore: PushDedupeStoring?
  private let toneLeaseStore: PushToneLeaseStoring?
  private let eventEmitter: PushPreviewEventEmitting
  private let localeIdentifierProvider: () -> String

  init(
    keyReader: PushKeyReading,
    decryptor: PushPayloadDecrypting,
    dedupeStore: PushDedupeStoring?,
    toneLeaseStore: PushToneLeaseStoring? = nil,
    eventEmitter: PushPreviewEventEmitting = LogPushPreviewEventEmitter(),
    localeIdentifierProvider: @escaping () -> String = {
      Locale.preferredLanguages.first ?? Locale.current.identifier
    }
  ) {
    self.keyReader = keyReader
    self.decryptor = decryptor
    self.dedupeStore = dedupeStore
    self.toneLeaseStore = toneLeaseStore
    self.eventEmitter = eventEmitter
    self.localeIdentifierProvider = localeIdentifierProvider
  }

  func resolve(
    userInfo: [AnyHashable: Any],
    fallbackTitle: String,
    fallbackBody: String,
    fallbackThreadIdentifier: String? = nil
  ) -> NotificationPreviewResult {
    let data = PushRouteData(userInfo: userInfo)

    // FDC-S1 Method 5(d) (observation-only): record whether the self decrypt key
    // (App-Group keychain) and the sender peerId (push userInfo) are in hand
    // inside the out-of-process NSE, with the NSE wall-clock epoch and pushId.
    // The libp2p host is NOT running here, so the earliest a warm dial can start
    // is node:start-return on the main isolate. nseEpochMs is correlated by
    // pushId with the main isolate's FDC_COLDSTART_NOTIF_TAP_NODE_READY to yield
    // the NSE→main gap off-device (APNs userInfo carries no timestamp to thread
    // inline). Synchronous NSLog only — does not delay contentHandler.
    let selfKeyPresent = keyReader.readString(
      key: PushSharedKeyNames.identityMlKemSecretKey
    ) != nil
    let senderPeerIdPresent =
      (data.string("sender_id", aliases: "s")
        ?? data.string("group_id", aliases: "g", "groupId")) != nil
    eventEmitter.emit(
      event: "FDC_NSE_PEERID_AVAILABLE",
      details: [
        "selfKeyPresent": selfKeyPresent ? "true" : "false",
        "senderPeerIdPresent": senderPeerIdPresent ? "true" : "false",
        "nseEpochMs": String(Int64(Date().timeIntervalSince1970 * 1000)),
        "pushId": data.messageId ?? "unknown",
        "pushType": data.string("type", aliases: "t") ?? "unknown",
      ]
    )

    guard let type = data.string("type", aliases: "t") else {
      return fallback(
        title: fallbackTitle,
        body: fallbackBody,
        threadIdentifier: fallbackThreadIdentifier,
        reason: "missing_type"
      )
    }

    guard type == "new_message" ||
      type == "group_message" ||
      type == "message_reaction" ||
      type == "group_reaction" else {
      return fallback(
        title: fallbackTitle,
        body: fallbackBody,
        threadIdentifier: fallbackThreadIdentifier,
        reason: "unsupported_type"
      )
    }

    if type == "new_message" {
      return resolveOneToOne(
        data: data,
        fallbackTitle: fallbackTitle,
        fallbackBody: fallbackBody,
        fallbackThreadIdentifier: fallbackThreadIdentifier
      )
    }
    if type == "message_reaction" {
      return resolveReaction(
        data: data,
        fallbackThreadIdentifier: fallbackThreadIdentifier
      )
    }
    if type == "group_reaction" {
      return resolveGroupReaction(data: data)
    }
    return resolveGroup(
      data: data,
      fallbackTitle: fallbackTitle,
      fallbackBody: fallbackBody,
      fallbackThreadIdentifier: fallbackThreadIdentifier
    )
  }

  private func resolveOneToOne(
    data: PushRouteData,
    fallbackTitle: String,
    fallbackBody: String,
    fallbackThreadIdentifier: String?
  ) -> NotificationPreviewResult {
    guard let projection = OrdinaryNotificationProjectionSnapshot(
      keyReader: keyReader
    ),
      let senderPeerId = data.exactString("sender_id", aliases: "s"),
      senderPeerId != projection.localAccountPeerId,
      let contact = projection.contacts[senderPeerId],
      !contact.blocked,
      !contact.archived else {
      return suppressOrdinary(
        title: "Mknoon",
        body: "New message",
        threadIdentifier: fallbackThreadIdentifier,
        reason: "chat_recipient_policy_rejected",
        eventKind: "chat"
      )
    }
    let messageId = data.exactMessageId
    if data.exactCanonicalString("preview_unavailable") == "1" {
      guard data.exactCanonicalString("type") == "new_message",
            data.exactCanonicalString("sender_id") == senderPeerId else {
        return suppressOrdinary(
          title: contact.username,
          body: "New message",
          threadIdentifier: senderPeerId,
          reason: "chat_preview_unavailable_route_rejected",
          eventKind: "chat"
        )
      }
      return prepareOrdinaryDisplay(
        type: "new_message",
        messageId: messageId,
        accountPeerId: projection.localAccountPeerId,
        lane: .direct,
        recoveryConversationId: senderPeerId,
        toneConversationId: senderPeerId,
        title: contact.username,
        body: "New message",
        threadIdentifier: senderPeerId,
        didDecrypt: false,
        reason: "chat_preview_unavailable"
      )
    }

    guard let kem = data.string("kem", aliases: "k"),
          let ciphertext = data.string("ciphertext", aliases: "c"),
          let nonce = data.string("nonce", aliases: "n") else {
      return suppressOrdinary(
        title: contact.username,
        body: "New message",
        threadIdentifier: senderPeerId,
        reason: "missing_chat_decrypt_input",
        eventKind: "chat",
        eventDetails: data.decryptInputPresenceDetails(
          requiredKeys: [
            ("kem", ["k"]),
            ("ciphertext", ["c"]),
            ("nonce", ["n"]),
          ]
        )
      )
    }
    guard let secretKey = keyReader.readString(
      key: PushSharedKeyNames.identityMlKemSecretKey
    ) else {
      return suppressOrdinary(
        title: contact.username,
        body: "New message",
        threadIdentifier: senderPeerId,
        reason: "missing_chat_secret",
        eventKind: "chat"
      )
    }

    do {
      let plaintext = try decryptor.decryptOneToOne(
        secretKey: secretKey,
        kem: kem,
        ciphertext: ciphertext,
        nonce: nonce
      )
      guard let payload = decodeJSONObject(plaintext),
            trimmedString(payload["senderPeerId"]) == senderPeerId,
            messageId == nil || trimmedString(payload["id"]) == messageId else {
        return suppressOrdinary(
          title: contact.username,
          body: "New message",
          threadIdentifier: senderPeerId,
          reason: "chat_plaintext_parity_mismatch",
          eventKind: "chat"
        )
      }

      emitDecryptOK(kind: "chat")
      let previewBody = payload.keys.contains("privateMedia")
        ? privateMediaNotificationBody(
          localeIdentifier: localeIdentifierProvider()
        )
        : pushPreviewBody(
          text: trimmedString(payload["text"]) ?? "",
          media: payload["media"]
        )
      return prepareOrdinaryDisplay(
        type: "new_message",
        messageId: messageId,
        accountPeerId: projection.localAccountPeerId,
        lane: .direct,
        recoveryConversationId: senderPeerId,
        toneConversationId: senderPeerId,
        title: contact.username,
        body: previewBody,
        threadIdentifier: senderPeerId,
        didDecrypt: true,
        reason: "chat"
      )
    } catch {
      return suppressOrdinary(
        title: contact.username,
        body: "New message",
        threadIdentifier: senderPeerId,
        reason: "chat_decrypt_error",
        eventKind: "chat"
      )
    }
  }

  private func resolveReaction(
    data: PushRouteData,
    fallbackThreadIdentifier: String?
  ) -> NotificationPreviewResult {
    let senderPeerId = data.string("sender_id", aliases: "from", "s")
    let eventId = data.string("event_id", aliases: "reaction_id", "r")
    let targetMessageId = data.string(
      "target_message_id",
      aliases: "targetMessageId", "target_id"
    )
    let action = data.string("action", aliases: "a")
    let threadIdentifier = senderPeerId ?? fallbackThreadIdentifier

    guard let senderPeerId,
          let eventId,
          let targetMessageId,
          action == "add",
          let kem = data.string("kem", aliases: "k"),
          let ciphertext = data.string("ciphertext", aliases: "c"),
          let nonce = data.string("nonce", aliases: "n") else {
      return reactionFallback(
        threadIdentifier: threadIdentifier,
        eventId: eventId,
        reason: action == "add" ? "missing_reaction_input" : "reaction_not_add"
      )
    }

    guard let projection = DirectReactionProjectionSnapshot(
      keyReader: keyReader
    ) else {
      return reactionFallback(
        threadIdentifier: senderPeerId,
        eventId: eventId,
        reason: "reaction_recipient_projection_rejected"
      )
    }
    guard let contact = projection.contacts[senderPeerId], !contact.blocked else {
      return reactionFallback(
        threadIdentifier: senderPeerId,
        eventId: eventId,
        reason: projection.contacts[senderPeerId] == nil
          ? "reaction_unknown_contact"
          : "reaction_blocked_contact"
      )
    }
    guard !contact.archived else {
      return reactionFallback(
        threadIdentifier: senderPeerId,
        eventId: eventId,
        reason: "reaction_archived_contact",
        trustedTitle: contact.username
      )
    }
    guard projection.authoredTargets[targetMessageId] == senderPeerId else {
      return reactionFallback(
        threadIdentifier: senderPeerId,
        eventId: eventId,
        reason: "reaction_target_not_locally_authored",
        trustedTitle: contact.username
      )
    }
    guard let secretKey = keyReader.readString(
      key: PushSharedKeyNames.identityMlKemSecretKey
    ) else {
      return reactionFallback(
        threadIdentifier: senderPeerId,
        eventId: eventId,
        reason: "missing_reaction_secret",
        trustedTitle: contact.username
      )
    }

    do {
      let plaintext = try decryptor.decryptOneToOne(
        secretKey: secretKey,
        kem: kem,
        ciphertext: ciphertext,
        nonce: nonce
      )
      guard let payload = decodeJSONObject(plaintext),
            trimmedString(payload["id"]) == eventId,
            trimmedString(payload["messageId"]) == targetMessageId,
            trimmedString(payload["action"]) == "add",
            trimmedString(payload["senderPeerId"]) == senderPeerId,
            let emoji = trimmedString(payload["emoji"]) else {
        return reactionFallback(
          threadIdentifier: senderPeerId,
          eventId: eventId,
          reason: "reaction_parity_mismatch",
          trustedTitle: contact.username
        )
      }

      let notificationIdentity = boundedReactionNotificationIdentity(
        eventId: eventId
      )
      if let dedupeStore,
         !dedupeStore.claim(
           type: "message_reaction",
           messageId: notificationIdentity
         ) {
        return reactionFallback(
          threadIdentifier: senderPeerId,
          eventId: eventId,
          reason: "duplicate_reaction",
          trustedTitle: contact.username,
          markAsShown: true
        )
      }

      let tone = prepareReactionTone(
        conversationId: senderPeerId,
        eventKind: "reaction"
      )
      emitDecryptOK(kind: "reaction")
      return NotificationPreviewResult(
        title: contact.username,
        body: "Reacted \(emoji) to your message",
        threadIdentifier: senderPeerId,
        didDecrypt: true,
        reason: "reaction",
        suppress: !tone.shouldAlert,
        markAsShown: true,
        categoryIdentifier: "MESSAGE_REACTION",
        targetContentIdentifier: notificationIdentity,
        toneReservation: tone.reservation,
        recoveryIdentity: IosNotificationRecoveryIdentity(
          accountPeerId: projection.localAccountPeerId,
          lane: .direct,
          conversationId: senderPeerId,
          eventId: eventId,
          kind: .reaction
        )
      )
    } catch {
      return reactionFallback(
        threadIdentifier: senderPeerId,
        eventId: eventId,
        reason: "reaction_decrypt_error",
        trustedTitle: contact.username
      )
    }
  }

  private func reactionFallback(
    threadIdentifier: String?,
    eventId: String?,
    reason: String,
    trustedTitle: String? = nil,
    markAsShown: Bool = false
  ) -> NotificationPreviewResult {
    emitDecryptFail(kind: "reaction", reason: reason)
    return NotificationPreviewResult(
      title: trustedTitle ?? "Reaction",
      body: "Someone reacted to your message",
      threadIdentifier: threadIdentifier,
      didDecrypt: false,
      reason: reason,
      suppress: true,
      markAsShown: markAsShown,
      categoryIdentifier: "MESSAGE_REACTION",
      targetContentIdentifier: eventId.map {
        boundedReactionNotificationIdentity(eventId: $0)
      }
    )
  }

  private func resolveGroupReaction(
    data: PushRouteData
  ) -> NotificationPreviewResult {
    let groupId = data.exactString("groupId", aliases: "group_id", "g")
    let eventId = data.exactString(
      "event_id",
      aliases: "transition_id", "transitionId"
    )
    let targetMessageId = data.exactString(
      "target_message_id",
      aliases: "targetMessageId", "target_id"
    )
    let action = data.exactString("action", aliases: "a")
    if let action, action != "add" {
      return groupReactionFallback(
        groupId: groupId,
        eventId: eventId,
        reason: "group_reaction_not_add"
      )
    }

    guard let groupId,
          let eventId,
          let targetMessageId,
          action == "add",
          data.exactString("type", aliases: "t") == "group_reaction",
          data.exactString("capability_version") == "group_reaction_v1",
          data.exactString("envelope_version") == "1",
          data.exactString("kind") == "group_offline_replay",
          data.exactString("payloadType") == "group_reaction",
          let keyEpochString = data.exactString("keyEpoch", aliases: "e"),
          let keyEpoch = Int(keyEpochString),
          keyEpoch >= 0,
          let stateId = data.exactString(
            "message_id",
            aliases: "messageId", "id", "msgId"
          ),
          let reactorPeerId = data.exactString(
            "reactor_peer_id",
            aliases: "reactorPeerId"
          ),
          let reactorTransportPeerId = data.exactString(
            "reactor_transport_peer_id",
            aliases: "reactorTransportPeerId"
          ),
          let baseEnvelopeHash = data.exactString("base_envelope_hash"),
          let notificationExtension = data.exactString(
            "notification_extension"
          ),
          let senderPublicKey = data.exactString("sender_public_key"),
          let ciphertext = data.exactString("ciphertext", aliases: "c"),
          let nonce = data.exactString("nonce", aliases: "n") else {
      return groupReactionFallback(
        groupId: groupId,
        eventId: eventId,
        reason: "group_reaction_missing_input"
      )
    }

    guard let projection = GroupReactionProjectionSnapshot(
      keyReader: keyReader
    ) else {
      return groupReactionFallback(
        groupId: groupId,
        eventId: eventId,
        reason: "group_reaction_missing_projection"
      )
    }
    guard let group = projection.groups[groupId] else {
      return groupReactionFallback(
        groupId: groupId,
        eventId: eventId,
        reason: "group_reaction_unknown_group"
      )
    }
    guard group.type == "chat" || group.type == "announcement" else {
      return groupReactionFallback(
        groupId: groupId,
        eventId: eventId,
        reason: "group_reaction_invalid_group_type"
      )
    }
    guard !group.muted else {
      return groupReactionFallback(
        groupId: groupId,
        eventId: eventId,
        reason: "group_reaction_muted"
      )
    }
    guard !group.archived else {
      return groupReactionFallback(
        groupId: groupId,
        eventId: eventId,
        reason: "group_reaction_archived"
      )
    }
    guard !group.dissolved else {
      return groupReactionFallback(
        groupId: groupId,
        eventId: eventId,
        reason: "group_reaction_dissolved"
      )
    }
    guard group.keyEpoch == keyEpoch else {
      return groupReactionFallback(
        groupId: groupId,
        eventId: eventId,
        reason: "group_reaction_key_epoch_mismatch"
      )
    }
    guard let localMember = group.members[projection.localAccountPeerId],
          localMember.deviceIds.contains(projection.localDeviceId),
          localMember.transportPeerIds.contains(
            projection.localTransportPeerId
          ) else {
      return groupReactionFallback(
        groupId: groupId,
        eventId: eventId,
        reason: "group_reaction_local_member_missing"
      )
    }
    guard reactorPeerId != projection.localAccountPeerId else {
      return groupReactionFallback(
        groupId: groupId,
        eventId: eventId,
        reason: "group_reaction_self"
      )
    }
    guard let reactor = group.members[reactorPeerId],
          reactor.transportPeerIds.contains(reactorTransportPeerId) else {
      return groupReactionFallback(
        groupId: groupId,
        eventId: eventId,
        reason: "group_reaction_actor_missing"
      )
    }
    guard let target = projection.authoredTargets[targetMessageId],
          target.groupId == groupId else {
      return groupReactionFallback(
        groupId: groupId,
        eventId: eventId,
        reason: "group_reaction_target_not_locally_authored"
      )
    }
    guard verifyGroupReactionNotificationExtension(
      notificationExtension,
      senderPublicKey: senderPublicKey,
      expectedEventId: eventId,
      expectedAction: "add",
      expectedTargetMessageId: targetMessageId,
      expectedReactorPeerId: reactorPeerId,
      expectedReactorTransportPeerId: reactorTransportPeerId,
      expectedBaseEnvelopeHash: baseEnvelopeHash,
      localTransportPeerIds: Set([projection.localTransportPeerId])
    ) else {
      return groupReactionFallback(
        groupId: groupId,
        eventId: eventId,
        reason: "group_reaction_invalid_extension"
      )
    }

    guard let groupKey = keyReader.readString(
      key: PushSharedKeyNames.groupKey(
        groupId: groupId,
        keyEpoch: keyEpoch
      )
    ) else {
      return groupReactionFallback(
        groupId: groupId,
        eventId: eventId,
        reason: "group_reaction_missing_key",
        trustedGroupName: group.name,
        trustedActorName: reactor.username
      )
    }

    do {
      let plaintext = try decryptor.decryptGroup(
        groupKey: groupKey,
        ciphertext: ciphertext,
        nonce: nonce
      )
      guard let payload = decodeJSONObject(plaintext),
            exactNonEmptyString(payload["id"]) == stateId,
            exactNonEmptyString(payload["eventId"]) == eventId,
            exactNonEmptyString(payload["messageId"]) == targetMessageId,
            exactNonEmptyString(payload["action"]) == "add",
            exactNonEmptyString(payload["senderPeerId"]) == reactorPeerId,
            let reactionTimestamp = exactISO8601Date(payload["timestamp"]),
            reactionTimestamp >= target.timestamp,
            let emoji = exactNonEmptyString(payload["emoji"]) else {
        return groupReactionFallback(
          groupId: groupId,
          eventId: eventId,
          reason: "group_reaction_parity_mismatch"
        )
      }

      let stateKey = GroupReactionProjectedStateKey(
        targetMessageId: targetMessageId,
        reactorPeerId: reactorPeerId
      )
      if let current = projection.latestReactionStates[stateKey],
         reactionTimestamp < current.authoritativeTimestamp {
        return groupReactionFallback(
          groupId: groupId,
          eventId: eventId,
          reason: "group_reaction_stale_state"
        )
      }

      let notificationIdentity = boundedReactionNotificationIdentity(
        eventId: eventId
      )
      let body = "\(reactor.username) reacted \(emoji) to your message"
      if let dedupeStore,
         !dedupeStore.claim(
           type: "message_reaction",
           messageId: notificationIdentity
         ) {
        return NotificationPreviewResult(
          title: group.name,
          body: body,
          threadIdentifier: groupId,
          didDecrypt: true,
          reason: "group_reaction_duplicate",
          suppress: true,
          markAsShown: true,
          categoryIdentifier: "MESSAGE_REACTION",
          targetContentIdentifier: notificationIdentity
        )
      }

      let tone = prepareReactionTone(
        conversationId: "group:\(groupId)",
        eventKind: "group_reaction"
      )
      emitDecryptOK(kind: "group_reaction")
      return NotificationPreviewResult(
        title: group.name,
        body: body,
        threadIdentifier: groupId,
        didDecrypt: true,
        reason: "group_reaction",
        suppress: !tone.shouldAlert,
        markAsShown: true,
        categoryIdentifier: "MESSAGE_REACTION",
        targetContentIdentifier: notificationIdentity,
        toneReservation: tone.reservation,
        recoveryIdentity: IosNotificationRecoveryIdentity(
          accountPeerId: projection.localAccountPeerId,
          lane: .group,
          conversationId: groupId,
          eventId: eventId,
          kind: .reaction
        )
      )
    } catch {
      return groupReactionFallback(
        groupId: groupId,
        eventId: eventId,
        reason: "group_reaction_decrypt_error",
        trustedGroupName: group.name,
        trustedActorName: reactor.username
      )
    }
  }

  private func groupReactionFallback(
    groupId: String?,
    eventId: String?,
    reason: String,
    trustedGroupName: String? = nil,
    trustedActorName: String? = nil,
    markAsShown: Bool = false
  ) -> NotificationPreviewResult {
    emitDecryptFail(kind: "group_reaction", reason: reason)
    let hasTrustedCopy = trustedGroupName != nil && trustedActorName != nil
    return NotificationPreviewResult(
      title: hasTrustedCopy ? trustedGroupName! : "New reaction",
      body: hasTrustedCopy
        ? "\(trustedActorName!) reacted to your message"
        : "Someone reacted to your message",
      threadIdentifier: groupId,
      didDecrypt: false,
      reason: reason,
      suppress: true,
      markAsShown: markAsShown,
      categoryIdentifier: "MESSAGE_REACTION",
      targetContentIdentifier: eventId.map {
        boundedReactionNotificationIdentity(eventId: $0)
      }
    )
  }

  private func resolveGroup(
    data: PushRouteData,
    fallbackTitle: String,
    fallbackBody: String,
    fallbackThreadIdentifier: String?
  ) -> NotificationPreviewResult {
    guard let projection = OrdinaryNotificationProjectionSnapshot(
      keyReader: keyReader,
      requiresDirectContacts: false
    ),
      let groupId = data.exactString("groupId", aliases: "group_id", "g"),
      let senderTransportPeerId = data.exactString(
        "sender_transport_peer_id"
      ),
      !data.containsAny("sender_id", "senderId", "senderPeerId", "from"),
      let group = projection.groups[groupId],
      group.type == "chat" || group.type == "announcement",
      !group.muted,
      !group.archived,
      !group.dissolved,
      let localMember = group.members[projection.localAccountPeerId],
      localMember.deviceIds.contains(projection.localDeviceId),
      localMember.transportPeerIds.contains(projection.localTransportPeerId) else {
      return suppressOrdinary(
        title: "Mknoon",
        body: "New message",
        threadIdentifier: fallbackThreadIdentifier,
        reason: "group_recipient_policy_rejected",
        eventKind: "group"
      )
    }
    let senderMatches = group.members.filter { peerId, member in
      peerId != projection.localAccountPeerId &&
        member.transportPeerIds.contains(senderTransportPeerId)
    }
    guard senderMatches.count == 1,
          let sender = senderMatches.first?.value,
          (group.type == "announcement"
            ? sender.role == "admin"
            : sender.role == "admin" || sender.role == "writer") else {
      return suppressOrdinary(
        title: group.name,
        body: "New message",
        threadIdentifier: groupId,
        reason: "group_sender_not_authorized",
        eventKind: "group"
      )
    }
    let senderPeerId = senderMatches.first!.key
    let messageId = data.exactMessageId
    if data.exactCanonicalString("preview_unavailable") == "1" {
      guard data.exactCanonicalString("type") == "group_message",
            data.exactCanonicalString("groupId") == groupId else {
        return suppressOrdinary(
          title: group.name,
          body: "New message",
          threadIdentifier: groupId,
          reason: "group_preview_unavailable_route_rejected",
          eventKind: "group"
        )
      }
      return prepareOrdinaryDisplay(
        type: "group_message",
        messageId: messageId,
        accountPeerId: projection.localAccountPeerId,
        lane: .group,
        recoveryConversationId: groupId,
        toneConversationId: "group:\(groupId)",
        title: group.name,
        body: "\(sender.username): New message",
        threadIdentifier: groupId,
        didDecrypt: false,
        reason: "group_preview_unavailable"
      )
    }

    guard let keyEpochString = data.exactString("keyEpoch", aliases: "e"),
          let keyEpoch = Int(keyEpochString),
          keyEpoch >= 0,
          keyEpoch == group.keyEpoch,
          let ciphertext = data.string("ciphertext", aliases: "c"),
          let nonce = data.string("nonce", aliases: "n") else {
      return suppressOrdinary(
        title: group.name,
        body: "New message",
        threadIdentifier: groupId,
        reason: "missing_group_decrypt_input",
        eventKind: "group",
        eventDetails: data.decryptInputPresenceDetails(
          requiredKeys: [
            ("groupId", ["g"]),
            ("keyEpoch", ["e"]),
            ("ciphertext", ["c"]),
            ("nonce", ["n"]),
          ]
        )
      )
    }
    guard let groupKey = keyReader.readString(
      key: PushSharedKeyNames.groupKey(groupId: groupId, keyEpoch: keyEpoch)
    ) else {
      return suppressOrdinary(
        title: group.name,
        body: "New message",
        threadIdentifier: groupId,
        reason: "missing_group_key",
        eventKind: "group"
      )
    }

    do {
      let plaintext = try decryptor.decryptGroup(
        groupKey: groupKey,
        ciphertext: ciphertext,
        nonce: nonce
      )
      guard let payload = decodeJSONObject(plaintext) else {
        return suppressOrdinary(
          title: group.name,
          body: "New message",
          threadIdentifier: groupId,
          reason: "invalid_group_plaintext",
          eventKind: "group"
        )
      }

      let extra = payload["extra"] as? [String: Any]
      let decodedGroupId = trimmedString(payload["groupId"])
        ?? trimmedString(payload["group_id"])
        ?? trimmedString(extra?["groupId"])
        ?? trimmedString(extra?["group_id"])
      let decodedMessageId = trimmedString(payload["messageId"])
        ?? trimmedString(payload["message_id"])
        ?? trimmedString(payload["id"])
        ?? trimmedString(extra?["messageId"])
        ?? trimmedString(extra?["message_id"])
        ?? trimmedString(extra?["id"])
      let decodedSenderPeerId = trimmedString(payload["senderPeerId"])
        ?? trimmedString(payload["senderId"])
        ?? trimmedString(payload["sender_id"])
        ?? trimmedString(extra?["senderPeerId"])
        ?? trimmedString(extra?["senderId"])
        ?? trimmedString(extra?["sender_id"])
      guard decodedGroupId == groupId,
            decodedSenderPeerId == senderPeerId,
            messageId == nil || decodedMessageId == messageId else {
        return suppressOrdinary(
          title: group.name,
          body: "New message",
          threadIdentifier: groupId,
          reason: "group_plaintext_parity_mismatch",
          eventKind: "group"
        )
      }
      if containsGroupPrivateMediaPolicyMarker(payload: payload, extra: extra) {
        emitDecryptOK(kind: "group")
        return prepareOrdinaryDisplay(
          type: "group_message",
          messageId: messageId,
          accountPeerId: projection.localAccountPeerId,
          lane: .group,
          recoveryConversationId: groupId,
          toneConversationId: "group:\(groupId)",
          title: "Mknoon",
          body: groupPrivateMediaNotificationBody(
            localeIdentifier: localeIdentifierProvider()
          ),
          threadIdentifier: groupId,
          didDecrypt: true,
          reason: "group"
        )
      }

      let text = trimmedString(payload["text"]) ?? ""
      let systemPreview = groupSystemPreviewBody(
        text: text,
        trustedMemberNames: group.members.mapValues(\.username)
      )
      let body = systemPreview ?? groupUserPreviewBody(
        text: text,
        media: payload["media"] ?? extra?["media"],
        senderUsername: sender.username
      )
      emitDecryptOK(kind: "group")
      return prepareOrdinaryDisplay(
        type: "group_message",
        messageId: messageId,
        accountPeerId: projection.localAccountPeerId,
        lane: .group,
        recoveryConversationId: groupId,
        toneConversationId: "group:\(groupId)",
        title: group.name,
        body: body,
        threadIdentifier: groupId,
        didDecrypt: true,
        reason: "group"
      )
    } catch {
      return suppressOrdinary(
        title: group.name,
        body: "New message",
        threadIdentifier: groupId,
        reason: "group_decrypt_error",
        eventKind: "group"
      )
    }
  }

  private func prepareOrdinaryDisplay(
    type: String,
    messageId: String?,
    accountPeerId: String,
    lane: IosNotificationRecoveryLane,
    recoveryConversationId: String,
    toneConversationId: String,
    title: String,
    body: String,
    threadIdentifier: String,
    didDecrypt: Bool,
    reason: String
  ) -> NotificationPreviewResult {
    if let messageId,
       let dedupeStore,
       !dedupeStore.claim(type: type, messageId: messageId) {
      return suppressOrdinary(
        title: title,
        body: body,
        threadIdentifier: threadIdentifier,
        reason: "duplicate_message"
      )
    }

    var suppress = false
    var toneReservation: PushToneReservation?
    if let reservationStore = toneLeaseStore as? PushToneReservationStoring {
      switch reservationStore.reserve(
        conversationId: toneConversationId,
        now: Date()
      ) {
      case let .reserved(reservation):
        toneReservation = reservation
      case .leaseHeld:
        suppress = true
      case .storageUnavailable:
        eventEmitter.emit(
          event: "PUSH_NSE_TONE_STORAGE_UNAVAILABLE",
          details: ["kind": pushPreviewEventKind(type: type)]
        )
      }
    } else if toneLeaseStore != nil {
      eventEmitter.emit(
        event: "PUSH_NSE_TONE_STORAGE_UNAVAILABLE",
        details: ["kind": pushPreviewEventKind(type: type)]
      )
    }

    return NotificationPreviewResult(
      title: title,
      body: body,
      threadIdentifier: threadIdentifier,
      didDecrypt: didDecrypt,
      reason: reason,
      suppress: suppress,
      markAsShown: true,
      toneReservation: toneReservation,
      recoveryIdentity: IosNotificationRecoveryIdentity(
        accountPeerId: accountPeerId,
        lane: lane,
        conversationId: recoveryConversationId,
        eventId: messageId,
        kind: .ordinary
      )
    )
  }

  private func prepareReactionTone(
    conversationId: String,
    eventKind: String
  ) -> (shouldAlert: Bool, reservation: PushToneReservation?) {
    guard let toneLeaseStore else { return (true, nil) }
    if let reservationStore = toneLeaseStore as? PushToneReservationStoring {
      switch reservationStore.reserve(
        conversationId: conversationId,
        now: Date()
      ) {
      case let .reserved(reservation):
        return (true, reservation)
      case .leaseHeld:
        return (false, nil)
      case .storageUnavailable:
        eventEmitter.emit(
          event: "PUSH_NSE_TONE_STORAGE_UNAVAILABLE",
          details: ["kind": eventKind]
        )
        return (false, nil)
      }
    }
    return (
      toneLeaseStore.acquire(conversationId: conversationId, now: Date()),
      nil
    )
  }

  private func suppressOrdinary(
    title: String,
    body: String,
    threadIdentifier: String?,
    reason: String,
    eventKind: String? = nil,
    eventDetails: [String: String] = [:]
  ) -> NotificationPreviewResult {
    return fallback(
      title: title,
      body: body,
      threadIdentifier: threadIdentifier,
      reason: reason,
      eventKind: eventKind,
      eventDetails: eventDetails,
      suppress: true
    )
  }

  private func fallback(
    title: String,
    body: String,
    threadIdentifier: String?,
    reason: String,
    eventKind: String? = nil,
    eventDetails: [String: String] = [:],
    suppress: Bool = false
  ) -> NotificationPreviewResult {
    if let eventKind {
      emitDecryptFail(kind: eventKind, reason: reason, details: eventDetails)
    }
    return NotificationPreviewResult(
      title: title,
      body: body,
      threadIdentifier: threadIdentifier,
      didDecrypt: false,
      reason: reason,
      suppress: suppress,
      markAsShown: !suppress
    )
  }

  private func emitDecryptOK(kind: String) {
    eventEmitter.emit(
      event: "PUSH_NSE_DECRYPT_OK",
      details: ["kind": kind]
    )
  }

  private func emitDecryptFail(
    kind: String,
    reason: String,
    details: [String: String] = [:]
  ) {
    var eventDetails = details
    eventDetails["kind"] = kind
    eventDetails["reason"] = reason
    eventEmitter.emit(
      event: "PUSH_NSE_DECRYPT_FAIL",
      details: eventDetails
    )
  }
}

private struct DirectReactionProjectedContact {
  let username: String
  let blocked: Bool
  let archived: Bool
}

private struct DirectContactsProjectionSnapshot {
  let localAccountPeerId: String
  let contacts: [String: DirectReactionProjectedContact]

  init?(keyReader: PushKeyReading) {
    guard let contextsJSON = keyReader.readString(
      key: PushSharedKeyNames.groupReactionContexts
    ),
      let contexts = decodeJSONObject(contextsJSON),
      exactJSONInteger(contexts["version"]) == 1,
      contexts["localAccountPeerIds"] == nil,
      let recipientAccount = exactNonEmptyString(
        contexts["localAccountPeerId"]
      ),
      let decodedContacts = Self.decodeContacts(
        keyReader.readString(key: PushSharedKeyNames.directReactionContacts)
      ),
      decodedContacts.accountPeerId == recipientAccount else {
      return nil
    }
    localAccountPeerId = recipientAccount
    contacts = decodedContacts.values
  }

  private static func decodeContacts(
    _ value: String?
  ) -> (
    accountPeerId: String,
    values: [String: DirectReactionProjectedContact]
  )? {
    guard let root = decodeJSONObject(value ?? ""),
          exactJSONInteger(root["version"]) == 1,
          root["localAccountPeerIds"] == nil,
          let accountPeerId = exactNonEmptyString(
            root["localAccountPeerId"]
          ),
          let values = root["contacts"] as? [String: Any] else {
      return nil
    }
    var result: [String: DirectReactionProjectedContact] = [:]
    for (peerId, raw) in values {
      guard exactNonEmptyString(peerId) != nil,
            let contact = raw as? [String: Any],
            let username = trimmedString(contact["username"]),
            let blocked = exactJSONBool(contact["blocked"]),
            let archived = exactJSONBool(contact["archived"]) else {
        return nil
      }
      result[peerId] = DirectReactionProjectedContact(
        username: username,
        blocked: blocked,
        archived: archived
      )
    }
    return (accountPeerId, result)
  }
}

private struct DirectReactionProjectionSnapshot {
  let localAccountPeerId: String
  let contacts: [String: DirectReactionProjectedContact]
  let authoredTargets: [String: String]

  init?(keyReader: PushKeyReading) {
    guard let contacts = DirectContactsProjectionSnapshot(
      keyReader: keyReader
    ),
      let decodedTargets = Self.decodeAuthoredTargets(
        keyReader.readString(
          key: PushSharedKeyNames.directReactionAuthoredTargets
        )
      ),
      decodedTargets.accountPeerId == contacts.localAccountPeerId else {
      return nil
    }
    localAccountPeerId = contacts.localAccountPeerId
    self.contacts = contacts.contacts
    authoredTargets = decodedTargets.values
  }

  private static func decodeAuthoredTargets(
    _ value: String?
  ) -> (accountPeerId: String, values: [String: String])? {
    guard let root = decodeJSONObject(value ?? ""),
          exactJSONInteger(root["version"]) == 1,
          root["localAccountPeerIds"] == nil,
          let accountPeerId = exactNonEmptyString(
            root["localAccountPeerId"]
          ),
          let values = root["targets"] as? [[String: Any]] else {
      return nil
    }
    var result: [String: String] = [:]
    for target in values {
      guard let id = trimmedString(target["id"]),
            result[id] == nil,
            let peerId = trimmedString(target["peerId"]) else {
        return nil
      }
      result[id] = peerId
    }
    return (accountPeerId, result)
  }
}

private struct GroupReactionProjectedMember {
  let username: String
  let role: String
  let deviceIds: Set<String>
  let transportPeerIds: Set<String>
}

private struct GroupReactionProjectedGroup {
  let name: String
  let type: String
  let muted: Bool
  let archived: Bool
  let dissolved: Bool
  let keyEpoch: Int
  let members: [String: GroupReactionProjectedMember]
}

private struct GroupReactionProjectedTarget {
  let groupId: String
  let keyEpoch: Int
  let timestamp: Date
}

private struct GroupReactionProjectedStateKey: Hashable {
  let targetMessageId: String
  let reactorPeerId: String
}

private struct GroupReactionProjectedState {
  let groupId: String
  let timestamp: Date
  let removedAt: Date?

  var authoritativeTimestamp: Date { removedAt ?? timestamp }
}

private struct OrdinaryNotificationProjectionSnapshot {
  let localAccountPeerId: String
  let localDeviceId: String
  let localTransportPeerId: String
  let contacts: [String: DirectReactionProjectedContact]
  let groups: [String: GroupReactionProjectedGroup]

  init?(
    keyReader: PushKeyReading,
    requiresDirectContacts: Bool = true
  ) {
    let direct = requiresDirectContacts
      ? DirectContactsProjectionSnapshot(keyReader: keyReader)
      : nil
    if requiresDirectContacts && direct == nil {
      return nil
    }
    guard let contextsJSON = keyReader.readString(
      key: PushSharedKeyNames.groupReactionContexts
    ),
      let contexts = decodeJSONObject(contextsJSON),
      exactJSONInteger(contexts["version"]) == 1,
      contexts["localAccountPeerIds"] == nil,
      contexts["localDeviceIds"] == nil,
      contexts["localTransportPeerIds"] == nil,
      let localAccountPeerId = exactNonEmptyString(
        contexts["localAccountPeerId"]
      ),
      let localDeviceId = exactNonEmptyString(contexts["localDeviceId"]),
      let localTransportPeerId = exactNonEmptyString(
        contexts["localTransportPeerId"]
      ),
      let rawGroups = contexts["groups"] as? [String: Any] else {
      return nil
    }
    if let direct,
       direct.localAccountPeerId != localAccountPeerId {
      return nil
    }

    var parsedGroups: [String: GroupReactionProjectedGroup] = [:]
    for (rawGroupId, rawGroup) in rawGroups {
      guard let groupId = exactNonEmptyString(rawGroupId),
            let value = rawGroup as? [String: Any],
            let name = exactNonEmptyString(value["name"]),
            let type = exactNonEmptyString(value["type"]),
            type == "chat" || type == "announcement",
            let muted = exactJSONBool(value["muted"]),
            let archived = exactJSONBool(value["archived"]),
            let dissolved = exactJSONBool(value["dissolved"]),
            let keyEpoch = exactJSONInteger(value["keyEpoch"]),
            keyEpoch >= 0,
            let rawMembers = value["members"] as? [String: Any] else {
        continue
      }
      var parsedMembers: [String: GroupReactionProjectedMember] = [:]
      for (rawPeerId, rawMember) in rawMembers {
        guard let peerId = exactNonEmptyString(rawPeerId),
              let member = rawMember as? [String: Any],
              let username = exactNonEmptyString(member["username"]),
              let role = exactNonEmptyString(member["role"]),
              role == "admin" || role == "writer" || role == "reader",
              let deviceIds = exactStringSet(
                member["deviceIds"],
                requireNonEmpty: true
              ),
              let transportPeerIds = exactStringSet(
                member["transportPeerIds"],
                requireNonEmpty: true
              ) else {
          continue
        }
        parsedMembers[peerId] = GroupReactionProjectedMember(
          username: username,
          role: role,
          deviceIds: deviceIds,
          transportPeerIds: transportPeerIds
        )
      }
      parsedGroups[groupId] = GroupReactionProjectedGroup(
        name: name,
        type: type,
        muted: muted,
        archived: archived,
        dissolved: dissolved,
        keyEpoch: keyEpoch,
        members: parsedMembers
      )
    }

    self.localAccountPeerId = localAccountPeerId
    self.localDeviceId = localDeviceId
    self.localTransportPeerId = localTransportPeerId
    contacts = direct?.contacts ?? [:]
    groups = parsedGroups
  }
}

private struct GroupReactionProjectionSnapshot {
  let localAccountPeerId: String
  let localDeviceId: String
  let localTransportPeerId: String
  let groups: [String: GroupReactionProjectedGroup]
  let authoredTargets: [String: GroupReactionProjectedTarget]
  let latestReactionStates:
    [GroupReactionProjectedStateKey: GroupReactionProjectedState]

  init?(keyReader: PushKeyReading) {
    guard let contextsJSON = keyReader.readString(
      key: PushSharedKeyNames.groupReactionContexts
    ),
      let targetsJSON = keyReader.readString(
        key: PushSharedKeyNames.groupReactionAuthoredTargets
      ),
      let statesJSON = keyReader.readString(
        key: PushSharedKeyNames.groupReactionLatestStates
      ),
      let contexts = decodeJSONObject(contextsJSON),
      let targets = decodeJSONObject(targetsJSON),
      let states = decodeJSONObject(statesJSON),
      exactJSONInteger(contexts["version"]) == 1,
      exactJSONInteger(targets["version"]) == 1,
      exactJSONInteger(states["version"]) == 1,
      let contextsAccount = exactNonEmptyString(
        contexts["localAccountPeerId"]
      ),
      let targetsAccount = exactNonEmptyString(
        targets["localAccountPeerId"]
      ),
      let statesAccount = exactNonEmptyString(
        states["localAccountPeerId"]
      ),
      contextsAccount == targetsAccount,
      contextsAccount == statesAccount,
      let localDeviceId = exactNonEmptyString(contexts["localDeviceId"]),
      let localTransportPeerId = exactNonEmptyString(
        contexts["localTransportPeerId"]
      ),
      let rawGroups = contexts["groups"] as? [String: Any],
      let rawTargets = targets["targets"] as? [[String: Any]],
      let rawStates = states["states"] as? [[String: Any]] else {
      return nil
    }

    var parsedGroups: [String: GroupReactionProjectedGroup] = [:]
    for (rawGroupId, rawGroup) in rawGroups {
      guard let groupId = exactNonEmptyString(rawGroupId),
            let value = rawGroup as? [String: Any],
            let name = exactNonEmptyString(value["name"]),
            let type = exactNonEmptyString(value["type"]),
            let muted = exactJSONBool(value["muted"]),
            let archived = exactJSONBool(value["archived"]),
            let dissolved = exactJSONBool(value["dissolved"]),
            let keyEpoch = exactJSONInteger(value["keyEpoch"]),
            keyEpoch >= 0,
            let rawMembers = value["members"] as? [String: Any] else {
        continue
      }
      var parsedMembers: [String: GroupReactionProjectedMember] = [:]
      for (rawPeerId, rawMember) in rawMembers {
        guard let peerId = exactNonEmptyString(rawPeerId),
              let member = rawMember as? [String: Any],
              let username = exactNonEmptyString(member["username"]),
              let role = exactNonEmptyString(member["role"]),
              role == "admin" || role == "writer" || role == "reader",
              let deviceIds = exactStringSet(
                member["deviceIds"],
                requireNonEmpty: true
              ),
              let transportPeerIds = exactStringSet(
                member["transportPeerIds"],
                requireNonEmpty: true
              ) else {
          continue
        }
        parsedMembers[peerId] = GroupReactionProjectedMember(
          username: username,
          role: role,
          deviceIds: deviceIds,
          transportPeerIds: transportPeerIds
        )
      }
      parsedGroups[groupId] = GroupReactionProjectedGroup(
        name: name,
        type: type,
        muted: muted,
        archived: archived,
        dissolved: dissolved,
        keyEpoch: keyEpoch,
        members: parsedMembers
      )
    }

    var parsedTargets: [String: GroupReactionProjectedTarget] = [:]
    for value in rawTargets {
      guard let id = exactNonEmptyString(value["id"]),
            parsedTargets[id] == nil,
            let groupId = exactNonEmptyString(value["groupId"]),
            let keyEpoch = exactJSONInteger(value["keyEpoch"]),
            keyEpoch >= 0,
            let timestamp = exactISO8601Date(value["timestamp"]) else {
        continue
      }
      parsedTargets[id] = GroupReactionProjectedTarget(
        groupId: groupId,
        keyEpoch: keyEpoch,
        timestamp: timestamp
      )
    }

    var parsedStates:
      [GroupReactionProjectedStateKey: GroupReactionProjectedState] = [:]
    for value in rawStates {
      guard let groupId = exactNonEmptyString(value["groupId"]),
            let targetMessageId = exactNonEmptyString(
              value["targetMessageId"]
            ),
            let reactorPeerId = exactNonEmptyString(value["reactorPeerId"]),
            let timestamp = exactISO8601Date(value["timestamp"]),
            let target = parsedTargets[targetMessageId],
            target.groupId == groupId else {
        continue
      }
      let removedAt: Date?
      if value["removedAt"] == nil {
        removedAt = nil
      } else if let parsed = exactISO8601Date(value["removedAt"]) {
        removedAt = parsed
      } else {
        continue
      }
      let key = GroupReactionProjectedStateKey(
        targetMessageId: targetMessageId,
        reactorPeerId: reactorPeerId
      )
      guard parsedStates[key] == nil else { return nil }
      parsedStates[key] = GroupReactionProjectedState(
        groupId: groupId,
        timestamp: timestamp,
        removedAt: removedAt
      )
    }

    localAccountPeerId = contextsAccount
    self.localDeviceId = localDeviceId
    self.localTransportPeerId = localTransportPeerId
    groups = parsedGroups
    authoredTargets = parsedTargets
    latestReactionStates = parsedStates
  }
}

private func verifyGroupReactionNotificationExtension(
  _ encodedExtension: String,
  senderPublicKey: String,
  expectedEventId: String,
  expectedAction: String,
  expectedTargetMessageId: String,
  expectedReactorPeerId: String,
  expectedReactorTransportPeerId: String,
  expectedBaseEnvelopeHash: String,
  localTransportPeerIds: Set<String>
) -> Bool {
  let expectedExtensionKeys = Set([
    "version",
    "transitionId",
    "action",
    "targetMessageId",
    "reactorPeerId",
    "reactorTransportPeerId",
    "replayRecipientSetHash",
    "notificationRecipientTransportPeerIds",
    "baseEnvelopeHash",
    "signatureAlgorithm",
    "signedPayload",
    "signature",
  ])
  guard isLowercaseSHA256Hex(expectedBaseEnvelopeHash),
        let value = decodeJSONObject(encodedExtension),
        canonicalJSONString(value) == encodedExtension,
        Set(value.keys) == expectedExtensionKeys,
        exactJSONInteger(value["version"]) == 1,
        exactNonEmptyString(value["transitionId"]) == expectedEventId,
        exactNonEmptyString(value["action"]) == expectedAction,
        exactNonEmptyString(value["targetMessageId"]) ==
          expectedTargetMessageId,
        exactNonEmptyString(value["reactorPeerId"]) ==
          expectedReactorPeerId,
        exactNonEmptyString(value["reactorTransportPeerId"]) ==
          expectedReactorTransportPeerId,
        let replayRecipientSetHash = exactNonEmptyString(
          value["replayRecipientSetHash"]
        ),
        isLowercaseSHA256Hex(replayRecipientSetHash),
        exactNonEmptyString(value["baseEnvelopeHash"]) ==
          expectedBaseEnvelopeHash,
        exactNonEmptyString(value["signatureAlgorithm"]) == "ed25519",
        let notificationRecipients = exactCanonicalStringArray(
          value["notificationRecipientTransportPeerIds"]
        ),
        !Set(notificationRecipients).isDisjoint(with: localTransportPeerIds),
        let signedPayload = exactNonEmptyString(value["signedPayload"]),
        let signatureBase64 = exactNonEmptyString(value["signature"]),
        let signed = decodeJSONObject(signedPayload) else {
    return false
  }

  let expectedSignedKeys = Set([
    "kind",
    "version",
    "transitionId",
    "action",
    "targetMessageId",
    "reactorPeerId",
    "reactorTransportPeerId",
    "replayRecipientSetHash",
    "notificationRecipientTransportPeerIds",
    "baseEnvelopeHash",
  ])
  guard Set(signed.keys) == expectedSignedKeys,
        exactNonEmptyString(signed["kind"]) ==
          "group_reaction_notification",
        exactJSONInteger(signed["version"]) == 1,
        exactNonEmptyString(signed["transitionId"]) == expectedEventId,
        exactNonEmptyString(signed["action"]) == expectedAction,
        exactNonEmptyString(signed["targetMessageId"]) ==
          expectedTargetMessageId,
        exactNonEmptyString(signed["reactorPeerId"]) ==
          expectedReactorPeerId,
        exactNonEmptyString(signed["reactorTransportPeerId"]) ==
          expectedReactorTransportPeerId,
        exactNonEmptyString(signed["replayRecipientSetHash"]) ==
          replayRecipientSetHash,
        exactNonEmptyString(signed["baseEnvelopeHash"]) ==
          expectedBaseEnvelopeHash,
        exactCanonicalStringArray(
          signed["notificationRecipientTransportPeerIds"]
        ) == notificationRecipients else {
    return false
  }

  let canonicalSignedPayload: [String: Any] = [
    "kind": "group_reaction_notification",
    "version": 1,
    "transitionId": expectedEventId,
    "action": expectedAction,
    "targetMessageId": expectedTargetMessageId,
    "reactorPeerId": expectedReactorPeerId,
    "reactorTransportPeerId": expectedReactorTransportPeerId,
    "replayRecipientSetHash": replayRecipientSetHash,
    "notificationRecipientTransportPeerIds": notificationRecipients,
    "baseEnvelopeHash": expectedBaseEnvelopeHash,
  ]
  guard canonicalJSONString(canonicalSignedPayload) == signedPayload,
        let publicKeyData = Data(base64Encoded: senderPublicKey),
        publicKeyData.count == 32,
        let signatureData = Data(base64Encoded: signatureBase64),
        signatureData.count == 64,
        let publicKey = try? Curve25519.Signing.PublicKey(
          rawRepresentation: publicKeyData
        ) else {
    return false
  }
  return publicKey.isValidSignature(
    signatureData,
    for: Data(signedPayload.utf8)
  )
}

private func exactCanonicalStringArray(_ value: Any?) -> [String]? {
  guard let values = value as? [Any] else { return nil }
  let strings = values.compactMap(exactNonEmptyString)
  guard strings.count == values.count,
        Set(strings).count == strings.count,
        strings == strings.sorted() else {
    return nil
  }
  return strings
}

private func exactStringSet(
  _ value: Any?,
  requireNonEmpty: Bool
) -> Set<String>? {
  guard let values = value as? [Any] else { return nil }
  let strings = values.compactMap(exactNonEmptyString)
  guard strings.count == values.count,
        Set(strings).count == strings.count,
        !requireNonEmpty || !strings.isEmpty else {
    return nil
  }
  return Set(strings)
}

private func exactJSONInteger(_ value: Any?) -> Int? {
  guard let number = value as? NSNumber,
        CFGetTypeID(number) != CFBooleanGetTypeID(),
        number.doubleValue.isFinite,
        number.doubleValue.rounded(.towardZero) == number.doubleValue,
        number.doubleValue >= Double(Int.min),
        number.doubleValue <= Double(Int.max) else {
    return nil
  }
  return number.intValue
}

private func exactJSONBool(_ value: Any?) -> Bool? {
  guard let number = value as? NSNumber,
        CFGetTypeID(number) == CFBooleanGetTypeID() else {
    return nil
  }
  return number.boolValue
}

private func exactISO8601Date(_ value: Any?) -> Date? {
  guard let encoded = exactNonEmptyString(value) else { return nil }
  let fractional = ISO8601DateFormatter()
  fractional.formatOptions = [
    .withInternetDateTime,
    .withFractionalSeconds,
  ]
  if let date = fractional.date(from: encoded) {
    return date
  }
  let standard = ISO8601DateFormatter()
  standard.formatOptions = [.withInternetDateTime]
  return standard.date(from: encoded)
}

private func isLowercaseSHA256Hex(_ value: String) -> Bool {
  value.utf8.count == 64 && value.utf8.allSatisfy { byte in
    (48...57).contains(byte) || (97...102).contains(byte)
  }
}

private func canonicalJSONString(_ value: Any) -> String? {
  guard let data = try? JSONSerialization.data(
    withJSONObject: value,
    options: [.sortedKeys, .withoutEscapingSlashes]
  ) else {
    return nil
  }
  return String(data: data, encoding: .utf8)
}

/// Cross-language APNs request/collapse identity. Keep this byte-for-byte in
/// sync with Dart/Go and test_fixtures/si5_dedupe_keys.json.
func boundedReactionNotificationIdentity(eventId: String) -> String {
  let digest = SHA256.hash(data: Data(eventId.utf8))
    .map { String(format: "%02x", $0) }
    .joined()
  return "reaction:\(digest.prefix(48))"
}

final class KeychainPushKeyReader: PushKeyReading {
  private let service: String
  private let accessGroup: String?

  init(
    service: String = mknoonFlutterSecureStorageService,
    accessGroup: String? = mknoonSharedKeychainAccessGroupIdentifier
  ) {
    self.service = service
    self.accessGroup = accessGroup
  }

  func readQuery(key: String) -> [String: Any] {
    var query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrAccount as String: key,
      kSecAttrService as String: service,
      kSecReturnData as String: true,
      kSecMatchLimit as String: kSecMatchLimitOne,
    ]
    if let accessGroup {
      query[kSecAttrAccessGroup as String] = accessGroup
    }
    return query
  }

  func readString(key: String) -> String? {
    let query = readQuery(key: key)
    var item: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &item)
    guard status == errSecSuccess, let data = item as? Data else {
      return nil
    }
    return String(data: data, encoding: .utf8)
  }
}

final class AppGroupPushDedupeStore: PushDedupeStoring {
  private let directory: URL
  private let maxEntries: Int
  private let ttlSeconds: TimeInterval

  init?(
    appGroupIdentifier: String = mknoonSharedAppGroupIdentifier,
    maxEntries: Int = 256,
    ttlSeconds: TimeInterval = 48 * 60 * 60
  ) {
    guard let containerURL = FileManager.default.containerURL(
      forSecurityApplicationGroupIdentifier: appGroupIdentifier
    ) else {
      return nil
    }
    directory = containerURL.appendingPathComponent(
      "NotificationServiceDedupe",
      isDirectory: true
    )
    try? FileManager.default.createDirectory(
      at: directory,
      withIntermediateDirectories: true
    )
    self.maxEntries = maxEntries
    self.ttlSeconds = ttlSeconds
  }

  /// Test seam: inject the dedupe directory directly so the O_EXCL first-wins/
  /// second-loses claim() semantics are exercisable on a real filesystem without
  /// a real app-group container.
  init(
    directory: URL,
    maxEntries: Int = 256,
    ttlSeconds: TimeInterval = 48 * 60 * 60
  ) {
    self.directory = directory
    self.maxEntries = maxEntries
    self.ttlSeconds = ttlSeconds
    try? FileManager.default.createDirectory(
      at: directory,
      withIntermediateDirectories: true
    )
  }

  func claim(type: String, messageId: String) -> Bool {
    let lockPath = directory
      .deletingLastPathComponent()
      .appendingPathComponent(".\(directory.lastPathComponent).lock")
      .path
    let lockFD = open(lockPath, O_RDWR | O_CREAT, S_IRUSR | S_IWUSR)
    guard lockFD >= 0 else { return false }
    defer {
      flock(lockFD, LOCK_UN)
      close(lockFD)
    }
    guard flock(lockFD, LOCK_EX) == 0 else { return false }

    prune()
    let name = "\(safeFileComponent(type))-\(safeFileComponent(messageId))"
    let fileURL = directory.appendingPathComponent(name)
    let path = fileURL.path
    let fd = open(path, O_WRONLY | O_CREAT | O_EXCL, S_IRUSR | S_IWUSR)
    guard fd >= 0 else {
      return false
    }
    close(fd)
    prune(protecting: fileURL)
    return true
  }

  private func prune(protecting protectedURL: URL? = nil) {
    let files = (try? FileManager.default.contentsOfDirectory(
      at: directory,
      includingPropertiesForKeys: [.contentModificationDateKey],
      options: [.skipsHiddenFiles]
    )) ?? []
    let now = Date()
    var retained: [(url: URL, modified: Date)] = []
    for file in files {
      let modified = (
        try? file.resourceValues(forKeys: [.contentModificationDateKey])
      )?.contentModificationDate ?? now
      if now.timeIntervalSince(modified) > ttlSeconds {
        try? FileManager.default.removeItem(at: file)
      } else {
        retained.append((file, modified))
      }
    }
    let overflow = retained.count - maxEntries
    if overflow > 0 {
      let removalCandidates = retained
        .filter { item in item.url != protectedURL }
        .sorted(by: { left, right in
          if left.modified != right.modified {
            return left.modified < right.modified
          }
          return left.url.lastPathComponent < right.url.lastPathComponent
        })
        .prefix(overflow)
      for item in removalCandidates {
        try? FileManager.default.removeItem(at: item.url)
      }
    }
  }

  private func safeFileComponent(_ value: String) -> String {
    let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
    return value.unicodeScalars.map { scalar in
      allowed.contains(scalar) ? String(scalar) : "_"
    }.joined()
  }
}

final class AppGroupNotificationToneLeaseStore:
  PushToneLeaseStoring,
  PushToneReservationStoring {
  // Keep in-process callbacks ordered too; `flock` below is the matching
  // cross-isolate/cross-process protocol shared with Dart.
  private static let processLock = NSLock()
  private let directory: URL
  private let leaseSeconds: TimeInterval
  private let maxEntries: Int
  private let ttlSeconds: TimeInterval

  init?(
    appGroupIdentifier: String = mknoonSharedAppGroupIdentifier,
    leaseSeconds: TimeInterval = 30,
    maxEntries: Int = 256,
    ttlSeconds: TimeInterval = 48 * 60 * 60
  ) {
    guard let containerURL = FileManager.default.containerURL(
      forSecurityApplicationGroupIdentifier: appGroupIdentifier
    ) else {
      return nil
    }
    directory = containerURL.appendingPathComponent(
      "NotificationToneLeases",
      isDirectory: true
    )
    self.leaseSeconds = leaseSeconds
    self.maxEntries = maxEntries
    self.ttlSeconds = ttlSeconds
    try? FileManager.default.createDirectory(
      at: directory,
      withIntermediateDirectories: true
    )
  }

  init(
    directory: URL,
    leaseSeconds: TimeInterval = 30,
    maxEntries: Int = 256,
    ttlSeconds: TimeInterval = 48 * 60 * 60
  ) {
    self.directory = directory
    self.leaseSeconds = leaseSeconds
    self.maxEntries = maxEntries
    self.ttlSeconds = ttlSeconds
    try? FileManager.default.createDirectory(
      at: directory,
      withIntermediateDirectories: true
    )
  }

  func acquire(conversationId: String, now: Date) -> Bool {
    switch reserve(conversationId: conversationId, now: now) {
    case let .reserved(reservation):
      return reservation.commit(now: now)
    case .leaseHeld, .storageUnavailable:
      return false
    }
  }

  func reserve(
    conversationId: String,
    now: Date
  ) -> PushToneReservationOutcome {
    Self.processLock.lock()
    defer { Self.processLock.unlock() }

    let coordinationPath = directory.appendingPathComponent(".coordination.lock").path
    let coordinationFd = open(
      coordinationPath,
      O_RDWR | O_CREAT,
      S_IRUSR | S_IWUSR
    )
    guard coordinationFd >= 0 else { return .storageUnavailable }
    guard flock(coordinationFd, LOCK_EX) == 0 else {
      close(coordinationFd)
      return .storageUnavailable
    }
    defer {
      _ = flock(coordinationFd, LOCK_UN)
      close(coordinationFd)
    }

    let normalizedConversationId = conversationId.trimmingCharacters(
      in: .whitespacesAndNewlines
    )
    guard !normalizedConversationId.isEmpty else {
      return .storageUnavailable
    }
    prune(now: now)
    let identity = SHA256.hash(data: Data(normalizedConversationId.utf8))
      .map { String(format: "%02x", $0) }
      .joined()
    let leaseURL = directory.appendingPathComponent("\(identity).lease")
    let pendingURL = directory.appendingPathComponent(".\(identity).pending-tone")
    let nowMs = Int64((now.timeIntervalSince1970 * 1000).rounded(.down))

    do {
      if FileManager.default.fileExists(atPath: pendingURL.path) {
        if let record = readToneReservationRecord(pendingURL) {
          if record.state == "committed", let committedAtMs = record.committedAtMs {
            let currentMs = readToneTimestampMs(leaseURL)
            if currentMs == nil ||
              currentMs == record.reservedAtMs ||
              currentMs == committedAtMs {
              try writeToneTimestampMs(committedAtMs, to: leaseURL)
            }
            try? FileManager.default.removeItem(at: pendingURL)
          } else if record.state == "pending" {
            let leaseMatches = readToneTimestampMs(leaseURL) == record.reservedAtMs
            if !leaseMatches {
              try? FileManager.default.removeItem(at: pendingURL)
            } else if nowMs - record.createdAtMs < 60_000 {
              return .leaseHeld
            } else {
              try? FileManager.default.removeItem(at: leaseURL)
              try? FileManager.default.removeItem(at: pendingURL)
            }
          } else {
            try? FileManager.default.removeItem(at: pendingURL)
          }
        } else {
          try? FileManager.default.removeItem(at: pendingURL)
        }
      }

      if let previousMs = readToneTimestampMs(leaseURL),
         nowMs - previousMs < Int64(leaseSeconds * 1000) {
        return .leaseHeld
      }

      let token = UUID().uuidString.lowercased()
      try writeToneReservationRecord(
        ToneReservationRecord(
          state: "pending",
          token: token,
          reservedAtMs: nowMs,
          createdAtMs: nowMs,
          committedAtMs: nil
        ),
        to: pendingURL
      )
      do {
        try writeToneTimestampMs(nowMs, to: leaseURL)
      } catch {
        try? FileManager.default.removeItem(at: pendingURL)
        throw error
      }
      prune(now: now)
      return .reserved(
        AppGroupNotificationToneReservation(
          store: self,
          token: token,
          reservedAtMs: nowMs,
          leaseURL: leaseURL,
          pendingURL: pendingURL
        )
      )
    } catch {
      return .storageUnavailable
    }
  }

  fileprivate func commit(
    reservation: AppGroupNotificationToneReservation,
    now: Date
  ) -> Bool {
    return mutateReservation(reservation) { record in
      let committedAtMs = Int64((now.timeIntervalSince1970 * 1000).rounded(.down))
      do {
        try writeToneReservationRecord(
          ToneReservationRecord(
            state: "committed",
            token: reservation.token,
            reservedAtMs: reservation.reservedAtMs,
            createdAtMs: record.createdAtMs,
            committedAtMs: committedAtMs
          ),
          to: reservation.pendingURL
        )
        try writeToneTimestampMs(committedAtMs, to: reservation.leaseURL)
        try FileManager.default.removeItem(at: reservation.pendingURL)
        prune(now: now)
        return true
      } catch {
        return false
      }
    }
  }

  fileprivate func release(
    reservation: AppGroupNotificationToneReservation
  ) -> Bool {
    return mutateReservation(reservation) { _ in
      let leaseMatches = readToneTimestampMs(reservation.leaseURL)
        == reservation.reservedAtMs
      if leaseMatches {
        try? FileManager.default.removeItem(at: reservation.leaseURL)
      }
      try? FileManager.default.removeItem(at: reservation.pendingURL)
      return leaseMatches &&
        !FileManager.default.fileExists(atPath: reservation.leaseURL.path) &&
        !FileManager.default.fileExists(atPath: reservation.pendingURL.path)
    }
  }

  private func mutateReservation(
    _ reservation: AppGroupNotificationToneReservation,
    mutation: (ToneReservationRecord) -> Bool
  ) -> Bool {
    Self.processLock.lock()
    defer { Self.processLock.unlock() }
    let coordinationPath = directory.appendingPathComponent(".coordination.lock").path
    let coordinationFd = open(
      coordinationPath,
      O_RDWR | O_CREAT,
      S_IRUSR | S_IWUSR
    )
    guard coordinationFd >= 0 else { return false }
    guard flock(coordinationFd, LOCK_EX) == 0 else {
      close(coordinationFd)
      return false
    }
    defer {
      _ = flock(coordinationFd, LOCK_UN)
      close(coordinationFd)
    }
    guard let record = readToneReservationRecord(reservation.pendingURL),
          record.state == "pending",
          record.token == reservation.token,
          record.reservedAtMs == reservation.reservedAtMs,
          readToneTimestampMs(reservation.leaseURL) == reservation.reservedAtMs else {
      return false
    }
    return mutation(record)
  }

  private struct ToneReservationRecord {
    let state: String
    let token: String
    let reservedAtMs: Int64
    let createdAtMs: Int64
    let committedAtMs: Int64?
  }

  private func readToneReservationRecord(_ url: URL) -> ToneReservationRecord? {
    guard let data = try? Data(contentsOf: url),
          let value = try? JSONSerialization.jsonObject(with: data),
          let object = value as? [String: Any],
          let state = object["state"] as? String,
          let token = object["token"] as? String,
          !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
          let reservedAt = exactJSONInteger(object["reservedAtMs"]),
          let createdAt = exactJSONInteger(object["createdAtMs"]) else {
      return nil
    }
    let committedAt: Int?
    if object["committedAtMs"] == nil {
      committedAt = nil
    } else {
      guard let parsed = exactJSONInteger(object["committedAtMs"]) else {
        return nil
      }
      committedAt = parsed
    }
    return ToneReservationRecord(
      state: state,
      token: token,
      reservedAtMs: Int64(reservedAt),
      createdAtMs: Int64(createdAt),
      committedAtMs: committedAt.map(Int64.init)
    )
  }

  private func writeToneReservationRecord(
    _ record: ToneReservationRecord,
    to url: URL
  ) throws {
    var object: [String: Any] = [
      "state": record.state,
      "token": record.token,
      "reservedAtMs": record.reservedAtMs,
      "createdAtMs": record.createdAtMs,
    ]
    if let committedAtMs = record.committedAtMs {
      object["committedAtMs"] = committedAtMs
    }
    let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    try data.write(to: url, options: [.atomic])
  }

  private func readToneTimestampMs(_ url: URL) -> Int64? {
    guard let value = try? String(contentsOf: url, encoding: .utf8),
          let seconds = TimeInterval(value.trimmingCharacters(in: .whitespacesAndNewlines)) else {
      return nil
    }
    return Int64((seconds * 1000).rounded())
  }

  private func writeToneTimestampMs(_ milliseconds: Int64, to url: URL) throws {
    let seconds = Double(milliseconds) / 1000
    try String(format: "%.3f", seconds).write(
      to: url,
      atomically: true,
      encoding: .utf8
    )
    try FileManager.default.setAttributes(
      [.modificationDate: Date(timeIntervalSince1970: seconds)],
      ofItemAtPath: url.path
    )
  }

  private func prune(now: Date) {
    let files = (try? FileManager.default.contentsOfDirectory(
      at: directory,
      includingPropertiesForKeys: [.contentModificationDateKey],
      options: [.skipsHiddenFiles]
    )) ?? []
    var retained: [(url: URL, modified: Date)] = []
    for file in files where file.pathExtension == "lease" {
      let modified = (
        try? file.resourceValues(forKeys: [.contentModificationDateKey])
      )?.contentModificationDate ?? now
      if now.timeIntervalSince(modified) > ttlSeconds {
        try? FileManager.default.removeItem(at: file)
      } else {
        retained.append((file, modified))
      }
    }
    let overflow = retained.count - maxEntries
    if overflow > 0 {
      for item in retained
        .sorted(by: { $0.modified < $1.modified })
        .prefix(overflow) {
        try? FileManager.default.removeItem(at: item.url)
      }
    }
  }
}

final class AppGroupNotificationToneReservation: PushToneReservation {
  fileprivate weak var store: AppGroupNotificationToneLeaseStore?
  fileprivate let token: String
  fileprivate let reservedAtMs: Int64
  fileprivate let leaseURL: URL
  fileprivate let pendingURL: URL

  fileprivate init(
    store: AppGroupNotificationToneLeaseStore,
    token: String,
    reservedAtMs: Int64,
    leaseURL: URL,
    pendingURL: URL
  ) {
    self.store = store
    self.token = token
    self.reservedAtMs = reservedAtMs
    self.leaseURL = leaseURL
    self.pendingURL = pendingURL
  }

  func commit(now: Date) -> Bool {
    return store?.commit(reservation: self, now: now) ?? false
  }

  func release() -> Bool {
    return store?.release(reservation: self) ?? false
  }
}

final class AppGroupPushEnvelopeStore {
  private let directory: URL?
  private let maxEntries: Int
  private let ttlSeconds: TimeInterval

  init?(
    appGroupIdentifier: String = mknoonSharedAppGroupIdentifier,
    maxEntries: Int = 64,
    ttlSeconds: TimeInterval = 48 * 60 * 60
  ) {
    guard let containerURL = FileManager.default.containerURL(
      forSecurityApplicationGroupIdentifier: appGroupIdentifier
    ) else {
      return nil
    }
    let dir = containerURL.appendingPathComponent(
      "PushEnvelopeStaging",
      isDirectory: true
    )
    try? FileManager.default.createDirectory(
      at: dir,
      withIntermediateDirectories: true
    )
    directory = dir
    self.maxEntries = maxEntries
    self.ttlSeconds = ttlSeconds
  }

  init(directory: URL, maxEntries: Int = 64, ttlSeconds: TimeInterval = 48 * 60 * 60) {
    try? FileManager.default.createDirectory(
      at: directory,
      withIntermediateDirectories: true
    )
    self.directory = directory
    self.maxEntries = maxEntries
    self.ttlSeconds = ttlSeconds
  }

  @discardableResult
  func stage(userInfo: [AnyHashable: Any]) -> Bool {
    guard let directory,
          let envelope = Self.envelope(userInfo: userInfo) else {
      return false
    }
    let fileURL = directory.appendingPathComponent(
      Self.fileName(forNonce: envelope.nonce)
    )
    do {
      let data = try JSONSerialization.data(
        withJSONObject: envelope.json,
        options: [.sortedKeys]
      )
      try data.write(to: fileURL, options: [.atomic])
      prune()
      return true
    } catch {
      return false
    }
  }

  @discardableResult
  func clear(nonce: String) -> Bool {
    guard let directory else {
      return false
    }
    let fileURL = directory.appendingPathComponent(
      Self.fileName(forNonce: nonce)
    )
    do {
      try FileManager.default.removeItem(at: fileURL)
      return true
    } catch {
      return !FileManager.default.fileExists(atPath: fileURL.path)
    }
  }

  private func prune() {
    guard let directory else {
      return
    }
    let files = (try? FileManager.default.contentsOfDirectory(
      at: directory,
      includingPropertiesForKeys: [.contentModificationDateKey],
      options: [.skipsHiddenFiles]
    )) ?? []
    let now = Date()
    var jsonFiles: [(url: URL, modified: Date)] = []
    for file in files where file.pathExtension == "json" {
      let modified = (
        try? file.resourceValues(forKeys: [.contentModificationDateKey])
      )?.contentModificationDate ?? now
      if now.timeIntervalSince(modified) > ttlSeconds {
        try? FileManager.default.removeItem(at: file)
      } else {
        jsonFiles.append((file, modified))
      }
    }
    let overflow = jsonFiles.count - maxEntries
    if overflow > 0 {
      for file in jsonFiles.sorted(by: { $0.modified < $1.modified }).prefix(overflow) {
        try? FileManager.default.removeItem(at: file.url)
      }
    }
  }

  private static func envelope(userInfo: [AnyHashable: Any]) -> (
    nonce: String,
    json: [String: Any]
  )? {
    let data = PushRouteData(userInfo: userInfo)
    guard let type = data.string("type", aliases: "t"),
          let senderPeerId = data.string("sender_id", aliases: "from", "s"),
          let kem = data.string("kem", aliases: "k"),
          let ciphertext = data.string("ciphertext", aliases: "c"),
          let nonce = data.string("nonce", aliases: "n") else {
      return nil
    }
    if type == "message_reaction" {
      guard let eventId = data.string(
        "event_id",
        aliases: "reaction_id", "r"
      ),
        let targetMessageId = data.string(
          "target_message_id",
          aliases: "targetMessageId", "target_id"
        ),
        data.string("action", aliases: "a") == "add" else {
        return nil
      }
      return (
        nonce,
        [
          "kind": "reaction",
          "eventId": eventId,
          "targetMessageId": targetMessageId,
          "action": "add",
          "kem": kem,
          "ciphertext": ciphertext,
          "nonce": nonce,
          "senderPeerId": senderPeerId,
          "receivedAtMs": Int64(Date().timeIntervalSince1970 * 1000),
        ]
      )
    }
    guard type == "new_message" else { return nil }
    let messageId = data.string(
      "message_id",
      aliases: "messageId", "id", "msgId"
    )
    var json: [String: Any] = [
      "kind": "chat",
      "kem": kem,
      "ciphertext": ciphertext,
      "nonce": nonce,
      "senderPeerId": senderPeerId,
      "receivedAtMs": Int64(Date().timeIntervalSince1970 * 1000),
    ]
    json["messageId"] = messageId ?? NSNull()
    return (nonce, json)
  }

  static func fileName(forNonce nonce: String) -> String {
    let hex = nonce.utf8.map { byte in
      String(format: "%02x", byte)
    }.joined()
    return "nonce-v1-\(hex).json"
  }
}

// 04-P0 SI-5: the NSE drops a per-message "already shown" marker into the SHARED
// app-group container so the Dart RecentRemoteNotificationGate can suppress a
// duplicate Dart-side banner even when iOS never schedules the Dart isolate.
// The marker filename is sha256 hex of the EXACT Dart gate message key, so the
// two processes name the same file for the same push. Locked by the SI-5
// contract test.
final class RecentRemoteShownMarkerStore {
  private let directory: URL?

  init?(appGroupIdentifier: String = mknoonSharedAppGroupIdentifier) {
    guard let containerURL = FileManager.default.containerURL(
      forSecurityApplicationGroupIdentifier: appGroupIdentifier
    ) else {
      return nil
    }
    let dir = containerURL.appendingPathComponent(
      "RecentRemoteShown",
      isDirectory: true
    )
    try? FileManager.default.createDirectory(
      at: dir,
      withIntermediateDirectories: true
    )
    directory = dir
  }

  /// Test seam: inject the marker directory directly (no real app-group needed).
  init(directory: URL) {
    try? FileManager.default.createDirectory(
      at: directory,
      withIntermediateDirectories: true
    )
    self.directory = directory
  }

  /// The EXACT Dart `RecentRemoteNotificationGate` message key for this push, or
  /// nil if it is not a message-aware target. Mirrors Dart
  /// `NotificationRouteTarget.fromRemoteMessageData` + `.toPayload`, then the
  /// gate's `_messageKey('message:<payload>|<messageId>')`.
  /// NOTE: deliberately does NOT use `PushRouteData.messageId` (that accepts the
  /// `m` alias Dart's `messageIdFromRemoteMessageData` does not) so the key
  /// matches Dart byte-for-byte.
  static func gateMessageKey(userInfo: [AnyHashable: Any]) -> String? {
    let data = PushRouteData(userInfo: userInfo)
    switch data.string("type") {
    case "group_message":
      guard let messageId = data.string(
        "message_id",
        aliases: "messageId", "id", "msgId"
      ) else {
        return nil
      }
      guard let groupId = data.string(
        "groupId",
        aliases: "group_id", "gid", "conversation_id"
      ) else {
        return nil
      }
      // Dart group toPayload (with messageId) = 'group:<gid>|message:<id>'.
      return "message:group:\(groupId)|message:\(messageId)|\(messageId)"
    case "new_message":
      guard let messageId = data.string(
        "message_id",
        aliases: "messageId", "id", "msgId"
      ) else {
        return nil
      }
      guard let peerId = data.string("sender_id", aliases: "from") else {
        return nil
      }
      return "message:\(peerId)|\(messageId)"
    case "group_reaction":
      guard data.exactString("action") == "add",
            let groupId = data.exactString(
              "groupId",
              aliases: "group_id", "gid", "conversation_id"
            ),
            let targetMessageId = data.exactString(
              "target_message_id",
              aliases: "targetMessageId", "target_id"
            ),
            let eventId = data.exactString(
              "event_id",
              aliases: "transition_id", "transitionId"
            ) else {
        return nil
      }
      return "message:group:\(groupId)|message:\(targetMessageId)|\(eventId)"
    case "message_reaction":
      guard let eventId = data.string(
        "event_id",
        aliases: "reaction_id"
      ),
        let peerId = data.string("sender_id", aliases: "from") else {
        return nil
      }
      return "message:\(peerId)|\(eventId)"
    default:
      return nil
    }
  }

  static func markerName(forKey key: String) -> String {
    SHA256.hash(data: Data(key.utf8))
      .map { String(format: "%02x", $0) }
      .joined()
  }

  /// Atomically records that the NSE handled this push. Idempotent (a duplicate
  /// O_EXCL create returns EEXIST → still "present"). No-op for non-message
  /// pushes or when the container is unavailable.
  @discardableResult
  func mark(userInfo: [AnyHashable: Any]) -> Bool {
    guard let directory, let key = Self.gateMessageKey(userInfo: userInfo) else {
      return false
    }
    let path = directory.appendingPathComponent(
      Self.markerName(forKey: key)
    ).path
    let fd = open(path, O_WRONLY | O_CREAT | O_EXCL, S_IRUSR | S_IWUSR)
    if fd >= 0 {
      close(fd)
      return true
    }
    return errno == EEXIST
  }
}

final class BridgePushDecryptor: PushPayloadDecrypting {
  func decryptOneToOne(
    secretKey: String,
    kem: String,
    ciphertext: String,
    nonce: String
  ) throws -> String {
    #if canImport(GoMknoon)
    let params = try jsonString([
      "secretKey": secretKey,
      "kem": kem,
      "ciphertext": ciphertext,
      "nonce": nonce,
    ])
    return try bridgePlaintext(BridgeDecryptMessage(params))
    #else
    throw NotificationPreviewError.bridgeUnavailable
    #endif
  }

  func decryptGroup(
    groupKey: String,
    ciphertext: String,
    nonce: String
  ) throws -> String {
    #if canImport(GoMknoon)
    let params = try jsonString([
      "groupKey": groupKey,
      "ciphertext": ciphertext,
      "nonce": nonce,
    ])
    return try bridgePlaintext(BridgeGroupDecryptMessage(params))
    #else
    throw NotificationPreviewError.bridgeUnavailable
    #endif
  }
}

private struct PushRouteData {
  private let values: [String: Any]

  init(userInfo: [AnyHashable: Any]) {
    var flattened: [String: Any] = [:]
    for (key, value) in userInfo {
      guard let key = key as? String, key != "aps" else {
        continue
      }
      flattened[key] = value
    }
    if let nestedData = flattened["data"] as? [String: Any] {
      for (key, value) in nestedData {
        flattened[key] = value
      }
    } else if let nestedData = flattened["data"] as? [AnyHashable: Any] {
      for (key, value) in nestedData {
        if let key = key as? String {
          flattened[key] = value
        }
      }
    }
    values = flattened
  }

  func string(_ key: String, aliases: String...) -> String? {
    string(key, aliases: aliases)
  }

  func string(_ key: String, aliases: [String]) -> String? {
    if let value = trimmedString(values[key]) {
      return value
    }
    for alias in aliases {
      if let value = trimmedString(values[alias]) {
        return value
      }
    }
    return nil
  }

  func exactString(_ key: String, aliases: String...) -> String? {
    exactString(key, aliases: aliases)
  }

  func exactCanonicalString(_ key: String) -> String? {
    exactNonEmptyString(values[key])
  }

  func exactString(_ key: String, aliases: [String]) -> String? {
    if let value = exactNonEmptyString(values[key]) {
      return value
    }
    for alias in aliases {
      if let value = exactNonEmptyString(values[alias]) {
        return value
      }
    }
    return nil
  }

  var messageId: String? {
    string("message_id", aliases: "messageId", "id", "msgId", "m")
  }

  var exactMessageId: String? {
    exactString("message_id", aliases: "messageId", "id", "msgId", "m")
  }

  func containsAny(_ keys: String...) -> Bool {
    return keys.contains { values[$0] != nil }
  }

  func decryptInputPresenceDetails(
    requiredKeys: [(canonical: String, aliases: [String])]
  ) -> [String: String] {
    var details: [String: String] = [
      "dataKeys": values.keys.sorted().joined(separator: ","),
    ]
    for key in requiredKeys {
      let present = string(key.canonical, aliases: key.aliases) != nil
      details["has\(key.canonical.prefix(1).uppercased())\(key.canonical.dropFirst())"] =
        present ? "true" : "false"
    }
    return details
  }
}

private func pushPreviewEventKind(type: String) -> String {
  type == "group_message" ? "group" : "chat"
}

private func groupUserPreviewBody(
  text: String,
  media: Any?,
  senderUsername: String?
) -> String {
  let preview = pushPreviewBody(text: text, media: media)
  guard let senderUsername else {
    return preview
  }
  return "\(senderUsername): \(preview)"
}

private func groupSystemPreviewBody(
  text: String,
  trustedMemberNames: [String: String]
) -> String? {
  let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
  guard trimmed.hasPrefix("{"), trimmed.hasSuffix("}"),
        let decoded = decodeJSONObject(trimmed),
        let systemType = trimmedString(decoded["__sys"]) else {
    return nil
  }

  guard systemType == "member_joined" else {
    return "Group update"
  }

  let member = decoded["member"] as? [String: Any]
  let memberPeerId = trimmedString(member?["peerId"])
  let displayName = memberPeerId.flatMap { trustedMemberNames[$0] }
  guard let displayName else {
    return "A member joined the group"
  }
  return "\(displayName) joined the group"
}

private func bridgePlaintext(_ response: String) throws -> String {
  guard let object = decodeJSONObject(response) else {
    throw NotificationPreviewError.invalidBridgeResponse
  }
  if (object["ok"] as? Bool) == true,
     let plaintext = trimmedString(object["plaintext"]) {
    return plaintext
  }
  throw NotificationPreviewError.bridgeFailure(
    trimmedString(object["errorMessage"]) ??
      trimmedString(object["errorCode"]) ??
      "decrypt_failed"
  )
}

private func jsonString(_ object: [String: String]) throws -> String {
  let data = try JSONSerialization.data(withJSONObject: object)
  guard let string = String(data: data, encoding: .utf8) else {
    throw NotificationPreviewError.invalidBridgeInput
  }
  return string
}

private func decodeJSONObject(_ value: String) -> [String: Any]? {
  guard let data = value.data(using: .utf8),
        let object = try? JSONSerialization.jsonObject(with: data),
        let dictionary = object as? [String: Any] else {
    return nil
  }
  return dictionary
}

func pushPreviewBody(text: String, media: Any?) -> String {
  let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
  if !trimmed.isEmpty {
    return capPreview(trimmed)
  }

  guard let mediaList = media as? [[String: Any]], !mediaList.isEmpty else {
    return "Message"
  }
  let types = mediaList.compactMap { trimmedString($0["mediaType"]) }
  guard let first = types.first else {
    return "Media"
  }
  if types.contains(where: { $0 != first }) {
    return "Media"
  }
  switch first {
  case "image":
    return "Photo"
  case "video":
    return "Video"
  case "audio":
    return "Voice message"
  case "file":
    return "File"
  default:
    return "Media"
  }
}

private func privateMediaNotificationBody(localeIdentifier: String) -> String {
  switch Locale(identifier: localeIdentifier).languageCode?.lowercased() {
  case "ar":
    return "وسائط خاصة"
  case "de":
    return "Private Medien"
  default:
    return "Private media"
  }
}

private func containsGroupPrivateMediaPolicyMarker(
  payload: [String: Any],
  extra: [String: Any]?
) -> Bool {
  let policyKeys = [
    "mediaPolicyVersion",
    "mediaLifecycle",
    "mediaDurationSeconds",
    "mediaProtected",
  ]
  return policyKeys.contains { payload.keys.contains($0) || extra?.keys.contains($0) == true }
}

private func groupPrivateMediaNotificationBody(localeIdentifier: String) -> String {
  switch Locale(identifier: localeIdentifier).languageCode?.lowercased() {
  case "ar":
    return "وسائط خاصة جديدة"
  case "de":
    return "Neue private Medien"
  default:
    return "New private media"
  }
}

private func capPreview(_ text: String, maxScalars: Int = 140) -> String {
  if text.unicodeScalars.count <= maxScalars {
    return text
  }
  return String(String.UnicodeScalarView(text.unicodeScalars.prefix(maxScalars)))
}

private func trimmedString(_ value: Any?) -> String? {
  let raw: String?
  switch value {
  case let value as String:
    raw = value
  case let value as NSNumber:
    raw = value.stringValue
  default:
    raw = nil
  }
  let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines)
  guard let trimmed, !trimmed.isEmpty else {
    return nil
  }
  return trimmed
}

private func exactNonEmptyString(_ value: Any?) -> String? {
  guard let raw = value as? String,
        !raw.isEmpty,
        raw == raw.trimmingCharacters(in: .whitespacesAndNewlines) else {
    return nil
  }
  return raw
}
