import Foundation
import XCTest

final class NotificationTapUITests: XCTestCase {
  private let readyMarker = "MKNOON_APNS_TAP_READY"

  override func setUpWithError() throws {
    continueAfterFailure = false
    executionTimeAllowance = 120
  }

  func testNotificationTap() throws {
    try performNotificationTap(mode: "warm")
  }

  func testColdNotificationTap() throws {
    try performNotificationTap(mode: "cold")
  }

  func testPrepareWarmNotificationTap() throws {
    try prepareWarmNotificationTap()
  }

  func testTapExistingNotification() throws {
    try tapExistingNotification(waitForHostPush: false)
  }

  /// Pure decoder coverage for the system-owned Control Center switch. This
  /// selector does not launch an app or change device radio state.
  func testAirplaneToggleStateDecoderContract() {
    let english = (on: "On", off: "Off")
    XCTAssertEqual(
      decodeAirplaneToggleState(
        value: true,
        isSelected: false,
        localizedValues: english
      ),
      true
    )
    XCTAssertEqual(
      decodeAirplaneToggleState(
        value: NSNumber(value: 0),
        isSelected: false,
        localizedValues: english
      ),
      false
    )
    XCTAssertEqual(
      decodeAirplaneToggleState(
        value: "Airplane Mode, On",
        isSelected: false,
        localizedValues: english
      ),
      true
    )

    let german = (on: "Ein", off: "Aus")
    XCTAssertEqual(
      decodeAirplaneToggleState(
        value: "Flugmodus: Ein",
        isSelected: false,
        localizedValues: german
      ),
      true
    )
    XCTAssertEqual(
      decodeAirplaneToggleState(
        value: "Aus",
        isSelected: true,
        localizedValues: german
      ),
      false,
      "An explicit switch value must take precedence over selection state"
    )
    XCTAssertNil(
      decodeAirplaneToggleState(
        value: "unknown-state",
        isSelected: false,
        localizedValues: english
      ),
      "An unknown switch value must never be collapsed to off"
    )
    XCTAssertEqual(
      decodeAirplaneToggleState(
        value: nil,
        isSelected: true,
        localizedValues: english
      ),
      true
    )
  }

  /// Plan 258 / Plan 225 TC-B12 preparation. The host has installed the
  /// centrally prepared IPA and staged the private fixture. This selector
  /// grants notification permission, backgrounds the app, and emits a bounded
  /// readiness marker before the host asks the staging provider to send.
  func testPreparePayloadFastPathNotificationTap() throws {
    try prepareWarmNotificationTap()
    emitPlan258Marker("READY", fields: ["permission_automated": "true"])
  }

  /// Plan 258 / Plan 225 TC-B12 physical-iPhone closure. The provider has
  /// already delivered an NSE-eligible envelope. This selector proves that the
  /// card exists, enables airplane mode before the tap, performs the tap, and
  /// requires the exact message to render while the network remains cut.
  func testPayloadFastPathNotificationTap() throws {
    let bundleId = ProcessInfo.processInfo.environment["MKNOON_APNS_TAP_APP_BUNDLE_ID"] ?? "com.mknoon.app"
    guard let expectedMessage = configuredValue(
      environmentName: "MKNOON_258_EXPECTED_MESSAGE_TEXT",
      configKey: "expectedMessageText"
    ), !expectedMessage.isEmpty else {
      XCTFail("Plan 258 payload fast path requires expectedMessageText")
      return
    }

    let app = XCUIApplication(bundleIdentifier: bundleId)
    app.terminate()
    var mustRestoreNetwork = false
    defer {
      if mustRestoreNetwork {
        app.terminate()
        let appTerminated = app.wait(for: .notRunning, timeout: 5)
        var networkRestored = false
        do {
          networkRestored = try setAirplaneMode(false)
        } catch {
          XCTFail("Payload fast-path inline network restoration threw an error")
        }
        if !appTerminated {
          XCTFail("Payload fast-path app did not terminate before network restoration")
        }
        if networkRestored && appTerminated {
          emitPlan258Marker(
            "NETWORK_RESTORED",
            fields: [
              "airplane": "false",
              "app_terminated": "true",
              "inline": "true",
            ]
          )
        } else if !networkRestored {
          XCTFail("Payload fast-path inline network restoration did not complete")
        }
      }
    }

    guard configuredNotificationIsPresent() else {
      XCTFail("Could not find the configured APNs notification card")
      return
    }
    emitPlan258Marker("APNS_DELIVERED", fields: ["card_observed": "true"])
    mustRestoreNetwork = true
    guard try setAirplaneMode(true) else {
      return
    }
    emitPlan258Marker("AIRPLANE_ENABLED", fields: ["before_tap": "true"])
    try tapExistingNotification(
      waitForHostPush: false,
      requireTitleMatchedNotification: true
    )
    emitPlan258Marker("TAPPED", fields: ["automated": "true"])

    let message = element(in: app, containing: expectedMessage)
    guard message.waitForExistence(timeout: 20) else {
      XCTFail("Payload fast-path tap did not render the expected staged message")
      return
    }
    emitPlan258Marker(
      "VISIBLE",
      fields: ["staged_envelope": "true", "relay_drain_before_visibility": "0"]
    )
  }

  /// Plan 333 physical boundary, before Runner reconciliation. The fresh
  /// dedicated install makes the one real APNs card the unique owned claim.
  /// Observe both the exact card and the system-owned absolute badge without
  /// opening the app or manufacturing another remote notification.
  func testObservePayloadNotificationRecovery() throws {
    guard configuredNotificationIsPresent() else {
      XCTFail("Could not find the unique APNs recovery notification card")
      return
    }
    emitPlan258Marker("RECOVERY_CARD_READY", fields: ["unique": "true"])
    guard waitForApplicationBadge(1, timeout: 12) else {
      XCTFail("SpringBoard did not expose the expected absolute badge of one")
      return
    }
    emitPlan258Marker("RECOVERY_BADGE_READY", fields: ["absolute": "1"])
  }

  /// Plan 333 physical boundary, after the protected Runner proof command.
  /// The real APNs card A must be gone, the unrelated app-local sentinel C
  /// must remain, and SpringBoard must expose Runner's final absolute zero.
  func testVerifyPayloadNotificationRecoveryRetirement() throws {
    let title = configuredValue(
      environmentName: "MKNOON_APNS_TAP_EXPECTED_TITLE",
      configKey: "expectedTitle"
    ) ?? "New Message"
    let body = configuredValue(
      environmentName: "MKNOON_APNS_TAP_EXPECTED_BODY",
      configKey: "expectedBody"
    )
    guard !notificationIsPresent(title: title, body: body, timeout: 3) else {
      XCTFail("The exact APNs recovery card was not retired")
      return
    }
    guard notificationIsPresent(
      title: "Mknoon recovery sentinel",
      body: "Unrelated notification preservation",
      timeout: 10
    ) else {
      XCTFail("The unrelated app-local recovery sentinel did not survive")
      return
    }
    emitPlan258Marker(
      "RECOVERY_RETIREMENT_READY",
      fields: ["owned_absent": "true", "sentinel_present": "true"]
    )
    guard waitForApplicationBadge(0, timeout: 12) else {
      XCTFail("SpringBoard did not expose the final absolute zero badge")
      return
    }
    emitPlan258Marker("RECOVERY_ZERO_BADGE_READY", fields: ["absolute": "0"])
  }

