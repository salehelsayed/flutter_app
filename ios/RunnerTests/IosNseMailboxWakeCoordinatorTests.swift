import CryptoKit
import Darwin
import Foundation
import UserNotifications
import XCTest

@testable import Runner

final class IosNseMailboxWakeCoordinatorTests: XCTestCase {
  private let binding = "v1:" + String(repeating: "c", count: 64)
  private let account = "peer-self"
  private let transport = "transport-self"

  func testTC37303ExactFixedGrammarAndRichCompatibility() throws {
    let exact = fixedWake()
    XCTAssertTrue(NseMailboxWakeClassifier.isExactFixedWake(exact))

    var reserved = exact
    reserved["gcm.message_id"] = "provider-id"
    reserved["google.c.a.e"] = "1"
    var reservedAps = try XCTUnwrap(reserved["aps"] as? [String: Any])
    reservedAps["content-available"] = 1
    reservedAps["thread-id"] = "provider-thread"
    reserved["aps"] = reservedAps
    XCTAssertTrue(NseMailboxWakeClassifier.isExactFixedWake(reserved))

    var numericVersion = exact
    numericVersion["v"] = 1
    XCTAssertFalse(NseMailboxWakeClassifier.isExactFixedWake(numericVersion))
    var android = exact
    android["w"] = "1"
    XCTAssertFalse(NseMailboxWakeClassifier.isExactFixedWake(android))
    var unknown = exact
    unknown["event_id"] = "provider-event"
    XCTAssertFalse(NseMailboxWakeClassifier.isExactFixedWake(unknown))
    var rich = exact
    rich["type"] = "new_message"
    rich["ciphertext"] = "ciphertext"
    XCTAssertFalse(NseMailboxWakeClassifier.isExactFixedWake(rich))

    var futureAps = exact
    var aps = try XCTUnwrap(futureAps["aps"] as? [String: Any])
    aps["future-app-field"] = "no"
    futureAps["aps"] = aps
    XCTAssertFalse(NseMailboxWakeClassifier.isExactFixedWake(futureAps))

    // Exercise the production branch shape: exactly one fixed wake fetches
    // once and never stages, while a real incumbent rich envelope stages and
    // never reaches the mailbox retriever.
    let root = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let recovery = initializedRecoveryStore(root)
    let retriever = CountingNseRetriever(
      response: #"{"ok":true,"messages":[],"hasMore":false,"custodyContract":"ack_or_expiry_v1"}"#
    )
    let coordinator = NseMailboxWakeCoordinator(
      credentialReader: NseInboxCredentialReader(
        keyReader: FixedKeyReader(try credentialKeys())
      ),
      retriever: retriever,
      candidateAdapter: FixedCandidateAdapter(candidate: nil),
      recoveryStore: recovery,
      timeoutMs: 250,
      outerDeadlineMs: 400
    )
    let stagingDirectory = root.appendingPathComponent("rich-staging")
    let stagingStore = AppGroupPushEnvelopeStore(
      directory: stagingDirectory
    )
    let fixedResolved = expectation(description: "fixed fetch completes")
    var richStaged = false
    func route(_ userInfo: [AnyHashable: Any], identifier: String) {
      if NseMailboxWakeClassifier.isExactFixedWake(userInfo) {
        coordinator.resolve(requestIdentifier: identifier) { _ in
          fixedResolved.fulfill()
        }
      } else {
        richStaged = stagingStore.stage(userInfo: userInfo)
      }
    }
    route(exact, identifier: "fixed-fetch-once")
    route([
      "type": "new_message",
      "sender_id": "peer-rich",
      "message_id": "message-rich",
      "kem": "kem-rich",
      "ciphertext": "cipher-rich",
      "nonce": "nonce-rich",
    ], identifier: "rich-does-not-fetch")
    wait(for: [fixedResolved], timeout: 1)
    XCTAssertEqual(retriever.calls, 1)
    XCTAssertTrue(richStaged)
    XCTAssertEqual(
      try FileManager.default.contentsOfDirectory(
        atPath: stagingDirectory.path
      ).filter { $0.hasSuffix(".json") }.count,
      1
    )
  }

  func testTC37304OperationalFailureAndExpiryPreserveGenericOnce() throws {
    let root = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let store = initializedRecoveryStore(root)
    let keys = try credentialKeys()
    let adapter = FixedCandidateAdapter(candidate: candidate())
    let retriever = DelayedNseRetriever(
      delay: 0.8,
      response: successPage()
    )
    let coordinator = NseMailboxWakeCoordinator(
      credentialReader: NseInboxCredentialReader(
        keyReader: FixedKeyReader(keys)
      ),
      retriever: retriever,
      candidateAdapter: adapter,
      recoveryStore: store,
      queue: DispatchQueue(label: "tc37304.work"),
      deadlineQueue: DispatchQueue(label: "tc37304.deadline"),
      timeoutMs: 250,
      outerDeadlineMs: 350
    )

    let first = expectation(description: "outer deadline wins")
    let lock = NSLock()
    var resolutions: [NseMailboxWakeResolution] = []
    coordinator.resolve(requestIdentifier: "fixed-request") { resolution in
      lock.lock()
      resolutions.append(resolution)
      lock.unlock()
      first.fulfill()
    }
    wait(for: [first], timeout: 1.5)
    Thread.sleep(forTimeInterval: 0.7)
    lock.lock()
    let exactResolutions = resolutions
    lock.unlock()
    XCTAssertEqual(exactResolutions.count, 1)
    guard case let .generic(lease) = try XCTUnwrap(exactResolutions.first)
    else {
      return XCTFail("deadline must resolve generic")
    }
    XCTAssertNotNil(lease)
    XCTAssertEqual(adapter.calls, 0, "late bridge result must not enter adapter")

    let original = UNMutableNotificationContent()
    original.title = "Localized generic title"
    original.subtitle = "Localized generic subtitle"
    original.body = "Localized generic body"
    original.categoryIdentifier = "MESSAGE_WAKE"
    original.threadIdentifier = "provider-thread"
    original.sound = .default
    original.userInfo = fixedWake()
    var handedOff: [UNNotificationContent] = []
    coordinator.handoffGeneric(
      lease: lease,
      content: original,
      contentHandler: { handedOff.append($0) }
    )
    XCTAssertEqual(handedOff.count, 1)
    XCTAssertTrue(handedOff[0] === original)
    XCTAssertEqual(handedOff[0].title, "Localized generic title")
    XCTAssertEqual(handedOff[0].subtitle, "Localized generic subtitle")
    XCTAssertEqual(handedOff[0].body, "Localized generic body")
    XCTAssertEqual(handedOff[0].categoryIdentifier, "MESSAGE_WAKE")
    XCTAssertEqual(handedOff[0].threadIdentifier, "provider-thread")
    XCTAssertNotNil(handedOff[0].sound)
    XCTAssertEqual(
      store.beginReconciliation(accountPeerId: account)?
        .mailboxAlertLease?.phase,
      .audibleAmbiguous
    )

    let validKeys = try credentialKeys()
    var wrongBindingKeys = validKeys
    wrongBindingKeys[NseInboxCredential.bindingKey] =
      "v1:" + String(repeating: "e", count: 64)
    let acceptedPage = successPage()
    let operationalCases: [(
      name: String,
      keys: [String: String],
      retriever: NseInboxRetrieving,
      adapter: FixedCandidateAdapter
    )] = [
      (
        "empty",
        validKeys,
        CountingNseRetriever(response:
          #"{"ok":true,"messages":[],"hasMore":false,"custodyContract":"ack_or_expiry_v1"}"#
        ),
        FixedCandidateAdapter(candidate: candidate())
      ),
      (
        "hasMore",
        validKeys,
        CountingNseRetriever(response:
          #"{"ok":true,"messages":[{"id":"row","from":"transport-self","message":"{}","timestamp":1}],"hasMore":true,"custodyContract":"ack_or_expiry_v1"}"#
        ),
        FixedCandidateAdapter(candidate: candidate())
      ),
      (
        "missing-key",
        [:],
        CountingNseRetriever(response: acceptedPage),
        FixedCandidateAdapter(candidate: candidate())
      ),
      (
        "binding-mismatch",
        wrongBindingKeys,
        CountingNseRetriever(response: acceptedPage),
        FixedCandidateAdapter(candidate: candidate())
      ),
      (
        "network",
        validKeys,
        ThrowingNseRetriever(),
        FixedCandidateAdapter(candidate: candidate())
      ),
      (
        "proof",
        validKeys,
        CountingNseRetriever(response:
          #"{"ok":false,"errorCode":"INTERNAL_ERROR","errorMessage":"raw provider detail"}"#
        ),
        FixedCandidateAdapter(candidate: candidate())
      ),
      (
        "decrypt",
        validKeys,
        CountingNseRetriever(response: acceptedPage),
        FixedCandidateAdapter(candidate: nil)
      ),
      (
        "policy-unknown",
        validKeys,
        CountingNseRetriever(response: acceptedPage),
        FixedCandidateAdapter(candidate: nil)
      ),
    ]
    for item in operationalCases {
      let observation = try resolveAndHandoffSynchronously(
        keys: item.keys,
        retriever: item.retriever,
        adapter: item.adapter,
        name: item.name
      )
      guard case .generic = observation.resolution else {
        XCTFail("\(item.name) must preserve generic")
        continue
      }
      XCTAssertEqual(observation.handlers, 1, item.name)
      XCTAssertTrue(observation.sameIdentity, item.name)
      XCTAssertEqual(observation.title, "title-\(item.name)", item.name)
      XCTAssertEqual(observation.subtitle, "subtitle-\(item.name)", item.name)
      XCTAssertEqual(observation.body, "body-\(item.name)", item.name)
      XCTAssertEqual(observation.category, "category-\(item.name)", item.name)
      XCTAssertEqual(observation.thread, "thread-\(item.name)", item.name)
      XCTAssertTrue(observation.hasSound, item.name)
    }

    // Expiry claims the same completion generation before the late resolver
    // can publish. The stale callback cannot mutate state or invoke a second
    // handler even when it carries an authenticated result.
    let completionGeneration = NotificationServiceCompletionGate()
    var expiredHandlers = 0
    var latePublished = false
    let generation = completionGeneration.reset { _ in }
    XCTAssertTrue(completionGeneration.claim(generation: generation) {
      expiredHandlers += 1
    })
    let latePublish = expectation(description: "late generation rejected")
    DispatchQueue.global().asyncAfter(deadline: .now() + .milliseconds(25)) {
      latePublished = completionGeneration.publish(generation: generation) {
        expiredHandlers += 100
      }
      latePublish.fulfill()
    }
    wait(for: [latePublish], timeout: 1)
    XCTAssertFalse(latePublished)
    XCTAssertEqual(expiredHandlers, 1)

    // A contended recovery flock returns within the NSE bound and never
    // mutates/copies the immutable generic content.
    let recoveryLock = root.appendingPathComponent(
      ".ios_notification_recovery.lock"
    )
    let descriptor = open(recoveryLock.path, O_RDWR | O_CLOEXEC)
    XCTAssertGreaterThanOrEqual(descriptor, 0)
    XCTAssertEqual(flock(descriptor, LOCK_EX | LOCK_NB), 0)
    let contended = expectation(description: "bounded recovery contention")
    let started = Date()
    coordinator.resolve(requestIdentifier: "contended-request") { resolution in
      guard case let .generic(contendedLease) = resolution else {
        return XCTFail("contention must stay generic")
      }
      XCTAssertNil(contendedLease)
      contended.fulfill()
    }
    wait(for: [contended], timeout: 1)
    XCTAssertLessThan(Date().timeIntervalSince(started), 0.75)
    _ = flock(descriptor, LOCK_UN)
    close(descriptor)

    // Mutable-copy unavailability is checked before any ledger seed/claim.
    let registry = root.appendingPathComponent("copy-unavailable-registry")
    try FileManager.default.createDirectory(
      at: registry,
      withIntermediateDirectories: false
    )
    try Data().write(
      to: registry.appendingPathComponent(
        IosLocalNotificationFinalEffect.lockFileName
      )
    )
    let ledgerURL = registry.appendingPathComponent(
      IosLocalNotificationFinalEffect.ledgerFileName
    )
    try emptyLedger().write(to: ledgerURL)
    let before = try Data(contentsOf: ledgerURL)
    let copyUnavailable = IosLocalNotificationFinalEffect(
      directory: registry,
      recoveryStore: store,
      currentOpaqueBinding: { self.binding },
      readProjectionDocument: { key in self.projectionDocuments()[key] },
      readVisibility: { self.backgroundVisibility() },
      readDeliveredInventory: { .unavailable },
      retireDeliveredRequests: { _ in },
      mutableContentCopy: { _ in nil }
    )
    let copyLease = try XCTUnwrap(
      store.prepareMailboxAlertLease(
        requestIdentifier: "copy-unavailable",
        accountPeerId: account,
        opaqueBinding: binding
      )
    )
    var copyHandlers = 0
    XCTAssertEqual(
      copyUnavailable.complete(
        candidate: candidate(),
        lease: copyLease,
        originalContent: original,
        contentHandler: { _ in copyHandlers += 1 }
      ),
      .genericFallback
    )
    XCTAssertEqual(copyHandlers, 0)
    XCTAssertEqual(try Data(contentsOf: ledgerURL), before)
    var copyFallbackHandlers = 0
    coordinator.handoffGeneric(
      lease: copyLease,
      content: original,
      contentHandler: { fallback in
        copyFallbackHandlers += 1
        XCTAssertTrue(fallback === original)
      }
    )
    XCTAssertEqual(copyFallbackHandlers, 1)

    // The shared Plan-372 ledger flock is also bounded. Contention cannot seed
    // or claim a row and the caller remains responsible for handing off the
    // immutable generic content.
    let ledgerLockURL = registry.appendingPathComponent(
      IosLocalNotificationFinalEffect.lockFileName
    )
    let ledgerDescriptor = open(ledgerLockURL.path, O_RDWR | O_CLOEXEC)
    XCTAssertGreaterThanOrEqual(ledgerDescriptor, 0)
    XCTAssertEqual(flock(ledgerDescriptor, LOCK_EX | LOCK_NB), 0)
    let ledgerStarted = Date()
    let ledgerBusyLease = try XCTUnwrap(
      store.prepareMailboxAlertLease(
        requestIdentifier: "ledger-busy",
        accountPeerId: account,
        opaqueBinding: binding
      )
    )
    XCTAssertEqual(
      IosLocalNotificationFinalEffect(
        directory: registry,
        recoveryStore: store,
        currentOpaqueBinding: { self.binding },
        readProjectionDocument: { self.projectionDocuments()[$0] },
        readVisibility: { self.backgroundVisibility() },
        readDeliveredInventory: { .unavailable },
        retireDeliveredRequests: { _ in }
      ).complete(
        candidate: candidate(),
        lease: ledgerBusyLease,
        originalContent: original,
        contentHandler: { _ in XCTFail("busy ledger cannot own handoff") }
      ),
      .genericFallback
    )
    XCTAssertLessThan(Date().timeIntervalSince(ledgerStarted), 0.75)
    _ = flock(ledgerDescriptor, LOCK_UN)
    close(ledgerDescriptor)
    XCTAssertEqual(try Data(contentsOf: ledgerURL), before)
    var ledgerBusyFallbackHandlers = 0
    coordinator.handoffGeneric(
      lease: ledgerBusyLease,
      content: original,
      contentHandler: { fallback in
        ledgerBusyFallbackHandlers += 1
        XCTAssertTrue(fallback === original)
      }
    )
    XCTAssertEqual(ledgerBusyFallbackHandlers, 1)
  }

