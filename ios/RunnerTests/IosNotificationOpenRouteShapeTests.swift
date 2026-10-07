import XCTest

@testable import Runner

// Regression lock for the APNs notification-open gate. On an iPhone 13 /
// iOS 26.5, tapping a direct-reaction notification from the background opened
// Orbit: the gate had no `message_reaction` case, so the tap was skipped as
// `not_route_shaped` and never reached Dart. Manual-only: no automated gate runs
// xcodebuild RunnerTests; test/core/notifications/
// ios_notification_open_route_shape_contract_test.dart pins Dart/Swift parity.
final class IosNotificationOpenRouteShapeTests: XCTestCase {
  private func directReaction() -> [String: Any] {
    return [
      "type": "message_reaction",
      "action": "add",
      "sender_id": "peer-reactor-1",
      "target_message_id": "msg-target-1",
    ]
  }

  func testDirectReactionAddIsRouteShaped() {
    XCTAssertTrue(IosNotificationOpenRouteShape.isRouteShaped(directReaction()))
  }

  func testDirectReactionAcceptsLegacyFieldNames() {
    var payload = directReaction()
    payload.removeValue(forKey: "sender_id")
    payload.removeValue(forKey: "target_message_id")
    payload["from"] = "peer-reactor-1"
    payload["targetMessageId"] = "msg-target-1"
    XCTAssertTrue(IosNotificationOpenRouteShape.isRouteShaped(payload))
  }

  func testDirectReactionWithoutRoutableFieldsIsNotRouteShaped() {
    for (key, value) in [
      ("action", "remove"),
      ("action", " "),
      ("sender_id", ""),
      ("target_message_id", "  "),
    ] {
      var payload = directReaction()
      payload[key] = value
      XCTAssertFalse(
        IosNotificationOpenRouteShape.isRouteShaped(payload),
        "\(key)=\"\(value)\" must not route"
      )
    }
    for key in ["action", "sender_id", "target_message_id"] {
      var payload = directReaction()
      payload.removeValue(forKey: key)
      XCTAssertFalse(
        IosNotificationOpenRouteShape.isRouteShaped(payload),
        "missing \(key) must not route"
      )
    }
  }

  func testExistingTypesKeepTheirShape() {
    XCTAssertTrue(IosNotificationOpenRouteShape.isRouteShaped([
      "type": "new_message",
      "sender_id": "peer-1",
    ]))
    XCTAssertTrue(IosNotificationOpenRouteShape.isRouteShaped([
      "type": "group_reaction",
      "action": "add",
      "groupId": "group-1",
      "event_id": "event-1",
      "target_message_id": "msg-1",
      "reactor_peer_id": "peer-1",
    ]))
    XCTAssertTrue(IosNotificationOpenRouteShape.isRouteShaped([
      "type": "intros",
    ]))
    XCTAssertFalse(IosNotificationOpenRouteShape.isRouteShaped([
      "type": "new_message",
    ]))
    XCTAssertFalse(IosNotificationOpenRouteShape.isRouteShaped([
      "type": "unknown_type",
      "sender_id": "peer-1",
    ]))
    XCTAssertFalse(IosNotificationOpenRouteShape.isRouteShaped([:]))
  }
}
