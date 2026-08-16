import CoreFoundation
import CryptoKit
import Foundation

struct NseInboxCredential: Equatable {
  static let projectionKey = "nse_inbox_transport_v1"
  static let bindingKey = "canonical_runtime_shared_account_binding_v1"

  let opaqueBinding: String
  let logicalAccountPeerId: String
  let transportPeerId: String
  let transportPrivateKeyBase64: String
  let relayMultiaddrs: [String]
  let projectionRevision: Int64
  let transportProjectionDigest: String

  func requestJSON(timeoutMs: Int) -> String? {
    guard timeoutMs >= 250, timeoutMs <= 3_000 else { return nil }
    let value: [String: Any] = [
      "transportPrivateKeyBase64": transportPrivateKeyBase64,
      "expectedTransportPeerId": transportPeerId,
      "relayMultiaddrs": relayMultiaddrs,
      "timeoutMs": timeoutMs,
    ]
    guard let data = try? JSONSerialization.data(
      withJSONObject: value,
      options: [.sortedKeys, .withoutEscapingSlashes]
    ) else {
      return nil
    }
    return String(data: data, encoding: .utf8)
  }
}

/// Strict reader for the one binding-qualified NSE transport projection. The
/// projection is a cache of incumbent authority; malformed, stale or partial
/// bytes grant no retrieval authority.
struct NseInboxCredentialReader {
  private static let exactKeys: Set<String> = [
    "schemaVersion",
    "opaqueBinding",
    "logicalAccountPeerId",
    "transportPeerId",
    "transportPrivateKeyBase64",
    "relayMultiaddrs",
    "projectionRevision",
  ]

  let keyReader: PushKeyReading

  func read() -> NseInboxCredential? {
    guard let encoded = keyReader.readString(
            key: NseInboxCredential.projectionKey
          ),
          encoded.utf8.count <= 16_384,
          let data = encoded.data(using: .utf8),
          let root = try? JSONSerialization.jsonObject(with: data),
          let value = root as? [String: Any],
          Set(value.keys) == Self.exactKeys,
          Self.exactInteger(value["schemaVersion"]) == 1,
          let opaqueBinding = Self.exactNonEmptyString(
            value["opaqueBinding"],
            maxBytes: 67
          ),
          Self.isCanonicalOpaqueBinding(opaqueBinding),
          keyReader.readString(key: NseInboxCredential.bindingKey) ==
            opaqueBinding,
          let logicalAccountPeerId = Self.exactPeerId(
            value["logicalAccountPeerId"]
          ),
          let transportPeerId = Self.exactPeerId(
            value["transportPeerId"]
          ),
          let privateKey = Self.exactNonEmptyString(
            value["transportPrivateKeyBase64"],
            maxBytes: 256
          ),
          let privateKeyBytes = Data(base64Encoded: privateKey),
          privateKeyBytes.count == 64,
          privateKeyBytes.base64EncodedString() == privateKey,
          let relays = Self.exactRelays(value["relayMultiaddrs"]),
          let projectionRevision = Self.exactInteger(
            value["projectionRevision"]
          ),
          projectionRevision > 0 else {
      return nil
    }
    return NseInboxCredential(
      opaqueBinding: opaqueBinding,
      logicalAccountPeerId: logicalAccountPeerId,
      transportPeerId: transportPeerId,
      transportPrivateKeyBase64: privateKey,
      relayMultiaddrs: relays,
      projectionRevision: projectionRevision,
      transportProjectionDigest: SHA256.hash(data: Data(encoded.utf8)).map {
        String(format: "%02x", $0)
      }.joined()
    )
  }

  private static func exactInteger(_ raw: Any?) -> Int64? {
    guard let number = raw as? NSNumber,
          CFGetTypeID(number) != CFBooleanGetTypeID(),
          !CFNumberIsFloatType(number) else {
      return nil
    }
    return Int64(number.stringValue)
  }

  private static func exactNonEmptyString(
    _ raw: Any?,
    maxBytes: Int
  ) -> String? {
    guard let value = raw as? String,
          !value.isEmpty,
          value == value.trimmingCharacters(in: .whitespacesAndNewlines),
          value.utf8.count <= maxBytes else {
      return nil
    }
    return value
  }

  private static func exactPeerId(_ raw: Any?) -> String? {
    guard let value = exactNonEmptyString(raw, maxBytes: 256),
          value.unicodeScalars.allSatisfy({ scalar in
            !scalar.properties.isWhitespace && scalar.value > 31 &&
              !(127...159).contains(scalar.value)
          }) else {
      return nil
    }
    return value
  }

  private static func exactRelays(_ raw: Any?) -> [String]? {
    guard let values = raw as? [Any],
          (1...8).contains(values.count) else {
      return nil
    }
    var result: [String] = []
    var totalBytes = 0
    for rawValue in values {
      guard let value = exactNonEmptyString(rawValue, maxBytes: 512),
            value.hasPrefix("/"),
            !value.hasSuffix("/"),
            value.utf8.allSatisfy({ (0x21...0x7e).contains($0) }),
            Self.isCanonicalRelayMultiaddr(value),
            !result.contains(value) else {
        return nil
      }
      totalBytes += value.utf8.count
      guard totalBytes <= 8_192 else { return nil }
      result.append(value)
    }
    return result
  }

  private static func isCanonicalRelayMultiaddr(_ value: String) -> Bool {
    let segments = value.dropFirst().split(
      separator: "/",
      omittingEmptySubsequences: false
    ).map(String.init)
    let hostProtocols: Set<String> = [
      "dns", "dns4", "dns6", "dnsaddr", "ip4", "ip6",
    ]
    guard segments.count >= 6,
          !segments.contains(where: \.isEmpty),
          let first = segments.first,
          hostProtocols.contains(first),
          segments.count >= 2,
          segments[segments.count - 2] == "p2p",
          !segments[segments.count - 1].isEmpty else {
      return false
    }
    return segments.contains("tcp") || segments.contains("udp")
  }

  private static func isCanonicalOpaqueBinding(_ value: String) -> Bool {
    value.utf8.count == 67 && value.hasPrefix("v1:") &&
      value.dropFirst(3).utf8.allSatisfy { byte in
        (byte >= 48 && byte <= 57) || (byte >= 97 && byte <= 102)
      }
  }
}
