import CoreFoundation
import Foundation
import UserNotifications

#if canImport(GoMknoon)
import GoMknoon
#endif

enum NseMailboxWakeClassifier {
  static func isExactFixedWake(_ userInfo: [AnyHashable: Any]) -> Bool {
    var root: [String: Any] = [:]
    for (rawKey, value) in userInfo {
      guard let key = rawKey as? String else { return false }
      root[key] = value
    }
    guard root["v"] as? String == "1",
          let aps = root["aps"] as? [String: Any],
          Set(aps.keys).isSubset(of: allowedApsKeys),
          aps["category"] as? String == "MESSAGE_WAKE",
          aps["sound"] as? String == "default",
          exactOne(aps["mutable-content"]),
          let alert = aps["alert"] as? [String: Any],
          Set(alert.keys) == ["title-loc-key", "loc-key"],
          alert["title-loc-key"] as? String == "NEW_MESSAGE_TITLE",
          alert["loc-key"] as? String == "NEW_MESSAGE_BODY" else {
      return false
    }
    return root.keys.allSatisfy { key in
      key == "aps" || key == "v" || key.hasPrefix("gcm.") ||
        key.hasPrefix("google.")
    }
  }

  /// Apple-reserved APS presentation metadata may coexist but is never read as
  /// event identity. The generic localized alert itself stays exact.
  private static let allowedApsKeys: Set<String> = [
    "alert",
    "mutable-content",
    "sound",
    "category",
    "badge",
    "content-available",
    "thread-id",
    "interruption-level",
    "relevance-score",
    "target-content-id",
    "filter-criteria",
    "url-args",
  ]

  private static func exactOne(_ raw: Any?) -> Bool {
    guard let number = raw as? NSNumber,
          CFGetTypeID(number) != CFBooleanGetTypeID(),
          !CFNumberIsFloatType(number) else {
      return false
    }
    return number.int64Value == 1
  }
}

struct NseInboxRetrievedMessage: Equatable {
  let id: String
  let from: String
  let message: String
  let timestamp: Int64
}

struct NseInboxRetrievedPage: Equatable {
  let messages: [NseInboxRetrievedMessage]
  let hasMore: Bool
}

protocol NseInboxRetrieving {
  func retrievePending(requestJSON: String) throws -> String
}

struct GoNseInboxRetriever: NseInboxRetrieving {
  func retrievePending(requestJSON: String) throws -> String {
#if canImport(GoMknoon)
    return BridgeNSEInboxRetrievePending(requestJSON)
#else
    throw NseMailboxWakeError.bridgeUnavailable
#endif
  }
}

enum NseMailboxWakeError: Error {
  case bridgeUnavailable
}

enum NseMailboxWakeResolution {
  case authenticated(
    candidate: NseInboxCandidate,
    lease: IosNotificationMailboxAlertLease
  )
  case generic(lease: IosNotificationMailboxAlertLease?)
}

/// Owns the bounded asynchronous retrieval portion of the fixed wake. It does
/// not own Apple's completion gate or the Plan-372 ledger lock.
final class NseMailboxWakeCoordinator {
  private static let successKeys: Set<String> = [
    "ok", "messages", "hasMore", "custodyContract",
  ]
  private static let errorKeys: Set<String> = [
    "ok", "errorCode", "errorMessage",
  ]
  private static let messageKeys: Set<String> = [
    "id", "from", "message", "timestamp",
  ]
  private static let allowedErrors: [String: String] = [
    "INVALID_INPUT": "invalid NSE inbox request",
    "IDENTITY_MISMATCH": "NSE inbox transport identity mismatch",
    "INBOX_UNAVAILABLE": "NSE inbox retrieval unavailable",
    "INTERNAL_ERROR": "NSE inbox retrieval failed",
  ]

