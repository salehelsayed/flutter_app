import Flutter
import Foundation
import Network

/// Read-only OS inputs for the video quality policy (U3j-QN).
///
/// Nothing is observed until Dart listens, and Dart listens only while video
/// is enabled. Each event is one complete snapshot map with `networkClass`,
/// `lowDataMode` and `metered` (Bool or NSNull when unknown) and
/// `thermalState`. NWPathMonitor and ProcessInfo need no permission or
/// entitlement.
final class MknoonCallVideoQualityEnvironment: NSObject, FlutterStreamHandler {
  static let eventChannelName = "mknoon/call_video_quality/events"

  private let eventChannel: FlutterEventChannel
  private var observation: Observation?

  init(messenger: FlutterBinaryMessenger) {
    eventChannel = FlutterEventChannel(name: Self.eventChannelName, binaryMessenger: messenger)
    super.init()
    eventChannel.setStreamHandler(self)
  }

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    observation?.stop()
    let next = Observation(sink: events)
    observation = next
    next.start()
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    observation?.stop()
    observation = nil
    return nil
  }

  func dispose() {
    observation?.stop()
    observation = nil
    eventChannel.setStreamHandler(nil)
  }

  /// One listen's observations. After `stop` no callback can emit.
  private final class Observation {
    private let sink: FlutterEventSink
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "mknoon.call.video_quality")
    private var active = false
    private var network = MknoonVideoQualitySnapshot.NetworkInputs.unknown
    private var thermalObserver: NSObjectProtocol?

    init(sink: @escaping FlutterEventSink) {
      self.sink = sink
    }

    func start() {
      active = true
      monitor.pathUpdateHandler = { [weak self] path in
        let inputs = MknoonVideoQualitySnapshot.NetworkInputs(path: path)
        DispatchQueue.main.async {
          guard let self, self.active else { return }
          self.network = inputs
          self.emit()
        }
      }
      monitor.start(queue: queue)
      thermalObserver = NotificationCenter.default.addObserver(
        forName: ProcessInfo.thermalStateDidChangeNotification,
        object: nil,
        queue: .main
      ) { [weak self] _ in
        guard let self, self.active else { return }
        self.emit()
      }
      emit()
    }

    func stop() {
      guard active else { return }
      active = false
      monitor.pathUpdateHandler = nil
      monitor.cancel()
      if let thermalObserver {
        NotificationCenter.default.removeObserver(thermalObserver)
      }
      thermalObserver = nil
    }

    private func emit() {
      guard active else { return }
      sink(MknoonVideoQualitySnapshot.build(
        network: network,
        thermal: ProcessInfo.processInfo.thermalState
      ))
    }
  }
}

/// Pure mapping from OS values to the Dart snapshot map.
enum MknoonVideoQualitySnapshot {
  struct NetworkInputs: Equatable {
    var satisfied: Bool
    var wifi: Bool
    var cellular: Bool
    var wired: Bool
    var constrained: Bool
    var expensive: Bool

    static let unknown = NetworkInputs(
      satisfied: false, wifi: false, cellular: false, wired: false,
      constrained: false, expensive: false
    )

    init(
      satisfied: Bool, wifi: Bool, cellular: Bool, wired: Bool,
      constrained: Bool, expensive: Bool
    ) {
      self.satisfied = satisfied
      self.wifi = wifi
      self.cellular = cellular
      self.wired = wired
      self.constrained = constrained
      self.expensive = expensive
    }

    init(path: NWPath) {
      self.init(
        satisfied: path.status == .satisfied,
        wifi: path.usesInterfaceType(.wifi),
        cellular: path.usesInterfaceType(.cellular),
        wired: path.usesInterfaceType(.wiredEthernet),
        constrained: path.isConstrained,
        expensive: path.isExpensive
      )
    }
  }

  static func build(network: NetworkInputs, thermal: ProcessInfo.ThermalState) -> [String: Any] {
    [
      "networkClass": networkClass(network),
      "lowDataMode": network.satisfied ? network.constrained : NSNull(),
      "metered": network.satisfied ? network.expensive : NSNull(),
      "thermalState": thermalState(thermal),
    ]
  }

  /// A path with no known physical transport (for example a VPN) is unknown.
  static func networkClass(_ network: NetworkInputs) -> String {
    guard network.satisfied else { return "unknown" }
    if network.wifi { return "wifi" }
    if network.cellular { return "cellular" }
    if network.wired { return "other" }
    return "unknown"
  }

  static func thermalState(_ state: ProcessInfo.ThermalState) -> String {
    switch state {
    case .nominal: return "nominal"
    case .fair: return "elevated"
    case .serious: return "serious"
    case .critical: return "critical"
    @unknown default: return "unknown"
    }
  }
}