  func testTC37305AuthenticatedCandidatesShareOneFinalEffectOwner() throws {
    XCTAssertEqual(
      IosLocalNotificationFinalEffect.directoryName,
      "NotificationConversationIds",
      "NSE must use the one Plan-372 logical registry"
    )
    XCTAssertEqual(
      IosLocalNotificationFinalEffect.lockFileName,
      ".coordination.lock",
      "NSE must use the one Plan-372 flock"
    )
    XCTAssertEqual(
      NseInboxCandidateAdapter.dartJSONDoubleForTesting(0.0),
      "0.0"
    )
    XCTAssertEqual(
      NseInboxCandidateAdapter.dartJSONDoubleForTesting(0.000001),
      "0.000001"
    )
    XCTAssertEqual(
      NseInboxCandidateAdapter.dartJSONDoubleForTesting(1e-7),
      "1e-7"
    )
    XCTAssertEqual(
      NseInboxCandidateAdapter.dartJSONDoubleForTesting(1e20),
      "100000000000000000000.0"
    )

    let fixture = try loadMailboxFixture()
    XCTAssertEqual(
      Set(fixture.root.keys),
      [
        "schemaVersion", "transportProjection", "directContactsProjection",
        "directAuthoredTargetsProjection", "groupContextsProjection",
        "groupAuthoredTargetsProjection", "groupLatestStatesProjection",
        "relayOrder", "rows", "cryptoMaterial",
      ]
    )
    XCTAssertEqual((fixture.root["schemaVersion"] as? NSNumber)?.intValue, 1)
    XCTAssertEqual(fixture.rows.count, 31)

    let fixtureReader = FixedKeyReader(fixture.keychainValues)
    let fixtureCredential = try XCTUnwrap(
      NseInboxCredentialReader(keyReader: fixtureReader).read()
    )
    XCTAssertEqual(
      fixtureCredential.relayMultiaddrs,
      try XCTUnwrap(fixture.root["relayOrder"] as? [String])
    )
    // The same real Ed25519 bytes/peer/relay vector must cross Go's strict
    // libp2p parser and identity derivation. The reserved `.invalid` relays
    // make the bounded static result retrieval-unavailable—not malformed or
    // identity-mismatched—and do not expose a network dependency.
    let goRequest = try XCTUnwrap(fixtureCredential.requestJSON(timeoutMs: 250))
    let goStarted = Date()
    let goResponse = try GoNseInboxRetriever().retrievePending(
      requestJSON: goRequest
    )
    XCTAssertLessThan(Date().timeIntervalSince(goStarted), 3.0)
    let goError = try XCTUnwrap(
      try JSONSerialization.jsonObject(with: Data(goResponse.utf8))
        as? [String: Any]
    )
    XCTAssertEqual(Set(goError.keys), ["ok", "errorCode", "errorMessage"])
    XCTAssertEqual(goError["ok"] as? Bool, false)
    XCTAssertEqual(goError["errorCode"] as? String, "INBOX_UNAVAILABLE")
    XCTAssertEqual(
      goError["errorMessage"] as? String,
      "NSE inbox retrieval unavailable"
    )
    let fixtureDecryptor = BridgePushDecryptor()
    let fixtureResolver = NotificationPreviewResolver(
      keyReader: fixtureReader,
      decryptor: fixtureDecryptor,
      dedupeStore: nil,
      toneLeaseStore: nil,
      eventEmitter: FixedNoopEmitter()
    )
    let fixtureAdapter = NseInboxCandidateAdapter(
      keyReader: fixtureReader,
      decryptor: fixtureDecryptor,
      previewResolver: fixtureResolver,
      now: { self.isoDate("2026-08-16T00:04:00.000000Z") }
    )
    var seenFixtureIds = Set<String>()
    var fixtureCensus = [
      "accepted": 0,
      "rejected": 0,
      "invalid": 0,
    ]
    var acceptedCorrelations = Set<String>()
    var acceptedCandidates: [String: NseInboxCandidate] = [:]
    for rawRow in fixture.rows {
      let classification = rawRow["classification"] as? String
      XCTAssertEqual(
        Set(rawRow.keys),
        classification == "accepted"
          ? ["id", "classification", "kind", "rawEnvelope", "expected"]
          : ["id", "classification", "kind", "rawEnvelope"]
      )
      let rowId = try XCTUnwrap(rawRow["id"] as? String)
      XCTAssertTrue(seenFixtureIds.insert(rowId).inserted, rowId)
      let expected = try XCTUnwrap(rawRow["classification"] as? String)
      XCTAssertNotNil(fixtureCensus[expected], rowId)
      let expectedKind = try XCTUnwrap(rawRow["kind"] as? String)
      let rawEnvelope = try XCTUnwrap(
        rawRow["rawEnvelope"] as? [String: Any]
      )
      let encodedPage = try canonicalJSONString(rawEnvelope)
      let observed: String
      if let page = NseMailboxWakeCoordinator.decodePage(encodedPage),
         !page.hasMore,
         let retrieved = page.messages.first {
        if let adapted = fixtureAdapter.adapt(
          retrieved,
          credential: fixtureCredential
        ) {
          observed = "accepted"
          if let expectedCandidate = rawRow["expected"] as? [String: Any] {
            XCTAssertTrue(
              acceptedCorrelations.insert(adapted.eventCorrelation).inserted,
              rowId
            )
            acceptedCandidates[rowId] = adapted
            assertFixtureCandidate(
              adapted,
              expected: expectedCandidate,
              expectedKind: expectedKind,
              rowId: rowId
            )
          } else {
            XCTFail("nonaccepted fixture row unexpectedly adapted: \(rowId)")
          }
        } else if isExplicitlyRejectedFixtureEnvelope(
          retrieved.message,
          decryptor: fixtureDecryptor,
          secretKey: fixture.keychainValues[
            PushSharedKeyNames.identityMlKemSecretKey
          ]
        ) {
          observed = "rejected"
        } else {
          observed = "invalid"
        }
      } else {
        observed = "invalid"
      }
      XCTAssertEqual(observed, expected, rowId)
      fixtureCensus[observed, default: 0] += 1
    }
    XCTAssertEqual(seenFixtureIds.count, 31)
    XCTAssertEqual(acceptedCorrelations.count, 14)
    XCTAssertEqual(fixtureCensus["accepted"], 14)
    XCTAssertEqual(fixtureCensus["rejected"], 6)
    XCTAssertEqual(fixtureCensus["invalid"], 11)
    XCTAssertEqual(acceptedCandidates.count, 14)
    XCTAssertEqual(
      acceptedCandidates["accepted-group-message-voice-descriptor"]?
        .preview.body,
      "Group Sender: Voice message"
    )
    XCTAssertEqual(
      acceptedCandidates["accepted-group-reaction-add"]?.preview.reason,
      "group_reaction",
      "verified reaction state id must reach the incumbent rich renderer"
    )
    try emitFixtureCensus(fixtureCensus)

    // Native attacker mutations are derived serially from accepted real
    // producer rows and never alter the frozen 31-row census. Each changes one
    // authenticated field/document and recomputes nothing.
    XCTAssertNotNil(try adaptFixtureRow(
      "accepted-group-message-text",
      fixture: fixture
    ))
    for mutation in [
      "signature",
      "recipient-removal",
      "recipient-addition",
      "ciphertext-hash-binding",
      "nonce-hash-binding",
      "content-event-key",
      "message-event-key",
      "signed-plaintext-hash-binding",
    ] {
      let mutated = try mutatedGroupEnvelope(
        fixture: fixture,
        rowId: "accepted-group-message-text",
        mutation: mutation
      )
      XCTAssertNil(try adaptFixtureRow(
        "accepted-group-message-text",
        fixture: fixture,
        rawEnvelopeOverride: mutated
      ), mutation)
    }

    var signerMismatch = try deepCopyMap(
      fixture.root["groupContextsProjection"]
    )
    var signerGroups = try XCTUnwrap(
      signerMismatch["groups"] as? [String: Any]
    )
    var signerGroup = try XCTUnwrap(signerGroups["group-chat"] as? [String: Any])
    var signerAuthority = try XCTUnwrap(
      signerGroup["senderAuthority"] as? [String: Any]
    )
    var signerTuples = try XCTUnwrap(
      signerAuthority["tuples"] as? [[String: Any]]
    )
    signerTuples[0]["signingPublicKey"] = Data(repeating: 1, count: 32)
      .base64EncodedString()
    signerAuthority["tuples"] = signerTuples
    signerGroup["senderAuthority"] = signerAuthority
    signerGroups["group-chat"] = signerGroup
    signerMismatch["groups"] = signerGroups
    XCTAssertNil(try adaptFixtureRow(
      "accepted-group-message-text",
      fixture: fixture,
      keyOverrides: [
        PushSharedKeyNames.groupReactionContexts:
          try canonicalJSONString(signerMismatch),
      ]
    ), "signer-key versus authenticated transport")

    // Muted/archived policy cannot bypass current group membership merely
    // because the candidate will render passively. Keep the signed sender
    // tuple intact and retire only that sender's member row.
    let mutedRow = try XCTUnwrap(fixture.rows.first {
      $0["id"] as? String == "accepted-group-message-policy-muted"
    })
    let mutedPage = try XCTUnwrap(
      mutedRow["rawEnvelope"] as? [String: Any]
    )
    let mutedMessage = try XCTUnwrap(
      (mutedPage["messages"] as? [[String: Any]])?.first?["message"]
        as? String
    )
    let mutedEnvelope = try XCTUnwrap(
      try JSONSerialization.jsonObject(with: Data(mutedMessage.utf8))
        as? [String: Any]
    )
    let mutedSender = try XCTUnwrap(mutedEnvelope["senderPeerId"] as? String)
    var missingMutedMember = try deepCopyMap(
      fixture.root["groupContextsProjection"]
    )
    var mutedGroups = try XCTUnwrap(
      missingMutedMember["groups"] as? [String: Any]
    )
    var mutedGroup = try XCTUnwrap(
      mutedGroups["group-muted"] as? [String: Any]
    )
    var mutedMembers = try XCTUnwrap(
      mutedGroup["members"] as? [String: Any]
    )
    mutedMembers.removeValue(forKey: mutedSender)
    mutedGroup["members"] = mutedMembers
    mutedGroups["group-muted"] = mutedGroup
    missingMutedMember["groups"] = mutedGroups
    XCTAssertNil(try adaptFixtureRow(
      "accepted-group-message-policy-muted",
      fixture: fixture,
      keyOverrides: [
        PushSharedKeyNames.groupReactionContexts:
          try canonicalJSONString(missingMutedMember),
      ]
    ), "suppressed group message requires current member authority")

    // Both ADD and REMOVE require current local-authored target/state
    // authority even when REMOVE will render only a suppressed passive effect.
    var directTargets = try deepCopyMap(
      fixture.root["directAuthoredTargetsProjection"]
    )
    var rawDirectTargets = try XCTUnwrap(
      directTargets["targets"] as? [[String: Any]]
    )
    rawDirectTargets.removeAll { $0["id"] as? String == "direct-target" }
    directTargets["targets"] = rawDirectTargets
    XCTAssertNil(try adaptFixtureRow(
      "accepted-direct-reaction-remove-linked",
      fixture: fixture,
      keyOverrides: [
        PushSharedKeyNames.directReactionAuthoredTargets:
          try canonicalJSONString(directTargets),
      ]
    ), "direct REMOVE wrong target")

    var crossedDirectTargets = try deepCopyMap(
      fixture.root["directAuthoredTargetsProjection"]
    )
    var crossedDirectRows = try XCTUnwrap(
      crossedDirectTargets["targets"] as? [[String: Any]]
    )
    crossedDirectRows.append([
      "id": "unused-crossed-target",
      "peerId": "12D3KooWJsEmQWn5WGGn9AZX79emq3RkGNx2ihFwWzZAqbiUQGMF",
      "timestamp": "2026-08-15T23:59:59.000000Z",
    ])
    crossedDirectTargets["targets"] = crossedDirectRows
    XCTAssertNil(try adaptFixtureRow(
      "accepted-direct-reaction-add-linked",
      fixture: fixture,
      keyOverrides: [
        PushSharedKeyNames.directReactionAuthoredTargets:
          try canonicalJSONString(crossedDirectTargets),
      ]
    ), "malformed unused direct target reference")

    var groupTargets = try deepCopyMap(
      fixture.root["groupAuthoredTargetsProjection"]
    )
    var rawGroupTargets = try XCTUnwrap(
      groupTargets["targets"] as? [[String: Any]]
    )
    let removeTargetIndex = try XCTUnwrap(rawGroupTargets.firstIndex {
      $0["id"] as? String == "group-target-message-remove"
    })
    rawGroupTargets[removeTargetIndex]["groupId"] = "group-muted"
    groupTargets["targets"] = rawGroupTargets
    XCTAssertNil(try adaptFixtureRow(
      "accepted-group-reaction-remove",
      fixture: fixture,
      keyOverrides: [
        PushSharedKeyNames.groupReactionAuthoredTargets:
          try canonicalJSONString(groupTargets),
      ]
    ), "group REMOVE wrong target")

    var groupStates = try deepCopyMap(
      fixture.root["groupLatestStatesProjection"]
    )
    var rawGroupStates = try XCTUnwrap(
      groupStates["states"] as? [[String: Any]]
    )
    let removeStateIndex = try XCTUnwrap(rawGroupStates.firstIndex {
      $0["targetMessageId"] as? String == "group-target-message-remove"
    })
    rawGroupStates[removeStateIndex]["removedAt"] =
      "2026-08-16T00:01:00.000000Z"
    groupStates["states"] = rawGroupStates
    XCTAssertNil(try adaptFixtureRow(
      "accepted-group-reaction-remove",
      fixture: fixture,
      keyOverrides: [
        PushSharedKeyNames.groupReactionLatestStates:
          try canonicalJSONString(groupStates),
      ]
    ), "group REMOVE stale state")

    // Carry real incumbent-producer ciphertext/signatures through the shared
    // Plan-372 owner, not merely through the adapter. Direct and protected
    // group candidates must land on the exact frozen stable notification id.
    let fixtureDocuments = [
      NseInboxCredential.projectionKey: try XCTUnwrap(
        fixture.keychainValues[NseInboxCredential.projectionKey]
      ),
      PushSharedKeyNames.directReactionContacts: try XCTUnwrap(
        fixture.keychainValues[PushSharedKeyNames.directReactionContacts]
      ),
      PushSharedKeyNames.groupReactionContexts: try XCTUnwrap(
        fixture.keychainValues[PushSharedKeyNames.groupReactionContexts]
      ),
      PushSharedKeyNames.directReactionAuthoredTargets: try XCTUnwrap(
        fixture.keychainValues[
          PushSharedKeyNames.directReactionAuthoredTargets
        ]
      ),
      PushSharedKeyNames.groupReactionAuthoredTargets: try XCTUnwrap(
        fixture.keychainValues[
          PushSharedKeyNames.groupReactionAuthoredTargets
        ]
      ),
      PushSharedKeyNames.groupReactionLatestStates: try XCTUnwrap(
        fixture.keychainValues[PushSharedKeyNames.groupReactionLatestStates]
      ),
    ]
    var fixtureDirectHarness: EffectHarness?
    var fixtureHarnessRoots: [URL] = []
    defer {
      for root in fixtureHarnessRoots {
        try? FileManager.default.removeItem(at: root)
      }
    }
    for rowId in [
      "accepted-direct-text-linked",
      "accepted-group-message-text",
      "accepted-direct-reaction-add-linked",
      "accepted-group-reaction-add",
    ] {
      let realCandidate = try XCTUnwrap(acceptedCandidates[rowId])
      let realHarness = try makeEffectHarness(
        phase: "READY",
        updatedAt: "2026-08-16T10:00:00.000Z",
        now: "2026-08-16T10:00:01.000Z",
        inventory: IosLocalNotificationDeliveredInventory(
          querySucceeded: true,
          activeNotificationIds: [],
          requestIdentifiersByNotificationId: [:]
        ),
        candidate: realCandidate,
        projectionDocuments: fixtureDocuments
      )
      fixtureHarnessRoots.append(realHarness.root)
      var realContent: UNNotificationContent?
      XCTAssertEqual(realHarness.effect.complete(
        candidate: realCandidate,
        lease: realHarness.lease,
        originalContent: genericContent(),
        contentHandler: { realContent = $0 }
      ), .handled, rowId)
      XCTAssertEqual(realHarness.notificationId,
                     stableId(realCandidate.conversationKey), rowId)
      XCTAssertEqual(realContent?.targetContentIdentifier,
                     String(realHarness.notificationId), rowId)
      XCTAssertNotNil(realContent?.sound, rowId)
      let realRecord = try ledgerRecord(at: realHarness.registry)
      XCTAssertEqual(realRecord["eventCorrelation"] as? String,
                     realCandidate.eventCorrelation, rowId)
      XCTAssertEqual(realRecord["presentationOwner"] as? String,
                     "IOS_NSE", rowId)
      XCTAssertEqual(realRecord["effectPhase"] as? String,
                     "EFFECT_TERMINAL", rowId)
      if rowId == "accepted-direct-text-linked" {
        fixtureDirectHarness = realHarness
      }
    }

    // A second real owner for the same direct event is a privacy-clean,
    // same-id loser. Custody remains relay-owned and is never ACKed here.
    let realWinner = try XCTUnwrap(fixtureDirectHarness)
    let realLoserLease = try XCTUnwrap(
      realWinner.recovery.prepareMailboxAlertLease(
        requestIdentifier: "real-terminal-replay",
        accountPeerId: realWinner.candidate.recoveryIdentity.accountPeerId,
        opaqueBinding: realWinner.candidate.currentOpaqueBinding
      )
    )
    var realLoserContent: UNNotificationContent?
    XCTAssertEqual(realWinner.effect.complete(
      candidate: realWinner.candidate,
      lease: realLoserLease,
      originalContent: genericContent(),
      contentHandler: { realLoserContent = $0 }
    ), .handled)
    assertPrivacyCleanPassive(
      realLoserContent,
      targetNotificationId: realWinner.notificationId,
      message: "real fixture terminal loser"
    )
    XCTAssertEqual(
      try ledgerRecord(at: realWinner.registry)["sourceCustody"] as? String,
      "RELAY_VERIFIED_UNACKED"
    )

    // Every reaction-only authority document is part of the effect barrier.
    // Retiring it after adaptation but before cancel/final publication yields
    // only a privacy-clean same-id completion and retains PUBLISHING.
    for authorityCase in [
      (rowId: "accepted-direct-reaction-add-linked",
       key: PushSharedKeyNames.directReactionAuthoredTargets,
       failAfterReads: 1,
       includeOldCard: true),
      (rowId: "accepted-group-reaction-add",
       key: PushSharedKeyNames.groupReactionAuthoredTargets,
       failAfterReads: 2,
       includeOldCard: false),
      (rowId: "accepted-group-reaction-add",
       key: PushSharedKeyNames.groupReactionLatestStates,
       failAfterReads: 2,
       includeOldCard: false),
    ] {
      let reactionCandidate = try XCTUnwrap(
        acceptedCandidates[authorityCase.rowId]
      )
      let reactionId = stableId(reactionCandidate.conversationKey)
      var reads: [String: Int] = [:]
      var cancelled: [String] = []
      let reactionBarrier = try makeEffectHarness(
        phase: "READY",
        updatedAt: "2026-08-16T10:00:00.000Z",
        now: "2026-08-16T10:00:01.000Z",
        inventory: IosLocalNotificationDeliveredInventory(
          querySucceeded: true,
          activeNotificationIds: authorityCase.includeOldCard
            ? [reactionId] : [],
          requestIdentifiersByNotificationId: authorityCase.includeOldCard
            ? [reactionId: ["reaction-old-card"]] : [:]
        ),
        projectionReader: { key in
          reads[key, default: 0] += 1
          if key == authorityCase.key,
             reads[key, default: 0] > authorityCase.failAfterReads {
            return nil
          }
          return fixtureDocuments[key]
        },
        candidate: reactionCandidate,
        projectionDocuments: fixtureDocuments,
        retireDeliveredRequests: { cancelled.append(contentsOf: $0) }
      )
      defer { try? FileManager.default.removeItem(at: reactionBarrier.root) }
      var output: UNNotificationContent?
      XCTAssertEqual(reactionBarrier.effect.complete(
        candidate: reactionCandidate,
        lease: reactionBarrier.lease,
        originalContent: genericContent(),
        contentHandler: { output = $0 }
      ), .handled, authorityCase.key)
      XCTAssertTrue(cancelled.isEmpty, authorityCase.key)
      assertPrivacyCleanPassive(
        output,
        targetNotificationId: reactionId,
        message: authorityCase.key
      )
      XCTAssertEqual(
        try ledgerRecord(at: reactionBarrier.registry)["effectPhase"]
          as? String,
        "PUBLISHING",
        authorityCase.key
      )
    }

    let busyLedger = try makeEffectHarness(
      phase: "READY",
      updatedAt: "2026-08-16T10:00:00.000Z",
      now: "2026-08-16T10:00:01.000Z",
      inventory: .unavailable
    )
    defer { try? FileManager.default.removeItem(at: busyLedger.root) }
    let busyBefore = try Data(contentsOf:
      busyLedger.registry.appendingPathComponent(
        IosLocalNotificationFinalEffect.ledgerFileName
      )
    )
    let busyDescriptor = open(
      busyLedger.registry.appendingPathComponent(
        IosLocalNotificationFinalEffect.lockFileName
      ).path,
      O_RDWR | O_CLOEXEC
    )
    XCTAssertGreaterThanOrEqual(busyDescriptor, 0)
    XCTAssertEqual(flock(busyDescriptor, LOCK_EX | LOCK_NB), 0)
    var busyHandlers = 0
    XCTAssertEqual(busyLedger.effect.complete(
      candidate: busyLedger.candidate,
      lease: busyLedger.lease,
      originalContent: genericContent(),
      contentHandler: { _ in busyHandlers += 1 }
    ), .genericFallback)
    _ = flock(busyDescriptor, LOCK_UN)
    close(busyDescriptor)
    XCTAssertEqual(busyHandlers, 0)
    XCTAssertEqual(
      try Data(contentsOf: busyLedger.registry.appendingPathComponent(
        IosLocalNotificationFinalEffect.ledgerFileName
      )),
      busyBefore,
      "bounded flock contention never grants effect authority"
    )

    let sqlReady = try makeEffectHarness(
      phase: "READY",
      updatedAt: "2026-08-16T10:00:00.000Z",
      now: "2026-08-16T10:00:01.000Z",
      inventory: .unavailable,
      sourceCustody: "SQL_READY"
    )
    defer { try? FileManager.default.removeItem(at: sqlReady.root) }
    let sqlBefore = try Data(contentsOf:
      sqlReady.registry.appendingPathComponent(
        IosLocalNotificationFinalEffect.ledgerFileName
      )
    )
    var sqlHandlers = 0
    XCTAssertEqual(sqlReady.effect.complete(
      candidate: sqlReady.candidate,
      lease: sqlReady.lease,
      originalContent: genericContent(),
      contentHandler: { _ in sqlHandlers += 1 }
    ), .genericFallback)
    XCTAssertEqual(sqlHandlers, 0)
    XCTAssertEqual(
      try Data(contentsOf: sqlReady.registry.appendingPathComponent(
        IosLocalNotificationFinalEffect.ledgerFileName
      )),
      sqlBefore,
      "NSE cannot claim SQL-ready custody"
    )

    // A dangling symlink is an existing non-regular Plan-372 sidecar, even
    // though FileManager's follow-links existence check reports it absent.
    // It must never be replaced with candidate metadata.
    let nonregularMarker = try makeEffectHarness(
      phase: "READY",
      updatedAt: "2026-08-16T10:00:00.000Z",
      now: "2026-08-16T10:00:01.000Z",
      inventory: IosLocalNotificationDeliveredInventory(
        querySucceeded: true,
        activeNotificationIds: [],
        requestIdentifiersByNotificationId: [:]
      )
    )
    defer { try? FileManager.default.removeItem(at: nonregularMarker.root) }
    let nonregularURL = nonregularMarker.registry.appendingPathComponent(
      "\(nonregularMarker.notificationId)" +
        IosLocalNotificationFinalEffect.contentKindSuffix
    )
    XCTAssertEqual(
      symlink("missing-content-kind-target", nonregularURL.path),
      0
    )
    var nonregularHandlers = 0
    XCTAssertEqual(nonregularMarker.effect.complete(
      candidate: nonregularMarker.candidate,
      lease: nonregularMarker.lease,
      originalContent: genericContent(),
      contentHandler: { _ in nonregularHandlers += 1 }
    ), .genericFallback)
    XCTAssertEqual(nonregularHandlers, 0)
    var markerInfo = stat()
    XCTAssertEqual(lstat(nonregularURL.path, &markerInfo), 0)
    XCTAssertEqual(markerInfo.st_mode & S_IFMT, S_IFLNK)

    let ready = try makeEffectHarness(
      phase: "READY",
      updatedAt: "2026-08-16T10:00:00.123999Z",
      now: "2026-08-16T10:00:00.123Z",
      inventory: IosLocalNotificationDeliveredInventory(
        querySucceeded: true,
        activeNotificationIds: [],
        requestIdentifiersByNotificationId: [:]
      )
    )
    defer { try? FileManager.default.removeItem(at: ready.root) }
    var readyContent: UNNotificationContent?
    XCTAssertEqual(
      ready.effect.complete(
        candidate: ready.candidate,
        lease: ready.lease,
        originalContent: genericContent(),
        contentHandler: { readyContent = $0 }
      ),
      .handled
    )
    XCTAssertEqual(readyContent?.title, "Authenticated sender")
    XCTAssertNotNil(readyContent?.sound, "current READY claim may be audible")
    XCTAssertEqual(
      readyContent?.targetContentIdentifier,
      String(ready.notificationId)
    )
    let readyRecord = try ledgerRecord(at: ready.registry)
    XCTAssertEqual(readyRecord["effectPhase"] as? String, "EFFECT_TERMINAL")
    XCTAssertEqual(readyRecord["sourceCustody"] as? String,
                   "RELAY_VERIFIED_UNACKED")
    XCTAssertEqual(readyRecord["presentationOwner"] as? String, "IOS_NSE")
    XCTAssertEqual(
      readyRecord["updatedAtUtc"] as? String,
      "2026-08-16T10:00:00.123999Z",
      "millisecond now must not lexically precede a later microsecond instant"
    )
    let terminalReplayLease = try XCTUnwrap(
      ready.recovery.prepareMailboxAlertLease(
        requestIdentifier: "terminal-replay",
        accountPeerId: account,
        opaqueBinding: binding
      )
    )
    var terminalReplayContent: UNNotificationContent?
    XCTAssertEqual(ready.effect.complete(
      candidate: ready.candidate,
      lease: terminalReplayLease,
      originalContent: genericContent(),
      contentHandler: { terminalReplayContent = $0 }
    ), .handled)
    assertPrivacyCleanPassive(
      terminalReplayContent,
      targetNotificationId: ready.notificationId,
      message: "same-correlation loser"
    )
    let terminalReplayRecord = try ledgerRecord(at: ready.registry)
    XCTAssertEqual(
      terminalReplayRecord["effectPhase"] as? String,
      "EFFECT_TERMINAL"
    )
    XCTAssertEqual(
      terminalReplayRecord["sourceCustody"] as? String,
      "RELAY_VERIFIED_UNACKED",
      "NSE preview never upgrades or ACKs relay custody"
    )

    let freshClaim = try makeEffectHarness(
      phase: "CLAIMED",
      updatedAt: "2026-08-16T10:00:00.000Z",
      now: "2026-08-16T10:00:30.000Z",
      inventory: .unavailable
    )
    defer { try? FileManager.default.removeItem(at: freshClaim.root) }
    var freshContent: UNNotificationContent?
    XCTAssertEqual(freshClaim.effect.complete(
      candidate: freshClaim.candidate,
      lease: freshClaim.lease,
      originalContent: genericContent(),
      contentHandler: { freshContent = $0 }
    ), .handled)
    assertPrivacyCleanPassive(freshContent, targetNotificationId: nil)
    XCTAssertEqual(
      try ledgerRecord(at: freshClaim.registry)["effectPhase"] as? String,
      "CLAIMED"
    )
    XCTAssertEqual(
      freshClaim.recovery.beginReconciliation(accountPeerId: account)?
        .mailboxAlertLease?.phase,
      .publishing,
      "fresh CLAIMED ambiguity must remain available to silent drain recovery"
    )

    let agedClaim = try makeEffectHarness(
      phase: "CLAIMED",
      updatedAt: "2026-08-16T09:58:00.000Z",
      now: "2026-08-16T10:00:00.000Z",
      inventory: IosLocalNotificationDeliveredInventory(
        querySucceeded: true,
        activeNotificationIds: [],
        requestIdentifiersByNotificationId: [:]
      )
    )
    defer { try? FileManager.default.removeItem(at: agedClaim.root) }
    var agedContent: UNNotificationContent?
    XCTAssertEqual(agedClaim.effect.complete(
      candidate: agedClaim.candidate,
      lease: agedClaim.lease,
      originalContent: genericContent(),
      contentHandler: { agedContent = $0 }
    ), .handled)
    assertPrivacyCleanPassive(
      agedContent,
      targetNotificationId: agedClaim.notificationId
    )
    XCTAssertEqual(
      try ledgerRecord(at: agedClaim.registry)["effectPhase"] as? String,
      "EFFECT_TERMINAL"
    )

    for item in [
      (name: "exact-active", inventory: IosLocalNotificationDeliveredInventory(
        querySucceeded: true,
        activeNotificationIds: [agedClaim.notificationId],
        requestIdentifiersByNotificationId: [
          agedClaim.notificationId: ["apple-existing"],
        ]
      ), age: 5.0, terminal: true, target: true),
      (name: "fresh-unknown", inventory: .unavailable,
       age: 5.0, terminal: false, target: true),
      (name: "aged-unknown", inventory: .unavailable,
       age: 70.0, terminal: true, target: true),
    ] {
      let publishing = try makeEffectHarness(
        phase: "PUBLISHING",
        updatedAt: "2026-08-16T09:58:50.000Z",
        now: isoDate("2026-08-16T09:58:50.000Z")
          .addingTimeInterval(item.age),
        inventory: item.inventory,
        notificationIdOverride: agedClaim.notificationId
      )
      defer { try? FileManager.default.removeItem(at: publishing.root) }
      var output: UNNotificationContent?
      XCTAssertEqual(publishing.effect.complete(
        candidate: publishing.candidate,
        lease: publishing.lease,
        originalContent: genericContent(),
        contentHandler: { output = $0 }
      ), .handled, item.name)
      assertPrivacyCleanPassive(
        output,
        targetNotificationId: item.target ? publishing.notificationId : nil,
        message: item.name
      )
      XCTAssertEqual(
        try ledgerRecord(at: publishing.registry)["effectPhase"] as? String,
        item.terminal ? "EFFECT_TERMINAL" : "PUBLISHING",
        item.name
      )
    }

    var currentDocuments = projectionDocuments()
    let retiredAuthority = try makeEffectHarness(
      phase: "READY",
      updatedAt: "2026-08-16T10:00:00.000Z",
      now: "2026-08-16T10:00:01.000Z",
      inventory: IosLocalNotificationDeliveredInventory(
        querySucceeded: true,
        activeNotificationIds: [],
        requestIdentifiersByNotificationId: [:]
      ),
      projectionReader: { currentDocuments[$0] }
    )
    defer { try? FileManager.default.removeItem(at: retiredAuthority.root) }
    let retiredBefore = try Data(contentsOf:
      retiredAuthority.registry.appendingPathComponent(
        IosLocalNotificationFinalEffect.ledgerFileName
      )
    )
    currentDocuments.removeValue(
      forKey: PushSharedKeyNames.directReactionContacts
    )
    var retiredHandlers = 0
    XCTAssertEqual(retiredAuthority.effect.complete(
      candidate: retiredAuthority.candidate,
      lease: retiredAuthority.lease,
      originalContent: genericContent(),
      contentHandler: { _ in retiredHandlers += 1 }
    ), .genericFallback)
    XCTAssertEqual(retiredHandlers, 0)
    XCTAssertEqual(
      try Data(contentsOf: retiredAuthority.registry.appendingPathComponent(
        IosLocalNotificationFinalEffect.ledgerFileName
      )),
      retiredBefore
    )

    // Authority is checked again only after the recovery lease has crossed
    // PUBLISHING. Retiring either exact document between adaptation and that
    // last barrier must yield a same-id passive completion and leave the
    // ledger PUBLISHING for conservative recovery.
    for retiredKey in [
      NseInboxCredential.projectionKey,
      PushSharedKeyNames.directReactionContacts,
    ] {
      let documents = projectionDocuments()
      var readsByKey: [String: Int] = [:]
      let midBarrierRetirement = try makeEffectHarness(
        phase: "READY",
        updatedAt: "2026-08-16T10:00:00.000Z",
        now: "2026-08-16T10:00:01.000Z",
        inventory: IosLocalNotificationDeliveredInventory(
          querySucceeded: true,
          activeNotificationIds: [],
          requestIdentifiersByNotificationId: [:]
        ),
        projectionReader: { key in
          readsByKey[key, default: 0] += 1
          if key == retiredKey && readsByKey[key, default: 0] > 1 {
            return nil
          }
          return documents[key]
        }
      )
      defer {
        try? FileManager.default.removeItem(at: midBarrierRetirement.root)
      }
      var output: UNNotificationContent?
      XCTAssertEqual(midBarrierRetirement.effect.complete(
        candidate: midBarrierRetirement.candidate,
        lease: midBarrierRetirement.lease,
        originalContent: genericContent(),
        contentHandler: { output = $0 }
      ), .handled, retiredKey)
      assertPrivacyCleanPassive(
        output,
        targetNotificationId: midBarrierRetirement.notificationId,
        message: retiredKey
      )
      XCTAssertEqual(
        try ledgerRecord(at: midBarrierRetirement.registry)[
          "effectPhase"
        ] as? String,
        "PUBLISHING",
        retiredKey
      )
    }

    // Delivered-request cancellation is an irreversible effect too. A
    // suppressed exact-active recovery may cancel only after the same final
    // projection barrier that gates publication and terminalization.
    let suppressedCandidate = try XCTUnwrap(
      acceptedCandidates["accepted-group-message-policy-muted"]
    )
    var suppressedReads: [String: Int] = [:]
    var retiredRequestIdentifiers: [String] = []
    let suppressedId = stableId(suppressedCandidate.conversationKey)
    let cancelledAfterBarrier = try makeEffectHarness(
      phase: "PUBLISHING",
      updatedAt: "2026-08-16T09:59:00.000Z",
      now: "2026-08-16T10:00:01.000Z",
      inventory: IosLocalNotificationDeliveredInventory(
        querySucceeded: true,
        activeNotificationIds: [suppressedId],
        requestIdentifiersByNotificationId: [
          suppressedId: ["delivered-suppressed"],
        ]
      ),
      projectionReader: { key in
        suppressedReads[key, default: 0] += 1
        if key == PushSharedKeyNames.groupReactionContexts,
           suppressedReads[key, default: 0] > 1 {
          return nil
        }
        return fixtureDocuments[key]
      },
      candidate: suppressedCandidate,
      projectionDocuments: fixtureDocuments,
      retireDeliveredRequests: {
        retiredRequestIdentifiers.append(contentsOf: $0)
      }
    )
    defer {
      try? FileManager.default.removeItem(at: cancelledAfterBarrier.root)
    }
    var cancelledOutput: UNNotificationContent?
    XCTAssertEqual(cancelledAfterBarrier.effect.complete(
      candidate: suppressedCandidate,
      lease: cancelledAfterBarrier.lease,
      originalContent: genericContent(),
      contentHandler: { cancelledOutput = $0 }
    ), .handled)
    XCTAssertTrue(retiredRequestIdentifiers.isEmpty)
    assertPrivacyCleanPassive(
      cancelledOutput,
      targetNotificationId: suppressedId,
      message: "retired group projection before cancel barrier"
    )
    XCTAssertEqual(
      try ledgerRecord(at: cancelledAfterBarrier.registry)["effectPhase"]
        as? String,
      "PUBLISHING"
    )

    let replacementCandidate = try XCTUnwrap(
      acceptedCandidates["accepted-direct-text-linked"]
    )
    let oldMetadata = metadata(
      kind: "message",
      event: String(repeating: "e", count: 64)
    )
    let oldMetadataDigest = metadataDigest(oldMetadata)
    let nextMetadata = metadata(replacementCandidate)
    let nextMetadataDigest = metadataDigest(nextMetadata)

    // Fresh replacement: projection retirement at the pre-cancel boundary
    // leaves both the old card and old marker untouched.
    var freshCancelReads: [String: Int] = [:]
    var freshCancelled: [String] = []
    let freshReplacementId = stableId(replacementCandidate.conversationKey)
    let freshReplacement = try makeEffectHarness(
      phase: "READY",
      updatedAt: "2026-08-16T10:00:00.000Z",
      now: "2026-08-16T10:00:01.000Z",
      inventory: IosLocalNotificationDeliveredInventory(
        querySucceeded: true,
        activeNotificationIds: [freshReplacementId],
        requestIdentifiersByNotificationId: [
          freshReplacementId: ["old-direct-card"],
        ]
      ),
      projectionReader: { key in
        freshCancelReads[key, default: 0] += 1
        if key == PushSharedKeyNames.directReactionContacts,
           freshCancelReads[key, default: 0] > 1 {
          return nil
        }
        return fixtureDocuments[key]
      },
      candidate: replacementCandidate,
      projectionDocuments: fixtureDocuments,
      retireDeliveredRequests: { freshCancelled.append(contentsOf: $0) }
    )
    defer { try? FileManager.default.removeItem(at: freshReplacement.root) }
    let freshMarker = freshReplacement.registry.appendingPathComponent(
      "\(freshReplacementId)\(IosLocalNotificationFinalEffect.contentKindSuffix)"
    )
    try oldMetadata.write(to: freshMarker)
    var freshReplacementOutput: UNNotificationContent?
    XCTAssertEqual(freshReplacement.effect.complete(
      candidate: replacementCandidate,
      lease: freshReplacement.lease,
      originalContent: genericContent(),
      contentHandler: { freshReplacementOutput = $0 }
    ), .handled)
    XCTAssertTrue(freshCancelled.isEmpty)
    XCTAssertEqual(try Data(contentsOf: freshMarker), oldMetadata)
    assertPrivacyCleanPassive(
      freshReplacementOutput,
      targetNotificationId: freshReplacementId,
      message: "fresh replacement authority retirement"
    )

    // Recovered intent follows the identical pre-cancel barrier. Losing
    // authority cannot retire the incumbent request or activate new metadata.
    var recoveredCancelReads: [String: Int] = [:]
    var recoveredCancelled: [String] = []
    let recoveredReplacement = try makeEffectHarness(
      phase: "PUBLISHING",
      updatedAt: "2026-08-16T09:59:00.000Z",
      now: "2026-08-16T10:00:01.000Z",
      inventory: IosLocalNotificationDeliveredInventory(
        querySucceeded: true,
        activeNotificationIds: [freshReplacementId],
        requestIdentifiersByNotificationId: [
          freshReplacementId: ["old-recovered-card"],
        ]
      ),
      notificationIdOverride: freshReplacementId,
      projectionReader: { key in
        recoveredCancelReads[key, default: 0] += 1
        if key == PushSharedKeyNames.directReactionContacts,
           recoveredCancelReads[key, default: 0] > 1 {
          return nil
        }
        return fixtureDocuments[key]
      },
      candidate: replacementCandidate,
      projectionDocuments: fixtureDocuments,
      retireDeliveredRequests: { recoveredCancelled.append(contentsOf: $0) }
    )
    defer {
      try? FileManager.default.removeItem(at: recoveredReplacement.root)
    }
    let recoveredMarker = recoveredReplacement.registry.appendingPathComponent(
      "\(freshReplacementId)\(IosLocalNotificationFinalEffect.contentKindSuffix)"
    )
    try oldMetadata.write(to: recoveredMarker, options: .atomic)
    try contentIntent(
      binding: replacementCandidate.currentOpaqueBinding,
      previousDigest: oldMetadataDigest,
      nextDigest: nextMetadataDigest
    ).write(to: recoveredReplacement.registry.appendingPathComponent(
      "\(freshReplacementId)\(IosLocalNotificationFinalEffect.contentIntentSuffix)"
    ))
    var recoveredOutput: UNNotificationContent?
    XCTAssertEqual(recoveredReplacement.effect.complete(
      candidate: replacementCandidate,
      lease: recoveredReplacement.lease,
      originalContent: genericContent(),
      contentHandler: { recoveredOutput = $0 }
    ), .handled)
    XCTAssertTrue(recoveredCancelled.isEmpty)
    XCTAssertEqual(try Data(contentsOf: recoveredMarker), oldMetadata)
    assertPrivacyCleanPassive(
      recoveredOutput,
      targetNotificationId: freshReplacementId,
      message: "recovered intent authority retirement"
    )

    // Stable authority proves the exact effect order: cancel the incumbent
    // request, activate/fsync the new marker, then invoke Apple's handler.
    var orderedRegistry: URL?
    var effectOrder: [String] = []
    let orderedReplacement = try makeEffectHarness(
      phase: "READY",
      updatedAt: "2026-08-16T10:00:00.000Z",
      now: "2026-08-16T10:00:01.000Z",
      inventory: IosLocalNotificationDeliveredInventory(
        querySucceeded: true,
        activeNotificationIds: [freshReplacementId],
        requestIdentifiersByNotificationId: [
          freshReplacementId: ["ordered-old-card"],
        ]
      ),
      candidate: replacementCandidate,
      projectionDocuments: fixtureDocuments,
      retireDeliveredRequests: { identifiers in
        XCTAssertEqual(identifiers, ["ordered-old-card"])
        if let orderedRegistry {
          let marker = orderedRegistry.appendingPathComponent(
            "\(freshReplacementId)\(IosLocalNotificationFinalEffect.contentKindSuffix)"
          )
          XCTAssertEqual(try? Data(contentsOf: marker), oldMetadata)
        }
        effectOrder.append("cancel")
      }
    )
    defer {
      try? FileManager.default.removeItem(at: orderedReplacement.root)
    }
    orderedRegistry = orderedReplacement.registry
    let orderedMarker = orderedReplacement.registry.appendingPathComponent(
      "\(freshReplacementId)\(IosLocalNotificationFinalEffect.contentKindSuffix)"
    )
    try oldMetadata.write(to: orderedMarker)
    XCTAssertEqual(orderedReplacement.effect.complete(
      candidate: replacementCandidate,
      lease: orderedReplacement.lease,
      originalContent: genericContent(),
      contentHandler: { _ in
        XCTAssertEqual(try? Data(contentsOf: orderedMarker), nextMetadata)
        effectOrder.append("handler")
      }
    ), .handled)
    XCTAssertEqual(effectOrder, ["cancel", "handler"])
  }

