import Darwin
import Foundation
import Security

#if canImport(GoMknoon)
import GoMknoon
#endif

let mknoonSharedAppGroupIdentifier = "group.com.mknoon.app.share"
let mknoonFlutterSecureStorageService = "flutter_secure_storage_service"

enum PushSharedKeyNames {
  static let identityMlKemSecretKey = "identity_ml_kem_secret_key"

  static func groupKey(groupId: String, keyEpoch: Int) -> String {
    "group_key:\(groupId):\(keyEpoch)"
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

protocol PushPreviewEventEmitting {
  func emit(event: String, details: [String: String])
}

final class LogPushPreviewEventEmitter: PushPreviewEventEmitting {
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
    NSLog("[FLOW] %@", json)
  }
}

struct NotificationPreviewResult {
  let title: String
  let body: String
  let threadIdentifier: String?
  let didDecrypt: Bool
  let reason: String
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
  private let eventEmitter: PushPreviewEventEmitting

  init(
    keyReader: PushKeyReading,
    decryptor: PushPayloadDecrypting,
    dedupeStore: PushDedupeStoring?,
    eventEmitter: PushPreviewEventEmitting = LogPushPreviewEventEmitter()
  ) {
    self.keyReader = keyReader
    self.decryptor = decryptor
    self.dedupeStore = dedupeStore
    self.eventEmitter = eventEmitter
  }

