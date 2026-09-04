import 'dart:async';

import 'package:flutter_app/features/call/domain/call_engine.dart';
import 'package:flutter_app/features/call/infrastructure/call_stats_sampler.dart';
import 'package:flutter_app/features/call/infrastructure/flutter_webrtc_call_engine.dart';
import 'package:flutter_app/features/call/infrastructure/webrtc_types.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as webrtc;

/// In-memory totals used only to collapse real WebRTC statistics into phase
/// booleans. Instances are never serialized, logged, or placed in evidence.
final class AndroidForegroundAudioRtpTotals {
  const AndroidForegroundAudioRtpTotals({
    required this.outboundPackets,
    required this.outboundBytes,
    required this.inboundPackets,
    required this.inboundBytes,
  });

  final int outboundPackets;
  final int outboundBytes;
  final int inboundPackets;
  final int inboundBytes;

  bool outboundAdvancedFrom(AndroidForegroundAudioRtpTotals earlier) =>
      outboundPackets > earlier.outboundPackets &&
      outboundBytes > earlier.outboundBytes;

  bool inboundAdvancedFrom(AndroidForegroundAudioRtpTotals earlier) =>
      inboundPackets > earlier.inboundPackets &&
      inboundBytes > earlier.inboundBytes;
}

/// Fixed-shape progress marker used only to diagnose the device proof.
///
/// No SDP, candidate, address, identity, route, or statistics value is ever
/// retained here.
enum AndroidForegroundWebRtcAudioProbeStage {
  idle,
  creatingConnection,
  connectionReady,
  samplingSnapshot,
  snapshotSampled,
  creatingOffer,
  offerCreated,
  creatingAnswer,
  answerCreated,
  applyingLocalDescription,
  localDescriptionApplied,
  applyingRemoteDescription,
  remoteDescriptionApplied,
  addingCandidates,
  candidatesApplied,
}

/// Privacy-safe classification of candidate attributes in the latest locally
/// created description. The SDP and candidate values never leave this adapter.
enum AndroidForegroundWebRtcAudioDescriptionCandidateProfile {
  notCreated,
  none,
  relayOnly,
  nonRelayPresent,
}

/// Fixed-shape structural result for the latest locally created description.
///
/// This records neither the SDP nor a fingerprint. It only distinguishes the
/// exact engine-compatible SHA-256 shape from bounded rejection classes.
enum AndroidForegroundWebRtcAudioDescriptionSecurityProfile {
  notCreated,
  validAudioOnlySha256,
  sha256CaseVariant,
  fingerprintMissing,
  fingerprintMalformed,
  fingerprintAmbiguous,
  videoPresent,
}

AndroidForegroundWebRtcAudioDescriptionSecurityProfile
classifyAndroidForegroundWebRtcAudioDescriptionSecurity(String description) {
  final fingerprints = <String>{};
  var sawCaseVariant = false;
  for (final line in description.split(RegExp(r'\r?\n'))) {
    if (line.startsWith('m=video ')) {
      return AndroidForegroundWebRtcAudioDescriptionSecurityProfile
          .videoPresent;
    }
    if (!line.toLowerCase().startsWith('a=fingerprint:')) continue;
    if (!line.startsWith('a=fingerprint:')) {
      return AndroidForegroundWebRtcAudioDescriptionSecurityProfile
          .fingerprintMalformed;
    }
    final value = line.substring('a=fingerprint:'.length).trim();
    final exact = RegExp(
      r'^sha-256 ([0-9a-fA-F]{2})(:[0-9a-fA-F]{2}){31}$',
    ).hasMatch(value);
    final caseInsensitive = RegExp(
      r'^sha-256 ([0-9a-fA-F]{2})(:[0-9a-fA-F]{2}){31}$',
      caseSensitive: false,
    ).hasMatch(value);
    if (!caseInsensitive) {
      return AndroidForegroundWebRtcAudioDescriptionSecurityProfile
          .fingerprintMalformed;
    }
    sawCaseVariant = sawCaseVariant || !exact;
    fingerprints.add(value.toUpperCase());
  }
  if (fingerprints.isEmpty) {
    return AndroidForegroundWebRtcAudioDescriptionSecurityProfile
        .fingerprintMissing;
  }
  if (fingerprints.length != 1) {
    return AndroidForegroundWebRtcAudioDescriptionSecurityProfile
        .fingerprintAmbiguous;
  }
  return sawCaseVariant
      ? AndroidForegroundWebRtcAudioDescriptionSecurityProfile.sha256CaseVariant
      : AndroidForegroundWebRtcAudioDescriptionSecurityProfile
            .validAudioOnlySha256;
}

