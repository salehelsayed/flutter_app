import 'dart:async';

import '../domain/call_engine.dart';

/// Legacy native WebRTC constraints required by flutter_webrtc 1.6.0.
///
/// Passing no map enables the plugin's default OfferToReceiveVideo=true and
/// creates a video m-section even for an audio-only peer connection.
const Map<String, dynamic> webRtcAudioOnlySdpConstraints = <String, dynamic>{
  'mandatory': <String, bool>{
    'OfferToReceiveAudio': true,
    'OfferToReceiveVideo': false,
  },
  'optional': <Map<String, dynamic>>[],
};

enum WebRtcIceTransportPolicy { all, relayOnly }

enum WebRtcPeerConnectionEventKind { state, statistics, overflow, closed }

enum WebRtcConnectionState {
  newConnection,
  connecting,
  connected,
  disconnected,
  failed,
  closed,
}

enum WebRtcTransportClass { unknown, direct, relay, turnUdp, turnTcpTls }

enum WebRtcRelayProtocol { notRelay, unknown, udp, tcp, tls }

enum WebRtcQualityBand { unknown, good, degraded, poor }

enum WebRtcFailureReason {
  none,
  transportUnavailable,
  configurationRejected,
  notReady,
  closed,
  other,
}

final class WebRtcPeerConnectionConfiguration {
  const WebRtcPeerConnectionConfiguration({
    required this.iceTransportPolicy,
    required this.receiveAudio,
    required this.receiveVideo,
    required this.captureAudio,
    required this.captureVideo,
    this.iceServers = const <CallIceServer>[],
  });

  final WebRtcIceTransportPolicy iceTransportPolicy;
  final bool receiveAudio;
  final bool receiveVideo;
  final bool captureAudio;
  final bool captureVideo;
  final List<CallIceServer> iceServers;
}

final class WebRtcPeerConnectionSnapshot {
  const WebRtcPeerConnectionSnapshot({
    required this.isClosed,
    required this.iceTransportPolicy,
    required this.localAudioCaptureTrackCount,
    required this.localVideoCaptureTrackCount,
    required this.audioReceiveTransceiverCount,
    required this.videoTransceiverCount,
    this.connectionState = WebRtcConnectionState.newConnection,
    this.transport = WebRtcTransportClass.unknown,
    this.quality = WebRtcQualityBand.unknown,
    this.selectedPairSucceeded = false,
    this.selectedPairNominated = false,
    this.selectedRelayProtocol = WebRtcRelayProtocol.unknown,
    this.dtlsReady = false,
    this.localAudioSenderAttached = false,
    this.localAudioTrackLive = false,
    this.remoteAudioReceiverAttached = false,
    this.remoteAudioTrackLive = false,
    this.localAudioEnabled = false,
    this.inboundAudioRtpObserved = false,
    this.outboundAudioRtpObserved = false,
  });

  final bool isClosed;
  final WebRtcIceTransportPolicy iceTransportPolicy;
  final int localAudioCaptureTrackCount;
  final int localVideoCaptureTrackCount;
  final int audioReceiveTransceiverCount;
  final int videoTransceiverCount;
  final WebRtcConnectionState connectionState;
  final WebRtcTransportClass transport;
  final WebRtcQualityBand quality;
  final bool selectedPairSucceeded;
  final bool selectedPairNominated;
  final WebRtcRelayProtocol selectedRelayProtocol;
  final bool dtlsReady;
  final bool localAudioSenderAttached;
  final bool localAudioTrackLive;
  final bool remoteAudioReceiverAttached;
  final bool remoteAudioTrackLive;
  final bool localAudioEnabled;
  final bool inboundAudioRtpObserved;
  final bool outboundAudioRtpObserved;
}

final class WebRtcPeerConnectionEvent {
  const WebRtcPeerConnectionEvent({
    required this.kind,
    required this.connectionState,
    required this.transport,
    required this.quality,
    required this.failureReason,
  });

  final WebRtcPeerConnectionEventKind kind;
  final WebRtcConnectionState connectionState;
  final WebRtcTransportClass transport;
  final WebRtcQualityBand quality;
  final WebRtcFailureReason failureReason;

  Map<String, String> toDiagnosticMap() => <String, String>{
    'eventType': kind.name,
    'connectionState': connectionState.name,
    'transport': transport.name,
    'quality': quality.name,
    'failureReason': failureReason.name,
  };
}

final class WebRtcAdapterException implements Exception {
  const WebRtcAdapterException(this.reason);

  final WebRtcFailureReason reason;

  @override
  String toString() => 'WebRtcAdapterException(${reason.name})';
}

/// Fakeable, app-owned facade around the external connection implementation.
abstract interface class WebRtcPeerConnectionAdapter {
  Stream<WebRtcPeerConnectionEvent> get events;

  bool get isClosed;

  Future<void> create(WebRtcPeerConnectionConfiguration configuration);

  Future<CallSessionDescription> createOffer();

  Future<CallSessionDescription> createAnswer();

  Future<void> setLocalDescription(CallSessionDescription description);

  Future<void> setRemoteDescription(CallSessionDescription description);

  Future<void> addIceCandidates(List<CallIceCandidate> candidates);

  Future<void> restartIce();

  Future<void> setLocalAudioEnabled(bool enabled);

  Future<WebRtcPeerConnectionSnapshot> snapshot();

  Future<void> close();
}

/// Optional opaque candidate source implemented by the production facade.
/// Keeping it separate preserves simple host fakes that do not exercise
/// candidate egress.
abstract interface class WebRtcLocalCandidateSource {
  Stream<CallIceCandidate> get localCandidates;
}

/// Optional configuration update used before the single bounded ICE restart.
abstract interface class WebRtcIceServerUpdater {
  Future<void> updateIceServers(List<CallIceServer> iceServers);
}
