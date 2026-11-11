import Flutter
import Foundation

/// The published engine owner retains and closes only its own cutout bridge.
final class StickerCutoutPlugin: NSObject, FlutterPlugin {
  private var bridge: StickerCutoutBridge?

  init(
    messenger: FlutterBinaryMessenger,
    segmenter: StickerCutoutSegmenting? = nil,
    majorVersion: Int = ProcessInfo.processInfo.operatingSystemVersion.majorVersion
  ) {
    bridge = StickerCutoutBridge(
      messenger: messenger, segmenter: segmenter, majorVersion: majorVersion
    )
    super.init()
  }

  static func register(with registrar: FlutterPluginRegistrar) {
    registrar.publish(StickerCutoutPlugin(messenger: registrar.messenger()))
  }

  func close() {
    let ownedBridge = bridge
    bridge = nil
    ownedBridge?.close()
  }

  func detachFromEngine(for registrar: FlutterPluginRegistrar) { close() }
  deinit { close() }
}