AndroidForegroundWebRtcAudioDescriptionCandidateProfile
classifyAndroidForegroundWebRtcAudioDescriptionCandidates(String description) {
  var sawCandidate = false;
  for (final rawLine in description.split(RegExp(r'\r?\n'))) {
    var line = rawLine.trim();
    if (!RegExp(r'^a=candidate:', caseSensitive: false).hasMatch(line)) {
      continue;
    }
    sawCandidate = true;
    line = line.substring(2);
    final tokens = line.split(RegExp(r'\s+'));
    if (tokens.length < 8 ||
        !tokens.first.toLowerCase().startsWith('candidate:') ||
        tokens[6].toLowerCase() != 'typ' ||
        tokens[7].toLowerCase() != 'relay') {
      return AndroidForegroundWebRtcAudioDescriptionCandidateProfile
          .nonRelayPresent;
    }
  }
  return sawCandidate
      ? AndroidForegroundWebRtcAudioDescriptionCandidateProfile.relayOnly
      : AndroidForegroundWebRtcAudioDescriptionCandidateProfile.none;
}

/// Bounded test-only bridge for WebRTC implementations that report connected
/// before their selected-pair/DTLS/track statistics have settled.
///
/// Production readiness still belongs to CallNegotiationEffectExecutor. This
/// helper emits one additional ordinary connected event, causing that owner to
/// resample through the canonical engine/coordinator/reducer path. It never
/// retains a stats row or emits on each poll.
final class AndroidForegroundWebRtcReadinessPulse {
  AndroidForegroundWebRtcReadinessPulse({
    required Future<bool> Function() sampleReady,
    required void Function() emitReadyPulse,
    this.pollInterval = const Duration(milliseconds: 100),
    this.maximumSamples = 100,
  }) : assert(maximumSamples > 0),
       _sampleReady = sampleReady,
       _emitReadyPulse = emitReadyPulse;

  final Future<bool> Function() _sampleReady;
  final void Function() _emitReadyPulse;
  final Duration pollInterval;
  final int maximumSamples;

  Future<void>? _watch;
  var _epoch = 0;
  var _readyPulseEmitted = false;
  var _closed = false;

  Future<void> get settled => _watch ?? Future<void>.value();

  void observe(WebRtcConnectionState state) {
    if (_closed) return;
    if (state != WebRtcConnectionState.connected) {
      _epoch++;
      _readyPulseEmitted = false;
      return;
    }
    if (_readyPulseEmitted || _watch != null) return;
    final epoch = _epoch;
    late final Future<void> attempt;
    attempt = _watchEpoch(epoch).whenComplete(() {
      if (identical(_watch, attempt)) _watch = null;
    });
    _watch = attempt;
  }

  Future<void> _watchEpoch(int epoch) async {
    for (var sample = 0; sample < maximumSamples; sample++) {
      await Future<void>.delayed(pollInterval);
      if (_closed || epoch != _epoch) return;
      bool ready;
      try {
        ready = await _sampleReady();
      } on Object {
        return;
      }
      if (_closed || epoch != _epoch || !ready) continue;
      _readyPulseEmitted = true;
      _emitReadyPulse();
      return;
    }
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _epoch++;
    await settled;
  }
}

