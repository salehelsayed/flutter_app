import Flutter
import Foundation

/// The published instance receives engine detach and owns only its own helper.
final class StickerClipFramePlugin: NSObject, FlutterPlugin {
  private var bridge: StickerClipFrameBridge?

  init(messenger: FlutterBinaryMessenger) {
    bridge = StickerClipFrameBridge(messenger: messenger)
    super.init()
  }

  static func register(with registrar: FlutterPluginRegistrar) {
    registrar.publish(StickerClipFramePlugin(messenger: registrar.messenger()))
  }

  func close() {
    let ownedBridge = bridge
    // A late old-engine detach must not clear a replacement's channel handler.
    bridge = nil
    ownedBridge?.close()
  }

  func detachFromEngine(for registrar: FlutterPluginRegistrar) {
    close()
  }

  deinit {
    close()
  }
}
