import Flutter
import Foundation
import UIKit
import XCTest

@testable import Runner

/// Registration-owner behavior, using the accepted helper and a messenger.
/// Does not extract frames, start an engine, or prove real engine callbacks.
final class StickerClipFramePluginTests: XCTestCase {
  func testRegisterPublishesTheDetachableOwnerOfTheRealChannel() throws {
    try onMain {
      let messenger = ClipRecordingMessenger()
      let registrar = ClipRecordingRegistrar(messenger: messenger)
      StickerClipFramePlugin.register(with: registrar)

      let owner = try XCTUnwrap(registrar.published as? StickerClipFramePlugin)
      defer { owner.close() }
      XCTAssertEqual(registrar.publications, 1)
      XCTAssertEqual(messenger.events, ["attach"])
      messenger.assertCancelReplies()

      owner.detachFromEngine(for: registrar)
      XCTAssertNil(messenger.handler)
      XCTAssertEqual(messenger.events, ["attach", "remove"])
    }
  }

  func testCloseAndDetachRemoveTheOwnedHandlerOnlyOnce() {
    onMain {
      let messenger = ClipRecordingMessenger()
      let registrar = ClipRecordingRegistrar(messenger: messenger)
      let owner = StickerClipFramePlugin(messenger: messenger)
      owner.close()
      owner.close()
      owner.detachFromEngine(for: registrar)

      XCTAssertNil(messenger.handler)
      XCTAssertEqual(messenger.events, ["attach", "remove"])
    }
  }

  func testLateOldDetachAndDeinitCannotEraseAReplacementOnTheSameMessenger() {
    onMain {
      let messenger = ClipRecordingMessenger()
      let oldRegistrar = ClipRecordingRegistrar(messenger: messenger)
      var old: StickerClipFramePlugin? = StickerClipFramePlugin(messenger: messenger)
      weak var releasedOld = old
      old?.close()
      let next = StickerClipFramePlugin(messenger: messenger)
      defer { next.close() }
      XCTAssertEqual(messenger.events, ["attach", "remove", "attach"])

      // The old engine can deliver detach after AppDelegate has installed next.
      // A second close of the old raw helper would clear next's channel.
      old?.detachFromEngine(for: oldRegistrar)
      old = nil
      XCTAssertNil(releasedOld)
      XCTAssertEqual(messenger.events, ["attach", "remove", "attach"])
      messenger.assertCancelReplies()
    }
  }

  func testAnOldEngineDetachOnlyRemovesItsOwnMessengerHandler() {
    onMain {
      let oldMessenger = ClipRecordingMessenger()
      let nextMessenger = ClipRecordingMessenger()
      let oldRegistrar = ClipRecordingRegistrar(messenger: oldMessenger)
      let old = StickerClipFramePlugin(messenger: oldMessenger)
      let next = StickerClipFramePlugin(messenger: nextMessenger)
      defer { old.close(); next.close() }

      old.detachFromEngine(for: oldRegistrar)
      XCTAssertNil(oldMessenger.handler)
      XCTAssertEqual(oldMessenger.events, ["attach", "remove"])
      XCTAssertEqual(nextMessenger.events, ["attach"])
      nextMessenger.assertCancelReplies()
    }
  }

  func testOwnerDeinitExplicitlyClosesItsHelperWithoutAnEngineDetach() {
    onMain {
      let messenger = ClipRecordingMessenger()
      weak var releasedOwner: StickerClipFramePlugin?
      var retainedHelper: StickerClipFrameBridge?
      autoreleasepool {
        let owner = StickerClipFramePlugin(messenger: messenger)
        releasedOwner = owner
        // Keep the helper alive past owner deinit: MethodChannel ARC cleanup
        // must not make this assertion pass without the owner's explicit close.
        let storedHelper = Mirror(reflecting: owner).children.first { $0.label == "bridge" }
        if let storedHelper {
          retainedHelper = Mirror(reflecting: storedHelper.value).children.first?.value
            as? StickerClipFrameBridge
        }
        XCTAssertNotNil(retainedHelper)
        withExtendedLifetime(owner) {
          messenger.assertCancelReplies()
          XCTAssertEqual(messenger.events, ["attach"])
        }
      }

      withExtendedLifetime(retainedHelper) {
        XCTAssertNil(releasedOwner)
        XCTAssertNil(messenger.handler)
        XCTAssertEqual(messenger.events, ["attach", "remove"])
      }
    }
  }

