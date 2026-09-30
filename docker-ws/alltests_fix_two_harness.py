"""(B) Android payload permission-denied leg: use the provider-first send (the ordinary live send is confirmed live
and intentionally suppresses the provider while the receiver is P2P-connected).
(A) iOS group media XCTest: background proof after Home uses the device-proven SpringBoard-foreground wait, then
reads app.state directly; same 15 s budget; the assertion message now reports the observed state. [roots...]"""
import pathlib, sys
B_REL = 'integration_test/scripts/notification_android_payload_campaign.dart'
B = [("    final send = await _sendSpacedMarker(marker, runId: runId);\n    final attempt = await _requirePostAttempt(\n      send.cursor,\n      'G7 permission denied',",
      "    final send = await _sendSpacedProviderMarker(marker, runId: runId);\n    final attempt = await _requirePostAttempt(\n      send.cursor,\n      'G7 permission denied',"),
     ("    final control = await _sendSpacedMarker(controlMarker, runId: '$runId-ctl');",
      "    final control = await _sendSpacedProviderMarker(\n      controlMarker,\n      runId: '$runId-ctl',\n    );")]
A_REL = 'ios/RunnerUITests/GroupMediaBackgroundRecoveryUITests.swift'
A = [("    XCUIDevice.shared.press(.home)\n    XCTAssertTrue(waitForBackground(app, timeout: 15))\n    emitNativeHome(processId: phaseAProcessId)",
      "    XCUIDevice.shared.press(.home)\n    XCTAssertTrue(\n      waitForBackground(app, timeout: 15),\n      \"App state after Home: \\(app.state.rawValue)\"\n    )\n    emitNativeHome(processId: phaseAProcessId)"),
     ("""    let expectation = XCTNSPredicateExpectation(
      predicate: NSPredicate { _, _ in
        app.state == .runningBackground
          || app.state == .runningBackgroundSuspended
      },
      object: nil
    )
    return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
  }""",
      """    // Same pattern as NotificationTapUITests (proven on the physical iPhone):
    // wait for SpringBoard to own the foreground, then read app.state
    // directly within the same budget.
    let deadline = Date().addingTimeInterval(timeout)
    let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
    guard springboard.wait(for: .runningForeground, timeout: timeout) else {
      return false
    }
    repeat {
      let state = app.state
      if state == .runningBackground || state == .runningBackgroundSuspended {
        return true
      }
      RunLoop.current.run(until: Date().addingTimeInterval(0.5))
    } while Date() < deadline
    return false
  }""")]
for root in (sys.argv[1:] or ['/Volumes/CrucialX9/flutter_app', '/Volumes/CrucialX9/.mknoon-all-tests-y227gs8x-worktree']):
    for rel, pairs in ((B_REL, B), (A_REL, A)):
        p = pathlib.Path(root, rel); s = p.read_text()
        for old, new in pairs:
            if new in s: continue
            assert s.count(old) == 1, (root, rel, old[:60]); s = s.replace(old, new)
        p.write_text(s)
    print('patched', root)
