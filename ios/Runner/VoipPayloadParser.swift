import Foundation

internal struct VoipWakePayload: Equatable {
  let nativeCallId: UUID
  let callHandle: String
  let wakeHandle: String
  let receivedAtMs: Int64
  let expiresAtMs: Int64
}

internal enum VoipPayloadRejectionReason: String, Equatable {
  case invalidShape
  case duplicateKey
  case tooLarge
  case malformed
  case stale
  case tooFarFuture
}

internal enum VoipPayloadParseResult: Equatable {
  case accepted(VoipWakePayload)
  case rejected(VoipPayloadRejectionReason)
}

/// Parses the deliberately tiny APNs VoIP wake contract. Values from a push
/// are never incorporated into an error, description, or log message.
internal final class VoipPayloadParser {
  static let schemaVersion = 1
  static let maxPayloadBytes = 256
  static let maxFutureSkewMs: Int64 = 45_000

  private static let expectedKeys: Set<String> = ["aps", "v", "w", "c", "h", "e"]
  private static let strictMilliseconds = try! NSRegularExpression(
    pattern: "^[1-9][0-9]{0,18}$"
  )
  private static let randomIdentifier = try! NSRegularExpression(
    pattern: "^(?:[0-9a-f]{32}|[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12})$"
  )

  private let nowMs: () -> Int64

  init(nowMs: @escaping () -> Int64 = {
    Int64(Date().timeIntervalSince1970 * 1_000)
  }) {
    self.nowMs = nowMs
  }

  func parse(dictionary: [AnyHashable: Any]) -> VoipPayloadParseResult {
    var entries: [(String, Any)] = []
    entries.reserveCapacity(dictionary.count)
    for (rawKey, value) in dictionary {
      guard let key = rawKey as? String else {
        return .rejected(.invalidShape)
      }
      entries.append((key, value))
    }
    return parse(entries: entries)
  }

  /// The entry-list form exists so duplicate-key rejection remains directly
  /// host-testable even though Foundation dictionaries have already collapsed
  /// duplicate JSON keys by the time PushKit exposes a payload.
  func parse(entries: [(String, Any)]) -> VoipPayloadParseResult {
    let keys = entries.map(\.0)
    guard Set(keys).count == keys.count else {
      return .rejected(.duplicateKey)
    }
    guard Set(keys) == Self.expectedKeys, entries.count == Self.expectedKeys.count else {
      return .rejected(.invalidShape)
    }
    guard encodedSize(of: entries) <= Self.maxPayloadBytes else {
      return .rejected(.tooLarge)
    }

    let values = Dictionary(uniqueKeysWithValues: entries)
    guard
      isContentAvailableOnly(values["aps"]),
      values["v"] as? String == "1",
      values["w"] as? String == "call",
      let rawCallHandle = values["c"] as? String,
      let wakeHandle = values["h"] as? String,
      let expiryText = values["e"] as? String,
      Self.matches(Self.randomIdentifier, rawCallHandle),
      Self.matches(Self.randomIdentifier, wakeHandle),
      Self.matches(Self.strictMilliseconds, expiryText),
      let expiresAtMs = Int64(expiryText),
      let nativeCallId = Self.canonicalUUID(from: rawCallHandle)
    else {
      return .rejected(.malformed)
    }

    let receivedAtMs = nowMs()
    guard receivedAtMs >= 0 else { return .rejected(.malformed) }
    guard expiresAtMs > receivedAtMs else { return .rejected(.stale) }
    guard expiresAtMs - receivedAtMs <= Self.maxFutureSkewMs else {
      return .rejected(.tooFarFuture)
    }

    return .accepted(VoipWakePayload(
      nativeCallId: nativeCallId,
      callHandle: nativeCallId.uuidString.lowercased(),
      wakeHandle: wakeHandle,
      receivedAtMs: receivedAtMs,
      expiresAtMs: expiresAtMs
    ))
  }

  private func isContentAvailableOnly(_ value: Any?) -> Bool {
    guard let aps = value as? [String: Any], Set(aps.keys) == ["content-available"] else {
      return false
    }
    return Self.strictInteger(aps["content-available"]) == 1
  }

  private func encodedSize(of entries: [(String, Any)]) -> Int {
    var count = 2 // outer braces
    for (index, entry) in entries.enumerated() {
      if index > 0 { count += 1 }
      count += entry.0.utf8.count + 3 // quoted key and colon
      switch entry.1 {
      case let text as String:
        count += text.utf8.count + 2
      case let aps as [String: Any]:
        guard JSONSerialization.isValidJSONObject(aps),
              let encoded = try? JSONSerialization.data(withJSONObject: aps)
        else { return Self.maxPayloadBytes + 1 }
        count += encoded.count
      default:
        return Self.maxPayloadBytes + 1
      }
      if count > Self.maxPayloadBytes { return count }
    }
    return count
  }

  private static func strictInteger(_ value: Any?) -> Int64? {
    guard let number = value as? NSNumber,
          CFGetTypeID(number) != CFBooleanGetTypeID()
    else { return nil }
    switch String(cString: number.objCType) {
    case "c", "s", "i", "l", "q":
      return number.int64Value
    case "C", "S", "I", "L", "Q":
      let unsigned = number.uint64Value
      return unsigned <= UInt64(Int64.max) ? Int64(unsigned) : nil
    default:
      return nil
    }
  }

  private static func matches(_ expression: NSRegularExpression, _ value: String) -> Bool {
    let range = NSRange(value.startIndex..<value.endIndex, in: value)
    return expression.firstMatch(in: value, range: range)?.range == range
  }

  private static func canonicalUUID(from value: String) -> UUID? {
    let canonical: String
    if value.utf8.count == 32 {
      canonical = String(value.prefix(8)) + "-"
        + String(value.dropFirst(8).prefix(4)) + "-"
        + String(value.dropFirst(12).prefix(4)) + "-"
        + String(value.dropFirst(16).prefix(4)) + "-"
        + String(value.dropFirst(20).prefix(12))
    } else {
      canonical = value
    }
    return UUID(uuidString: canonical)
  }
}