  func testDartRemoteAdoptionAttemptsDecodeAndRemainPassive() throws {
    for testCase in [
      (phase: "CLAIMED", attempt: "ADOPT_EXISTING_REMOTE"),
      (
        phase: "PUBLISHING",
        attempt: "CANCEL_LOCAL_FOR_REMOTE_ADOPTION"
      ),
    ] {
      let harness = try makeEffectHarness(
        phase: testCase.phase,
        updatedAt: "2026-08-16T09:58:00.000Z",
        now: "2026-08-16T10:00:00.000Z",
        inventory: .unavailable
      )
      defer { try? FileManager.default.removeItem(at: harness.root) }

      try replaceLedgerAttemptKind(
        testCase.attempt,
        candidate: harness.candidate,
        registry: harness.registry
      )
      let ledgerURL = harness.registry.appendingPathComponent(
        IosLocalNotificationFinalEffect.ledgerFileName
      )
      let before = try Data(contentsOf: ledgerURL)
      var output: UNNotificationContent?
      var handlers = 0

      XCTAssertEqual(
        harness.effect.complete(
          candidate: harness.candidate,
          lease: harness.lease,
          originalContent: genericContent(),
          contentHandler: {
            handlers += 1
            output = $0
          }
        ),
        .handled,
        testCase.attempt
      )
      XCTAssertEqual(handlers, 1, testCase.attempt)
      assertPrivacyCleanPassive(
        output,
        targetNotificationId: nil,
        message: testCase.attempt
      )
      XCTAssertEqual(
        try Data(contentsOf: ledgerURL),
        before,
        "NSE must not reconcile Dart-owned \(testCase.attempt)"
      )
      XCTAssertEqual(
        try ledgerRecord(at: harness.registry)["attemptKind"] as? String,
        testCase.attempt
      )
      XCTAssertEqual(
        harness.recovery.beginReconciliation(accountPeerId: account)?
          .mailboxAlertLease?.phase,
        .publishing,
        "passive ambiguity remains available to canonical Dart recovery"
      )
    }
  }

