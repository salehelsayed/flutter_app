import 'call_id.dart';
import 'call_media.dart';

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

/// Literal selected-candidate evidence only; never a DNS or network-type guess.
enum CallAddressFamily { ipv4, ipv6, unknown }

/// Separate from the local route used to verify the local privacy policy.
enum CallPairRelayInvolvement { none, local, remote, both, unknown }

enum CallSelectedPairState { succeeded, failed, pending, unknown }

enum CallFailureDisposition { provisional, terminal }

enum CallQualityBand { unknown, good, degraded, poor }

enum CallFailureReason {
  none,
  transportUnavailable,

  /// Native ICE, rather than an unclassified aggregate transport, failed.
  iceConnectionFailed,
  configurationRejected,
  notReady,
  closed,
  other,
}

enum CallEngineEventType { state, statistics, overflow, closed }

enum CallEngineErrorCode {
  configurationRejected,
  transportUnavailable,

  /// Native ICE exhausted its current candidate checklist. Negotiation or an
  /// existing reconnect episode may recover before its canonical deadline.
  iceConnectionFailed,
  notReady,

  /// A snapshot read failed without establishing a media/transport failure.
  /// Retry observation within the existing setup/reconnect deadline; never
  /// substitute a previous successful readiness sample.
  observationUnavailable,
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

/// Explicit opt-in capability. The existing audio engine contract stays v1-only.
abstract interface class CallVideoEngine {
  CallVideoSession bindV2Video({
    required CallId callId,
    required bool localIsCaller,
    required CallWireVersion wireVersion,
    required bool Function() canApply,
    bool videoEnabled = false,
  });
}

/// Session-created identity; implementations reject foreign and retired tokens.
abstract interface class CallVideoNegotiation {
  CallId get callId;
  String get negotiationId;
  int get mediaRevision;
  CallMediaKind get media;
}

/// A fresh local UI decision, never inferred from a peer or native answer.
/// [isCurrent] must recheck foreground, permission and consent after awaits.
final class CallLocalCameraGrant {
  const CallLocalCameraGrant({
    required this.foregroundConsent,
    required this.permissionGranted,
    required this.videoAgreed,
    required this.isCurrent,
  });

  final bool foregroundConsent;
  final bool permissionGranted;
  final bool videoAgreed;
  final bool Function() isCurrent;
}

enum CallVideoRendererSlot { local, remote }

/// Opaque native texture metadata; no plugin, stream or peer handles escape.
final class CallVideoView {
  const CallVideoView({
    required this.textureId,
    required this.width,
    required this.height,
  });

  final int textureId;
  final int width;
  final int height;
}

/// One session-owned presentation snapshot, including renderer invalidation.
/// A null negotiation means no live video negotiation owns this slot.
final class CallVideoPresentationState {
  const CallVideoPresentationState({
    required this.callId,
    required this.negotiation,
    required this.slot,
    required this.hasTrack,
    required this.view,
  });

  final CallId callId;
  final CallVideoNegotiation? negotiation;
  final CallVideoRendererSlot slot;
  final bool hasTrack;
  final CallVideoView? view;
}

/// Optional capability on the bound [CallVideoSession], not a global feed.
/// Read the current snapshot after subscribing. Publish track arrival or
/// replacement, renderer metadata changes, and a null view before retiring its
/// texture. Notifications never attach a renderer or grant camera permission.
abstract interface class CallVideoPresentationSource {
  Stream<CallVideoPresentationState> get presentationChanges;
  CallVideoPresentationState presentationFor(CallVideoRendererSlot slot);
}

/// Optional capability on the bound [CallVideoSession]. Only switches an
/// already-active local capture owned by the current committed token. Recheck
/// [grant] after native awaits; never enable a stopped camera or alter audio,
/// SDP, or ICE. False means unsupported, stale, revoked, or no switch completed.
abstract interface class CallVideoCameraSwitch {
  Future<bool> switchCamera(
    CallVideoNegotiation token,
    CallLocalCameraGrant grant,
  );
}

/// Positive native SDP reconciliation proof for an exact session-owned token.
enum CallVideoSdpReconciliationOutcome {
  rolledBack,
  alreadyStable,
  unreconciled,
}

/// Optional capability on the bound [CallVideoSession]. Closes video gates and
/// reconciles the exact current token, including a retired token, on the native
/// serial queue. A positive result requires a native stable-state observation.
/// [canApply] must retain the selected operation and its original time budget;
/// it and session/token ownership are rechecked after every native await.
/// Stale ownership, expired authority or native failure returns unreconciled.
/// Live audio/ICE remain owned by the session. The existing rollback bool and
/// error contract is unchanged; a stable answer is never rolled back.
abstract interface class CallVideoSdpReconciler {
  Future<CallVideoSdpReconciliationOutcome> reconcilePending(
    CallVideoNegotiation token, {
    required bool Function() canApply,
  });
}

/// Optional operations fail independently of the live audio connection.
abstract interface class CallVideoSession {
  CallId get callId;
  bool get hasPendingCleanup;

  CallVideoNegotiation beginNegotiation({
    required String negotiationId,
    required int mediaRevision,
    required CallMediaKind media,
    required bool Function() canApply,
  });

  Future<CallSessionDescription> createOffer(CallVideoNegotiation token);
  Future<CallSessionDescription> createAnswer(CallVideoNegotiation token);
  Future<void> applyLocal(
    CallVideoNegotiation token,
    CallSessionDescription description,
  );
  Future<void> applyRemote(
    CallVideoNegotiation token,
    CallSessionDescription description,
  );

  /// Called only after authenticated commit/ACK agreement. Never grants camera.
  Future<void> commit(CallVideoNegotiation token);

  /// True only when an actual pending offer was successfully rolled back.
  /// A stable answer cannot be rolled back; the caller owns audio repair.
  Future<bool> rollbackPending(CallVideoNegotiation token);

  Future<bool> setLocalCamera(
    CallVideoNegotiation token,
    CallLocalCameraGrant grant,
  );

  /// Closes the send gate synchronously; remote reception remains independent.
  Future<bool> stopLocalCamera();
  Future<CallVideoView?> attachRenderer(
    CallVideoNegotiation token,
    CallVideoRendererSlot slot,
  );
  Future<bool> detachRenderer(CallVideoRendererSlot slot);

  /// Closes both video gates, retires the token and preserves live audio/ICE.
  Future<bool> retireVideo();
  Future<bool> retryCleanup();
  Future<bool> close();
}
