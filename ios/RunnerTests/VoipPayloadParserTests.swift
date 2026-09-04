import XCTest

@testable import Runner

final class VoipPayloadParserTests: XCTestCase {
  private let now: Int64 = 1_900_000_000_000
  private let call = "123e4567-e89b-42d3-a456-426614174000"
  private let contact = "223e4567-e89b-42d3-a456-426614174001"

  func testExactOpaqueAppleEnvelopeIsAcceptedAndCanonicalized() throws {
    let result = parser().parse(dictionary: validPayload())
    guard case let .accepted(payload) = result else {
      return XCTFail("expected accepted payload")
    }
    XCTAssertEqual(payload.nativeCallId.uuidString.lowercased(), call)
    XCTAssertEqual(payload.callHandle, call)
    XCTAssertEqual(payload.wakeHandle, contact)
    XCTAssertEqual(payload.receivedAtMs, now)
    XCTAssertEqual(payload.expiresAtMs, now + 30_000)
  }

  func testCompactOpaqueIdentifiersAreAcceptedWithoutReadableAuthority() throws {
    var value = validPayload()
    value["c"] = "123e4567e89b42d3a456426614174000"
    value["h"] = "223e4567e89b42d3a456426614174001"
    guard case let .accepted(payload) = parser().parse(dictionary: value) else {
      return XCTFail("expected accepted compact payload")
    }
    XCTAssertEqual(payload.callHandle, call)
    XCTAssertEqual(payload.wakeHandle, "223e4567e89b42d3a456426614174001")
  }

  func testUnknownMissingDuplicateAndNonCallApsShapesReject() {
    var unknown = validPayload()
    unknown["sender"] = "readable"
    XCTAssertEqual(parser().parse(dictionary: unknown), .rejected(.invalidShape))

    var missing = validPayload()
    missing.removeValue(forKey: "h")
    XCTAssertEqual(parser().parse(dictionary: missing), .rejected(.invalidShape))

    let entries: [(String, Any)] = [
      ("aps", ["content-available": 1]),
      ("v", "1"), ("w", "call"), ("c", call), ("h", contact),
      ("e", String(now + 10_000)), ("e", String(now + 20_000)),
    ]
    XCTAssertEqual(parser().parse(entries: entries), .rejected(.duplicateKey))

    var alert = validPayload()
    alert["aps"] = ["content-available": 1, "alert": "call"]
    XCTAssertEqual(parser().parse(dictionary: alert), .rejected(.malformed))
  }

  func testObjectiveCNumberContentAvailableIsAcceptedButBooleanIsRejected() {
    var payload = validPayload()
    payload["aps"] = ["content-available": NSNumber(value: 1)]
    guard case .accepted = parser().parse(dictionary: payload) else {
      return XCTFail("PushKit NSNumber integer must remain an integer")
    }
    payload["aps"] = ["content-available": NSNumber(value: true)]
    XCTAssertEqual(parser().parse(dictionary: payload), .rejected(.malformed))
  }

  func testMalformedStaleFarFutureAndOversizedValuesRejectWithReasonOnly() {
    var malformed = validPayload()
    malformed["c"] = "not-a-uuid"
    XCTAssertEqual(parser().parse(dictionary: malformed), .rejected(.malformed))

    var stale = validPayload()
    stale["e"] = String(now)
    XCTAssertEqual(parser().parse(dictionary: stale), .rejected(.stale))

    var future = validPayload()
    future["e"] = String(now + VoipPayloadParser.maxFutureSkewMs + 1)
    XCTAssertEqual(parser().parse(dictionary: future), .rejected(.tooFarFuture))

    var oversized = validPayload()
    oversized["h"] = String(repeating: "a", count: 300)
    XCTAssertEqual(parser().parse(dictionary: oversized), .rejected(.tooLarge))
  }

  func testSchemaHasNoReadableIdentityOrMediaKeys() {
    XCTAssertEqual(Set(validPayload().keys.map(String.init)), ["aps", "v", "w", "c", "h", "e"])
    for forbidden in ["sender", "name", "peerId", "conversationId", "sdp", "ice", "turn"] {
      XCTAssertNil(validPayload()[AnyHashable(forbidden)])
    }
    XCTAssertFalse(String(describing: VoipPayloadRejectionReason.malformed).contains(call))
    XCTAssertFalse(String(describing: VoipPayloadRejectionReason.malformed).contains(contact))
  }

  private func parser() -> VoipPayloadParser { VoipPayloadParser(nowMs: { self.now }) }

  private func validPayload() -> [AnyHashable: Any] {
    [
      "aps": ["content-available": 1],
      "v": "1",
      "w": "call",
      "c": call,
      "h": contact,
      "e": String(now + 30_000),
    ]
  }
}