  func testTC37306LegacyGroupAndUnsupportedRowsDoNotInventAuthority() throws {
    let hasMoreJSON =
      #"{"ok":true,"messages":[],"hasMore":true,"custodyContract":"ack_or_expiry_v1"}"#
    let hasMorePage = try XCTUnwrap(
      NseMailboxWakeCoordinator.decodePage(hasMoreJSON)
    )
    XCTAssertTrue(hasMorePage.messages.isEmpty)
    XCTAssertTrue(hasMorePage.hasMore)

    let hasMoreRetriever = CountingNseRetriever(response: hasMoreJSON)
    let hasMoreAdapter = FixedCandidateAdapter(candidate: candidate())
    let hasMoreObservation = try resolveAndHandoffSynchronously(
      keys: credentialKeys(),
      retriever: hasMoreRetriever,
      adapter: hasMoreAdapter,
      name: "tc37306-has-more"
    )
    guard case .generic = hasMoreObservation.resolution else {
      return XCTFail("hasMore must preserve the immutable generic handoff")
    }
    XCTAssertEqual(hasMoreObservation.handlers, 1)
    XCTAssertTrue(hasMoreObservation.sameIdentity)
    XCTAssertEqual(hasMoreRetriever.calls, 1, "hasMore must not refetch")
    XCTAssertEqual(hasMoreAdapter.calls, 0, "hasMore must not enter adaptation")

    XCTAssertNil(NseMailboxWakeCoordinator.decodePage(
      #"{"ok":true,"messages":[],"hasMore":false,"custodyContract":"future"}"#
    ))
    XCTAssertNil(NseMailboxWakeCoordinator.decodePage(
      #"{"ok":false,"errorCode":"FUTURE","errorMessage":"raw detail"}"#
    ))
    XCTAssertNil(NseMailboxWakeCoordinator.decodePage(
      #"{"ok":true,"messages":[{"id":"a","from":"b","message":"{}","timestamp":1},{"id":"c","from":"d","message":"{}","timestamp":2}],"hasMore":false,"custodyContract":"ack_or_expiry_v1"}"#
    ))
    let legacy = NseInboxRetrievedMessage(
      id: "legacy",
      from: "transport",
      message: #"{"type":"group_message","groupId":"guessed"}"#,
      timestamp: 1
    )
    let adapter = NseInboxCandidateAdapter(
      keyReader: FixedKeyReader([:]),
      decryptor: RejectingDecryptor(),
      previewResolver: NotificationPreviewResolver(
        keyReader: FixedKeyReader([:]),
        decryptor: RejectingDecryptor(),
        dedupeStore: nil,
        toneLeaseStore: nil,
        eventEmitter: FixedNoopEmitter()
      )
    )
    XCTAssertNil(adapter.adapt(legacy, credential: credential()))
  }

