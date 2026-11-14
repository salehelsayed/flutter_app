/// The active path's transport class, observed by the platform.
///
/// An unmetered cellular path is still [cellular]. A VPN or ambiguous path
/// must remain [unknown] unless its underlying transport is established.
enum CallVideoNetworkClass { unknown, wifi, cellular, other }

/// Normalized OS thermal pressure for the video quality policy.
///
/// iOS fair and Android light/moderate map to [elevated]. iOS serious and
/// Android severe map to [serious]. Android critical/emergency/shutdown and
/// iOS critical map to [critical]. Unavailable or unreadable state is [unknown].
enum CallVideoThermalState { unknown, nominal, elevated, serious, critical }

/// A read-only OS snapshot; it does not grant camera or call authority.
final class CallVideoQualityEnvironment {
  const CallVideoQualityEnvironment({
    this.networkClass = CallVideoNetworkClass.unknown,
    this.lowDataMode,
    this.metered,
    this.thermalState = CallVideoThermalState.unknown,
  });

  static const unknown = CallVideoQualityEnvironment();

  final CallVideoNetworkClass networkClass;

  /// iOS constrained-path / Android Data Saver state. Null means unknown.
  final bool? lowDataMode;

  /// iOS expensive-path / Android metered-network state. Null means unknown.
  /// This flag does not replace [networkClass] when applying the cellular cap.
  final bool? metered;

  final CallVideoThermalState thermalState;
}

/// One graph-owned source of optional video quality inputs.
///
/// Platform implementations default to video disabled. A disabled source
/// remains [CallVideoQualityEnvironment.unknown] and never registers platform
/// callbacks or reads native state. Unavailable fields stay explicitly unknown;
/// they must not be reported as unrestricted data or nominal temperature.
///
/// Native implementations require no new permission or entitlement. Sampling
/// this source cannot request camera access or change call/audio state.
abstract interface class CallVideoQualityEnvironmentSource {
  /// The latest snapshot, initially unknown and unknown again after close.
  CallVideoQualityEnvironment get current;

  /// Replays [current] to each subscriber, then publishes changed snapshots.
  /// [current] is updated before a live snapshot is published. Platform read
  /// failures become unknown fields rather than an error on the call's stream.
  Stream<CallVideoQualityEnvironment> get changes;

  /// Starts the gated OS observation once. Repeated calls are idempotent;
  /// a disabled or closed source stays inert. The existing audio graph must
  /// not wait for this optional observation to admit or retain a call.
  Future<void> start();

  /// Retires callbacks synchronously, then releases only this source's
  /// observations and closes its stream. Late native completions cannot update
  /// [current] or publish a live snapshot. Idempotent; a closed source cannot
  /// be restarted.
  Future<void> close();
}
