/// App-owned policy for establishing a call connection.
enum CallTransportPolicy { all, relayOnly }

enum CallSessionDescriptionType { offer, answer }

enum CallAudioOutputRoute {
  systemDefault,
  earpiece,
  speaker,
  wiredHeadset,
  bluetooth,
}

/// Optional plugin-independent signal that the platform output route changed.
///
/// Implementations expose only the app's coarse route vocabulary. Consumers
/// must refresh a snapshot rather than treating the signal as optimistic
/// output-selection truth.
abstract interface class CallAudioOutputRouteChangeSource {
  Stream<CallAudioOutputRoute> get outputRouteChanges;
}

enum CallConnectionState {
  newConnection,
  connecting,
  connected,
  disconnected,
  failed,
  closed,
}

enum CallTransportClass { unknown, direct, relay, turnUdp, turnTcpTls }

/// Exact selected relay protocol derived only from live WebRTC statistics.
///
/// This deliberately cannot carry candidate addresses, configured TURN URLs,
/// or other connection material.
enum CallRelayProtocol { notRelay, unknown, udp, tcp, tls }

enum CallQualityBand { unknown, good, degraded, poor }

enum CallFailureReason {
  none,
  transportUnavailable,
  configurationRejected,
  notReady,
  closed,
  other,
}

enum CallEngineEventType { state, statistics, overflow, closed }

enum CallEngineErrorCode {
  configurationRejected,
  notReady,
  malformedFingerprint,
  fingerprintMismatch,
  candidateOverflow,
  staleIceGeneration,
  futureIceGeneration,
  restartLimitReached,
  relayPolicyViolation,
  closed,
  other,
}

/// A fixed-shape media failure. Signaling bytes and credentials are never
/// included in the exception or its string representation.
final class CallEngineException implements Exception {
  const CallEngineException(this.code);

  final CallEngineErrorCode code;

  @override
  String toString() => 'CallEngineException(${code.name})';
}

/// One app-owned ICE server entry. [toString] is deliberately redacted.
final class CallIceServer {
  CallIceServer({
    required List<String> urls,
    this.username,
    this.credential,
    required DateTime expiresAt,
  }) : urls = List<String>.unmodifiable(urls),
       expiresAt = expiresAt.toUtc();

  final List<String> urls;
  final String? username;
  final String? credential;
  final DateTime expiresAt;

  bool get containsTurnUrl =>
      urls.any((url) => url.startsWith('turn:') || url.startsWith('turns:'));

  @override
  String toString() =>
      'CallIceServer(urlCount: ${urls.length}, hasUsername: '
      '${username?.isNotEmpty == true}, hasCredential: '
      '${credential?.isNotEmpty == true}, expiresAt: redacted)';
}

/// A deliberately small connection request. VC2-01 supports only the exact
/// receive-only audio shape exercised by the foundation probe.
final class CallConnectionConfiguration {
  const CallConnectionConfiguration({
    required this.transportPolicy,
    required this.receiveAudio,
    required this.receiveVideo,
    required this.captureAudio,
    required this.captureVideo,
    this.iceServers = const <CallIceServer>[],
  });

  final CallTransportPolicy transportPolicy;
  final bool receiveAudio;
  final bool receiveVideo;
  final bool captureAudio;
  final bool captureVideo;
  final List<CallIceServer> iceServers;
}

/// Opaque signaling value. Its contents are intentionally excluded from
/// diagnostics and from the default object representation.
final class CallSessionDescription {
  const CallSessionDescription({
    required this.type,
    required this.value,
    this.fingerprint,
  });

  final CallSessionDescriptionType type;
  final String value;
  final String? fingerprint;

  @override
  String toString() => 'CallSessionDescription(type: ${type.name}, redacted)';
}

/// Opaque remote connectivity value used only at the signaling boundary.
final class CallIceCandidate {
  const CallIceCandidate({
    required this.value,
    required this.mediaId,
    required this.mediaLineIndex,
    this.iceGeneration = 0,
  });

  final String value;
  final String? mediaId;
  final int? mediaLineIndex;
  final int iceGeneration;

  @override
  String toString() => 'CallIceCandidate(generation: $iceGeneration, redacted)';
}

