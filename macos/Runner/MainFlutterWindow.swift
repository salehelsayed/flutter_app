import Cocoa
import FlutterMacOS
#if canImport(GoMknoon)
import GoMknoon
#endif

class MainFlutterWindow: NSWindow {
  private var goBridge: GoBridge?

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)
#if canImport(GoMknoon)
    goBridge = GoBridge(messenger: flutterViewController.engine.binaryMessenger)
#endif

    super.awakeFromNib()
  }
}

#if canImport(GoMknoon)
/// Bridges Flutter MethodChannel/EventChannel to the Go native library on macOS.
class GoBridge: NSObject {
  private let methodChannel: FlutterMethodChannel
  private let eventChannel: FlutterEventChannel
  private var eventSink: FlutterEventSink?
  private var pendingEvents: [String] = []
  private let pendingEventsLock = NSLock()
  private let maxPendingEvents = 256

  init(messenger: FlutterBinaryMessenger) {
    methodChannel = FlutterMethodChannel(
      name: "com.mknoon/go_bridge",
      binaryMessenger: messenger
    )
    eventChannel = FlutterEventChannel(
      name: "com.mknoon/go_bridge_events",
      binaryMessenger: messenger
    )
    super.init()

    methodChannel.setMethodCallHandler(handleMethodCall)
    eventChannel.setStreamHandler(self)
    BridgeInitialize(self)
  }

  private func runOnBackground(
    _ work: @escaping () -> Any?,
    result: @escaping FlutterResult
  ) {
    DispatchQueue.global(qos: .userInitiated).async {
      let value = work()
      DispatchQueue.main.async {
        result(value)
      }
    }
  }

