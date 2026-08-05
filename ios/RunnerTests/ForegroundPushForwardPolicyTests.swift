import UserNotifications
import XCTest

@testable import Runner

// 191 (Fix N1): regression lock for the pure foreground-push forward decision.
// The behavioural RED is the device runsheet (TC-191-01: a foreground push
// reaches Dart onMessage and drains ≤5 s off the 189 grid); these lock the gate
// that drives it so a revert (stop forwarding / forward FLN / drop the nil-ref
// fail-safe) fails here. Manual-only: no automated gate runs xcodebuild
// RunnerTests (house state — documented in the plan).
final class ForegroundPushForwardPolicyTests: XCTestCase {
  func testRecoveryDispositionUsesActualPresentationOptionsAndCompletesOnce() {
    var suppressed: [String] = []
    var completions: [UNNotificationPresentationOptions] = []
    let suppressedGate = IosNotificationForegroundDispositionGate(
      requestIdentifier: "suppressed-request",
      onSuppressed: { suppressed.append($0) },
      completion: { completions.append($0) }
    )

    suppressedGate.complete(with: [])
    suppressedGate.complete(with: [.alert])

    XCTAssertEqual(suppressed, ["suppressed-request"])
    XCTAssertEqual(completions.count, 1)
    XCTAssertTrue(completions[0].isEmpty)

    let presentedGate = IosNotificationForegroundDispositionGate(
      requestIdentifier: "presented-request",
      onSuppressed: { suppressed.append($0) },
      completion: { completions.append($0) }
    )
    presentedGate.complete(with: [.alert])

    XCTAssertEqual(suppressed, ["suppressed-request"])
    XCTAssertEqual(completions.count, 2)
    XCTAssertEqual(completions[1], [.alert])
  }

  private func fcmUserInfo() -> [AnyHashable: Any] {
    return [
      "gcm.message_id": "0:1720000000000000%aabbccdd",
      "type": "new_message",
      "sender_id": "peer-apns-1",
      "message_id": "msg-apns-1",
    ]
  }

  private func flnUserInfo() -> [AnyHashable: Any] {
    return ["NotificationId": 42, "payload": "peer-apns-1"]
  }

  func testFcmShapedPayloadForwardsToPluginAndCompletesOnce() {
    let decision = ForegroundPushForwardPolicy.decide(
      userInfo: fcmUserInfo(),
      hasFcmPluginRef: true
    )
    XCTAssertEqual(decision, .forwardToFcmPlugin)

    // Mirror the AppDelegate dispatch: on a forward decision the ORIGINAL
    // completion handler is passed to the plugin, which completes EXACTLY ONCE
    // with the persisted foreground options (0 — no banner). A spy stands in for
    // the plugin's willPresent delegate.
    var completionCalls: [UNNotificationPresentationOptions] = []
    let spy = SpyWillPresentDelegate()

    switch decision {
    case .forwardToFcmPlugin:
      spy.forwardWillPresent { options in completionCalls.append(options) }
    case .superPath:
      XCTFail("FCM-shaped payload with a plugin ref must forward, not take super")
    }

    XCTAssertEqual(spy.forwardCount, 1, "the forward must happen exactly once")
    XCTAssertEqual(completionCalls.count, 1, "the completion must fire exactly once")
    XCTAssertEqual(completionCalls.first, [], "options must be 0 — no foreground banner")
  }

  func testFlnShapedPayloadTakesSuperPath() {
    XCTAssertEqual(
      ForegroundPushForwardPolicy.decide(userInfo: flnUserInfo(), hasFcmPluginRef: true),
      .superPath
    )

    // An FCM+FLN mixed payload must NOT forward — the FLN discriminator wins so
    // FLN local notifications keep their existing presentation/tap handling.
    var mixed = fcmUserInfo()
    mixed["payload"] = "peer-apns-1"
    XCTAssertEqual(
      ForegroundPushForwardPolicy.decide(userInfo: mixed, hasFcmPluginRef: true),
      .superPath
    )
  }