  private func fixedWake() -> [AnyHashable: Any] {
    [
      "v": "1",
      "aps": [
        "category": "MESSAGE_WAKE",
        "sound": "default",
        "mutable-content": 1,
        "alert": [
          "title-loc-key": "NEW_MESSAGE_TITLE",
          "loc-key": "NEW_MESSAGE_BODY",
        ],
      ],
    ]
  }

  private func credential() -> NseInboxCredential {
    NseInboxCredential(
      opaqueBinding: binding,
      logicalAccountPeerId: account,
      transportPeerId: transport,
      transportPrivateKeyBase64: Data(repeating: 7, count: 64)
        .base64EncodedString(),
      relayMultiaddrs: [
        "/dns4/relay.example/tcp/443/p2p/relay-peer",
      ],
      projectionRevision: 1,
      transportProjectionDigest: sha256(projectionDocuments()[
        NseInboxCredential.projectionKey
      ]!)
    )
  }

  private func credentialKeys() throws -> [String: String] {
    let credential = credential()
    let data = try JSONSerialization.data(withJSONObject: [
      "schemaVersion": 1,
      "opaqueBinding": credential.opaqueBinding,
      "logicalAccountPeerId": credential.logicalAccountPeerId,
      "transportPeerId": credential.transportPeerId,
      "transportPrivateKeyBase64": credential.transportPrivateKeyBase64,
      "relayMultiaddrs": credential.relayMultiaddrs,
      "projectionRevision": credential.projectionRevision,
    ])
    return [
      NseInboxCredential.projectionKey: try XCTUnwrap(
        String(data: data, encoding: .utf8)
      ),
      NseInboxCredential.bindingKey: binding,
    ]
  }