  func resolve(
    userInfo: [AnyHashable: Any],
    fallbackTitle: String,
    fallbackBody: String,
    fallbackThreadIdentifier: String? = nil
  ) -> NotificationPreviewResult {
    let data = PushRouteData(userInfo: userInfo)
    guard let type = data.string("type") else {
      return fallback(
        title: fallbackTitle,
        body: fallbackBody,
        threadIdentifier: fallbackThreadIdentifier,
        reason: "missing_type"
      )
    }

    guard type == "new_message" || type == "group_message" else {
      return fallback(
        title: fallbackTitle,
        body: fallbackBody,
        threadIdentifier: fallbackThreadIdentifier,
        reason: "unsupported_type"
      )
    }

    if let messageId = data.messageId,
       let dedupeStore,
       !dedupeStore.claim(type: type, messageId: messageId) {
      return fallback(
        title: fallbackTitle,
        body: fallbackBody,
        threadIdentifier: fallbackThreadIdentifier,
        reason: "duplicate_message",
        eventKind: pushPreviewEventKind(type: type)
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
    guard let kem = data.string("kem"),
          let ciphertext = data.string("ciphertext"),
          let nonce = data.string("nonce") else {
      return fallback(
        title: fallbackTitle,
        body: fallbackBody,
        threadIdentifier: fallbackThreadIdentifier,
        reason: "missing_chat_decrypt_input",
        eventKind: "chat"
      )
    }
    guard let secretKey = keyReader.readString(
      key: PushSharedKeyNames.identityMlKemSecretKey
    ) else {
      return fallback(
        title: fallbackTitle,
        body: fallbackBody,
        threadIdentifier: fallbackThreadIdentifier,
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
      guard let payload = decodeJSONObject(plaintext) else {
        return fallback(
          title: fallbackTitle,
          body: fallbackBody,
          threadIdentifier: fallbackThreadIdentifier,
          reason: "invalid_chat_plaintext",
          eventKind: "chat"
        )
      }

      emitDecryptOK(kind: "chat")
      return NotificationPreviewResult(
        title: trimmedString(payload["senderUsername"]) ?? fallbackTitle,
        body: pushPreviewBody(
          text: trimmedString(payload["text"]) ?? "",
          media: payload["media"]
        ),
        threadIdentifier: data.string("sender_id") ?? fallbackThreadIdentifier,
        didDecrypt: true,
        reason: "chat"
      )
    } catch {
      return fallback(
        title: fallbackTitle,
        body: fallbackBody,
        threadIdentifier: fallbackThreadIdentifier,
        reason: "chat_decrypt_error",
        eventKind: "chat"
      )
    }
  }

  private func resolveGroup(
    data: PushRouteData,
    fallbackTitle: String,
    fallbackBody: String,
    fallbackThreadIdentifier: String?
  ) -> NotificationPreviewResult {
    guard let groupId = data.string("groupId"),
          let keyEpochString = data.string("keyEpoch"),
          let keyEpoch = Int(keyEpochString),
          let ciphertext = data.string("ciphertext"),
          let nonce = data.string("nonce") else {
      return fallback(
        title: fallbackTitle,
        body: fallbackBody,
        threadIdentifier: fallbackThreadIdentifier,
        reason: "missing_group_decrypt_input",
        eventKind: "group"
      )
    }
    guard let groupKey = keyReader.readString(
      key: PushSharedKeyNames.groupKey(groupId: groupId, keyEpoch: keyEpoch)
    ) else {
      return fallback(
        title: fallbackTitle,
        body: fallbackBody,
        threadIdentifier: fallbackThreadIdentifier,
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
        return fallback(
          title: fallbackTitle,
          body: fallbackBody,
          threadIdentifier: fallbackThreadIdentifier,
          reason: "invalid_group_plaintext",
          eventKind: "group"
        )
      }

      let preview = pushPreviewBody(
        text: trimmedString(payload["text"]) ?? "",
        media: payload["media"]
      )
      let senderUsername = trimmedString(payload["senderUsername"])
      emitDecryptOK(kind: "group")
      return NotificationPreviewResult(
        title: fallbackTitle,
        body: senderUsername == nil ? preview : "\(senderUsername!): \(preview)",
        threadIdentifier: groupId,
        didDecrypt: true,
        reason: "group"
      )
    } catch {
      return fallback(
        title: fallbackTitle,
        body: fallbackBody,
        threadIdentifier: fallbackThreadIdentifier,
        reason: "group_decrypt_error",
        eventKind: "group"
      )
    }
  }

  private func fallback(
    title: String,
    body: String,
    threadIdentifier: String?,
    reason: String,
    eventKind: String? = nil
  ) -> NotificationPreviewResult {
    if let eventKind {
      emitDecryptFail(kind: eventKind, reason: reason)
    }
    return NotificationPreviewResult(
      title: title,
      body: body,
      threadIdentifier: threadIdentifier,
      didDecrypt: false,
      reason: reason
    )
  }

  private func emitDecryptOK(kind: String) {
    eventEmitter.emit(
      event: "PUSH_NSE_DECRYPT_OK",
      details: ["kind": kind]
    )
  }

  private func emitDecryptFail(kind: String, reason: String) {
    eventEmitter.emit(
      event: "PUSH_NSE_DECRYPT_FAIL",
      details: [
        "kind": kind,
        "reason": reason,
      ]
    )
  }
}

final class KeychainPushKeyReader: PushKeyReading {
  private let service: String
  private let accessGroup: String?

  init(
    service: String = mknoonFlutterSecureStorageService,
    accessGroup: String? = mknoonSharedAppGroupIdentifier
  ) {
    self.service = service
    self.accessGroup = accessGroup
  }

  func readString(key: String) -> String? {
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

  init?(appGroupIdentifier: String = mknoonSharedAppGroupIdentifier) {
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
  }

  func claim(type: String, messageId: String) -> Bool {
    let name = "\(safeFileComponent(type))-\(safeFileComponent(messageId))"
    let path = directory.appendingPathComponent(name).path
    let fd = open(path, O_WRONLY | O_CREAT | O_EXCL, S_IRUSR | S_IWUSR)
    guard fd >= 0 else {
      return false
    }
    close(fd)
    return true
  }

  private func safeFileComponent(_ value: String) -> String {
    let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
    return value.unicodeScalars.map { scalar in
      allowed.contains(scalar) ? String(scalar) : "_"
    }.joined()
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

  func string(_ key: String) -> String? {
    trimmedString(values[key])
  }

  var messageId: String? {
    string("message_id") ?? string("messageId") ?? string("id") ?? string("msgId")
  }
}

private func pushPreviewEventKind(type: String) -> String {
  type == "group_message" ? "group" : "chat"
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
