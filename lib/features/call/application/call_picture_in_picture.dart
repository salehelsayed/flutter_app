import 'dart:async';

import '../domain/call_engine.dart';
import '../domain/call_id.dart';

/// An exact remote source, issued by the current video session, never a texture.
final class CallPipSource {
  const CallPipSource({
    required this.negotiation,
    required this.rendererEpoch,
    required this.peerConnectionId,
    required this.remoteTrackId,
    required this.isCurrent,
  });

  final CallVideoNegotiation negotiation;
  final int rendererEpoch;
  final String peerConnectionId;
  final String remoteTrackId;
  final bool Function() isCurrent;

  bool sameBinding(CallPipSource other) =>
      identical(negotiation, other.negotiation) &&
      rendererEpoch == other.rendererEpoch &&
      peerConnectionId == other.peerConnectionId &&
      remoteTrackId == other.remoteTrackId;
}

/// Optional native-sink capability; plugin types never reach graph or widgets.
abstract interface class CallVideoPictureInPictureSource {
  CallPipSource? get pictureInPictureSource;
  Stream<void> get pictureInPictureSourceChanges;
}

final class CallPipIdentity {
  const CallPipIdentity(this.callId, this.leaseId, {required this.instanceId});
  final String instanceId;
  final CallId callId;
  final int leaseId;

  @override
  bool operator ==(Object other) =>
      other is CallPipIdentity &&
      instanceId == other.instanceId &&
      callId == other.callId &&
      leaseId == other.leaseId;

  @override
  int get hashCode => Object.hash(instanceId, callId, leaseId);
}

final class CallPipAvailability {
  const CallPipAvailability({
    required this.supported,
    required this.cameraInPip,
  });

  static const unavailable = CallPipAvailability(
    supported: false,
    cameraInPip: false,
  );
  final bool supported;
  final bool cameraInPip;
}

enum CallPipEventType { entered, exited, action, failed, blocked }

final class CallPipEvent {
  const CallPipEvent({
    required this.identity,
    required this.sequence,
    required this.type,
    this.detail,
  });
  final CallPipIdentity identity;
  final int sequence;
  final CallPipEventType type;
  final String? detail;
}

abstract interface class CallPictureInPictureBridge {
  Stream<CallPipEvent> get events;
  Future<CallPipAvailability> availability(CallPipIdentity identity);
  Future<bool> arm(
    CallPipIdentity identity,
    CallPipSource source, {
    required bool muted,
    required bool cameraOn,
    required bool cameraEnabled,
  });
  Future<bool> enter(CallPipIdentity identity);
  Future<bool> update(
    CallPipIdentity identity, {
    required bool muted,
    required bool cameraOn,
    required bool cameraEnabled,
  });
  Future<bool> disarm(CallPipIdentity identity, String reason);
  Future<void> close();
}

enum CallPipPhase { preparing, armed, entered }

final class CallPipLease {
  CallPipLease(this.identity, this.source);
  final CallPipIdentity identity;
  final CallPipSource source;
  CallPipPhase phase = CallPipPhase.preparing;
  bool cameraInPip = false;
  int lastSequence = 0;
}

/// Owns native sink leases only. Camera consent and call actions stay in graph.
final class CallPictureInPictureController {
  CallPictureInPictureController({
    required this.bridge,
    required this.canApply,
    required this.onEvent,
    this.onReady,
    this.videoEnabled = false,
  });

  final CallPictureInPictureBridge bridge;
  final bool Function(CallPipSource source) canApply;
  final void Function(CallPipLease lease, CallPipEvent event) onEvent;
  final void Function()? onReady;
  final bool videoEnabled;

  CallPipLease? get current => null;
  bool get hasPendingCleanup => false;
  void bind(
    CallPipSource? source, {
    required bool muted,
    required bool cameraOn,
  }) {}
  void background() {}
  void foreground() {}
  void invalidate([String reason = 'retired']) {}
  Future<bool> retryCleanup() async => true;
  Future<void> close() async {}
}