  private func candidate() -> NseInboxCandidate {
    let recovery = IosNotificationRecoveryIdentity(
      accountPeerId: account,
      lane: .direct,
      conversationId: "peer-sender",
      eventId: "event-1",
      kind: .ordinary
    )
    return NseInboxCandidate(
      preview: NotificationPreviewResult(
        title: "Authenticated sender",
        body: "Authenticated message",
        threadIdentifier: "peer-sender",
        didDecrypt: true,
        reason: "chat",
        recoveryIdentity: recovery
      ),
      policy: .eligible,
      currentOpaqueBinding: binding,
      eventCorrelation: String(repeating: "a", count: 64),
      conversationDigest: String(repeating: "b", count: 64),
      conversationKey: "peer-sender",
      producerKind: "direct_message",
      contentKind: "message",
      recoveryIdentity: recovery,
      transportProjectionDigest: sha256(projectionDocuments()[
        NseInboxCredential.projectionKey
      ]!),
      authorityProjectionDigests: [
        PushSharedKeyNames.directReactionContacts: sha256(
          projectionDocuments()[PushSharedKeyNames.directReactionContacts]!
        ),
      ]
    )
  }

  private func successPage() -> String {
    #"{"ok":true,"messages":[{"id":"row-1","from":"transport-self","message":"{}","timestamp":1}],"hasMore":false,"custodyContract":"ack_or_expiry_v1"}"#
  }

  private struct OperationalHandoffObservation {
    let resolution: NseMailboxWakeResolution
    let handlers: Int
    let sameIdentity: Bool
    let title: String
    let subtitle: String
    let body: String
    let category: String
    let thread: String
    let hasSound: Bool
  }

  private func resolveAndHandoffSynchronously(
    keys: [String: String],
    retriever: NseInboxRetrieving,
    adapter: NseInboxCandidateAdapting,
    name: String
  ) throws -> OperationalHandoffObservation {
    let root = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let recovery = initializedRecoveryStore(root)
    let coordinator = NseMailboxWakeCoordinator(
      credentialReader: NseInboxCredentialReader(
        keyReader: FixedKeyReader(keys)
      ),
      retriever: retriever,
      candidateAdapter: adapter,
      recoveryStore: recovery,
      queue: DispatchQueue(label: "tc37304.\(name).work"),
      deadlineQueue: DispatchQueue(label: "tc37304.\(name).deadline"),
      timeoutMs: 250,
      outerDeadlineMs: 400
    )
    let resolved = expectation(description: "\(name) resolves once")
    let lock = NSLock()
    var result: NseMailboxWakeResolution?
    coordinator.resolve(requestIdentifier: "case-\(name)") { resolution in
      lock.lock()
      result = resolution
      lock.unlock()
      resolved.fulfill()
    }
    wait(for: [resolved], timeout: 1)
    lock.lock()
    let exact = result
    lock.unlock()
    let resolution = try XCTUnwrap(exact)
    let original = UNMutableNotificationContent()
    original.title = "title-\(name)"
    original.subtitle = "subtitle-\(name)"
    original.body = "body-\(name)"
    original.categoryIdentifier = "category-\(name)"
    original.threadIdentifier = "thread-\(name)"
    original.sound = .default
    original.userInfo = fixedWake()
    var output: UNNotificationContent?
    var handlers = 0
    if case let .generic(lease) = resolution {
      coordinator.handoffGeneric(
        lease: lease,
        content: original,
        contentHandler: {
          handlers += 1
          output = $0
        }
      )
    }
    return OperationalHandoffObservation(
      resolution: resolution,
      handlers: handlers,
      sameIdentity: output === original,
      title: output?.title ?? "<missing>",
      subtitle: output?.subtitle ?? "<missing>",
      body: output?.body ?? "<missing>",
      category: output?.categoryIdentifier ?? "<missing>",
      thread: output?.threadIdentifier ?? "<missing>",
      hasSound: output?.sound != nil
    )
  }

  private func initializedRecoveryStore(
    _ directory: URL,
    binding bindingOverride: String? = nil,
    account accountOverride: String? = nil
  ) -> IosNotificationRecoveryStore {
    let effectiveBinding = bindingOverride ?? binding
    let effectiveAccount = accountOverride ?? account
    let store = IosNotificationRecoveryStore(
      directory: directory,
      currentOpaqueBinding: { effectiveBinding }
    )
    XCTAssertNotNil(store.beginReconciliation(accountPeerId: effectiveAccount))
    return store
  }

  private func genericContent() -> UNMutableNotificationContent {
    let content = UNMutableNotificationContent()
    content.title = "Generic title"
    content.body = "Generic body"
    content.categoryIdentifier = "MESSAGE_WAKE"
    content.sound = .default
    content.userInfo = fixedWake()
    return content
  }

  private struct MailboxFixture {
    let root: [String: Any]
    let rows: [[String: Any]]
    let keychainValues: [String: String]
  }

  private func loadMailboxFixture() throws -> MailboxFixture {
    let url = try XCTUnwrap(
      Bundle(for: type(of: self)).url(
        forResource: "ios_nse_mailbox_v1",
        withExtension: "json"
      )
    )
    let data = try Data(contentsOf: url)
    let root = try XCTUnwrap(
      try JSONSerialization.jsonObject(with: data) as? [String: Any]
    )
    let rows = try XCTUnwrap(root["rows"] as? [[String: Any]])
    let transport = try XCTUnwrap(
      root["transportProjection"] as? [String: Any]
    )
    let direct = try XCTUnwrap(
      root["directContactsProjection"] as? [String: Any]
    )
    let directTargets = try XCTUnwrap(
      root["directAuthoredTargetsProjection"] as? [String: Any]
    )
    let groups = try XCTUnwrap(
      root["groupContextsProjection"] as? [String: Any]
    )
    let groupTargets = try XCTUnwrap(
      root["groupAuthoredTargetsProjection"] as? [String: Any]
    )
    let groupStates = try XCTUnwrap(
      root["groupLatestStatesProjection"] as? [String: Any]
    )
    let crypto = try XCTUnwrap(root["cryptoMaterial"] as? [String: Any])
    XCTAssertEqual(Set(crypto.keys), [
      PushSharedKeyNames.identityMlKemSecretKey,
      PushSharedKeyNames.groupKey(groupId: "group-chat", keyEpoch: 7),
      PushSharedKeyNames.groupKey(groupId: "group-muted", keyEpoch: 7),
    ])
    let identitySecret = try XCTUnwrap(
      crypto[PushSharedKeyNames.identityMlKemSecretKey] as? String
    )
    XCTAssertTrue(isCanonicalBase64(identitySecret, decodedCount: 2_400))
    let chatKeyName = PushSharedKeyNames.groupKey(
      groupId: "group-chat",
      keyEpoch: 7
    )
    let mutedKeyName = PushSharedKeyNames.groupKey(
      groupId: "group-muted",
      keyEpoch: 7
    )
    let chatKey = try XCTUnwrap(crypto[chatKeyName] as? String)
    let mutedKey = try XCTUnwrap(crypto[mutedKeyName] as? String)
    XCTAssertTrue(isCanonicalBase64(chatKey, decodedCount: 32))
    XCTAssertTrue(isCanonicalBase64(mutedKey, decodedCount: 32))
    let binding = try XCTUnwrap(transport["opaqueBinding"] as? String)
    let keys: [String: String] = [
      NseInboxCredential.projectionKey: try canonicalJSONString(transport),
      NseInboxCredential.bindingKey: binding,
      PushSharedKeyNames.directReactionContacts:
        try canonicalJSONString(direct),
      PushSharedKeyNames.directReactionAuthoredTargets:
        try canonicalJSONString(directTargets),
      PushSharedKeyNames.groupReactionContexts:
        try canonicalJSONString(groups),
      PushSharedKeyNames.groupReactionAuthoredTargets:
        try canonicalJSONString(groupTargets),
      PushSharedKeyNames.groupReactionLatestStates:
        try canonicalJSONString(groupStates),
      PushSharedKeyNames.identityMlKemSecretKey: identitySecret,
      chatKeyName: chatKey,
      mutedKeyName: mutedKey,
    ]
    // Keep the exact key inventory explicit so future fixture groups cannot
    // silently gain a test-only decryption key.
    XCTAssertEqual(keys.count, 10)
    return MailboxFixture(root: root, rows: rows, keychainValues: keys)
  }