/// Device-proof-only peer adapter.
///
/// It uses the same flutter_webrtc connection, audio constraints, transceiver
/// shape, coarse readiness sampler, and fixed diagnostic events as the
/// production adapter. Its sole extra surface is [audioRtpTotals], which keeps
/// counters in memory so the proof can persist only directional booleans.
final class AndroidForegroundWebRtcAudioProbeAdapter
    implements WebRtcPeerConnectionAdapter, WebRtcLocalCandidateSource {
  AndroidForegroundWebRtcAudioProbeAdapter() {
    _readinessPulse = AndroidForegroundWebRtcReadinessPulse(
      sampleReady: _sampleCanonicalReadiness,
      emitReadyPulse: () => _emit(_connectedEvent),
    );
  }

  static const CallStatsSampler _statsSampler = CallStatsSampler();
  static const WebRtcPeerConnectionEvent _connectedEvent =
      WebRtcPeerConnectionEvent(
        kind: WebRtcPeerConnectionEventKind.state,
        connectionState: WebRtcConnectionState.connected,
        transport: WebRtcTransportClass.unknown,
        quality: WebRtcQualityBand.unknown,
        failureReason: WebRtcFailureReason.none,
      );
  final StreamController<WebRtcPeerConnectionEvent> _events =
      StreamController<WebRtcPeerConnectionEvent>.broadcast(sync: true);
  final StreamController<CallIceCandidate> _localCandidates =
      StreamController<CallIceCandidate>.broadcast(sync: true);

  webrtc.RTCPeerConnection? _connection;
  webrtc.MediaStream? _localStream;
  webrtc.MediaStreamTrack? _localAudioTrack;
  webrtc.MediaStreamTrack? _remoteAudioTrack;
  WebRtcPeerConnectionConfiguration? _configuration;
  bool _localTrackLive = false;
  bool _remoteTrackLive = false;
  bool _closed = false;
  int _iceGeneration = 0;
  Future<void>? _closeFuture;
  late final AndroidForegroundWebRtcReadinessPulse _readinessPulse;
  AndroidForegroundWebRtcAudioProbeStage _diagnosticStage =
      AndroidForegroundWebRtcAudioProbeStage.idle;
  AndroidForegroundWebRtcAudioDescriptionCandidateProfile
  _descriptionCandidateProfile =
      AndroidForegroundWebRtcAudioDescriptionCandidateProfile.notCreated;
  AndroidForegroundWebRtcAudioDescriptionSecurityProfile
  _descriptionSecurityProfile =
      AndroidForegroundWebRtcAudioDescriptionSecurityProfile.notCreated;

  AndroidForegroundWebRtcAudioProbeStage get diagnosticStage =>
      _diagnosticStage;

  AndroidForegroundWebRtcAudioDescriptionCandidateProfile
  get descriptionCandidateProfile => _descriptionCandidateProfile;

  AndroidForegroundWebRtcAudioDescriptionSecurityProfile
  get descriptionSecurityProfile => _descriptionSecurityProfile;

  @override
  Stream<WebRtcPeerConnectionEvent> get events => _events.stream;

  @override
  Stream<CallIceCandidate> get localCandidates => _localCandidates.stream;

  @override
  bool get isClosed => _closed;

  @override
  Future<void> create(WebRtcPeerConnectionConfiguration configuration) async {
    _diagnosticStage =
        AndroidForegroundWebRtcAudioProbeStage.creatingConnection;
    if (_closed) {
      throw const WebRtcAdapterException(WebRtcFailureReason.closed);
    }
    if (_connection != null ||
        !configuration.receiveAudio ||
        configuration.receiveVideo ||
        !configuration.captureAudio ||
        configuration.captureVideo) {
      throw const WebRtcAdapterException(
        WebRtcFailureReason.configurationRejected,
      );
    }

    webrtc.RTCPeerConnection? connection;
    webrtc.MediaStream? stream;
    webrtc.MediaStreamTrack? track;
    try {
      await configureFlutterWebRtcForExternalAudioFocus();
      connection = await webrtc.createPeerConnection(<String, dynamic>{
        'iceTransportPolicy':
            configuration.iceTransportPolicy ==
                WebRtcIceTransportPolicy.relayOnly
            ? 'relay'
            : 'all',
        'sdpSemantics': 'unified-plan',
        'iceServers': _pluginIceServers(configuration.iceServers),
      });
      _installCallbacks(connection);
      stream = await webrtc.navigator.mediaDevices.getUserMedia(
        <String, dynamic>{
          'audio': <String, dynamic>{
            'echoCancellation': true,
            'noiseSuppression': true,
            'autoGainControl': true,
          },
          'video': false,
        },
      );
      final audioTracks = stream.getAudioTracks();
      if (audioTracks.length != 1 || stream.getVideoTracks().isNotEmpty) {
        throw const WebRtcAdapterException(
          WebRtcFailureReason.configurationRejected,
        );
      }
      track = audioTracks.single;
      await connection.addTrack(track, stream);
      if (_closed) {
        throw const WebRtcAdapterException(WebRtcFailureReason.closed);
      }
      _connection = connection;
      _localStream = stream;
      _localAudioTrack = track;
      _configuration = configuration;
      _localTrackLive = true;
      _diagnosticStage = AndroidForegroundWebRtcAudioProbeStage.connectionReady;
      track.onEnded = () {
        _localTrackLive = false;
        _emitState();
      };
      _emit(
        const WebRtcPeerConnectionEvent(
          kind: WebRtcPeerConnectionEventKind.state,
          connectionState: WebRtcConnectionState.newConnection,
          transport: WebRtcTransportClass.unknown,
          quality: WebRtcQualityBand.unknown,
          failureReason: WebRtcFailureReason.none,
        ),
      );
    } catch (error) {
      if (track != null) await _stopTrack(track);
      if (stream != null) await _disposeStream(stream);
      if (connection != null) await _releaseConnection(connection);
      if (error is WebRtcAdapterException) rethrow;
      throw const WebRtcAdapterException(
        WebRtcFailureReason.configurationRejected,
      );
    }
  }

  void _installCallbacks(webrtc.RTCPeerConnection connection) {
    connection.onConnectionState = (_) => _emitState();
    connection.onIceConnectionState = (_) => _emitState();
    connection.onIceCandidate = (candidate) {
      final value = candidate.candidate;
      if (_closed ||
          value == null ||
          value.isEmpty ||
          _localCandidates.isClosed) {
        return;
      }
      _localCandidates.add(
        CallIceCandidate(
          value: value,
          mediaId: candidate.sdpMid,
          mediaLineIndex: candidate.sdpMLineIndex,
          iceGeneration: _iceGeneration,
        ),
      );
    };
    connection.onTrack = (event) {
      if (event.track.kind != 'audio') return;
      _remoteAudioTrack = event.track;
      _remoteTrackLive = true;
      event.track.onEnded = () {
        _remoteTrackLive = false;
        _emitState();
      };
      _emitState();
    };
  }

  void _emitState() {
    final state = _connection?.connectionState;
    if (state == null) return;
    final mappedState = _mapConnectionState(state);
    _emit(
      WebRtcPeerConnectionEvent(
        kind: WebRtcPeerConnectionEventKind.state,
        connectionState: mappedState,
        transport: WebRtcTransportClass.unknown,
        quality: WebRtcQualityBand.unknown,
        failureReason:
            state == webrtc.RTCPeerConnectionState.RTCPeerConnectionStateFailed
            ? WebRtcFailureReason.transportUnavailable
            : WebRtcFailureReason.none,
      ),
    );
    _readinessPulse.observe(mappedState);
  }

  Future<bool> _sampleCanonicalReadiness() async {
    final current = _connection?.connectionState;
    if (current !=
        webrtc.RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
      return false;
    }
    final sampled = await snapshot();
    return sampled.selectedPairSucceeded &&
        sampled.selectedPairNominated &&
        sampled.dtlsReady &&
        sampled.localAudioSenderAttached &&
        sampled.localAudioTrackLive &&
        sampled.remoteAudioReceiverAttached &&
        sampled.remoteAudioTrackLive;
  }

  @override
  Future<CallSessionDescription> createOffer() => _createDescription(
    CallSessionDescriptionType.offer,
    _requireConnection().createOffer,
  );

  @override
  Future<CallSessionDescription> createAnswer() => _createDescription(
    CallSessionDescriptionType.answer,
    _requireConnection().createAnswer,
  );

  Future<CallSessionDescription> _createDescription(
    CallSessionDescriptionType type,
    Future<webrtc.RTCSessionDescription> Function([Map<String, dynamic>])
    create,
  ) async {
    _diagnosticStage = switch (type) {
      CallSessionDescriptionType.offer =>
        AndroidForegroundWebRtcAudioProbeStage.creatingOffer,
      CallSessionDescriptionType.answer =>
        AndroidForegroundWebRtcAudioProbeStage.creatingAnswer,
    };
    try {
      final description = await create(webRtcAudioOnlySdpConstraints);
      final value = description.sdp;
      if (value == null || value.isEmpty) {
        throw const WebRtcAdapterException(WebRtcFailureReason.other);
      }
      _descriptionCandidateProfile =
          classifyAndroidForegroundWebRtcAudioDescriptionCandidates(value);
      _descriptionSecurityProfile =
          classifyAndroidForegroundWebRtcAudioDescriptionSecurity(value);
      _diagnosticStage = switch (type) {
        CallSessionDescriptionType.offer =>
          AndroidForegroundWebRtcAudioProbeStage.offerCreated,
        CallSessionDescriptionType.answer =>
          AndroidForegroundWebRtcAudioProbeStage.answerCreated,
      };
      return CallSessionDescription(type: type, value: value);
    } on WebRtcAdapterException {
      rethrow;
    } catch (_) {
      throw const WebRtcAdapterException(WebRtcFailureReason.other);
    }
  }

  @override
  Future<void> setLocalDescription(CallSessionDescription description) async {
    _diagnosticStage =
        AndroidForegroundWebRtcAudioProbeStage.applyingLocalDescription;
    try {
      await _requireConnection().setLocalDescription(
        webrtc.RTCSessionDescription(description.value, description.type.name),
      );
      _diagnosticStage =
          AndroidForegroundWebRtcAudioProbeStage.localDescriptionApplied;
    } catch (_) {
      throw const WebRtcAdapterException(WebRtcFailureReason.other);
    }
  }

  @override
  Future<void> setRemoteDescription(CallSessionDescription description) async {
    _diagnosticStage =
        AndroidForegroundWebRtcAudioProbeStage.applyingRemoteDescription;
    try {
      await _requireConnection().setRemoteDescription(
        webrtc.RTCSessionDescription(description.value, description.type.name),
      );
      _diagnosticStage =
          AndroidForegroundWebRtcAudioProbeStage.remoteDescriptionApplied;
    } catch (_) {
      throw const WebRtcAdapterException(WebRtcFailureReason.other);
    }
  }

  @override
  Future<void> addIceCandidates(List<CallIceCandidate> candidates) async {
    _diagnosticStage = AndroidForegroundWebRtcAudioProbeStage.addingCandidates;
    try {
      final connection = _requireConnection();
      for (final candidate in candidates) {
        await connection.addCandidate(
          webrtc.RTCIceCandidate(
            candidate.value,
            candidate.mediaId,
            candidate.mediaLineIndex,
          ),
        );
      }
      _diagnosticStage =
          AndroidForegroundWebRtcAudioProbeStage.candidatesApplied;
    } catch (_) {
      throw const WebRtcAdapterException(WebRtcFailureReason.other);
    }
  }

  @override
  Future<void> restartIce() async {
    try {
      await _requireConnection().restartIce();
      _iceGeneration += 1;
    } catch (_) {
      throw const WebRtcAdapterException(WebRtcFailureReason.other);
    }
  }

  @override
  Future<void> setLocalAudioEnabled(bool enabled) async {
    try {
      for (final sender in await _requireConnection().getSenders()) {
        final track = sender.track;
        if (track?.kind == 'audio') track!.enabled = enabled;
      }
    } catch (_) {
      throw const WebRtcAdapterException(WebRtcFailureReason.other);
    }
  }

  Future<AndroidForegroundAudioRtpTotals> audioRtpTotals() async {
    try {
      var outboundPackets = 0;
      var outboundBytes = 0;
      var inboundPackets = 0;
      var inboundBytes = 0;
      for (final report in await _requireConnection().getStats()) {
        final values = report.values;
        final mediaKind = '${values['kind'] ?? values['mediaType'] ?? ''}'
            .toLowerCase();
        if (mediaKind.isNotEmpty && mediaKind != 'audio') continue;
        if (report.type == 'outbound-rtp') {
          outboundPackets += _counter(values['packetsSent']);
          outboundBytes += _counter(values['bytesSent']);
        } else if (report.type == 'inbound-rtp') {
          inboundPackets += _counter(values['packetsReceived']);
          inboundBytes += _counter(values['bytesReceived']);
        }
      }
      return AndroidForegroundAudioRtpTotals(
        outboundPackets: outboundPackets,
        outboundBytes: outboundBytes,
        inboundPackets: inboundPackets,
        inboundBytes: inboundBytes,
      );
    } catch (_) {
      throw const WebRtcAdapterException(WebRtcFailureReason.other);
    }
  }

  @override
  Future<WebRtcPeerConnectionSnapshot> snapshot() async {
    _diagnosticStage = AndroidForegroundWebRtcAudioProbeStage.samplingSnapshot;
    try {
      final connection = _requireConnection();
      var localAudioCaptureTrackCount = 0;
      var localVideoCaptureTrackCount = 0;
      var localAudioEnabled = false;
      var localAudioSenderAttached = false;
      for (final sender in await connection.getSenders()) {
        switch (sender.track?.kind) {
          case 'audio':
            localAudioCaptureTrackCount += 1;
            localAudioSenderAttached = true;
            localAudioEnabled = sender.track!.enabled;
          case 'video':
            localVideoCaptureTrackCount += 1;
          case null:
          default:
        }
      }

      var audioReceiveTransceiverCount = 0;
      var videoTransceiverCount = 0;
      for (final transceiver in await connection.getTransceivers()) {
        final direction = await transceiver.getDirection();
        final kind =
            transceiver.receiver.track?.kind ?? transceiver.sender.track?.kind;
        if (kind == 'audio' &&
            (direction == webrtc.TransceiverDirection.RecvOnly ||
                direction == webrtc.TransceiverDirection.SendRecv)) {
          audioReceiveTransceiverCount += 1;
        } else if (kind == 'video') {
          videoTransceiverCount += 1;
        }
      }
      var remoteAudioReceiverAttached = false;
      for (final receiver in await connection.getReceivers()) {
        if (receiver.track?.kind == 'audio') {
          remoteAudioReceiverAttached = true;
          break;
        }
      }
      final sample = _statsSampler.sample(
        (await connection.getStats()).map(
          (report) => CallStatsRecord(
            id: report.id,
            type: report.type,
            values: Map<Object?, Object?>.of(report.values),
          ),
        ),
      );
      final snapshot = WebRtcPeerConnectionSnapshot(
        isClosed: _closed,
        iceTransportPolicy:
            _configuration?.iceTransportPolicy ?? WebRtcIceTransportPolicy.all,
        localAudioCaptureTrackCount: localAudioCaptureTrackCount,
        localVideoCaptureTrackCount: localVideoCaptureTrackCount,
        audioReceiveTransceiverCount: audioReceiveTransceiverCount,
        videoTransceiverCount: videoTransceiverCount,
        connectionState: _mapNullableConnectionState(
          connection.connectionState,
        ),
        transport: _webRtcTransport(sample.transport),
        selectedRelayProtocol: _webRtcRelayProtocol(
          sample.selectedRelayProtocol,
        ),
        selectedPairSucceeded: sample.selectedPairSucceeded,
        selectedPairNominated: sample.selectedPairNominated,
        dtlsReady: sample.dtlsReady,
        localAudioSenderAttached: localAudioSenderAttached,
        localAudioTrackLive: _localTrackLive,
        remoteAudioReceiverAttached: remoteAudioReceiverAttached,
        remoteAudioTrackLive: _remoteTrackLive,
        localAudioEnabled: localAudioEnabled,
      );
      _diagnosticStage = AndroidForegroundWebRtcAudioProbeStage.snapshotSampled;
      return snapshot;
    } catch (_) {
      throw const WebRtcAdapterException(WebRtcFailureReason.other);
    }
  }

  @override
  Future<void> close() => _closeFuture ??= _closeOnce();

  Future<void> _closeOnce() async {
    if (_closed) return;
    _closed = true;
    await _readinessPulse.close();
    final connection = _connection;
    final localTrack = _localAudioTrack;
    final remoteTrack = _remoteAudioTrack;
    final stream = _localStream;
    _connection = null;
    _localAudioTrack = null;
    _remoteAudioTrack = null;
    _localStream = null;
    _configuration = null;
    _localTrackLive = false;
    _remoteTrackLive = false;

    var failed = false;
    if (localTrack != null && !await _stopTrack(localTrack)) failed = true;
    if (stream != null && !await _disposeStream(stream)) failed = true;
    if (remoteTrack != null) remoteTrack.onEnded = null;
    if (connection != null) {
      connection.onConnectionState = null;
      connection.onIceConnectionState = null;
      connection.onIceCandidate = null;
      connection.onTrack = null;
      if (!await _releaseConnection(connection)) failed = true;
    }
    _emit(
      const WebRtcPeerConnectionEvent(
        kind: WebRtcPeerConnectionEventKind.closed,
        connectionState: WebRtcConnectionState.closed,
        transport: WebRtcTransportClass.unknown,
        quality: WebRtcQualityBand.unknown,
        failureReason: WebRtcFailureReason.none,
      ),
      allowClosed: true,
    );
    await _localCandidates.close();
    await _events.close();
    if (failed) {
      throw const WebRtcAdapterException(WebRtcFailureReason.other);
    }
  }

  webrtc.RTCPeerConnection _requireConnection() {
    if (_closed) {
      throw const WebRtcAdapterException(WebRtcFailureReason.closed);
    }
    final connection = _connection;
    if (connection == null) {
      throw const WebRtcAdapterException(WebRtcFailureReason.notReady);
    }
    return connection;
  }

  void _emit(WebRtcPeerConnectionEvent event, {bool allowClosed = false}) {
    if ((_closed && !allowClosed) || _events.isClosed) return;
    _events.add(event);
  }

  static int _counter(Object? value) {
    if (value is int && value >= 0) return value;
    if (value is num && value >= 0) return value.toInt();
    return value is String ? int.tryParse(value) ?? 0 : 0;
  }

  static List<Map<String, dynamic>> _pluginIceServers(
    List<CallIceServer> servers,
  ) => servers
      .map(
        (server) => <String, dynamic>{
          'urls': server.urls,
          if (server.username != null) 'username': server.username,
          if (server.credential != null) 'credential': server.credential,
        },
      )
      .toList(growable: false);

  static Future<bool> _releaseConnection(
    webrtc.RTCPeerConnection connection,
  ) async {
    var succeeded = true;
    try {
      await connection.close();
    } catch (_) {
      succeeded = false;
    }
    try {
      await connection.dispose();
    } catch (_) {
      succeeded = false;
    }
    return succeeded;
  }

  static Future<bool> _stopTrack(webrtc.MediaStreamTrack track) async {
    try {
      track.onEnded = null;
      await track.stop();
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> _disposeStream(webrtc.MediaStream stream) async {
    try {
      await stream.dispose();
      return true;
    } catch (_) {
      return false;
    }
  }
}

WebRtcConnectionState _mapNullableConnectionState(
  webrtc.RTCPeerConnectionState? state,
) => state == null
    ? WebRtcConnectionState.newConnection
    : _mapConnectionState(state);

WebRtcConnectionState _mapConnectionState(webrtc.RTCPeerConnectionState state) {
  switch (state) {
    case webrtc.RTCPeerConnectionState.RTCPeerConnectionStateNew:
      return WebRtcConnectionState.newConnection;
    case webrtc.RTCPeerConnectionState.RTCPeerConnectionStateConnecting:
      return WebRtcConnectionState.connecting;
    case webrtc.RTCPeerConnectionState.RTCPeerConnectionStateConnected:
      return WebRtcConnectionState.connected;
    case webrtc.RTCPeerConnectionState.RTCPeerConnectionStateDisconnected:
      return WebRtcConnectionState.disconnected;
    case webrtc.RTCPeerConnectionState.RTCPeerConnectionStateFailed:
      return WebRtcConnectionState.failed;
    case webrtc.RTCPeerConnectionState.RTCPeerConnectionStateClosed:
      return WebRtcConnectionState.closed;
  }
}

WebRtcTransportClass _webRtcTransport(CallTransportClass transport) {
  switch (transport) {
    case CallTransportClass.unknown:
      return WebRtcTransportClass.unknown;
    case CallTransportClass.direct:
      return WebRtcTransportClass.direct;
    case CallTransportClass.relay:
      return WebRtcTransportClass.relay;
    case CallTransportClass.turnUdp:
      return WebRtcTransportClass.turnUdp;
    case CallTransportClass.turnTcpTls:
      return WebRtcTransportClass.turnTcpTls;
  }
}

WebRtcRelayProtocol _webRtcRelayProtocol(CallRelayProtocol protocol) {
  return switch (protocol) {
    CallRelayProtocol.notRelay => WebRtcRelayProtocol.notRelay,
    CallRelayProtocol.unknown => WebRtcRelayProtocol.unknown,
    CallRelayProtocol.udp => WebRtcRelayProtocol.udp,
    CallRelayProtocol.tcp => WebRtcRelayProtocol.tcp,
    CallRelayProtocol.tls => WebRtcRelayProtocol.tls,
  };
}