  private let credentialReader: NseInboxCredentialReader
  private let retriever: NseInboxRetrieving
  private let candidateAdapter: NseInboxCandidateAdapting
  private let recoveryStore: IosNotificationRecoveryStore?
  private let queue: DispatchQueue
  private let deadlineQueue: DispatchQueue
  private let timeoutMs: Int
  private let outerDeadlineMs: Int

  init(
    credentialReader: NseInboxCredentialReader,
    retriever: NseInboxRetrieving,
    candidateAdapter: NseInboxCandidateAdapting,
    recoveryStore: IosNotificationRecoveryStore?,
    queue: DispatchQueue = DispatchQueue(
      label: "com.mknoon.nse-mailbox-wake",
      qos: .userInitiated
    ),
    deadlineQueue: DispatchQueue = DispatchQueue(
      label: "com.mknoon.nse-mailbox-wake-deadline",
      qos: .userInitiated
    ),
    timeoutMs: Int = 2_500,
    outerDeadlineMs: Int = 2_800
  ) {
    self.credentialReader = credentialReader
    self.retriever = retriever
    self.candidateAdapter = candidateAdapter
    self.recoveryStore = recoveryStore
    self.queue = queue
    self.deadlineQueue = deadlineQueue
    self.timeoutMs = min(3_000, max(250, timeoutMs))
    self.outerDeadlineMs = min(
      4_000,
      max(self.timeoutMs + 100, outerDeadlineMs)
    )
  }

  func resolve(
    requestIdentifier: String,
    completion: @escaping (NseMailboxWakeResolution) -> Void
  ) {
    guard let recoveryStore else {
      completion(.generic(lease: nil))
      return
    }
    // Persist ambiguity from incumbent account/binding authority before the
    // sensitive transport projection is touched. A locked/missing credential
    // therefore still silences the later canonical drain generation.
    let incumbentLease = recoveryStore.prepareMailboxAlertLease(
      requestIdentifier: requestIdentifier
    )
    guard let credential = credentialReader.read() else {
      completion(.generic(lease: incumbentLease))
      return
    }
    let lease: IosNotificationMailboxAlertLease
    if let incumbentLease {
      guard recoveryStore.mailboxAlertLeaseMatches(
        incumbentLease,
        accountPeerId: credential.logicalAccountPeerId,
        opaqueBinding: credential.opaqueBinding
      ) else {
        completion(.generic(lease: incumbentLease))
        return
      }
      lease = incumbentLease
    } else {
      // A genuinely uninitialized recovery file may adopt the first exact,
      // binding-qualified credential. This still precedes network/decrypt work.
      guard let initialized = recoveryStore.prepareMailboxAlertLease(
        requestIdentifier: requestIdentifier,
        accountPeerId: credential.logicalAccountPeerId,
        opaqueBinding: credential.opaqueBinding
      ) else {
        completion(.generic(lease: nil))
        return
      }
      lease = initialized
    }
    guard let requestJSON = credential.requestJSON(timeoutMs: timeoutMs) else {
      completion(.generic(lease: lease))
      return
    }

    let gate = NseMailboxWakeResolutionGate(completion: completion)
    deadlineQueue.asyncAfter(
      deadline: .now() + .milliseconds(outerDeadlineMs)
    ) {
      gate.complete(.generic(lease: lease))
    }
    queue.async { [retriever, candidateAdapter] in
      let resolution: NseMailboxWakeResolution
      do {
        let encoded = try retriever.retrievePending(requestJSON: requestJSON)
        guard !gate.isCompleted else { return }
        if let page = Self.decodePage(encoded),
           !page.hasMore,
           page.messages.count == 1,
           let candidate = candidateAdapter.adapt(
             page.messages[0],
             credential: credential
           ) {
          resolution = .authenticated(candidate: candidate, lease: lease)
        } else {
          resolution = .generic(lease: lease)
        }
      } catch {
        resolution = .generic(lease: lease)
      }
      gate.complete(resolution)
    }
  }