/// Coarse, non-identifying state that is safe to retain for diagnostics.
final class CallConnectionSnapshot {
  const CallConnectionSnapshot({
    required this.state,
    required this.transportPolicy,
    required this.transport,
    required this.quality,
    required this.localAudioCaptureTrackCount,
    required this.localVideoCaptureTrackCount,
    required this.audioReceiveTransceiverCount,
    required this.videoTransceiverCount,
    this.selectedPairSucceeded = false,
    this.selectedPairNominated = false,
    this.selectedRelayProtocol = CallRelayProtocol.unknown,
    this.dtlsReady = false,
    this.audioSessionActive = false,
    this.localAudioSenderAttached = false,
    this.localAudioTrackLive = false,
    this.remoteAudioReceiverAttached = false,
    this.remoteAudioTrackLive = false,
    this.localAudioEnabled = false,
    this.inboundAudioRtpObserved = false,
    this.outboundAudioRtpObserved = false,
    this.outputRoute = CallAudioOutputRoute.systemDefault,
  });

  final CallConnectionState state;
  final CallTransportPolicy transportPolicy;
  final CallTransportClass transport;
  final CallQualityBand quality;
  final int localAudioCaptureTrackCount;
  final int localVideoCaptureTrackCount;
  final int audioReceiveTransceiverCount;
  final int videoTransceiverCount;
  final bool selectedPairSucceeded;
  final bool selectedPairNominated;
  final CallRelayProtocol selectedRelayProtocol;
  final bool dtlsReady;
  final bool audioSessionActive;
  final bool localAudioSenderAttached;
  final bool localAudioTrackLive;
  final bool remoteAudioReceiverAttached;
  final bool remoteAudioTrackLive;
  final bool localAudioEnabled;
  final bool inboundAudioRtpObserved;
  final bool outboundAudioRtpObserved;
  final CallAudioOutputRoute outputRoute;

  /// Product connected readiness. Silence, mute, RTP counters, and audio
  /// energy are intentionally absent from this predicate.
  bool get isMediaReady =>
      state == CallConnectionState.connected &&
      selectedPairSucceeded &&
      selectedPairNominated &&
      dtlsReady &&
      audioSessionActive &&
      localAudioSenderAttached &&
      localAudioTrackLive &&
      remoteAudioReceiverAttached &&
      remoteAudioTrackLive;
}

/// A fixed-schema event. There is no free-form payload where connection
/// material, identities, or signaling values could escape.
final class CallEngineEvent {
  const CallEngineEvent({
    required this.type,
    required this.connectionState,
    required this.transport,
    required this.quality,
    required this.failureReason,
  });

  final CallEngineEventType type;
  final CallConnectionState connectionState;
  final CallTransportClass transport;
  final CallQualityBand quality;
  final CallFailureReason failureReason;

  Map<String, String> toDiagnosticMap() => <String, String>{
    'eventType': type.name,
    'connectionState': connectionState.name,
    'transport': transport.name,
    'quality': quality.name,
    'failureReason': failureReason.name,
  };
}

/// Plugin-independent call boundary owned by the app.
abstract interface class CallEngine {
  Stream<CallEngineEvent> get events;

  /// Opaque local candidates for the authenticated signaling adapter. This
  /// stream is never used for diagnostics or logging.
  Stream<CallIceCandidate> get localCandidates;

  /// A bounded snapshot of the same coarse events delivered by [events].
  List<CallEngineEvent> get recentEvents;

  bool get isClosed;

  int get iceGeneration;

  /// Positive maximum accepted by [addIceCandidates], fixed for this engine.
  int get candidateBatchCapacity;

  Future<void> createConnection(CallConnectionConfiguration configuration);

  Future<CallSessionDescription> createOffer();

  Future<CallSessionDescription> createAnswer();

  Future<void> setLocalDescription(CallSessionDescription description);

  Future<void> setRemoteDescription(CallSessionDescription description);

  Future<void> addIceCandidates(List<CallIceCandidate> candidates);

  Future<int> restartIce({List<CallIceServer> iceServers = const []});

  Future<void> setLocalAudioEnabled(bool enabled);

  Future<void> setAudioSessionActive(bool active);

  Future<List<CallAudioOutputRoute>> supportedOutputRoutes();

  Future<void> selectOutputRoute(CallAudioOutputRoute route);

  Future<CallConnectionSnapshot> snapshot();

  Future<void> close();
}