  private func onMain<T>(_ body: () throws -> T) rethrows -> T {
    if Thread.isMainThread { return try body() }
    return try DispatchQueue.main.sync(execute: body)
  }
}

private final class ClipRecordingMessenger: NSObject, FlutterBinaryMessenger {
  private static let channel = "mknoon/custom_sticker_clip_frames"
  private var nextConnection: FlutterBinaryMessengerConnection = 1
  private var currentConnection: FlutterBinaryMessengerConnection?
  private(set) var handler: FlutterBinaryMessageHandler?
  private(set) var events: [String] = []

  func send(onChannel channel: String, message: Data?) {}
  func send(onChannel channel: String, message: Data?, binaryReply callback: FlutterBinaryReply?) {}

  func setMessageHandlerOnChannel(
    _ channel: String,
    binaryMessageHandler handler: FlutterBinaryMessageHandler?
  ) -> FlutterBinaryMessengerConnection {
    XCTAssertEqual(channel, Self.channel)
    let connection = nextConnection
    nextConnection += 1
    currentConnection = handler == nil ? nil : connection
    self.handler = handler
    events.append(handler == nil ? "remove" : "attach")
    return connection
  }

  func cleanUpConnection(_ connection: FlutterBinaryMessengerConnection) {
    // Match the real API's connection guard; an old channel cannot remove a
    // successor. Flutter 3.47.2 also uses this API for setMethodCallHandler(nil),
    // so record the semantic removal, independent of its messenger entry point.
    guard currentConnection == connection else { return }
    currentConnection = nil
    handler = nil
    events.append("remove")
  }

  func assertCancelReplies(file: StaticString = #filePath, line: UInt = #line) {
    guard let handler else {
      XCTFail("the current helper must retain its channel handler", file: file, line: line)
      return
    }
    let codec = FlutterStandardMethodCodec.sharedInstance()
    let request = codec.encode(
      FlutterMethodCall(methodName: "cancel", arguments: ["jobId": "probe"])
    )
    var replies = 0
    handler(request) { data in
      replies += 1
      guard let data else {
        XCTFail("cancel must return a success envelope", file: file, line: line)
        return
      }
      XCTAssertNil(codec.decodeEnvelope(data), file: file, line: line)
    }
    XCTAssertEqual(replies, 1, file: file, line: line)
  }
}

private final class ClipRecordingRegistrar: NSObject, FlutterPluginRegistrar {
  let recordingMessenger: ClipRecordingMessenger
  private(set) var published: NSObject?
  private(set) var publications = 0

  init(messenger: ClipRecordingMessenger) { recordingMessenger = messenger }
  func messenger() -> FlutterBinaryMessenger { recordingMessenger }
  var viewController: UIViewController? { nil }
  func publish(_ value: NSObject) { published = value; publications += 1 }
  func valuePublished(byPlugin pluginKey: String) -> NSObject? { published }

  func textures() -> FlutterTextureRegistry { fatalError("sticker registration must not use textures") }
  func register(_ factory: FlutterPlatformViewFactory, withId factoryId: String) {
    XCTFail("sticker registration must not register a platform view")
  }
  func register(
    _ factory: FlutterPlatformViewFactory,
    withId factoryId: String,
    gestureRecognizersBlockingPolicy: FlutterPlatformViewGestureRecognizersBlockingPolicy
  ) {
    XCTFail("sticker registration must not register a platform view")
  }
  func addMethodCallDelegate(_ delegate: FlutterPlugin, channel: FlutterMethodChannel) {
    XCTFail("the accepted helper owns its own method handler")
  }
  func addApplicationDelegate(_ delegate: FlutterPlugin) {
    XCTFail("publish, rather than an application delegate, supplies engine detach")
  }
  func addSceneDelegate(_ delegate: FlutterSceneLifeCycleDelegate) {
    XCTFail("sticker registration must not register a scene delegate")
  }
  func lookupKey(forAsset asset: String) -> String { asset }
  func lookupKey(forAsset asset: String, fromPackage package: String) -> String { asset }
}