  /// Generic handoff never keeps the recovery flock across Apple code. A
  /// failed/superseded lease mutation does not authorize content mutation.
  func handoffGeneric(
    lease: IosNotificationMailboxAlertLease?,
    content: UNNotificationContent,
    contentHandler: (UNNotificationContent) -> Void
  ) {
    if let lease {
      _ = recoveryStore?.markMailboxAlertLeasePublishing(
        token: lease.token,
        generation: lease.generation,
        sequence: lease.sequence
      )
    }
    contentHandler(content)
    if let lease {
      _ = recoveryStore?.markMailboxAlertLeaseAudibleAmbiguous(
        token: lease.token,
        generation: lease.generation,
        sequence: lease.sequence
      )
    }
  }

  static func decodePage(_ encoded: String) -> NseInboxRetrievedPage? {
    guard encoded.utf8.count <= 1_048_576,
          let data = encoded.data(using: .utf8),
          let object = try? JSONSerialization.jsonObject(with: data),
          let root = object as? [String: Any],
          let ok = exactBool(root["ok"]) else {
      return nil
    }
    if !ok {
      guard Set(root.keys) == errorKeys,
            let code = exactString(root["errorCode"], maxBytes: 64),
            let message = exactString(root["errorMessage"], maxBytes: 128),
            allowedErrors[code] == message else {
        return nil
      }
      return nil
    }
    guard Set(root.keys) == successKeys,
          root["custodyContract"] as? String == "ack_or_expiry_v1",
          let hasMore = exactBool(root["hasMore"]),
          let rawMessages = root["messages"] as? [Any],
          rawMessages.count <= 1 else {
      return nil
    }
    var messages: [NseInboxRetrievedMessage] = []
    for raw in rawMessages {
      guard let value = raw as? [String: Any],
            Set(value.keys) == messageKeys,
            let id = exactString(value["id"], maxBytes: 512),
            let from = exactString(value["from"], maxBytes: 1_024),
            let message = exactString(value["message"], maxBytes: 524_288),
            let timestamp = exactInteger(value["timestamp"]),
            timestamp >= 0 else {
        return nil
      }
      messages.append(NseInboxRetrievedMessage(
        id: id,
        from: from,
        message: message,
        timestamp: timestamp
      ))
    }
    return NseInboxRetrievedPage(messages: messages, hasMore: hasMore)
  }

  private static func exactString(_ raw: Any?, maxBytes: Int) -> String? {
    guard let value = raw as? String,
          !value.isEmpty,
          value == value.trimmingCharacters(in: .whitespacesAndNewlines),
          value.utf8.count <= maxBytes,
          value.unicodeScalars.allSatisfy({ scalar in
            scalar.value > 31 && !(127...159).contains(scalar.value)
          }) else {
      return nil
    }
    return value
  }

  private static func exactBool(_ raw: Any?) -> Bool? {
    guard let number = raw as? NSNumber,
          CFGetTypeID(number) == CFBooleanGetTypeID() else {
      return nil
    }
    return number.boolValue
  }

  private static func exactInteger(_ raw: Any?) -> Int64? {
    guard let number = raw as? NSNumber,
          CFGetTypeID(number) != CFBooleanGetTypeID(),
          !CFNumberIsFloatType(number) else {
      return nil
    }
    return Int64(number.stringValue)
  }
}

/// Per-request once gate shared by the independent work and deadline queues.
/// A late Go/decrypt result is discarded before it can reach NotificationService's
/// completion generation or mutate the final-effect ledger.
private final class NseMailboxWakeResolutionGate {
  private let lock = NSLock()
  private var completed = false
  private let completion: (NseMailboxWakeResolution) -> Void

  init(completion: @escaping (NseMailboxWakeResolution) -> Void) {
    self.completion = completion
  }

  func complete(_ resolution: NseMailboxWakeResolution) {
    lock.lock()
    guard !completed else {
      lock.unlock()
      return
    }
    completed = true
    lock.unlock()
    completion(resolution)
  }

  var isCompleted: Bool {
    lock.lock()
    defer { lock.unlock() }
    return completed
  }
}
