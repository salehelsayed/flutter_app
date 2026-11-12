import 'call_coordinator.dart';
import '../domain/call_engine.dart';
import '../domain/call_media.dart';
import '../domain/call_media_switch.dart';

/// The existing v2 negotiation owner supplies its single native queue, bound
/// session and immutable signaling custody. The switch executor owns no engine
/// listener or independent SDP queue.
abstract interface class CallMediaSwitchHost {
  bool get current;
  CallVideoSession get session;
  Future<void> serialize(Future<void> Function() job);
  Future<bool> freshUpgradeAuthority();
  CallVideoNegotiation beginNegotiation({
    required String negotiationId,
    required int revision,
    required CallMediaKind media,
    required bool Function() canApply,
  });
  void expectRemoteOffer();
  Future<void> remoteDescriptionApplied(CallVideoNegotiation token);
  void localDescriptionAnnounced(CallVideoNegotiation token);
  Future<bool> closeVideo();
  Future<bool> sendControl(
    MediaSwitchEffect effect, {
    required bool Function() canApply,
  });
  Future<bool> sendDescription({
    required String switchId,
    required CallVideoNegotiation token,
    required CallSessionDescription description,
    required bool repair,
    required int deadlineMs,
    required bool Function() canApply,
  });
}

/// Executes the pure switch machine with fresh local consent and the host's
/// existing SDP queue. Native failures can disable switching but never end the
/// live audio call. Native reconciliation and repair share one abort-time budget.
final class CallMediaSwitchEffectExecutor {
  CallMediaSwitchEffectExecutor({
    required this.host,
    required this.localIsCaller,
    required CallMediaKind initialMedia,
    required this.nowMs,
    required this.idSource,
    this.videoEnabled = false,
    this.maximumTransactions = 32,
    this.onChanged,
    this.timerScheduler = const DartCallTimerScheduler(),
  }) : machine = CallMediaSwitchMachine(
         localIsCaller: localIsCaller,
         wireVersion: CallWireVersion.v2,
         videoEnabled: videoEnabled,
         connected: true,
         settledMedia: initialMedia,
         nowMs: nowMs,
       );

  final CallMediaSwitchHost host;
  final bool localIsCaller;
  final int Function() nowMs;
  final String Function() idSource;
  final bool videoEnabled;
  final int maximumTransactions;
  final void Function()? onChanged;
  final CallTimerScheduler timerScheduler;
  final CallMediaSwitchMachine machine;

  Future<void> get workSettled async {}

  bool request(
    MediaSwitchRequest request, {
    CallLocalCameraGrant? localGrant,
    bool Function()? canApply,
  }) => false;

  bool respond({
    required String id,
    required int baseRevision,
    required bool fromCaller,
    required MediaSwitchResponse response,
    CallCameraState camera = CallCameraState.off,
    CallLocalCameraGrant? localGrant,
    bool Function()? canApply,
  }) => false;

  bool receiveDescription({
    required String id,
    required String negotiationId,
    required int revision,
    required CallMediaKind media,
    required CallSessionDescription description,
    bool repair = false,
    bool Function()? canApply,
  }) => false;

  bool receiveCommit({
    required String id,
    required int revision,
    required CallMediaKind media,
  }) => false;
  bool receiveAck({
    required String id,
    required int revision,
    required CallMediaKind media,
  }) => false;
  bool abort({
    required String id,
    required int baseRevision,
    required int revision,
    bool remote = false,
    MediaSwitchAbortReason reason = MediaSwitchAbortReason.cancelled,
  }) => false;
  void tick() {}
  void reconnect() {}
  void terminate() {}
}