  func testNilPluginRefFallsBackToSuperWithDiag() {
    // No captured plugin ref → fail-safe super path (degrades to the 189
    // periodic-drain grid), even for a canonical FCM payload.
    XCTAssertEqual(
      ForegroundPushForwardPolicy.decide(userInfo: fcmUserInfo(), hasFcmPluginRef: false),
      .superPath
    )

    // A non-FCM notification with a ref also takes super (never forwarded).
    XCTAssertEqual(
      ForegroundPushForwardPolicy.decide(
        userInfo: ["aps": ["alert": "hello"]],
        hasFcmPluginRef: true
      ),
      .superPath
    )
  }
}

final class NotificationResponseDiagnosticTests: XCTestCase {
  func testDirectThreadMatchesRouteWithoutLoggingIdentifier() {
    let content = UNMutableNotificationContent()
    content.threadIdentifier = "peer-alice"

    let diagnostic = NotificationResponseDiagnostic.evaluate(
      content: content,
      userInfo: ["sender_id": "peer-alice"]
    )

    XCTAssertEqual(diagnostic.threadIdentifier, "<redacted>")
    XCTAssertEqual(diagnostic.threadIdentifierState, "present")
    XCTAssertEqual(diagnostic.threadMatchesRoute, "true")
    XCTAssertEqual(diagnostic.categoryIdentifier, "<empty>")
    XCTAssertEqual(diagnostic.categoryIdentifierState, "empty")
    XCTAssertFalse(diagnostic.logSummary.contains("peer-alice"))
  }

  func testGroupThreadUsesRecipientOwnedGroupRouteKey() {
    let content = UNMutableNotificationContent()
    content.threadIdentifier = "77777777-7777-4777-8777-777777777777"

    let diagnostic = NotificationResponseDiagnostic.evaluate(
      content: content,
      userInfo: [
        "groupId": "77777777-7777-4777-8777-777777777777",
        "sender_id": "must-not-win",
      ]
    )

    XCTAssertEqual(diagnostic.threadMatchesRoute, "true")
    XCTAssertFalse(diagnostic.logSummary.contains("77777777-7777-4777-8777-777777777777"))
    XCTAssertFalse(diagnostic.logSummary.contains("must-not-win"))
  }

  func testMismatchAndUnexpectedCategoryFailClosedAndStayRedacted() {
    let content = UNMutableNotificationContent()
    content.threadIdentifier = "unexpected-thread"
    content.categoryIdentifier = "UNREGISTERED_MESSAGE_CATEGORY"

    let diagnostic = NotificationResponseDiagnostic.evaluate(
      content: content,
      userInfo: ["sender_id": "peer-alice"]
    )

    XCTAssertEqual(diagnostic.threadIdentifier, "<redacted>")
    XCTAssertEqual(diagnostic.threadMatchesRoute, "false")
    XCTAssertEqual(diagnostic.categoryIdentifier, "<redacted>")
    XCTAssertEqual(diagnostic.categoryIdentifierState, "present")
    XCTAssertFalse(diagnostic.logSummary.contains("unexpected-thread"))
    XCTAssertFalse(diagnostic.logSummary.contains("UNREGISTERED_MESSAGE_CATEGORY"))
    XCTAssertFalse(diagnostic.logSummary.contains("peer-alice"))
  }

  func testMissingRecipientRouteKeyIsUnavailable() {
    let content = UNMutableNotificationContent()
    content.threadIdentifier = "orphan-thread"

    let diagnostic = NotificationResponseDiagnostic.evaluate(
      content: content,
      userInfo: [:]
    )

    XCTAssertEqual(diagnostic.threadIdentifierState, "present")
    XCTAssertEqual(diagnostic.threadMatchesRoute, "unavailable")
    XCTAssertFalse(diagnostic.logSummary.contains("orphan-thread"))
  }
}

/// Stands in for the FCM plugin's willPresent delegate — records the forward and
/// completes exactly once with the persisted foreground options (0 — no banner).
private final class SpyWillPresentDelegate {
  private(set) var forwardCount = 0

  func forwardWillPresent(_ completion: (UNNotificationPresentationOptions) -> Void) {
    forwardCount += 1
    completion([])
  }
}