  private func canonicalJSONString(_ value: Any) throws -> String {
    let data = try JSONSerialization.data(
      withJSONObject: value,
      options: [.sortedKeys, .withoutEscapingSlashes]
    )
    return try XCTUnwrap(String(data: data, encoding: .utf8))
  }

  private func deepCopyMap(_ value: Any?) throws -> [String: Any] {
    let source = try XCTUnwrap(value)
    let data = try JSONSerialization.data(withJSONObject: source)
    return try XCTUnwrap(
      try JSONSerialization.jsonObject(with: data) as? [String: Any]
    )
  }

  private func adaptFixtureRow(
    _ rowId: String,
    fixture: MailboxFixture,
    keyOverrides: [String: String] = [:],
    rawEnvelopeOverride: [String: Any]? = nil
  ) throws -> NseInboxCandidate? {
    let fixtureRow = try XCTUnwrap(fixture.rows.first {
      $0["id"] as? String == rowId
    })
    let page = try XCTUnwrap(fixtureRow["rawEnvelope"] as? [String: Any])
    let messages = try XCTUnwrap(page["messages"] as? [[String: Any]])
    let message = try XCTUnwrap(messages.first)
    let encodedOuter: String
    if let rawEnvelopeOverride {
      encodedOuter = try canonicalJSONString(rawEnvelopeOverride)
    } else {
      encodedOuter = try XCTUnwrap(message["message"] as? String)
    }
    var keyValues = fixture.keychainValues
    keyValues.merge(keyOverrides) { _, replacement in replacement }
    let reader = FixedKeyReader(keyValues)
    let credential = try XCTUnwrap(
      NseInboxCredentialReader(keyReader: reader).read()
    )
    let decryptor = BridgePushDecryptor()
    let resolver = NotificationPreviewResolver(
      keyReader: reader,
      decryptor: decryptor,
      dedupeStore: nil,
      toneLeaseStore: nil,
      eventEmitter: FixedNoopEmitter()
    )
    return NseInboxCandidateAdapter(
      keyReader: reader,
      decryptor: decryptor,
      previewResolver: resolver,
      now: { self.isoDate("2026-08-16T00:04:00.000000Z") }
    ).adapt(
      NseInboxRetrievedMessage(
        id: try XCTUnwrap(message["id"] as? String),
        from: try XCTUnwrap(message["from"] as? String),
        message: encodedOuter,
        timestamp: try XCTUnwrap(
          (message["timestamp"] as? NSNumber)?.int64Value
        )
      ),
      credential: credential
    )
  }

  private func mutatedGroupEnvelope(
    fixture: MailboxFixture,
    rowId: String,
    mutation: String
  ) throws -> [String: Any] {
    let fixtureRow = try XCTUnwrap(fixture.rows.first {
      $0["id"] as? String == rowId
    })
    let page = try XCTUnwrap(fixtureRow["rawEnvelope"] as? [String: Any])
    let messages = try XCTUnwrap(page["messages"] as? [[String: Any]])
    let encoded = try XCTUnwrap(messages.first?["message"] as? String)
    var envelope = try XCTUnwrap(
      try JSONSerialization.jsonObject(with: Data(encoded.utf8))
        as? [String: Any]
    )
    switch mutation {
    case "signature":
      let value = try XCTUnwrap(envelope["signature"] as? String)
      envelope["signature"] = flipBase64Character(value)
    case "recipient-addition":
      var recipients = try XCTUnwrap(envelope["recipientPeerIds"] as? [String])
      recipients.append(
        "12D3KooWJsEmQWn5WGGn9AZX79emq3RkGNx2ihFwWzZAqbiUQGMF"
      )
      envelope["recipientPeerIds"] = Array(Set(recipients)).sorted()
    case "recipient-removal":
      var recipients = try XCTUnwrap(envelope["recipientPeerIds"] as? [String])
      let transport = try XCTUnwrap(
        (fixture.root["transportProjection"] as? [String: Any])?[
          "transportPeerId"
        ] as? String
      )
      recipients.removeAll { $0 == transport }
      envelope["recipientPeerIds"] = recipients
    case "ciphertext-hash-binding":
      envelope["ciphertext"] = flipBase64Character(
        try XCTUnwrap(envelope["ciphertext"] as? String)
      )
    case "nonce-hash-binding":
      envelope["nonce"] = flipBase64Character(
        try XCTUnwrap(envelope["nonce"] as? String)
      )
    case "content-event-key":
      envelope["contentEventId"] =
        try XCTUnwrap(envelope["contentEventId"] as? String) + "x"
    case "message-event-key":
      envelope["messageId"] =
        try XCTUnwrap(envelope["messageId"] as? String) + "x"
    case "signed-plaintext-hash-binding":
      let encodedSigned = try XCTUnwrap(envelope["signedPayload"] as? String)
      var signed = try XCTUnwrap(
        try JSONSerialization.jsonObject(with: Data(encodedSigned.utf8))
          as? [String: Any]
      )
      signed["plaintextHash"] = flipBase64Character(
        try XCTUnwrap(signed["plaintextHash"] as? String)
      )
      envelope["signedPayload"] = try canonicalJSONString(signed)
    default:
      XCTFail("unknown fixture mutation: \(mutation)")
    }
    return envelope
  }

  private func flipBase64Character(_ value: String) -> String {
    guard let first = value.first else { return value }
    return String(first == "A" ? "B" : "A") + value.dropFirst()
  }

  private func isCanonicalBase64(
    _ value: String,
    decodedCount: Int
  ) -> Bool {
    guard let decoded = Data(base64Encoded: value) else { return false }
    return decoded.count == decodedCount && decoded.base64EncodedString() == value
  }

  private func isExplicitlyRejectedFixtureEnvelope(
    _ encoded: String,
    decryptor: PushPayloadDecrypting,
    secretKey: String?
  ) -> Bool {
    guard let data = encoded.data(using: .utf8),
          let envelope = try? JSONSerialization.jsonObject(with: data)
            as? [String: Any] else {
      return false
    }
    if envelope["type"] as? String == "message_deletion" {
      return envelope["version"] as? String == "2"
    }
    if let kind = envelope["kind"] as? String {
      return kind == "group_bootstrap_v1" || kind == "group_authority_v1"
    }
    guard envelope["type"] as? String == "chat_message" else {
      return false
    }
    if envelope["version"] as? String == "1" { return true }
    guard envelope["version"] as? String == "2",
          let encrypted = envelope["encrypted"] as? [String: Any],
          let secretKey,
          let kem = encrypted["kem"] as? String,
          let ciphertext = encrypted["ciphertext"] as? String,
          let nonce = encrypted["nonce"] as? String,
          let plaintext = try? decryptor.decryptOneToOne(
            secretKey: secretKey,
            kem: kem,
            ciphertext: ciphertext,
            nonce: nonce
          ),
          let innerData = plaintext.data(using: .utf8),
          let inner = try? JSONSerialization.jsonObject(with: innerData)
            as? [String: Any] else {
      return false
    }
    return inner["action"] as? String == "edit" || inner["media"] != nil
  }

  private func assertFixtureCandidate(
    _ candidate: NseInboxCandidate,
    expected: [String: Any],
    expectedKind: String,
    rowId: String
  ) {
    let commonExpectedKeys: Set<String> = [
      "contentKind", "conversationDigest", "conversationKey",
      "eventCorrelation", "policy", "producerKind", "recoveryEventId",
      "stableNotificationId",
    ]
    var expectedKeys = commonExpectedKeys
    if expectedKind.hasPrefix("group_message") ||
        expectedKind == "group_voice_descriptor" {
      expectedKeys.insert("logicalDeliveryId")
    }
    if expectedKind == "group_voice_descriptor" {
      expectedKeys.insert("previewBody")
    }
    XCTAssertEqual(Set(expected.keys), expectedKeys, rowId)
    /*
      Group-message fixture expectations additionally freeze the logical
      delivery identity used by the main-app correlation path. The voice row
      also freezes the descriptor-only preview without granting blob access.
    */
    let suppressed = expectedKind.hasSuffix("_suppressed")
    XCTAssertEqual(
      candidate.policy,
      suppressed ? .suppressedPolicy : .eligible,
      rowId
    )
    XCTAssertEqual(candidate.policy == .eligible ? "eligible" :
      "suppressedPolicy", expected["policy"] as? String, rowId)
    XCTAssertEqual(candidate.producerKind, expected["producerKind"] as? String,
                   rowId)
    XCTAssertEqual(candidate.contentKind, expected["contentKind"] as? String,
                   rowId)
    XCTAssertEqual(candidate.eventCorrelation,
                   expected["eventCorrelation"] as? String, rowId)
    XCTAssertEqual(candidate.conversationDigest,
                   expected["conversationDigest"] as? String, rowId)
    XCTAssertEqual(candidate.conversationKey,
                   expected["conversationKey"] as? String, rowId)
    XCTAssertEqual(candidate.recoveryIdentity.eventId,
                   expected["recoveryEventId"] as? String, rowId)
    if let logicalDeliveryId = expected["logicalDeliveryId"] as? String {
      XCTAssertEqual(candidate.recoveryIdentity.eventId, logicalDeliveryId,
                     rowId)
    }
    if let previewBody = expected["previewBody"] as? String {
      XCTAssertEqual(candidate.preview.body, previewBody, rowId)
    }
    XCTAssertEqual(stableId(candidate.conversationKey),
                   (expected["stableNotificationId"] as? NSNumber)?.intValue,
                   rowId)
    XCTAssertEqual(
      candidate.currentOpaqueBinding,
      "v1:" + String(repeating: "a", count: 64),
      rowId
    )
  }

  private func emitFixtureCensus(_ census: [String: Int]) throws {
    let disposition = "accepted=\(census["accepted"]!) " +
      "rejected=\(census["rejected"]!) " +
      "invalid=\(census["invalid"]!)"
    print("PLAN373_FIXTURE_CENSUS \(disposition)")
    guard let path = ProcessInfo.processInfo.environment[
      "PLAN373_FIXTURE_CENSUS_PATH"
    ], !path.isEmpty else {
      return
    }
    try Data("\(disposition)\n".utf8).write(
      to: URL(fileURLWithPath: path),
      options: .atomic
    )
  }