  private func handleMethodCall(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? String

    switch call.method {
    case "generateIdentity":
      runOnBackground({ BridgeGenerateIdentity() }, result: result)
    case "restoreIdentity":
      runOnBackground({ BridgeRestoreIdentity(args ?? "") }, result: result)
    case "mlKemKeygen":
      runOnBackground({ BridgeMlKemKeygen() }, result: result)
    case "encryptMessage":
      runOnBackground({ BridgeEncryptMessage(args ?? "") }, result: result)
    case "decryptMessage":
      runOnBackground({ BridgeDecryptMessage(args ?? "") }, result: result)
    case "signPayload":
      runOnBackground({ BridgeSignPayload(args ?? "") }, result: result)
    case "verifyPayload":
      runOnBackground({ BridgeVerifyPayload(args ?? "") }, result: result)
    case "encryptContactRequest":
      runOnBackground({ BridgeEncryptContactRequest(args ?? "") }, result: result)
    case "decryptContactRequest":
      runOnBackground({ BridgeDecryptContactRequest(args ?? "") }, result: result)
    case "startNode":
      runOnBackground({ BridgeStartNode(args ?? "") }, result: result)
    case "stopNode":
      runOnBackground({ BridgeStopNode() }, result: result)
    case "nodeStatus":
      runOnBackground({ BridgeNodeStatus() }, result: result)
    case "rendezvousRegister":
      runOnBackground({ BridgeRendezvousRegister(args ?? "") }, result: result)
    case "rendezvousDiscover":
      runOnBackground({ BridgeRendezvousDiscover(args ?? "") }, result: result)
    case "relayReconnect":
      runOnBackground({ BridgeRelayReconnect() }, result: result)
    case "relayProbe":
      runOnBackground({ BridgeRelayProbe(args ?? "") }, result: result)
    case "dialPeer":
      runOnBackground({ BridgeDialPeer(args ?? "") }, result: result)
    case "disconnectPeer":
      runOnBackground({ BridgeDisconnectPeer(args ?? "") }, result: result)
    case "sendMessage":
      runOnBackground({ BridgeSendMessage(args ?? "") }, result: result)
    case "confirmDirectMessage":
      runOnBackground({ BridgeConfirmDirectMessage(args ?? "") }, result: result)
    case "inboxStore":
      runOnBackground({ BridgeInboxStore(args ?? "") }, result: result)
    case "inboxRetrieve":
      runOnBackground({ BridgeInboxRetrieveWithParams(args ?? "") }, result: result)
    case "inboxRetrievePending":
      runOnBackground({ BridgeInboxRetrievePendingWithParams(args ?? "") }, result: result)
    case "inboxAck":
      runOnBackground({ BridgeInboxAck(args ?? "") }, result: result)
    case "inboxRegisterToken":
      runOnBackground({ BridgeInboxRegisterToken(args ?? "") }, result: result)
    case "mediaUpload":
      runOnBackground({ BridgeMediaUpload(args ?? "") }, result: result)
    case "mediaDownload":
      runOnBackground({ BridgeMediaDownload(args ?? "") }, result: result)
    case "mediaDelete":
      runOnBackground({ BridgeMediaDelete(args ?? "") }, result: result)
    case "mediaList":
      runOnBackground({ BridgeMediaList(args ?? "") }, result: result)
    case "blobKeygen":
      runOnBackground({ BridgeBlobKeygen(nil) }, result: result)
    case "blobEncrypt":
      runOnBackground({ BridgeBlobEncrypt(args ?? "") }, result: result)
    case "blobDecrypt":
      runOnBackground({ BridgeBlobDecrypt(args ?? "") }, result: result)
    case "profileUpload":
      runOnBackground({ BridgeProfileUpload(args ?? "") }, result: result)
    case "profileDownload":
      runOnBackground({ BridgeProfileDownload(args ?? "") }, result: result)
    case "generateGroupKey":
      runOnBackground({ BridgeGenerateGroupKey() }, result: result)
    case "groupCreate":
      runOnBackground({ BridgeGroupCreate(args ?? "") }, result: result)
    case "groupJoinTopic":
      runOnBackground({ BridgeGroupJoinTopic(args ?? "") }, result: result)
    case "groupLeaveTopic":
      runOnBackground({ BridgeGroupLeaveTopic(args ?? "") }, result: result)
    case "groupPublish":
      runOnBackground({ BridgeGroupPublish(args ?? "") }, result: result)
    case "groupSendReliable":
      runOnBackground({ BridgeGroupSendReliable(args ?? "") }, result: result)
    case "groupPublishReaction":
      runOnBackground({ BridgeGroupPublishReaction(args ?? "") }, result: result)
    case "groupUpdateConfig":
      runOnBackground({ BridgeGroupUpdateConfig(args ?? "") }, result: result)
    case "groupRotateKey":
      runOnBackground({ BridgeGroupRotateKey(args ?? "") }, result: result)
    case "groupUpdateKey":
      runOnBackground({ BridgeGroupUpdateKey(args ?? "") }, result: result)
    case "groupEncryptMessage":
      runOnBackground({ BridgeGroupEncryptMessage(args ?? "") }, result: result)
    case "groupDecryptMessage":
      runOnBackground({ BridgeGroupDecryptMessage(args ?? "") }, result: result)
    case "groupInboxStore":
      runOnBackground({ BridgeGroupInboxStore(args ?? "") }, result: result)
    case "groupInboxRetrieve":
      runOnBackground({ BridgeGroupInboxRetrieve(args ?? "") }, result: result)
    case "groupInboxRetrieveCursor":
      runOnBackground({ BridgeGroupInboxRetrieveCursor(args ?? "") }, result: result)
    case "groupAcknowledgeRecovery":
      runOnBackground({ BridgeGroupAcknowledgeRecovery() }, result: result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }
}

extension GoBridge: FlutterStreamHandler {
  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    NSLog("[GoBridge] onListen: eventSink registered")
    eventSink = events
    flushPendingEvents()
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    NSLog("[GoBridge] onCancel: eventSink cleared")
    eventSink = nil
    return nil
  }
}

extension GoBridge: BridgeEventCallbackProtocol {
  func onEvent(_ jsonString: String?) {
    guard let json = jsonString else { return }
    guard let sink = eventSink else {
      bufferEvent(json, reason: "no sink")
      return
    }
    DispatchQueue.main.async {
      guard let sink = self.eventSink else {
        self.bufferEvent(json, reason: "sink gone")
        return
      }
      sink(json)
    }
  }

  private func bufferEvent(_ json: String, reason: String) {
    pendingEventsLock.lock()
    if pendingEvents.count >= maxPendingEvents {
      pendingEvents.removeFirst()
      NSLog(
        "[GoBridge] bufferEvent: dropped oldest buffered event to keep queue <= %d",
        maxPendingEvents
      )
    }
    pendingEvents.append(json)
    pendingEventsLock.unlock()
    NSLog("[GoBridge] onEvent: BUFFERED (%@) event=%@", reason, String(json.prefix(80)))
  }

  private func flushPendingEvents() {
    DispatchQueue.main.async {
      guard let sink = self.eventSink else { return }
      self.pendingEventsLock.lock()
      let snapshot = self.pendingEvents
      self.pendingEvents.removeAll(keepingCapacity: true)
      self.pendingEventsLock.unlock()
      if snapshot.isEmpty { return }
      NSLog("[GoBridge] flushPendingEvents: replaying %d buffered event(s)", snapshot.count)
      snapshot.forEach { sink($0) }
    }
  }
}
#endif