  /// Best-effort cleanup selector used after a failed physical capture. It is
  /// intentionally idempotent so the next Sims row never inherits airplane
  /// mode from an interrupted run.
  func testRestorePayloadFastPathNetwork() throws {
    guard try setAirplaneMode(false) else {
      return
    }
    let bundleId = ProcessInfo.processInfo.environment["MKNOON_APNS_TAP_APP_BUNDLE_ID"] ?? "com.mknoon.app"
    let app = XCUIApplication(bundleIdentifier: bundleId)
    app.terminate()
    guard app.wait(for: .notRunning, timeout: 5) else {
      XCTFail("Payload fast-path cleanup app did not terminate")
      return
    }
    emitPlan258Marker(
      "NETWORK_RESTORED",
      fields: [
        "airplane": "false",
        "app_terminated": "true",
        "inline": "false",
      ]
    )
  }

  /// Plan 256 TC-14: cold-tap an already staged reaction notification and
  /// require a real conversation semantic from the app. The host staging
  /// controller owns APNs/NSE delivery and writes the existing tap config;
  /// this selector never accepts a manual tap or a route-only boolean.
  func testReactionNotificationTap() throws {
    let bundleId = ProcessInfo.processInfo.environment["MKNOON_APNS_TAP_APP_BUNDLE_ID"] ?? "com.mknoon.app"
    guard let expectedConversationLabel = configuredValue(
      environmentName: "MKNOON_REACTION_EXPECTED_CONVERSATION_LABEL",
      configKey: "expectedConversationLabel"
    ), !expectedConversationLabel.isEmpty else {
      XCTFail("Plan 256 reaction tap requires expectedConversationLabel in the staged tap config")
      return
    }

    let app = XCUIApplication(bundleIdentifier: bundleId)
    app.terminate()
    try tapExistingNotification(
      waitForHostPush: false,
      requireTitleMatchedNotification: true
    )

    let conversationMarker = "mknoon.conversation.\(expectedConversationLabel)"
    let rendered = app.descendants(matching: .any)
      .matching(identifier: conversationMarker)
      .firstMatch
    XCTAssertTrue(
      rendered.waitForExistence(timeout: 20),
      "Reaction notification tap did not render marker \(conversationMarker)"
    )
    NSLog("MKNOON_256_REACTION_TAP conversation_rendered=true cold_launch=true")
  }

