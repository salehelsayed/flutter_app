//  BonsoirServiceBroadcastOffMainTest.swift
//
//  mknoon 175 (TC-01) — OPTIONAL host-side falsifier for the off-main DNS-SD
//  broadcast patch in Classes/Broadcast/BonsoirServiceBroadcast.swift.
//
//  ── Why this file is NOT compiled by the pod ────────────────────────────────
//  The vendored podspec's `source_files` glob is 'Classes/**/*'; this file lives
//  under darwin/Tests/, so it is deliberately EXCLUDED from the shipping pod and
//  cannot break the build. It is the documented artifact for the plan's native
//  unit tier.
//
//  ── Why it is NOT executed in this session (degraded → STRUCTURAL) ──────────
//  Running it needs a test target that `@testable import bonsoir_darwin`
//  (BonsoirServiceBroadcast + its `processResult` seam are `internal`). In this
//  repo that means building the full Runner app + the GoMknoon gomobile
//  xcframework — the flagged-fragile iOS build path. Per the 175 plan's RED-1
//  feasibility note, TC-01 is therefore degraded to a STRUCTURAL assertion (the
//  patched `start()` wires `DNSServiceProcessResult` through a background
//  `DispatchSource.makeReadSource(queue: .global(...))` and no longer calls it
//  synchronously on the calling thread — verified mechanically + by the targeted
//  `xcodebuild -target bonsoir_darwin` compile), and the mutation-verifiable
//  closure is carried by the device-proof TC-02 (CV-08-RESPONSIVE).
//
//  ── To wire + run on a clean toolchain ──────────────────────────────────────
//   1. Add this file to a test target that links `bonsoir_darwin` built with
//      ENABLE_TESTABILITY=YES (e.g. add it to ios/RunnerTests, or add a
//      `test_spec` to the vendored podspec and use the generated unit-test
//      scheme).
//   2. xcodebuild test -workspace ios/Runner.xcworkspace -scheme Runner \
//        -destination 'platform=iOS Simulator,name=iPhone 17' \
//        -only-testing:RunnerTests/BonsoirServiceBroadcastOffMainTest
//
//  ── Contract (RED→GREEN, mutation-verified) ─────────────────────────────────
//   * GREEN (patched): start() returns immediately even when the DNS-SD drain
//     blocks, and the drain runs on a NON-main thread.
//   * RED (mutation = restore the synchronous `DNSServiceProcessResult(sdRef)` in
//     start()): start() blocks for the injected delay on the calling (main)
//     thread → the < 0.2 s bound fails AND the drain runs on the main thread.

import XCTest
@testable import bonsoir_darwin

@available(iOS 13.0, macOS 10.15, *)
final class BonsoirServiceBroadcastOffMainTest: XCTestCase {
    override func tearDown() {
        // Restore the production drain so the static seam never leaks across tests.
        BonsoirServiceBroadcast.processResult = { DNSServiceProcessResult($0) }
        super.tearDown()
    }

    /// INV-1: a slow DNS-SD drain must NOT block `start()`'s calling thread, and
    /// must run off the main thread.
    func test_start_does_not_block_calling_thread() {
        let drained = expectation(description: "DNS-SD drain ran")
        var ranOnMainThread = true

        // Inject a drain that blocks ~2 s and records its thread — simulating a
        // contended / permission-pending mDNSResponder (the device crash vector).
        BonsoirServiceBroadcast.processResult = { _ in
            ranOnMainThread = Thread.isMainThread
            Thread.sleep(forTimeInterval: 2.0)
            drained.fulfill()
            return DNSServiceErrorType(kDNSServiceErr_NoError)
        }

        let service = BonsoirService(
            name: "mknoon-offmain-test",
            type: "_mknoon._tcp",
            port: 54321,
            host: nil,
            attributes: ["peerId": "offmain-test"]
        )
        let broadcast = BonsoirServiceBroadcast(
            id: 1,
            printLogs: false,
            onDispose: {},
            messenger: FakeBinaryMessenger(),
            service: service
        )

        // start() must return well under the 2 s injected block.
        let t0 = Date()
        broadcast.start()
        let elapsed = Date().timeIntervalSince(t0)
        XCTAssertLessThan(
            elapsed, 0.2,
            "start() must return immediately; the DNS-SD drain runs off-main"
        )

        // The injected drain eventually runs (when the registration socket becomes
        // readable) on a background thread — never on main.
        wait(for: [drained], timeout: 5.0)
        XCTAssertFalse(
            ranOnMainThread,
            "DNSServiceProcessResult must be drained off the main thread"
        )

        broadcast.dispose()
    }
}

/// Minimal `FlutterBinaryMessenger` so `BonsoirAction`'s `FlutterEventChannel`
/// init succeeds in a unit test (no platform messages are exercised).
@available(iOS 13.0, macOS 10.15, *)
private final class FakeBinaryMessenger: NSObject, FlutterBinaryMessenger {
    func send(onChannel channel: String, message: Data?) {}
    func send(onChannel channel: String, message: Data?, binaryReply callback: FlutterBinaryReply?) {}
    func setMessageHandlerOnChannel(
        _ channel: String,
        binaryMessageHandler handler: FlutterBinaryMessageHandler?
    ) -> FlutterBinaryMessengerConnection { 0 }
    func cleanUpConnection(_ connection: FlutterBinaryMessengerConnection) {}
}