  private func assertPrivacyCleanPassive(
    _ content: UNNotificationContent?,
    targetNotificationId: Int?,
    message: String = ""
  ) {
    XCTAssertNotNil(content, message)
    XCTAssertEqual(content?.title, "", message)
    XCTAssertEqual(content?.subtitle, "", message)
    XCTAssertEqual(content?.body, "", message)
    XCTAssertEqual(content?.categoryIdentifier, "", message)
    XCTAssertEqual(content?.threadIdentifier, "", message)
    XCTAssertEqual(content?.attachments.count, 0, message)
    XCTAssertNil(content?.badge, message)
    XCTAssertNil(content?.sound, message)
    if #available(iOS 15.0, *) {
      XCTAssertEqual(
        content?.interruptionLevel,
        .passive,
        message
      )
      XCTAssertEqual(
        content?.targetContentIdentifier,
        targetNotificationId.map(String.init),
        message
      )
    }
    XCTAssertNil(content?.userInfo["ciphertext"], message)
    XCTAssertNil(content?.userInfo["message"], message)
  }

  private func backgroundVisibility() -> IosAppVisibilitySnapshotEnvelope {
    IosAppVisibilitySnapshotEnvelope(
      snapshot: IosAppVisibilitySnapshotV1(
        revision: 7,
        lifecycleGeneration: 11,
        lifecycle: .background,
        visibleConversationDigest: nil,
        updatedMonotonicMs: 100,
        bootSession: "ios:42:7"
      ),
      context: IosAppVisibilityContext(
        currentMonotonicMs: 101,
        currentBootSession: "ios:42:7"
      )
    )
  }

  private struct EffectHarness {
    let root: URL
    let registry: URL
    let recovery: IosNotificationRecoveryStore
    let effect: IosLocalNotificationFinalEffect
    let candidate: NseInboxCandidate
    let lease: IosNotificationMailboxAlertLease
    let notificationId: Int
  }

  private func makeEffectHarness(
    phase: String,
    updatedAt: String,
    now: String,
    inventory: IosLocalNotificationDeliveredInventory,
    notificationIdOverride: Int? = nil,
    projectionReader: ((String) -> String?)? = nil,
    sourceCustody: String = "RELAY_VERIFIED_UNACKED",
    candidate candidateOverride: NseInboxCandidate? = nil,
    projectionDocuments documentsOverride: [String: String]? = nil,
    retireDeliveredRequests retireOverride: (([String]) -> Void)? = nil
  ) throws -> EffectHarness {
    try makeEffectHarness(
      phase: phase,
      updatedAt: updatedAt,
      now: isoDate(now),
      inventory: inventory,
      notificationIdOverride: notificationIdOverride,
      projectionReader: projectionReader,
      sourceCustody: sourceCustody,
      candidate: candidateOverride,
      projectionDocuments: documentsOverride,
      retireDeliveredRequests: retireOverride
    )
  }

  private func makeEffectHarness(
    phase: String,
    updatedAt: String,
    now: Date,
    inventory: IosLocalNotificationDeliveredInventory,
    notificationIdOverride: Int? = nil,
    projectionReader: ((String) -> String?)? = nil,
    sourceCustody: String = "RELAY_VERIFIED_UNACKED",
    candidate candidateOverride: NseInboxCandidate? = nil,
    projectionDocuments documentsOverride: [String: String]? = nil,
    retireDeliveredRequests retireOverride: (([String]) -> Void)? = nil
  ) throws -> EffectHarness {
    let root = try temporaryDirectory()
    let registry = root.appendingPathComponent(
      IosLocalNotificationFinalEffect.directoryName
    )
    try FileManager.default.createDirectory(
      at: registry,
      withIntermediateDirectories: false
    )
    try Data().write(
      to: registry.appendingPathComponent(
        IosLocalNotificationFinalEffect.lockFileName
      )
    )
    let candidate = candidateOverride ?? candidate()
    let effectiveBinding = candidate.currentOpaqueBinding
    let effectiveAccount = candidate.recoveryIdentity.accountPeerId
    let effectiveDocuments = documentsOverride ?? projectionDocuments()
    let notificationId = notificationIdOverride ?? stableId(
      candidate.conversationKey
    )
    let owner = sha256(candidate.conversationKey)
    try Data(owner.utf8).write(
      to: registry.appendingPathComponent(
        "\(notificationId)\(IosLocalNotificationFinalEffect.ownerSuffix)"
      )
    )
    try ledger(
      candidate: candidate,
      notificationId: notificationId,
      phase: phase,
      updatedAt: updatedAt,
      sourceCustody: sourceCustody,
      opaqueBinding: effectiveBinding
    ).write(
      to: registry.appendingPathComponent(
        IosLocalNotificationFinalEffect.ledgerFileName
      )
    )
    if phase == "PUBLISHING" {
      try metadata(candidate).write(
        to: registry.appendingPathComponent(
          "\(notificationId)\(IosLocalNotificationFinalEffect.contentKindSuffix)"
        )
      )
    }
    let recovery = initializedRecoveryStore(
      root,
      binding: effectiveBinding,
      account: effectiveAccount
    )
    let lease = try XCTUnwrap(recovery.prepareMailboxAlertLease(
      requestIdentifier: "request-\(UUID().uuidString)",
      accountPeerId: effectiveAccount,
      opaqueBinding: effectiveBinding
    ))
    let effect = IosLocalNotificationFinalEffect(
      directory: registry,
      recoveryStore: recovery,
      currentOpaqueBinding: { effectiveBinding },
      readProjectionDocument: projectionReader ?? {
        key in effectiveDocuments[key]
      },
      readVisibility: { self.backgroundVisibility() },
      readDeliveredInventory: { inventory },
      retireDeliveredRequests: retireOverride ?? { _ in },
      now: { now }
    )
    return EffectHarness(
      root: root,
      registry: registry,
      recovery: recovery,
      effect: effect,
      candidate: candidate,
      lease: lease,
      notificationId: notificationId
    )
  }

  private func emptyLedger() throws -> Data {
    try JSONSerialization.data(withJSONObject: [
      "schemaVersion": 1,
      "storeRevision": 1,
      "opaqueBinding": binding,
      "claimsSuspended": false,
      "records": [:],
    ], options: [.sortedKeys])
  }

  private func ledger(
    candidate: NseInboxCandidate,
    notificationId: Int,
    phase: String,
    updatedAt: String,
    sourceCustody: String = "RELAY_VERIFIED_UNACKED",
    opaqueBinding: String? = nil
  ) throws -> Data {
    let attempt = phase == "CLAIMED" || phase == "PUBLISHING"
    let createdAt = "2026-08-16T09:58:00.000Z"
    let record: [String: Any] = [
      "eventCorrelation": candidate.eventCorrelation,
      "conversationDigest": candidate.conversationDigest,
      "producerKind": candidate.producerKind,
      "sourceCustody": sourceCustody,
      "readState": "UNREAD",
      "presentationState": "NOT_EVALUATED",
      "presentationOwner": "IOS_NSE",
      "notificationId": notificationId,
      "contentGeneration": "ledger:\(candidate.eventCorrelation)",
      "lastEvaluatedLifecycle": "UNKNOWN",
      "visibilityRevision": NSNull(),
      "lifecycleGeneration": NSNull(),
      "effectPhase": phase,
      "attemptKind": attempt ? "POST_OR_UPDATE" : NSNull(),
      "effectToken": attempt ? String(repeating: "d", count: 64) : NSNull(),
      "revision": phase == "READY" ? 1 : (phase == "CLAIMED" ? 2 : 3),
      "createdAtUtc": createdAt,
      "updatedAtUtc": updatedAt,
      "terminalAtUtc": NSNull(),
      "settledAtUtc": NSNull(),
    ]
    return try JSONSerialization.data(withJSONObject: [
      "schemaVersion": 1,
      "storeRevision": 1,
      "opaqueBinding": opaqueBinding ?? binding,
      "claimsSuspended": false,
      "records": [candidate.eventCorrelation: record],
    ], options: [.sortedKeys])
  }

  private func metadata(_ candidate: NseInboxCandidate) -> Data {
    metadata(kind: candidate.contentKind, event: candidate.eventCorrelation)
  }

  private func metadata(kind: String, event: String) -> Data {
    Data(
      "{\"v\":1,\"kind\":\"\(kind)\",\"event\":\"\(event)\",\"generation\":\"ledger:\(event)\"}".utf8
    )
  }

  private func metadataDigest(_ data: Data) -> String {
    SHA256.hash(
      data: Data("mknoon-content-activation-intent-v1\0".utf8) + data
    ).map { String(format: "%02x", $0) }.joined()
  }

  private func contentIntent(
    binding: String,
    previousDigest: String?,
    nextDigest: String
  ) -> Data {
    let previous = previousDigest.map { "\"\($0)\"" } ?? "null"
    return Data(
      "{\"v\":1,\"opaqueBinding\":\"\(binding)\",\"previousDigest\":\(previous),\"nextDigest\":\"\(nextDigest)\"}".utf8
    )
  }

  private func ledgerRecord(at registry: URL) throws -> [String: Any] {
    let data = try Data(contentsOf: registry.appendingPathComponent(
      IosLocalNotificationFinalEffect.ledgerFileName
    ))
    let root = try XCTUnwrap(
      try JSONSerialization.jsonObject(with: data) as? [String: Any]
    )
    let records = try XCTUnwrap(root["records"] as? [String: Any])
    return try XCTUnwrap(records.values.first as? [String: Any])
  }

  private func replaceLedgerAttemptKind(
    _ attemptKind: String,
    candidate: NseInboxCandidate,
    registry: URL
  ) throws {
    let url = registry.appendingPathComponent(
      IosLocalNotificationFinalEffect.ledgerFileName
    )
    let data = try Data(contentsOf: url)
    var root = try XCTUnwrap(
      try JSONSerialization.jsonObject(with: data) as? [String: Any]
    )
    var records = try XCTUnwrap(root["records"] as? [String: Any])
    var record = try XCTUnwrap(
      records[candidate.eventCorrelation] as? [String: Any]
    )
    record["attemptKind"] = attemptKind
    records[candidate.eventCorrelation] = record
    root["records"] = records
    try JSONSerialization.data(
      withJSONObject: root,
      options: [.sortedKeys]
    ).write(to: url, options: .atomic)
  }

  private func stableId(_ value: String) -> Int {
    let bytes = Array(SHA256.hash(data: Data(value.utf8)))
    let raw = UInt32(bytes[0]) << 24 | UInt32(bytes[1]) << 16 |
      UInt32(bytes[2]) << 8 | UInt32(bytes[3])
    return Int(raw & 0x7fffffff)
  }

  private func sha256(_ value: String) -> String {
    SHA256.hash(data: Data(value.utf8)).map {
      String(format: "%02x", $0)
    }.joined()
  }

  private func projectionDocuments() -> [String: String] {
    [
      NseInboxCredential.projectionKey: "transport-projection-bytes-v1",
      PushSharedKeyNames.directReactionContacts:
        "direct-authority-projection-bytes-v1",
      PushSharedKeyNames.groupReactionContexts:
        "group-authority-projection-bytes-v1",
    ]
  }

  private func isoDate(_ value: String) -> Date {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.date(from: value)!
  }

  private func temporaryDirectory() throws -> URL {
    let result = FileManager.default.temporaryDirectory.appendingPathComponent(
      "ios-nse-373-\(UUID().uuidString)",
      isDirectory: true
    )
    try FileManager.default.createDirectory(
      at: result,
      withIntermediateDirectories: false
    )
    return result
  }
}

private final class FixedKeyReader: PushKeyReading {
  private let values: [String: String]
  init(_ values: [String: String]) { self.values = values }
  func readString(key: String) -> String? { values[key] }
}

private final class DelayedNseRetriever: NseInboxRetrieving {
  let delay: TimeInterval
  let response: String
  init(delay: TimeInterval, response: String) {
    self.delay = delay
    self.response = response
  }
  func retrievePending(requestJSON: String) throws -> String {
    Thread.sleep(forTimeInterval: delay)
    return response
  }
}

private final class CountingNseRetriever: NseInboxRetrieving {
  private let lock = NSLock()
  private let response: String
  private(set) var calls = 0

  init(response: String) { self.response = response }

  func retrievePending(requestJSON: String) throws -> String {
    lock.lock()
    calls += 1
    lock.unlock()
    return response
  }
}

private struct ThrowingNseRetriever: NseInboxRetrieving {
  enum Failure: Error { case unavailable }
  func retrievePending(requestJSON: String) throws -> String {
    throw Failure.unavailable
  }
}

private final class FixedCandidateAdapter: NseInboxCandidateAdapting {
  private let lock = NSLock()
  private(set) var calls = 0
  let candidate: NseInboxCandidate?
  init(candidate: NseInboxCandidate?) { self.candidate = candidate }
  func adapt(
    _ row: NseInboxRetrievedMessage,
    credential: NseInboxCredential
  ) -> NseInboxCandidate? {
    lock.lock()
    calls += 1
    lock.unlock()
    return candidate
  }
}

private struct RejectingDecryptor: PushPayloadDecrypting {
  enum Failure: Error { case rejected }
  func decryptOneToOne(
    secretKey: String,
    kem: String,
    ciphertext: String,
    nonce: String
  ) throws -> String { throw Failure.rejected }
  func decryptGroup(
    groupKey: String,
    ciphertext: String,
    nonce: String
  ) throws -> String { throw Failure.rejected }
}

private struct FixedNoopEmitter: PushPreviewEventEmitting {
  func emit(event: String, details: [String: String]) {}
}