  /// Plan 257 host-controlled fixture step 1. The capture driver has already
  /// staged both identities and the Android member in this app's recipient-
  /// owned contact store. This selector creates the real announcement through
  /// the shipping UI; it does not seed group/message rows or declare success
  /// on behalf of the app.
  func testCreateAnnouncementReactionFixture() throws {
    let bundleId = ProcessInfo.processInfo.environment["MKNOON_APNS_TAP_APP_BUNDLE_ID"] ?? "com.mknoon.app"
    guard let expectedGroupName = configuredValue(
      environmentName: "MKNOON_257_EXPECTED_GROUP_NAME",
      configKey: "expectedGroupName"
    ), !expectedGroupName.isEmpty else {
      XCTFail("Plan 257 fixture creation requires expectedGroupName")
      return
    }
    guard let expectedMemberName = configuredValue(
      environmentName: "MKNOON_257_EXPECTED_MEMBER_NAME",
      configKey: "expectedMemberName"
    ), !expectedMemberName.isEmpty else {
      XCTFail("Plan 257 fixture creation requires expectedMemberName")
      return
    }

    let app = XCUIApplication(bundleIdentifier: bundleId)
    app.terminate()
    app.launch()
    XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30))

    app.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.08)).tap()
    let announce = element(in: app, containing: "New Announce")
    XCTAssertTrue(announce.waitForExistence(timeout: 15))
    announce.tap()

    let member = element(in: app, containing: expectedMemberName)
    XCTAssertTrue(member.waitForExistence(timeout: 30))
    member.tap()

    let nameField = app.textFields.matching(
      NSPredicate(
        format: "label CONTAINS[c] %@ OR value CONTAINS[c] %@",
        "Group name",
        "Group name"
      )
    ).firstMatch
    XCTAssertTrue(nameField.waitForExistence(timeout: 15))
    nameField.tap()
    nameField.typeText(expectedGroupName)

    let start = element(in: app, containing: "Start group chat")
    XCTAssertTrue(start.waitForExistence(timeout: 15))
    start.tap()
    let group = element(in: app, containing: expectedGroupName)
    XCTAssertTrue(group.waitForExistence(timeout: 90))
    NSLog(
      "MKNOON_257_ANNOUNCEMENT_FIXTURE_CREATED group=%@ member=%@",
      expectedGroupName,
      expectedMemberName
    )
  }

  /// Plan 257 host-controlled fixture step 2. The Android member has accepted
  /// before this selector runs, so the physical iPhone authors the real target
  /// only after membership has converged.
  func testAuthorAnnouncementReactionTarget() throws {
    let bundleId = ProcessInfo.processInfo.environment["MKNOON_APNS_TAP_APP_BUNDLE_ID"] ?? "com.mknoon.app"
    guard let expectedGroupName = configuredValue(
      environmentName: "MKNOON_257_EXPECTED_GROUP_NAME",
      configKey: "expectedGroupName"
    ), !expectedGroupName.isEmpty else {
      XCTFail("Plan 257 target authoring requires expectedGroupName")
      return
    }
    guard let expectedTargetText = configuredValue(
      environmentName: "MKNOON_257_EXPECTED_TARGET_TEXT",
      configKey: "expectedTargetMessageText"
    ), !expectedTargetText.isEmpty else {
      XCTFail("Plan 257 target authoring requires expectedTargetMessageText")
      return
    }

    let app = XCUIApplication(bundleIdentifier: bundleId)
    app.terminate()
    app.launch()
    XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30))
    let group = element(in: app, containing: expectedGroupName)
    XCTAssertTrue(group.waitForExistence(timeout: 60))
    group.tap()

    let compose = firstComposeElement(in: app)
    XCTAssertTrue(compose.waitForExistence(timeout: 30))
    compose.tap()
    compose.typeText(expectedTargetText)
    let send = app.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0))
      .withOffset(
        CGVector(
          dx: min(compose.frame.maxX + 20, app.frame.maxX - 12),
          dy: compose.frame.midY
        )
      )
    send.tap()
    let rendered = element(in: app, containing: expectedTargetText)
    XCTAssertTrue(rendered.waitForExistence(timeout: 90))
    NSLog(
      "MKNOON_257_ANNOUNCEMENT_TARGET_AUTHORED group=%@ target=%@",
      expectedGroupName,
      expectedTargetText
    )
  }

  /// Plan 397 setup step 1. The host has staged both real peer identities and
  /// this selector creates the ordinary chat group through the shipping UI.
  func testCreateChatGroupNotificationFixture() throws {
    let bundleId = ProcessInfo.processInfo.environment["MKNOON_APNS_TAP_APP_BUNDLE_ID"] ?? "com.mknoon.app"
    guard let expectedGroupName = configuredValue(
      environmentName: "MKNOON_257_EXPECTED_GROUP_NAME",
      configKey: "expectedGroupName"
    ), !expectedGroupName.isEmpty else {
      XCTFail("Plan 397 fixture creation requires expectedGroupName")
      return
    }
    guard let expectedMemberName = configuredValue(
      environmentName: "MKNOON_257_EXPECTED_MEMBER_NAME",
      configKey: "expectedMemberName"
    ), !expectedMemberName.isEmpty else {
      XCTFail("Plan 397 fixture creation requires expectedMemberName")
      return
    }

    let app = XCUIApplication(bundleIdentifier: bundleId)
    app.terminate()
    app.launch()
    XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30))

    app.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.08)).tap()
    let newGroup = element(in: app, containing: "New Group")
    XCTAssertTrue(newGroup.waitForExistence(timeout: 15))
    newGroup.tap()

    let member = element(in: app, containing: expectedMemberName)
    XCTAssertTrue(member.waitForExistence(timeout: 30))
    member.tap()

    let nameField = app.textFields.matching(
      NSPredicate(
        format: "label CONTAINS[c] %@ OR value CONTAINS[c] %@",
        "Group name",
        "Group name"
      )
    ).firstMatch
    XCTAssertTrue(nameField.waitForExistence(timeout: 15))
    nameField.tap()
    nameField.typeText(expectedGroupName)

    let start = element(in: app, containing: "Start group chat")
    XCTAssertTrue(start.waitForExistence(timeout: 15))
    start.tap()
    let group = element(in: app, containing: expectedGroupName)
    XCTAssertTrue(group.waitForExistence(timeout: 90))
    NSLog(
      "MKNOON_397_CHAT_GROUP_FIXTURE_CREATED group=%@ member=%@",
      expectedGroupName,
      expectedMemberName
    )
  }

  /// Plan 397 setup step 2. The Android member has accepted the chat group;
  /// this iPhone authors the reaction target through the normal composer.
  func testAuthorChatGroupReactionTarget() throws {
    let bundleId = ProcessInfo.processInfo.environment["MKNOON_APNS_TAP_APP_BUNDLE_ID"] ?? "com.mknoon.app"
    guard let expectedGroupName = configuredValue(
      environmentName: "MKNOON_257_EXPECTED_GROUP_NAME",
      configKey: "expectedGroupName"
    ), !expectedGroupName.isEmpty else {
      XCTFail("Plan 397 target authoring requires expectedGroupName")
      return
    }
    guard let expectedTargetText = configuredValue(
      environmentName: "MKNOON_257_EXPECTED_TARGET_TEXT",
      configKey: "expectedTargetMessageText"
    ), !expectedTargetText.isEmpty else {
      XCTFail("Plan 397 target authoring requires expectedTargetMessageText")
      return
    }

    let app = XCUIApplication(bundleIdentifier: bundleId)
    app.terminate()
    app.launch()
    XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30))
    let group = element(in: app, containing: expectedGroupName)
    XCTAssertTrue(group.waitForExistence(timeout: 60))
    group.tap()

    let compose = firstComposeElement(in: app)
    XCTAssertTrue(compose.waitForExistence(timeout: 30))
    compose.tap()
    compose.typeText(expectedTargetText)
    let send = app.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0))
      .withOffset(
        CGVector(
          dx: min(compose.frame.maxX + 20, app.frame.maxX - 12),
          dy: compose.frame.midY
        )
      )
    send.tap()
    let rendered = element(in: app, containing: expectedTargetText)
    XCTAssertTrue(rendered.waitForExistence(timeout: 90))
    NSLog(
      "MKNOON_397_CHAT_GROUP_TARGET_AUTHORED group=%@ target=%@",
      expectedGroupName,
      expectedTargetText
    )
  }

  /// Plan 397's single selector is parameterized by `notificationPhase` and is
  /// run once for the ordinary message card and once for the ADD reaction card.
  /// Both copies must belong to one SpringBoard card container before it taps.
  func testChatGroupNotificationTap() throws {
    let bundleId = ProcessInfo.processInfo.environment["MKNOON_APNS_TAP_APP_BUNDLE_ID"] ?? "com.mknoon.app"
    guard let phase = configuredValue(
      environmentName: "MKNOON_397_NOTIFICATION_PHASE",
      configKey: "notificationPhase"
    ), phase == "message" || phase == "reaction" else {
      XCTFail("Plan 397 notification tap requires message or reaction phase")
      return
    }
    guard let expectedGroupName = configuredValue(
      environmentName: "MKNOON_257_EXPECTED_GROUP_NAME",
      configKey: "expectedGroupName"
    ), !expectedGroupName.isEmpty else {
      XCTFail("Plan 397 notification tap requires expectedGroupName")
      return
    }
    guard let expectedTargetText = configuredValue(
      environmentName: "MKNOON_257_EXPECTED_TARGET_TEXT",
      configKey: "expectedTargetMessageText"
    ), !expectedTargetText.isEmpty else {
      XCTFail("Plan 397 notification tap requires expectedTargetMessageText")
      return
    }
    guard let expectedEventText = configuredValue(
      environmentName: "MKNOON_397_EXPECTED_EVENT_TEXT",
      configKey: "expectedEventText"
    ), !expectedEventText.isEmpty else {
      XCTFail("Plan 397 notification tap requires expectedEventText")
      return
    }
    guard let expectedBody = configuredValue(
      environmentName: "MKNOON_APNS_TAP_EXPECTED_BODY",
      configKey: "expectedBody"
    ), !expectedBody.isEmpty else {
      XCTFail("Plan 397 same-card tap requires expectedBody")
      return
    }
    let title = configuredValue(
      environmentName: "MKNOON_APNS_TAP_EXPECTED_TITLE",
      configKey: "expectedTitle"
    ) ?? expectedGroupName

    let app = XCUIApplication(bundleIdentifier: bundleId)
    app.terminate()
    let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
    XCUIDevice.shared.press(.home)
    XCTAssertTrue(springboard.wait(for: .runningForeground, timeout: 10))
    settleOnSpringboard()

    let match = try XCTUnwrap(
      findSameContainerNotificationCard(
        title: title,
        body: expectedBody,
        springboard: springboard,
        timeout: 20
      ),
      "Plan 397 could not find title and body in one notification card"
    )
    XCTAssertEqual(match.count, 1, "Plan 397 requires one same-copy card")
    NSLog(
      "MKNOON_397_IOS_NOTIFICATION_CARD phase=%@ same_card=true matching_card_count=1 title_matched=true body_matched=true",
      phase
    )
    XCTAssertTrue(
      tapSameContainerNotificationCard(
        match.card,
        title: title,
        springboard: springboard
      ),
      "Plan 397 could not tap the exact same-copy card container"
    )
    XCTAssertTrue(
      app.wait(for: .runningForeground, timeout: 30),
      "Plan 397 card tap did not cold-launch the app"
    )

    let group = element(in: app, containing: expectedGroupName)
    let expectedRouteText = phase == "message"
      ? expectedEventText
      : expectedTargetText
    let route = element(in: app, containing: expectedRouteText)
    XCTAssertTrue(group.waitForExistence(timeout: 20))
    XCTAssertTrue(route.waitForExistence(timeout: 20))
    let unread = app.descendants(matching: .any).matching(
      NSPredicate(format: "label ==[c] %@ OR value ==[c] %@", "Unread", "Unread")
    ).firstMatch
    XCTAssertFalse(
      unread.waitForExistence(timeout: 2),
      "Plan 397 final group UI retained an unread marker"
    )
    NSLog(
      "MKNOON_397_CHAT_GROUP_TAP phase=%@ group_rendered=true route_text_visible=true final_unread_clear=true manual_taps=0 cold_launch=true",
      phase
    )
  }

  /// Plan 257 TC-16: cold-tap a real announcement-reaction card prepared by
  /// the host capture driver and require both the announcement and reacted-to
  /// target to render. The staged config is authoritative; this selector never
  /// falls back to generic notification chrome or a manual tap.
  func testAnnouncementReactionNotificationTap() throws {
    let bundleId = ProcessInfo.processInfo.environment["MKNOON_APNS_TAP_APP_BUNDLE_ID"] ?? "com.mknoon.app"
    guard let expectedGroupName = configuredValue(
      environmentName: "MKNOON_257_EXPECTED_GROUP_NAME",
      configKey: "expectedGroupName"
    ), !expectedGroupName.isEmpty else {
      XCTFail("Plan 257 announcement reaction tap requires expectedGroupName in the staged tap config")
      return
    }
    guard let expectedTargetText = configuredValue(
      environmentName: "MKNOON_257_EXPECTED_TARGET_TEXT",
      configKey: "expectedTargetMessageText"
    ), !expectedTargetText.isEmpty else {
      XCTFail("Plan 257 announcement reaction tap requires expectedTargetMessageText in the staged tap config")
      return
    }
    guard let expectedActorName = configuredValue(
      environmentName: "MKNOON_257_EXPECTED_ACTOR_NAME",
      configKey: "expectedActorName"
    ), !expectedActorName.isEmpty else {
      XCTFail("Plan 257 announcement reaction tap requires expectedActorName")
      return
    }
    let expectedEmoji = configuredValue(
      environmentName: "MKNOON_257_EXPECTED_REACTION_EMOJI",
      configKey: "expectedReactionEmoji"
    ) ?? "👍"

    let app = XCUIApplication(bundleIdentifier: bundleId)
    app.terminate()
    try observeAnnouncementReactionNotification(
      expectedGroupName: expectedGroupName,
      expectedActorName: expectedActorName,
      expectedEmoji: expectedEmoji,
      expectedTargetText: expectedTargetText
    )
    try tapExistingNotification(
      waitForHostPush: false,
      requireTitleMatchedNotification: true
    )

    let groupPredicate = NSPredicate(
      format: "label CONTAINS[c] %@ OR value CONTAINS[c] %@",
      expectedGroupName,
      expectedGroupName
    )
    let targetPredicate = NSPredicate(
      format: "label CONTAINS[c] %@ OR value CONTAINS[c] %@",
      expectedTargetText,
      expectedTargetText
    )
    let group = app.descendants(matching: .any)
      .matching(groupPredicate)
      .firstMatch
    let target = app.descendants(matching: .any)
      .matching(targetPredicate)
      .firstMatch
    XCTAssertTrue(
      group.waitForExistence(timeout: 20),
      "Announcement reaction tap did not render group \(expectedGroupName)"
    )
    XCTAssertTrue(
      target.waitForExistence(timeout: 20),
      "Announcement reaction tap did not render target \(expectedTargetText)"
    )
    NSLog(
      "MKNOON_257_ANNOUNCEMENT_REACTION_TAP group_rendered=true target_message_visible=true manual_taps=0 cold_launch=true"
    )
  }

  private func element(
    in app: XCUIApplication,
    containing text: String
  ) -> XCUIElement {
    app.descendants(matching: .any).matching(
      NSPredicate(
        format: "label CONTAINS[c] %@ OR value CONTAINS[c] %@ OR identifier CONTAINS[c] %@",
        text,
        text,
        text
      )
    ).firstMatch
  }

  private func firstComposeElement(in app: XCUIApplication) -> XCUIElement {
    let textField = app.textFields.firstMatch
    if textField.exists {
      return textField
    }
    return app.textViews.firstMatch
  }

  private func findSameContainerNotificationCard(
    title: String,
    body: String,
    springboard: XCUIApplication,
    timeout: TimeInterval
  ) -> (card: XCUIElement, count: Int)? {
    let deadline = Date().addingTimeInterval(timeout)
    var surface = 0
    while Date() < deadline {
      let matches = sameContainerNotificationCards(
        title: title,
        body: body,
        springboard: springboard
      )
      if let card = matches.first {
        return (card, matches.count)
      }
      if surface == 0 {
        openNotificationCenter(from: springboard)
        surface = 1
      } else if surface == 1 {
        revealNotificationHistory(from: springboard)
        surface = 2
      }
      RunLoop.current.run(until: Date().addingTimeInterval(0.5))
    }
    return nil
  }

  private func sameContainerNotificationCards(
    title: String,
    body: String,
    springboard: XCUIApplication
  ) -> [XCUIElement] {
    let chrome = NSPredicate(
      format: "identifier CONTAINS[c] %@ OR identifier CONTAINS[c] %@ OR identifier CONTAINS[c] %@",
      "NotificationShortLookView",
      "NotificationCell",
      "NotificationListCell"
    )
    let preferred = springboard.descendants(matching: .any).matching(chrome)
    let preferredMatches = matchingSameContainerCards(
      in: preferred,
      title: title,
      body: body,
      limit: 30
    )
    if !preferredMatches.isEmpty {
      return preferredMatches
    }
    return matchingSameContainerCards(
      in: springboard.cells,
      title: title,
      body: body,
      limit: 40
    )
  }

  private func matchingSameContainerCards(
    in candidates: XCUIElementQuery,
    title: String,
    body: String,
    limit: Int
  ) -> [XCUIElement] {
    var matches: [XCUIElement] = []
    for index in 0..<min(candidates.count, limit) {
      let card = candidates.element(boundBy: index)
      if card.exists
        && notificationCard(card, containsExactText: title)
        && notificationCard(card, containsExactText: body)
      {
        matches.append(card)
      }
    }
    return matches
  }

  private func notificationCard(
    _ card: XCUIElement,
    containsExactText text: String
  ) -> Bool {
    if card.label.compare(text, options: [.caseInsensitive]) == .orderedSame
      || String(describing: card.value)
        .compare(text, options: [.caseInsensitive]) == .orderedSame
    {
      return true
    }
    let predicate = NSPredicate(
      format: "label ==[c] %@ OR value ==[c] %@",
      text,
      text
    )
    return card.descendants(matching: .any).matching(predicate).firstMatch.exists
  }

  private func tapSameContainerNotificationCard(
    _ card: XCUIElement,
    title: String,
    springboard: XCUIApplication
  ) -> Bool {
    if card.isHittable && !card.frame.isEmpty {
      card.tap()
      tapNotificationOpenActionIfPresent(in: springboard)
      return true
    }
    let titlePredicate = NSPredicate(
      format: "label ==[c] %@ OR value ==[c] %@",
      title,
      title
    )
    let titleInsideCard = card.descendants(matching: .any)
      .matching(titlePredicate)
      .firstMatch
    if titleInsideCard.exists && titleInsideCard.isHittable {
      titleInsideCard.tap()
      tapNotificationOpenActionIfPresent(in: springboard)
      return true
    }
    return false
  }

  private func observeAnnouncementReactionNotification(
    expectedGroupName: String,
    expectedActorName: String,
    expectedEmoji: String,
    expectedTargetText: String
  ) throws {
    let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
    XCUIDevice.shared.press(.home)
    guard springboard.wait(for: .runningForeground, timeout: 10) else {
      XCTFail("SpringBoard did not become ready for notification observation")
      return
    }
    settleOnSpringboard()
    openNotificationCenter(from: springboard)

    let expectedBody = "\(expectedActorName) reacted \(expectedEmoji) to your message"
    let titleMatches = springboard.descendants(matching: .any).matching(
      NSPredicate(
        format: "label ==[c] %@ OR value ==[c] %@",
        expectedGroupName,
        expectedGroupName
      )
    )
    let bodyMatches = springboard.descendants(matching: .any).matching(
      NSPredicate(
        format: "label ==[c] %@ OR value ==[c] %@",
        expectedBody,
        expectedBody
      )
    )
    XCTAssertEqual(titleMatches.count, 1, "Expected one matching announcement card title")
    XCTAssertEqual(bodyMatches.count, 1, "Expected one matching announcement reaction body")

    let observation: [String: Any] = [
      "schema": "mknoon.plan257.ios-notification-observation.v1",
      "title": titleMatches.firstMatch.label,
      "body": bodyMatches.firstMatch.label,
      "matchingCardCount": titleMatches.count,
      "containsNewMessageCopy":
        titleMatches.firstMatch.label.localizedCaseInsensitiveContains("New Message") ||
        bodyMatches.firstMatch.label.localizedCaseInsensitiveContains("New Message"),
      "expectedTargetMessageText": expectedTargetText,
    ]
    let data = try JSONSerialization.data(
      withJSONObject: observation,
      options: [.sortedKeys]
    )
    guard let json = String(data: data, encoding: .utf8) else {
      XCTFail("Plan 257 could not encode the raw notification observation")
      return
    }
    let line = "MKNOON_257_IOS_NOTIFICATION_OBSERVATION \(json)"
    NSLog("%@", line)
    fputs("\(line)\n", stdout)
    fflush(stdout)
  }

  private func configuredNotificationIsPresent() -> Bool {
    let title = configuredValue(
      environmentName: "MKNOON_APNS_TAP_EXPECTED_TITLE",
      configKey: "expectedTitle"
    ) ?? "New Message"
    let body = configuredValue(
      environmentName: "MKNOON_APNS_TAP_EXPECTED_BODY",
      configKey: "expectedBody"
    )
    let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")

    XCUIDevice.shared.press(.home)
    guard springboard.wait(for: .runningForeground, timeout: 10) else {
      return false
    }
    settleOnSpringboard()

    let titleOnCurrentSurface = notificationTextExists(
      title,
      springboard: springboard,
      timeout: 4
    )
    let bodyOnCurrentSurface = body == nil || notificationTextExists(
      body!,
      springboard: springboard,
      timeout: 2
    )
    emitPlan258Marker(
      "CARD_LOOKUP",
      fields: [
        "attempt": "1",
        "body_matched": bodyOnCurrentSurface ? "true" : "false",
        "surface": "current",
        "title_matched": titleOnCurrentSurface ? "true" : "false",
      ]
    )
    if titleOnCurrentSurface && bodyOnCurrentSurface {
      return true
    }

    for attempt in 2...3 {
      XCUIDevice.shared.press(.home)
      guard springboard.wait(for: .runningForeground, timeout: 10) else {
        return false
      }
      settleOnSpringboard()
      openNotificationCenter(from: springboard)
      if attempt == 3 {
        revealNotificationHistory(from: springboard)
      }
      let titleMatched = notificationTextExists(
        title,
        springboard: springboard,
        timeout: 10
      )
      let bodyMatched = body == nil || notificationTextExists(
        body!,
        springboard: springboard,
        timeout: 4
      )
      emitPlan258Marker(
        "CARD_LOOKUP",
        fields: [
          "attempt": String(attempt),
          "body_matched": bodyMatched ? "true" : "false",
          "surface": attempt == 2
            ? "notification_center"
            : "notification_history",
          "title_matched": titleMatched ? "true" : "false",
        ]
      )
      if titleMatched && bodyMatched {
        return true
      }
    }
    return false
  }

  private func notificationIsPresent(
    title: String,
    body: String?,
    timeout: TimeInterval
  ) -> Bool {
    let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
    XCUIDevice.shared.press(.home)
    guard springboard.wait(for: .runningForeground, timeout: 10) else {
      return false
    }
    settleOnSpringboard()
    openNotificationCenter(from: springboard)
    revealNotificationHistory(from: springboard)
    let titleMatched = notificationTextExists(
      title,
      springboard: springboard,
      timeout: timeout
    )
    let bodyMatched = body == nil || notificationTextExists(
      body!,
      springboard: springboard,
      timeout: titleMatched ? 2 : 0
    )
    return titleMatched && bodyMatched
  }

  private func waitForApplicationBadge(
    _ expected: Int,
    timeout: TimeInterval
  ) -> Bool {
    let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
    let appName = ProcessInfo.processInfo.environment["MKNOON_APNS_TAP_APP_NAME"] ?? "Mknoon"
    XCUIDevice.shared.press(.home)
    guard springboard.wait(for: .runningForeground, timeout: 10) else {
      return false
    }
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
      let exact = springboard.icons[appName]
      let icon: XCUIElement
      if exact.exists {
        icon = exact
      } else {
        let predicate = NSPredicate(
          format: "label BEGINSWITH[c] %@ OR identifier ==[c] %@",
          appName,
          appName
        )
        icon = springboard.icons.matching(predicate).firstMatch
      }
      if icon.exists, applicationBadgeValue(icon, appName: appName) == expected {
        return true
      }
      RunLoop.current.run(until: Date().addingTimeInterval(0.5))
    }
    return false
  }

  private func applicationBadgeValue(_ icon: XCUIElement, appName: String) -> Int? {
    let candidates = [String(describing: icon.value), icon.label]
    for candidate in candidates {
      let digits = candidate.split(whereSeparator: { !$0.isNumber })
      if let value = digits.compactMap({ Int($0) }).first {
        return value
      }
    }
    let normalizedLabel = icon.label.trimmingCharacters(in: .whitespacesAndNewlines)
    if normalizedLabel.localizedCaseInsensitiveContains(appName) {
      return 0
    }
    return nil
  }

  private func setAirplaneMode(_ enabled: Bool) throws -> Bool {
    let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
    XCUIDevice.shared.press(.home)
    guard springboard.wait(for: .runningForeground, timeout: 10) else {
      XCTFail("SpringBoard did not become ready for airplane-mode automation")
      return false
    }
    settleOnSpringboard()

    let topRight = springboard.coordinate(
      withNormalizedOffset: CGVector(dx: 0.92, dy: 0.01)
    )
    let center = springboard.coordinate(
      withNormalizedOffset: CGVector(dx: 0.92, dy: 0.62)
    )
    topRight.press(forDuration: 0.1, thenDragTo: center)
    RunLoop.current.run(until: Date().addingTimeInterval(1.5))

    let localizedValues = localizedAirplaneToggleValues()
    let toggle = airplaneModeToggle(in: springboard)
    guard toggle.waitForExistence(timeout: 10) else {
      XCTFail("Control Center airplane-mode toggle is unavailable")
      return false
    }
    guard let initialState = airplaneToggleIsOn(
      toggle,
      localizedValues: localizedValues
    ) else {
      XCTFail("Control Center airplane-mode toggle has an unknown initial state: \(airplaneToggleDiagnostic(toggle))")
      return false
    }

    var currentState: Bool? = initialState
    var currentToggle = toggle
    if initialState != enabled {
      toggle.tap()
      let deadline = Date().addingTimeInterval(8)
      while Date() < deadline {
        RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        currentToggle = airplaneModeToggle(in: springboard)
        if currentToggle.exists {
          currentState = airplaneToggleIsOn(
            currentToggle,
            localizedValues: localizedValues
          )
          if currentState == enabled {
            break
          }
        }
      }
    }
    guard currentState == enabled else {
      XCTFail(
        "Airplane mode did not reach the requested state: \(airplaneToggleDiagnostic(currentToggle))"
      )
      return false
    }
    XCUIDevice.shared.press(.home)
    settleOnSpringboard()
    return true
  }

  private func airplaneModeToggle(in springboard: XCUIApplication) -> XCUIElement {
    springboard.switches
      .matching(identifier: "airplane-mode-button")
      .firstMatch
  }

  private func airplaneToggleIsOn(
    _ element: XCUIElement,
    localizedValues: (on: String, off: String)
  ) -> Bool? {
    decodeAirplaneToggleState(
      value: element.value,
      isSelected: element.isSelected,
      localizedValues: localizedValues
    )
  }

  private func decodeAirplaneToggleState(
    value: Any?,
    isSelected: Bool,
    localizedValues: (on: String, off: String)
  ) -> Bool? {
    if let boolean = value as? Bool {
      return boolean
    }
    if let number = value as? NSNumber {
      switch number.intValue {
      case 0:
        return false
      case 1:
        return true
      default:
        break
      }
    }
    if let text = value as? String {
      let normalized = normalizedAirplaneStateText(text)
      let normalizedOn = normalizedAirplaneStateText(localizedValues.on)
      let normalizedOff = normalizedAirplaneStateText(localizedValues.off)
      if airplaneStateText(normalized, matches: normalizedOn)
        || ["1", "true", "yes", "on"].contains(normalized)
      {
        return true
      }
      if airplaneStateText(normalized, matches: normalizedOff)
        || ["0", "false", "no", "off"].contains(normalized)
      {
        return false
      }
    }

    // Selection is a reliable positive signal on some Control Center
    // versions, but false does not mean that a switch is off.
    return isSelected ? true : nil
  }

  private func localizedAirplaneToggleValues() -> (on: String, off: String) {
    let bundlePath = "/System/Library/ControlCenter/Bundles/ConnectivityModule.bundle"
    guard let bundle = Bundle(path: bundlePath) else {
      return (on: "On", off: "Off")
    }
    return (
      on: bundle.localizedString(
        forKey: "CONTROL_CENTER_STATUS_AIRPLANE_MODE_ON",
        value: "On",
        table: "Localizable"
      ),
      off: bundle.localizedString(
        forKey: "CONTROL_CENTER_STATUS_AIRPLANE_MODE_OFF",
        value: "Off",
        table: "Localizable"
      )
    )
  }

  private func normalizedAirplaneStateText(_ value: String) -> String {
    value
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .folding(
        options: [.caseInsensitive, .diacriticInsensitive],
        locale: Locale.current
      )
  }

  private func airplaneStateText(_ value: String, matches state: String) -> Bool {
    guard !state.isEmpty else {
      return false
    }
    if value == state {
      return true
    }
    for separator in [",", ":", ";", "،"] {
      if value.hasPrefix("\(state)\(separator)")
        || value.hasSuffix("\(separator)\(state)")
        || value.hasSuffix("\(separator) \(state)")
      {
        return true
      }
    }
    return false
  }

  private func airplaneToggleDiagnostic(_ element: XCUIElement) -> String {
    let rawValue = String(reflecting: element.value)
    return "identifier=\(element.identifier) type=\(element.elementType) selected=\(element.isSelected) value=\(rawValue)"
  }

  private func emitPlan258Marker(
    _ event: String,
    fields: [String: String] = [:]
  ) {
    let timestamp = ISO8601DateFormatter().string(from: Date())
    let suffix = fields.keys.sorted().map { key in
      "\(key)=\(fields[key] ?? "")"
    }.joined(separator: " ")
    let line = "MKNOON_258_IOS_PAYLOAD_\(event) at=\(timestamp) \(suffix)"
      .trimmingCharacters(in: .whitespaces)
    NSLog("%@", line)
    fputs("\(line)\n", stdout)
    fflush(stdout)
  }

  private func performNotificationTap(mode: String) throws {
    switch mode {
    case "cold":
      prepareColdNotificationTap()
    default:
      try prepareWarmNotificationTap()
    }

    try tapExistingNotification(waitForHostPush: true)
  }

  private func prepareWarmNotificationTap() throws {
    let bundleId = ProcessInfo.processInfo.environment["MKNOON_APNS_TAP_APP_BUNDLE_ID"] ?? "com.mknoon.app"
    let title = configuredValue(
      environmentName: "MKNOON_APNS_TAP_EXPECTED_TITLE",
      configKey: "expectedTitle"
    ) ?? "New Message"
    let preBackgroundWait = TimeInterval(
      configuredValue(
        environmentName: "MKNOON_APNS_TAP_PRE_BACKGROUND_WAIT_SECONDS",
        configKey: "preBackgroundWaitSeconds"
      ) ?? "8"
    ) ?? 8
    let app = XCUIApplication(bundleIdentifier: bundleId)
    let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")

    app.terminate()
    app.launch()
    XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30))
    // #21 fix: poll for the (late-appearing) notification-permission alert across
    // the pre-background window and grant it the moment it shows, instead of a
    // one-shot check that the prompt usually beats. Returns early once granted,
    // otherwise the poll itself doubles as the app-settle wait.
    allowNotificationPromptIfPresent(
      in: springboard,
      timeout: max(preBackgroundWait, 15)
    )
    RunLoop.current.run(until: Date().addingTimeInterval(2))
    XCUIDevice.shared.press(.home)
    XCTAssertTrue(springboard.wait(for: .runningForeground, timeout: 10))
    unlockSpringboardIfNeeded(springboard)
    settleOnSpringboard()
    emitReadyMarker(mode: "warm", title: title)
  }

  private func prepareColdNotificationTap() {
    let title = configuredValue(
      environmentName: "MKNOON_APNS_TAP_EXPECTED_TITLE",
      configKey: "expectedTitle"
    ) ?? "New Message"

    XCUIDevice.shared.press(.home)
    settleOnSpringboard()
    emitReadyMarker(mode: "cold", title: title)
  }

  private func tapExistingNotification(
    waitForHostPush: Bool,
    requireTitleMatchedNotification: Bool = false
  ) throws {
    let bundleId = ProcessInfo.processInfo.environment["MKNOON_APNS_TAP_APP_BUNDLE_ID"] ?? "com.mknoon.app"
    let title = configuredValue(
      environmentName: "MKNOON_APNS_TAP_EXPECTED_TITLE",
      configKey: "expectedTitle"
    ) ?? "New Message"
    let expectedBody = configuredValue(
      environmentName: "MKNOON_APNS_TAP_EXPECTED_BODY",
      configKey: "expectedBody"
    )
    let routeCategory = configuredValue(
      environmentName: "MKNOON_APNS_TAP_ROUTE_CATEGORY",
      configKey: "routeCategory"
    ) ?? "unspecified"
    let postTapWait = TimeInterval(ProcessInfo.processInfo.environment["MKNOON_APNS_TAP_POST_TAP_WAIT_SECONDS"] ?? "5") ?? 5
    let app = XCUIApplication(bundleIdentifier: bundleId)
    let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")

    XCUIDevice.shared.press(.home)
    XCTAssertTrue(springboard.wait(for: .runningForeground, timeout: 10))
    settleOnSpringboard()
    // #21: a permission alert can still be up over Springboard (granted late, or
    // raised after we backgrounded). Clear it before hunting the banner, else the
    // notification stays undelivered/untappable.
    allowNotificationPromptIfPresent(in: springboard, timeout: 3)

    if waitForHostPush {
      waitForHostPushInjection()
    }
    if let expectedBody {
      var bodyMatched = notificationTextExists(
        expectedBody,
        springboard: springboard,
        timeout: 8
      )
      if !bodyMatched {
        openNotificationCenter(from: springboard)
        bodyMatched = notificationTextExists(
          expectedBody,
          springboard: springboard,
          timeout: 12
        )
      }
      if !bodyMatched {
        revealNotificationHistory(from: springboard)
        bodyMatched = notificationTextExists(
          expectedBody,
          springboard: springboard,
          timeout: 8
        )
      }
      XCTAssertTrue(
        bodyMatched,
        "Could not find the configured Springboard notification body"
      )
      NSLog(
        "MKNOON_IOS_NOTIFICATION_PRESENTED title_matched=true body_matched=true routeCategory=%@",
        routeCategory
      )
    }
    XCTAssertTrue(
      tapNotification(
        title: title,
        expectedBody: expectedBody,
        springboard: springboard,
        allowGenericChromeFallback: !requireTitleMatchedNotification
      ),
      "Could not find the configured Springboard notification title"
    )
    if !app.wait(for: .runningForeground, timeout: 8) {
      XCTAssertTrue(
        tapNotification(
          title: title,
          expectedBody: expectedBody,
          springboard: springboard,
          allowGenericChromeFallback: !requireTitleMatchedNotification
        ),
        "Could not re-tap the configured Springboard notification"
      )
    }
    XCTAssertTrue(
      app.wait(for: .runningForeground, timeout: 30),
      "Expected notification tap to foreground \(bundleId)"
    )
    RunLoop.current.run(until: Date().addingTimeInterval(postTapWait))
  }

  /// Grants the iOS "Would Like to Send You Notifications" permission alert.
  ///
  /// #21 fix: the alert appears several seconds AFTER `app.launch()` (the app
  /// requests authorization only once startup settles), so a one-shot check
  /// right after launch races — and loses to — the prompt, leaving it lingering
  /// over Springboard and blocking notification delivery. Poll across [timeout]
  /// and tap "Allow" the moment it appears. Returns true once granted.
  @discardableResult
  private func allowNotificationPromptIfPresent(
    in springboard: XCUIApplication,
    timeout: TimeInterval = 3
  ) -> Bool {
    let allowPredicate = NSPredicate(format: "label CONTAINS[c] %@", "Allow")
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
      let allowButton = springboard.buttons["Allow"]
      if allowButton.exists && allowButton.isHittable {
        allowButton.tap()
        return true
      }
      let matchingButton = springboard.buttons.matching(allowPredicate).firstMatch
      if matchingButton.exists && matchingButton.isHittable {
        matchingButton.tap()
        return true
      }
      RunLoop.current.run(until: Date().addingTimeInterval(0.5))
    }
    return false
  }

  private func emitReadyMarker(mode: String, title: String) {
    let line = "\(readyMarker) mode=\(mode) title_configured=\(!title.isEmpty)"
    if let readyFile = configuredValue(
      environmentName: "MKNOON_APNS_TAP_READY_FILE",
      configKey: "readyFile"
    ) {
      try? line.write(
        toFile: readyFile,
        atomically: true,
        encoding: .utf8
      )
    }
    NSLog("%@", line)
    fputs("\(line)\n", stdout)
    fflush(stdout)
  }

  private func settleOnSpringboard() {
    RunLoop.current.run(until: Date().addingTimeInterval(1.5))
  }

  private func waitForHostPushInjection() {
    RunLoop.current.run(until: Date().addingTimeInterval(3))
  }

  private func unlockSpringboardIfNeeded(_ springboard: XCUIApplication) {
    let bottom = springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.92))
    let top = springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.20))
    bottom.press(forDuration: 0.05, thenDragTo: top)
    RunLoop.current.run(until: Date().addingTimeInterval(1))
  }

  private func configuredValue(
    environmentName: String,
    configKey: String
  ) -> String? {
    if let value = ProcessInfo.processInfo.environment[environmentName],
       !value.isEmpty {
      return value
    }
    return tapSmokeConfig()[configKey]
  }

  private func tapSmokeConfig() -> [String: String] {
    let explicitPath = ProcessInfo.processInfo.environment["MKNOON_APNS_TAP_CONFIG_FILE"]
    let configURL: URL
    if let explicitPath, !explicitPath.isEmpty {
      configURL = URL(fileURLWithPath: explicitPath)
    } else {
      configURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("build/ios-notification-tap-ui-smoke/current_tap_config.json")
    }

    guard let data = try? Data(contentsOf: configURL),
          let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
      return [:]
    }

    var config: [String: String] = [:]
    for (key, value) in object {
      if let stringValue = value as? String, !stringValue.isEmpty {
        config[key] = stringValue
      }
    }
    return config
  }

  private func tapNotification(
    title: String,
    expectedBody: String?,
    springboard: XCUIApplication,
    allowGenericChromeFallback: Bool = true
  ) -> Bool {
    if tapVisibleNotification(title: title, springboard: springboard, timeout: 8) {
      return true
    }

    if allowGenericChromeFallback &&
       tapVisibleNotificationChrome(springboard: springboard, timeout: 5) {
      return true
    }

    openNotificationCenter(from: springboard)
    if tapVisibleNotification(title: title, springboard: springboard, timeout: 20) {
      return true
    }

    revealNotificationHistory(from: springboard)
    let bodyMatched = expectedBody == nil || notificationTextExists(
      expectedBody!,
      springboard: springboard,
      timeout: 4
    )
    if bodyMatched && tapVisibleNotification(
      title: title,
      springboard: springboard,
      timeout: 10
    ) {
      return true
    }

    return allowGenericChromeFallback &&
      tapVisibleNotificationChrome(springboard: springboard, timeout: 10)
  }

  private func tapVisibleNotification(
    title: String,
    springboard: XCUIApplication,
    timeout: TimeInterval
  ) -> Bool {
    let predicate = NSPredicate(
      format: "label CONTAINS[c] %@ OR value CONTAINS[c] %@ OR identifier CONTAINS[c] %@",
      title,
      title,
      title
    )
    let deadline = Date().addingTimeInterval(timeout)

    while Date() < deadline {
      if tapFirstMatch(
        springboard.staticTexts.matching(predicate),
        limit: 20,
        springboard: springboard
      ) {
        return true
      }
      let matches = springboard.descendants(matching: .any).matching(predicate)
      if tapFirstMatch(matches, limit: 20, springboard: springboard) {
        return true
      }
      RunLoop.current.run(until: Date().addingTimeInterval(0.5))
    }

    return false
  }

  private func notificationTextExists(
    _ text: String,
    springboard: XCUIApplication,
    timeout: TimeInterval
  ) -> Bool {
    let predicate = NSPredicate(
      format: "label CONTAINS[c] %@ OR value CONTAINS[c] %@",
      text,
      text
    )
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
      let match = springboard.descendants(matching: .any)
        .matching(predicate)
        .firstMatch
      if match.exists {
        return true
      }
      RunLoop.current.run(until: Date().addingTimeInterval(0.5))
    }
    return false
  }

  private func tapVisibleNotificationChrome(
    springboard: XCUIApplication,
    timeout: TimeInterval
  ) -> Bool {
    let predicate = NSPredicate(
      format: "identifier CONTAINS[c] %@ OR label CONTAINS[c] %@ OR value CONTAINS[c] %@",
      "NotificationShortLookView",
      "NotificationShortLookView",
      "NotificationShortLookView"
    )
    let deadline = Date().addingTimeInterval(timeout)

    while Date() < deadline {
      let matches = springboard.descendants(matching: .any).matching(predicate)
      if tapFirstMatch(matches, limit: 10, springboard: springboard) {
        return true
      }
      RunLoop.current.run(until: Date().addingTimeInterval(0.5))
    }

    return false
  }

  private func tapFirstMatch(
    _ matches: XCUIElementQuery,
    limit: Int,
    springboard: XCUIApplication
  ) -> Bool {
    let count = min(matches.count, limit)
    if count == 0 {
      return false
    }

    for index in 0..<count {
      let element = matches.element(boundBy: index)
      if element.exists && element.isHittable && !element.frame.isEmpty {
        element.tap()
        // iOS 26 lock-screen notifications use a two-step activation: tapping
        // the title/card reveals a separate SpringBoard "Open" action. A
        // second title tap only reselects the card and never launches the app.
        // Prefer the action's accessibility identifier, then use an exact
        // button-role label/value fallback for localized SpringBoard variants.
        tapNotificationOpenActionIfPresent(in: springboard)
        return true
      }
    }

    return false
  }

  @discardableResult
  private func tapNotificationOpenActionIfPresent(
    in springboard: XCUIApplication,
    timeout: TimeInterval = 2
  ) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    let exactIdentifier = springboard.buttons
      .matching(identifier: "Open")
      .firstMatch
    let labelPredicate = NSPredicate(
      format: "label ==[c] %@ OR value ==[c] %@",
      "Open",
      "Open"
    )

    while Date() < deadline {
      if exactIdentifier.exists && exactIdentifier.isHittable {
        exactIdentifier.tap()
        NSLog("MKNOON_IOS_NOTIFICATION_OPEN_ACTION_TAPPED source=identifier")
        return true
      }
      let roleMatched = springboard.buttons.matching(labelPredicate).firstMatch
      if roleMatched.exists && roleMatched.isHittable {
        roleMatched.tap()
        NSLog("MKNOON_IOS_NOTIFICATION_OPEN_ACTION_TAPPED source=button_role")
        return true
      }
      RunLoop.current.run(until: Date().addingTimeInterval(0.2))
    }
    return false
  }

  private func openNotificationCenter(from springboard: XCUIApplication) {
    let top = springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.01))
    let center = springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.75))
    top.press(forDuration: 0.1, thenDragTo: center)
    RunLoop.current.run(until: Date().addingTimeInterval(2))
  }

  private func revealNotificationHistory(from springboard: XCUIApplication) {
    let lower = springboard.coordinate(
      withNormalizedOffset: CGVector(dx: 0.5, dy: 0.82)
    )
    let upper = springboard.coordinate(
      withNormalizedOffset: CGVector(dx: 0.5, dy: 0.28)
    )
    lower.press(forDuration: 0.05, thenDragTo: upper)
    RunLoop.current.run(until: Date().addingTimeInterval(1))
  }
}
