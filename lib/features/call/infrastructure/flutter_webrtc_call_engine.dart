import 'dart:async';

import 'package:flutter_webrtc/flutter_webrtc.dart' as webrtc;

import '../domain/call_engine.dart';
import 'call_audio_route_adapter.dart';
import 'call_stats_sampler.dart';
import 'webrtc_types.dart';

/// Fixed, privacy-safe boundaries for WebRTC startup and snapshot failures.
enum FlutterWebRtcFailureStage {
  androidAudioFocus,
  peerCreate,
  userMedia,
  trackInvariant,
  addTrack,
  snapshotSenders,
  snapshotTransceivers,
  snapshotTransceiverDirection,
  snapshotReceivers,
  snapshotStats,
  snapshotDeadline,
}

typedef FlutterWebRtcFailureStageObserver =
    void Function(FlutterWebRtcFailureStage stage);

typedef FlutterWebRtcPeerConnectionFactory =
    Future<webrtc.RTCPeerConnection> Function(
      Map<String, dynamic> configuration,
    );

typedef FlutterWebRtcAndroidAudioFocusConfigurator = Future<void> Function();

/// Keeps Android audio focus under the app/native call-session owner while
/// flutter_webrtc continues to manage communication mode and route selection.
Future<void> configureFlutterWebRtcForExternalAudioFocus() =>
    webrtc.Helper.setAndroidAudioConfiguration(
      webrtc.AndroidAudioConfiguration(manageAudioFocus: false),
    );

/// Reports only a fixed stage while preserving the guarded operation's result.
///
/// Observer failures are deliberately ignored so diagnostics can never change
/// call behavior or replace the original failure.
final class FlutterWebRtcFailureStageGuard {
  const FlutterWebRtcFailureStageGuard([
    FlutterWebRtcFailureStageObserver? observer,
  ]) : _observer = observer;

  final FlutterWebRtcFailureStageObserver? _observer;

  Future<T> run<T>(
    FlutterWebRtcFailureStage stage,
    FutureOr<T> Function() operation,
  ) async {
    try {
      return await operation();
    } catch (error, stackTrace) {
      _report(stage);
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  Future<T> runWithTimeoutFallback<T>(
    FlutterWebRtcFailureStage stage,
    FutureOr<T> Function() operation, {
    required Duration timeout,
    required T Function() onTimeout,
  }) async {
    try {
      return await run<T>(
        stage,
        () => Future<T>.sync(operation).timeout(timeout),
      );
    } on TimeoutException {
      return onTimeout();
    }
  }

  Future<T> runWithDeadlineFallback<T>(
    FlutterWebRtcFailureStage stage,
    FutureOr<T> Function() operation, {
    required Duration timeout,
    required T Function() onTimeout,
  }) => Future<T>.sync(operation).timeout(
    timeout,
    onTimeout: () {
      _report(stage);
      return onTimeout();
    },
  );

  void _report(FlutterWebRtcFailureStage stage) {
    try {
      _observer?.call(stage);
    } catch (_) {}
  }
}

/// The only class that touches the external WebRTC API.
///
final class FlutterWebRtcPeerConnectionAdapter
    implements
        WebRtcPeerConnectionAdapter,
        WebRtcLocalCandidateSource,
        WebRtcIceServerUpdater {
  FlutterWebRtcPeerConnectionAdapter({
    int eventBufferCapacity = 64,
    Duration snapshotReadTimeout = const Duration(seconds: 1),
    Duration snapshotDeadlineTimeout = const Duration(seconds: 6),
    FlutterWebRtcFailureStageObserver? onFailureStage,
    this.onDiagnosticSample,
    FlutterWebRtcAndroidAudioFocusConfigurator? configureAndroidAudioFocus,
    FlutterWebRtcPeerConnectionFactory? peerConnectionFactory,
  }) : assert(eventBufferCapacity > 0),
       assert(snapshotReadTimeout > Duration.zero),
       assert(snapshotDeadlineTimeout > snapshotReadTimeout),
       _eventBufferCapacity = eventBufferCapacity,
       _snapshotReadTimeout = snapshotReadTimeout,
       _snapshotDeadlineTimeout = snapshotDeadlineTimeout,
       _configureAndroidAudioFocus =
           configureAndroidAudioFocus ??
           configureFlutterWebRtcForExternalAudioFocus,
       _peerConnectionFactory =
           peerConnectionFactory ??
           ((configuration) => webrtc.createPeerConnection(configuration)),
       _failureStageGuard = FlutterWebRtcFailureStageGuard(onFailureStage);

  final void Function(CallStatsSample, CallRtpProgressSample)?
  onDiagnosticSample;
  final CallRtpProgressSampler _rtpProgressSampler = CallRtpProgressSampler();

  final int _eventBufferCapacity;
  final Duration _snapshotReadTimeout;
  final Duration _snapshotDeadlineTimeout;
  final FlutterWebRtcAndroidAudioFocusConfigurator _configureAndroidAudioFocus;
  final FlutterWebRtcPeerConnectionFactory _peerConnectionFactory;
  final FlutterWebRtcFailureStageGuard _failureStageGuard;
  final StreamController<WebRtcPeerConnectionEvent> _events =
      StreamController<WebRtcPeerConnectionEvent>.broadcast(sync: true);
  final StreamController<CallIceCandidate> _localCandidates =
      StreamController<CallIceCandidate>.broadcast(sync: true);
  final List<WebRtcPeerConnectionEvent> _recentEvents =
      <WebRtcPeerConnectionEvent>[];
  static const CallStatsSampler _statsSampler = CallStatsSampler();

  webrtc.RTCPeerConnection? _peerConnection;
  webrtc.MediaStream? _localStream;
  webrtc.MediaStreamTrack? _localAudioTrack;
  webrtc.MediaStreamTrack? _remoteAudioTrack;
  WebRtcPeerConnectionConfiguration? _configuration;
  Future<void>? _createFuture;
  Future<void>? _closeFuture;
  webrtc.RTCPeerConnection? _peerConnectionPendingClose;
  webrtc.MediaStream? _localStreamPendingClose;
  webrtc.MediaStreamTrack? _localAudioTrackPendingClose;
  bool _peerConnectionCloseCompleted = false;
  bool _peerConnectionDisposeCompleted = false;
  bool _closedEventEmitted = false;
  bool _localCandidatesClosed = false;
  bool _eventsClosed = false;
  bool _closed = false;
  bool _localTrackLive = false;
  bool _remoteTrackLive = false;
  bool _inboundAudioRtpObserved = false;
  bool _outboundAudioRtpObserved = false;
  int _iceGeneration = 0;
  bool _eventDeliveryInFlight = false;
  WebRtcPeerConnectionEvent? _pendingEvent;
  WebRtcPeerConnectionEvent? _pendingDisconnect;

  @override
  Stream<WebRtcPeerConnectionEvent> get events => _events.stream;

  @override
  Stream<CallIceCandidate> get localCandidates => _localCandidates.stream;

  List<WebRtcPeerConnectionEvent> get recentEvents =>
      List<WebRtcPeerConnectionEvent>.unmodifiable(_recentEvents);

  @override
  bool get isClosed => _closed;

  @override
  Future<void> create(WebRtcPeerConnectionConfiguration configuration) {
    if (_closed) {
      throw const WebRtcAdapterException(WebRtcFailureReason.closed);
    }
    if (_peerConnection != null || _createFuture != null) {
      throw const WebRtcAdapterException(
        WebRtcFailureReason.configurationRejected,
      );
    }
    _validateConfiguration(configuration);
    late final Future<void> attempt;
    attempt = _createOnce(configuration).whenComplete(() {
      if (identical(_createFuture, attempt)) _createFuture = null;
    });
    _createFuture = attempt;
    return attempt;
  }

  Future<void> _createOnce(
    WebRtcPeerConnectionConfiguration configuration,
  ) async {
    webrtc.RTCPeerConnection? connectionForCleanup;
    webrtc.MediaStream? localStreamForCleanup;
    webrtc.MediaStreamTrack? localTrackForCleanup;
    try {
      await _failureStageGuard.run<void>(
        FlutterWebRtcFailureStage.androidAudioFocus,
        _configureAndroidAudioFocus,
      );
      final connection = await _failureStageGuard.run(
        FlutterWebRtcFailureStage.peerCreate,
        () => _peerConnectionFactory(<String, dynamic>{
          'iceTransportPolicy':
              configuration.iceTransportPolicy ==
                  WebRtcIceTransportPolicy.relayOnly
              ? 'relay'
              : 'all',
          'sdpSemantics': 'unified-plan',
          'iceServers': _pluginIceServers(configuration.iceServers),
        }),
      );
      connectionForCleanup = connection;
      if (_closed) {
        await _releaseConnection(connection);
        throw const WebRtcAdapterException(WebRtcFailureReason.closed);
      }
      _peerConnection = connection;
      _installCallbacks(connection);
      if (configuration.captureAudio) {
        final localStream = await _failureStageGuard.run(
          FlutterWebRtcFailureStage.userMedia,
          () => webrtc.navigator.mediaDevices.getUserMedia(<String, dynamic>{
            'audio': <String, dynamic>{
              'echoCancellation': true,
              'noiseSuppression': true,
              'autoGainControl': true,
            },
            'video': false,
          }),
        );
        localStreamForCleanup = localStream;
        if (_closed) {
          await _disposeStream(localStream);
          throw const WebRtcAdapterException(WebRtcFailureReason.closed);
        }
        _localStream = localStream;
        final localTrack = await _failureStageGuard.run(
          FlutterWebRtcFailureStage.trackInvariant,
          () {
            final audioTracks = localStream.getAudioTracks();
            if (audioTracks.length != 1 ||
                localStream.getVideoTracks().isNotEmpty) {
              throw const WebRtcAdapterException(
                WebRtcFailureReason.configurationRejected,
              );
            }
            return audioTracks.single;
          },
        );
        localTrackForCleanup = localTrack;
        _localAudioTrack = localTrack;
        _localTrackLive = true;
        localTrack.onEnded = () {
          _localTrackLive = false;
          _emitStateFromConnection();
        };
        if (_closed) {
          throw const WebRtcAdapterException(WebRtcFailureReason.closed);
        }
        await _failureStageGuard.run<void>(
          FlutterWebRtcFailureStage.addTrack,
          () async {
            await connection.addTrack(localTrack, localStream);
          },
        );
      } else {
        await connection.addTransceiver(
          kind: webrtc.RTCRtpMediaType.RTCRtpMediaTypeAudio,
          init: webrtc.RTCRtpTransceiverInit(
            direction: webrtc.TransceiverDirection.RecvOnly,
          ),
        );
      }
      if (_closed) {
        throw const WebRtcAdapterException(WebRtcFailureReason.closed);
      }
      _configuration = configuration;
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
      if (identical(_localAudioTrack, localTrackForCleanup)) {
        _localAudioTrack = null;
        _localTrackLive = false;
      }
      if (identical(_localStream, localStreamForCleanup)) _localStream = null;
      if (identical(_peerConnection, connectionForCleanup)) {
        _peerConnection = null;
      }
      if (localTrackForCleanup != null) {
        await _stopTrack(localTrackForCleanup);
      }
      if (localStreamForCleanup != null) {
        await _disposeStream(localStreamForCleanup);
      }
      if (connectionForCleanup != null) {
        await _releaseConnection(connectionForCleanup);
      }
      if (error is WebRtcAdapterException) rethrow;
      throw const WebRtcAdapterException(
        WebRtcFailureReason.configurationRejected,
      );
    }
  }

  void _validateConfiguration(WebRtcPeerConnectionConfiguration configuration) {
    final supported =
        (configuration.iceTransportPolicy ==
                WebRtcIceTransportPolicy.relayOnly ||
            configuration.iceTransportPolicy == WebRtcIceTransportPolicy.all) &&
        configuration.receiveAudio &&
        !configuration.receiveVideo &&
        !configuration.captureVideo;
    if (!supported) {
      throw const WebRtcAdapterException(
        WebRtcFailureReason.configurationRejected,
      );
    }
  }

  void _installCallbacks(webrtc.RTCPeerConnection connection) {
    connection.onConnectionState = (webrtc.RTCPeerConnectionState state) {
      _emit(
        WebRtcPeerConnectionEvent(
          kind: WebRtcPeerConnectionEventKind.state,
          connectionState: _mapConnectionState(state),
          transport: WebRtcTransportClass.unknown,
          quality: WebRtcQualityBand.unknown,
          failureReason:
              state ==
                  webrtc.RTCPeerConnectionState.RTCPeerConnectionStateFailed
              ? WebRtcFailureReason.transportUnavailable
              : WebRtcFailureReason.none,
        ),
      );
    };
    connection.onIceConnectionState = (_) => _emitStateFromConnection();
    connection.onIceCandidate = (webrtc.RTCIceCandidate candidate) {
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
    connection.onTrack = (webrtc.RTCTrackEvent event) {
      if (event.track.kind != 'audio') return;
      _remoteAudioTrack = event.track;
      _remoteTrackLive = true;
      event.track.onEnded = () {
        _remoteTrackLive = false;
        _emitStateFromConnection();
      };
      _emitStateFromConnection();
    };
  }

  void _emitStateFromConnection() {
    final state = _peerConnection?.connectionState;
    if (state == null) return;
    _emit(
      WebRtcPeerConnectionEvent(
        kind: WebRtcPeerConnectionEventKind.state,
        connectionState: _mapConnectionState(state),
        transport: WebRtcTransportClass.unknown,
        quality: WebRtcQualityBand.unknown,
        failureReason:
            state == webrtc.RTCPeerConnectionState.RTCPeerConnectionStateFailed
            ? WebRtcFailureReason.transportUnavailable
            : WebRtcFailureReason.none,
      ),
    );
  }

  @override
  Future<CallSessionDescription> createOffer() async {
    final connection = _requireConnection();
    try {
      final description = await connection.createOffer(
        webRtcAudioOnlySdpConstraints,
      );
      final value = description.sdp;
      if (value == null) {
        throw const WebRtcAdapterException(WebRtcFailureReason.other);
      }
      return CallSessionDescription(
        type: CallSessionDescriptionType.offer,
        value: value,
      );
    } on WebRtcAdapterException {
      rethrow;
    } catch (_) {
      throw const WebRtcAdapterException(WebRtcFailureReason.other);
    }
  }

  @override
  Future<CallSessionDescription> createAnswer() async {
    final connection = _requireConnection();
    try {
      final description = await connection.createAnswer(
        webRtcAudioOnlySdpConstraints,
      );
      final value = description.sdp;
      if (value == null) {
        throw const WebRtcAdapterException(WebRtcFailureReason.other);
      }
      return CallSessionDescription(
        type: CallSessionDescriptionType.answer,
        value: value,
      );
    } on WebRtcAdapterException {
      rethrow;
    } catch (_) {
      throw const WebRtcAdapterException(WebRtcFailureReason.other);
    }
  }

  @override
  Future<void> setLocalDescription(CallSessionDescription description) async {
    final connection = _requireConnection();
    try {
      await connection.setLocalDescription(
        webrtc.RTCSessionDescription(description.value, description.type.name),
      );
    } catch (_) {
      throw const WebRtcAdapterException(WebRtcFailureReason.other);
    }
  }

  @override
  Future<void> setRemoteDescription(CallSessionDescription description) async {
    final connection = _requireConnection();
    try {
      await connection.setRemoteDescription(
        webrtc.RTCSessionDescription(description.value, description.type.name),
      );
    } catch (_) {
      throw const WebRtcAdapterException(WebRtcFailureReason.other);
    }
  }

  @override
  Future<void> addIceCandidates(List<CallIceCandidate> candidates) async {
    final connection = _requireConnection();
    try {
      for (final candidate in candidates) {
        await connection.addCandidate(
          webrtc.RTCIceCandidate(
            candidate.value,
            candidate.mediaId,
            candidate.mediaLineIndex,
          ),
        );
      }
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
  Future<void> updateIceServers(List<CallIceServer> iceServers) async {
    final configuration = _configuration;
    if (configuration == null) {
      throw const WebRtcAdapterException(WebRtcFailureReason.notReady);
    }
    try {
      await _requireConnection().setConfiguration(<String, dynamic>{
        'iceTransportPolicy':
            configuration.iceTransportPolicy ==
                WebRtcIceTransportPolicy.relayOnly
            ? 'relay'
            : 'all',
        'sdpSemantics': 'unified-plan',
        'iceServers': _pluginIceServers(iceServers),
      });
      _configuration = WebRtcPeerConnectionConfiguration(
        iceTransportPolicy: configuration.iceTransportPolicy,
        receiveAudio: configuration.receiveAudio,
        receiveVideo: configuration.receiveVideo,
        captureAudio: configuration.captureAudio,
        captureVideo: configuration.captureVideo,
        iceServers: iceServers,
      );
    } catch (_) {
      throw const WebRtcAdapterException(WebRtcFailureReason.other);
    }
  }

  @override
  Future<void> setLocalAudioEnabled(bool enabled) async {
    final connection = _requireConnection();
    try {
      final senders = await connection.getSenders();
      // The sender lookup can settle after teardown has released this peer.
      _requireConnection();
      for (final sender in senders) {
        final track = sender.track;
        if (track?.kind == 'audio') {
          track!.enabled = enabled;
        }
      }
    } on WebRtcAdapterException {
      rethrow;
    } catch (_) {
      throw const WebRtcAdapterException(WebRtcFailureReason.other);
    }
  }

  @override
  Future<WebRtcPeerConnectionSnapshot> snapshot() {
    final connection = _requireConnection();
    return _failureStageGuard.runWithDeadlineFallback(
      FlutterWebRtcFailureStage.snapshotDeadline,
      () => _snapshotOnce(connection),
      timeout: _snapshotDeadlineTimeout,
      onTimeout: _conservativeSnapshot,
    );
  }

  Future<WebRtcPeerConnectionSnapshot> _snapshotOnce(
    webrtc.RTCPeerConnection connection,
  ) async {
    try {
      var observationComplete = true;
      T incomplete<T>(T fallback) {
        observationComplete = false;
        return fallback;
      }

      var localAudioCaptureTrackCount = 0;
      var localVideoCaptureTrackCount = 0;
      final senders = await _failureStageGuard.runWithTimeoutFallback(
        FlutterWebRtcFailureStage.snapshotSenders,
        connection.getSenders,
        timeout: _snapshotReadTimeout,
        onTimeout: () => incomplete(<webrtc.RTCRtpSender>[]),
      );
      var localAudioEnabled = false;
      var localAudioSenderAttached = false;
      for (final sender in senders) {
        switch (sender.track?.kind) {
          case 'audio':
            localAudioCaptureTrackCount += 1;
            localAudioSenderAttached = true;
            localAudioEnabled = sender.track!.enabled;
          case 'video':
            localVideoCaptureTrackCount += 1;
        }
      }

      var audioReceiveTransceiverCount = 0;
      var videoTransceiverCount = 0;
      final transceivers = await _failureStageGuard.runWithTimeoutFallback(
        FlutterWebRtcFailureStage.snapshotTransceivers,
        connection.getTransceivers,
        timeout: _snapshotReadTimeout,
        onTimeout: () => incomplete(<webrtc.RTCRtpTransceiver>[]),
      );
      final directions = await _failureStageGuard
          .runWithTimeoutFallback<List<webrtc.TransceiverDirection?>>(
            FlutterWebRtcFailureStage.snapshotTransceiverDirection,
            () => Future.wait<webrtc.TransceiverDirection?>(
              transceivers.map((transceiver) => transceiver.getDirection()),
            ),
            timeout: _snapshotReadTimeout,
            onTimeout: () => incomplete(
              List<webrtc.TransceiverDirection?>.filled(
                transceivers.length,
                null,
                growable: false,
              ),
            ),
          );
      for (var index = 0; index < transceivers.length; index += 1) {
        final transceiver = transceivers[index];
        final direction = directions[index];
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
      final receivers = await _failureStageGuard.runWithTimeoutFallback(
        FlutterWebRtcFailureStage.snapshotReceivers,
        connection.getReceivers,
        timeout: _snapshotReadTimeout,
        onTimeout: () => incomplete(<webrtc.RTCRtpReceiver>[]),
      );
      for (final receiver in receivers) {
        if (receiver.track?.kind == 'audio') {
          remoteAudioReceiverAttached = true;
          break;
        }
      }
      final stats = await _failureStageGuard.runWithTimeoutFallback(
        FlutterWebRtcFailureStage.snapshotStats,
        connection.getStats,
        timeout: _snapshotReadTimeout,
        onTimeout: () => incomplete(<webrtc.StatsReport>[]),
      );
      // A per-read timeout invalidates this observation just like the aggregate
      // deadline. In particular, missing transceiver/direction data must not
      // be combined with successful stats to certify media readiness.
      if (!observationComplete) return _conservativeSnapshot();
      final diagnosticRecords = stats.map(
        (report) => CallStatsRecord(
          id: report.id,
          type: report.type,
          values: Map<Object?, Object?>.of(report.values),
        ),
      );
      final sample = _statsSampler.sample(diagnosticRecords);
      final observer = onDiagnosticSample;
      if (observer != null) {
        try {
          final progress = _rtpProgressSampler.sample(diagnosticRecords);
          observer(sample, progress);
        } catch (_) {
          // An optional diagnostic sink never changes media readiness.
        }
      }
      _inboundAudioRtpObserved |= sample.inboundAudioRtpObserved;
      _outboundAudioRtpObserved |= sample.outboundAudioRtpObserved;

      return WebRtcPeerConnectionSnapshot(
        isClosed: _closed,
        iceTransportPolicy:
            _configuration?.iceTransportPolicy ??
            WebRtcIceTransportPolicy.relayOnly,
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
        inboundAudioRtpObserved: _inboundAudioRtpObserved,
        outboundAudioRtpObserved: _outboundAudioRtpObserved,
      );
    } catch (_) {
      throw const WebRtcAdapterException(WebRtcFailureReason.other);
    }
  }

  WebRtcPeerConnectionSnapshot _conservativeSnapshot() =>
      WebRtcPeerConnectionSnapshot(
        isClosed: _closed,
        iceTransportPolicy:
            _configuration?.iceTransportPolicy ??
            WebRtcIceTransportPolicy.relayOnly,
        localAudioCaptureTrackCount: 0,
        localVideoCaptureTrackCount: 0,
        audioReceiveTransceiverCount: 0,
        videoTransceiverCount: 0,
        connectionState: _closed
            ? WebRtcConnectionState.closed
            : WebRtcConnectionState.newConnection,
        inboundAudioRtpObserved: _inboundAudioRtpObserved,
        outboundAudioRtpObserved: _outboundAudioRtpObserved,
      );

  webrtc.RTCPeerConnection _requireConnection() {
    if (_closed) {
      throw const WebRtcAdapterException(WebRtcFailureReason.closed);
    }
    final connection = _peerConnection;
    if (connection == null) {
      throw const WebRtcAdapterException(WebRtcFailureReason.notReady);
    }
    return connection;
  }

  void _emit(WebRtcPeerConnectionEvent event, {bool allowWhenClosed = false}) {
    if ((_closed && !allowWhenClosed) || _events.isClosed) return;

    // A native callback may reenter through a synchronous listener. Broadcast
    // controllers cannot add while firing. Retain only a disconnect edge and
    // the latest state until that delivery returns; failures supersede both.
    // This bounds actual reentrant work independently of diagnostic history.
    final pending = _pendingEvent;
    if (pending == null ||
        _isFailureEvent(event) ||
        !_isFailureEvent(pending)) {
      _pendingEvent = event;
      if (_isFailureEvent(event)) {
        _pendingDisconnect = null;
      } else if (event.connectionState == WebRtcConnectionState.disconnected) {
        _pendingDisconnect = event;
      }
    }
    if (_eventDeliveryInFlight) return;
    _eventDeliveryInFlight = true;
    try {
      while (true) {
        final next = _takePendingEvent();
        if (next == null) break;
        if (_closed && next.kind != WebRtcPeerConnectionEventKind.closed) {
          continue;
        }
        _retain(next);
        _events.add(next);
      }
    } finally {
      _eventDeliveryInFlight = false;
    }
  }

  WebRtcPeerConnectionEvent? _takePendingEvent() {
    final next = _pendingDisconnect ?? _pendingEvent;
    if (identical(next, _pendingDisconnect)) _pendingDisconnect = null;
    if (identical(next, _pendingEvent)) _pendingEvent = null;
    return next;
  }

  static bool _isFailureEvent(WebRtcPeerConnectionEvent event) =>
      event.kind == WebRtcPeerConnectionEventKind.overflow ||
      event.kind == WebRtcPeerConnectionEventKind.closed ||
      event.connectionState == WebRtcConnectionState.failed ||
      event.connectionState == WebRtcConnectionState.closed ||
      event.failureReason != WebRtcFailureReason.none;

  void _retain(WebRtcPeerConnectionEvent event) {
    if (_recentEvents.length == _eventBufferCapacity) {
      _recentEvents.removeAt(0);
    }
    _recentEvents.add(event);
  }

  @override
  Future<void> close() {
    final existing = _closeFuture;
    if (existing != null) return existing;
    _fenceForClose();
    final close = _runCloseAttempt();
    _closeFuture = close;
    return close;
  }

  void _fenceForClose() {
    if (_closed) return;
    _closed = true;
    _pendingEvent = null;
    _pendingDisconnect = null;
    _peerConnectionPendingClose = _peerConnection;
    _peerConnection = null;
    _peerConnectionCloseCompleted = false;
    _peerConnectionDisposeCompleted = false;
    _configuration = null;
    _localStreamPendingClose = _localStream;
    _localStream = null;
    _localAudioTrackPendingClose = _localAudioTrack;
    _localAudioTrack = null;
    final remoteTrack = _remoteAudioTrack;
    _remoteAudioTrack = null;
    _localTrackLive = false;
    _remoteTrackLive = false;

    if (remoteTrack != null) remoteTrack.onEnded = null;
    final connection = _peerConnectionPendingClose;
    if (connection != null) {
      connection.onConnectionState = null;
      connection.onIceConnectionState = null;
      connection.onIceCandidate = null;
      connection.onTrack = null;
    }
  }

  Future<void> _runCloseAttempt() async {
    try {
      await _closeOnce();
    } catch (_) {
      _closeFuture = null;
      rethrow;
    }
  }

  Future<void> _closeOnce() async {
    var releaseFailed = false;

    Future<void> attempt(
      Future<void> Function() action,
      void Function() markCompleted,
    ) async {
      try {
        await action();
        markCompleted();
      } catch (_) {
        releaseFailed = true;
      }
    }

    final localTrack = _localAudioTrackPendingClose;
    if (localTrack != null) {
      await attempt(
        () async {
          if (!await _stopTrack(localTrack)) {
            throw const WebRtcAdapterException(WebRtcFailureReason.other);
          }
        },
        () {
          if (identical(_localAudioTrackPendingClose, localTrack)) {
            _localAudioTrackPendingClose = null;
          }
        },
      );
    }
    final localStream = _localStreamPendingClose;
    if (_localAudioTrackPendingClose == null && localStream != null) {
      await attempt(
        () async {
          if (!await _disposeStream(localStream)) {
            throw const WebRtcAdapterException(WebRtcFailureReason.other);
          }
        },
        () {
          if (identical(_localStreamPendingClose, localStream)) {
            _localStreamPendingClose = null;
          }
        },
      );
    }

    final connection = _peerConnectionPendingClose;
    if (connection != null && !_peerConnectionCloseCompleted) {
      await attempt(connection.close, () {
        _peerConnectionCloseCompleted = true;
      });
    }
    if (connection != null &&
        _peerConnectionCloseCompleted &&
        !_peerConnectionDisposeCompleted) {
      await attempt(connection.dispose, () {
        _peerConnectionDisposeCompleted = true;
      });
    }
    if (_peerConnectionCloseCompleted && _peerConnectionDisposeCompleted) {
      _peerConnectionPendingClose = null;
    }

    if (!_closedEventEmitted) {
      _emit(
        const WebRtcPeerConnectionEvent(
          kind: WebRtcPeerConnectionEventKind.closed,
          connectionState: WebRtcConnectionState.closed,
          transport: WebRtcTransportClass.unknown,
          quality: WebRtcQualityBand.unknown,
          failureReason: WebRtcFailureReason.none,
        ),
        allowWhenClosed: true,
      );
      _closedEventEmitted = true;
    }
    if (!_localCandidatesClosed) {
      await attempt(_localCandidates.close, () {
        _localCandidatesClosed = true;
      });
    }
    if (!_eventsClosed) {
      await attempt(_events.close, () {
        _eventsClosed = true;
      });
    }

    if (releaseFailed) {
      throw const WebRtcAdapterException(WebRtcFailureReason.other);
    }
  }

  Future<bool> _releaseConnection(webrtc.RTCPeerConnection connection) async {
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

  Future<bool> _stopTrack(webrtc.MediaStreamTrack track) async {
    try {
      track.onEnded = null;
      await track.stop();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _disposeStream(webrtc.MediaStream stream) async {
    try {
      await stream.dispose();
      return true;
    } catch (_) {
      return false;
    }
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
}

final class FlutterWebRtcCallEngine
    implements CallEngine, CallAudioOutputRouteChangeSource {
  FlutterWebRtcCallEngine({
    required WebRtcPeerConnectionAdapter adapter,
    CallAudioRoutePort? audioRoutePort,
    int eventBufferCapacity = 64,
    this.candidateBatchCapacity = 8,
    int deferredCandidateCapacity = 64,
  }) : assert(eventBufferCapacity > 0),
       assert(candidateBatchCapacity > 0),
       assert(deferredCandidateCapacity > 0),
       _adapter = adapter,
       _audioRoutePort = audioRoutePort,
       _eventBufferCapacity = eventBufferCapacity,
       _deferredCandidateCapacity = deferredCandidateCapacity {
    _adapterSubscription = _adapter.events.listen(
      _onAdapterEvent,
      onError: (_) => _onAdapterError(),
    );
    final WebRtcLocalCandidateSource? candidateSource =
        adapter is WebRtcLocalCandidateSource
        ? adapter as WebRtcLocalCandidateSource
        : null;
    if (candidateSource != null) {
      _candidateSubscription = candidateSource.localCandidates.listen(
        _onLocalCandidate,
        onError: (_) {},
      );
    }
  }

  final WebRtcPeerConnectionAdapter _adapter;
  final CallAudioRoutePort? _audioRoutePort;
  final int _eventBufferCapacity;
  @override
  final int candidateBatchCapacity;
  final int _deferredCandidateCapacity;
  final StreamController<CallEngineEvent> _events =
      StreamController<CallEngineEvent>.broadcast(sync: true);
  final StreamController<CallIceCandidate> _localCandidates =
      StreamController<CallIceCandidate>.broadcast(sync: true);
  final List<CallEngineEvent> _recentEvents = <CallEngineEvent>[];
  final List<CallIceCandidate> _deferredCandidates = <CallIceCandidate>[];

  late final StreamSubscription<WebRtcPeerConnectionEvent> _adapterSubscription;
  StreamSubscription<CallIceCandidate>? _candidateSubscription;
  Future<void>? _closeFuture;
  Future<void>? _createFuture;
  Future<CallSessionDescription>? _offerFuture;
  Future<CallSessionDescription>? _answerFuture;
  Future<void>? _localDescriptionFuture;
  Future<void>? _remoteDescriptionFuture;
  bool _adapterClosed = false;
  bool _audioRouteLifecycleClosed = false;
  bool _closeStateReset = false;
  bool _closedEventEmitted = false;
  bool _candidateSubscriptionClosed = false;
  bool _localCandidatesClosed = false;
  bool _adapterSubscriptionClosed = false;
  bool _eventsClosed = false;
  bool _closed = false;
  bool _connectionCreated = false;
  bool _remoteDescriptionSet = false;
  bool _audioSessionActive = false;
  bool _localAudioEnabled = false;
  int _iceGeneration = 0;

  /// Reconnect episodes per call. TURN credentials are refreshed on each
  /// restart, so a long call may recover from more than one network change.
  static const int maxIceRestarts = 8;

  int _restartCount = 0;
  CallTransportPolicy? _transportPolicy;
  CallSessionDescription? _createdOffer;
  CallSessionDescription? _createdAnswer;
  CallSessionDescription? _localDescription;
  CallSessionDescription? _remoteDescription;
  CallSessionDescription? _pendingLocalDescription;
  CallSessionDescription? _pendingRemoteDescription;

  @override
  Stream<CallEngineEvent> get events => _events.stream;

  @override
  Stream<CallIceCandidate> get localCandidates => _localCandidates.stream;

  @override
  Stream<CallAudioOutputRoute> get outputRouteChanges {
    final routePort = _audioRoutePort;
    final CallAudioOutputRouteChangeSource? routeChangeSource =
        routePort is CallAudioOutputRouteChangeSource
        ? routePort as CallAudioOutputRouteChangeSource
        : null;
    return routeChangeSource?.outputRouteChanges ??
        const Stream<CallAudioOutputRoute>.empty();
  }

  @override
  List<CallEngineEvent> get recentEvents =>
      List<CallEngineEvent>.unmodifiable(_recentEvents);

  @override
  bool get isClosed => _closed;

  @override
  int get iceGeneration => _iceGeneration;

  @override
  Future<void> createConnection(CallConnectionConfiguration configuration) {
    _ensureOpen();
    if (_connectionCreated || _createFuture != null) {
      throw const CallEngineException(
        CallEngineErrorCode.configurationRejected,
      );
    }
    final supported =
        (configuration.transportPolicy == CallTransportPolicy.all ||
            configuration.transportPolicy == CallTransportPolicy.relayOnly) &&
        configuration.receiveAudio &&
        !configuration.receiveVideo &&
        !configuration.captureVideo;
    if (!supported || !_validIceServers(configuration.iceServers)) {
      throw const WebRtcAdapterException(
        WebRtcFailureReason.configurationRejected,
      );
    }
    final adapterConfiguration = WebRtcPeerConnectionConfiguration(
      iceTransportPolicy:
          configuration.transportPolicy == CallTransportPolicy.relayOnly
          ? WebRtcIceTransportPolicy.relayOnly
          : WebRtcIceTransportPolicy.all,
      receiveAudio: configuration.receiveAudio,
      receiveVideo: configuration.receiveVideo,
      captureAudio: configuration.captureAudio,
      captureVideo: configuration.captureVideo,
      iceServers: configuration.iceServers,
    );
    late final Future<void> attempt;
    attempt = _adapter
        .create(adapterConfiguration)
        .then((_) {
          if (_closed) {
            throw const CallEngineException(CallEngineErrorCode.closed);
          }
          _connectionCreated = true;
          _transportPolicy = configuration.transportPolicy;
          _localAudioEnabled = configuration.captureAudio;
        })
        .whenComplete(() {
          if (identical(_createFuture, attempt)) _createFuture = null;
        });
    _createFuture = attempt;
    return attempt;
  }

  @override
  Future<CallSessionDescription> createOffer() {
    _requireConnectionCreated();
    final created = _createdOffer;
    if (created != null) return Future<CallSessionDescription>.value(created);
    if (_remoteDescription?.type == CallSessionDescriptionType.offer ||
        _pendingRemoteDescription?.type == CallSessionDescriptionType.offer ||
        _createdAnswer != null ||
        _localDescription?.type == CallSessionDescriptionType.answer) {
      throw const CallEngineException(
        CallEngineErrorCode.configurationRejected,
      );
    }
    final inFlight = _offerFuture;
    if (inFlight != null) return inFlight;
    late final Future<CallSessionDescription> attempt;
    attempt = _createLocalDescription(CallSessionDescriptionType.offer)
        .then((description) {
          _createdOffer = description;
          return description;
        })
        .whenComplete(() {
          if (identical(_offerFuture, attempt)) _offerFuture = null;
        });
    _offerFuture = attempt;
    return attempt;
  }

  @override
  Future<CallSessionDescription> createAnswer() {
    _requireConnectionCreated();
    final created = _createdAnswer;
    if (created != null) return Future<CallSessionDescription>.value(created);
    if (_remoteDescription?.type != CallSessionDescriptionType.offer ||
        _createdOffer != null ||
        _localDescription?.type == CallSessionDescriptionType.offer) {
      throw const CallEngineException(
        CallEngineErrorCode.configurationRejected,
      );
    }
    final inFlight = _answerFuture;
    if (inFlight != null) return inFlight;
    late final Future<CallSessionDescription> attempt;
    attempt = _createLocalDescription(CallSessionDescriptionType.answer)
        .then((description) {
          _createdAnswer = description;
          return description;
        })
        .whenComplete(() {
          if (identical(_answerFuture, attempt)) _answerFuture = null;
        });
    _answerFuture = attempt;
    return attempt;
  }

  @override
  Future<void> setLocalDescription(CallSessionDescription description) {
    _requireConnectionCreated();
    _validateDescription(description);
    _validateLocalDescriptionPrivacy(description);
    final applied = _localDescription;
    if (applied != null) {
      if (_sameDescription(applied, description)) return Future<void>.value();
      throw const CallEngineException(
        CallEngineErrorCode.configurationRejected,
      );
    }
    final inFlight = _localDescriptionFuture;
    if (inFlight != null) {
      if (_sameDescription(_pendingLocalDescription, description)) {
        return inFlight;
      }
      throw const CallEngineException(
        CallEngineErrorCode.configurationRejected,
      );
    }
    final created = switch (description.type) {
      CallSessionDescriptionType.offer => _createdOffer,
      CallSessionDescriptionType.answer => _createdAnswer,
    };
    final orderIsValid = switch (description.type) {
      CallSessionDescriptionType.offer => _remoteDescription == null,
      CallSessionDescriptionType.answer =>
        _remoteDescription?.type == CallSessionDescriptionType.offer,
    };
    if (created == null ||
        !_sameDescription(created, description) ||
        !orderIsValid) {
      throw const CallEngineException(
        CallEngineErrorCode.configurationRejected,
      );
    }

    _pendingLocalDescription = description;
    late final Future<void> attempt;
    attempt = _adapter
        .setLocalDescription(description)
        .then((_) {
          _ensureOpen();
          _localDescription = description;
        })
        .whenComplete(() {
          if (identical(_localDescriptionFuture, attempt)) {
            _localDescriptionFuture = null;
            _pendingLocalDescription = null;
          }
        });
    _localDescriptionFuture = attempt;
    return attempt;
  }

  @override
  Future<void> setRemoteDescription(CallSessionDescription description) {
    _requireConnectionCreated();
    _validateDescription(description);
    final applied = _remoteDescription;
    if (applied != null) {
      if (_sameDescription(applied, description)) {
        return _drainDeferredCandidates();
      }
      throw const CallEngineException(
        CallEngineErrorCode.configurationRejected,
      );
    }
    final inFlight = _remoteDescriptionFuture;
    if (inFlight != null) {
      if (_sameDescription(_pendingRemoteDescription, description)) {
        return inFlight;
      }
      throw const CallEngineException(
        CallEngineErrorCode.configurationRejected,
      );
    }
    final orderIsValid = switch (description.type) {
      CallSessionDescriptionType.offer =>
        _createdOffer == null && _localDescription == null,
      CallSessionDescriptionType.answer =>
        _localDescription?.type == CallSessionDescriptionType.offer,
    };
    if (!orderIsValid) {
      throw const CallEngineException(
        CallEngineErrorCode.configurationRejected,
      );
    }

    _pendingRemoteDescription = description;
    late final Future<void> attempt;
    attempt = _setRemoteDescriptionOnce(description).whenComplete(() {
      if (identical(_remoteDescriptionFuture, attempt)) {
        _remoteDescriptionFuture = null;
        _pendingRemoteDescription = null;
      }
    });
    _remoteDescriptionFuture = attempt;
    return attempt;
  }

  @override
  Future<void> addIceCandidates(List<CallIceCandidate> candidates) async {
    _requireConnectionCreated();
    if (candidates.isEmpty) return;
    if (candidates.length > candidateBatchCapacity) {
      throw const CallEngineException(CallEngineErrorCode.candidateOverflow);
    }
    // Candidates of a superseded generation stay in flight for a short while
    // after an ICE restart. They are dropped, never fatal.
    candidates = List<CallIceCandidate>.unmodifiable(
      candidates.where(
        (candidate) => candidate.iceGeneration >= _iceGeneration,
      ),
    );
    if (candidates.isEmpty) return;
    for (final candidate in candidates) {
      if (candidate.iceGeneration > _iceGeneration) {
        throw const CallEngineException(
          CallEngineErrorCode.futureIceGeneration,
        );
      }
      // The remote endpoint owns its gathering policy. A local TURN candidate
      // can pair with a remote host/reflexive candidate without exposing our
      // direct addresses. Native ICE still validates and processes the candidate.
      if (_candidateTokens(candidate.value) == null) {
        throw const CallEngineException(
          CallEngineErrorCode.configurationRejected,
        );
      }
    }
    if (!_remoteDescriptionSet) {
      if (_deferredCandidates.length + candidates.length >
          _deferredCandidateCapacity) {
        throw const CallEngineException(CallEngineErrorCode.candidateOverflow);
      }
      _deferredCandidates.addAll(candidates);
      return;
    }
    await _adapter.addIceCandidates(candidates);
  }

  @override
  Future<int> restartIce({
    List<CallIceServer> iceServers = const <CallIceServer>[],
  }) async {
    _requireConnectionCreated();
    if (_restartCount >= maxIceRestarts) {
      throw const CallEngineException(CallEngineErrorCode.restartLimitReached);
    }
    if (!_validIceServers(iceServers)) {
      throw const CallEngineException(
        CallEngineErrorCode.configurationRejected,
      );
    }
    final updater = _adapter is WebRtcIceServerUpdater
        ? _adapter as WebRtcIceServerUpdater
        : null;
    if (updater != null) {
      // An empty replacement is meaningful after a transient credential outage:
      // clear previous (possibly expired) TURN, preserving the frozen policy.
      await updater.updateIceServers(iceServers);
    } else if (iceServers.isNotEmpty) {
      throw const CallEngineException(CallEngineErrorCode.notReady);
    }
    _ensureOpen();
    await _adapter.restartIce();
    _ensureOpen();
    _restartCount += 1;
    _iceGeneration += 1;
    _deferredCandidates.clear();
    _resetDescriptions();
    return _iceGeneration;
  }

  @override
  Future<void> setLocalAudioEnabled(bool enabled) async {
    _requireConnectionCreated();
    if (_localAudioEnabled == enabled) return;
    await _adapter.setLocalAudioEnabled(enabled);
    _localAudioEnabled = enabled;
  }

  @override
  Future<void> setAudioSessionActive(bool active) async {
    _ensureOpen();
    _audioSessionActive = active;
  }

  @override
  Future<List<CallAudioOutputRoute>> supportedOutputRoutes() async {
    _ensureOpen();
    return _audioRoutePort?.supportedOutputRoutes() ??
        const <CallAudioOutputRoute>[CallAudioOutputRoute.systemDefault];
  }

  @override
  Future<void> selectOutputRoute(CallAudioOutputRoute route) async {
    _requireConnectionCreated();
    final routePort = _audioRoutePort;
    if (routePort == null) {
      if (route == CallAudioOutputRoute.systemDefault) return;
      throw const CallEngineException(CallEngineErrorCode.notReady);
    }
    await routePort.selectOutputRoute(route);
  }

  @override
  Future<CallConnectionSnapshot> snapshot() async {
    _requireConnectionCreated();
    final WebRtcPeerConnectionSnapshot snapshot;
    try {
      snapshot = await _adapter.snapshot();
    } on WebRtcAdapterException catch (error, stackTrace) {
      // Native snapshot reads report `other` after recording a fixed failure
      // stage. A failed observation says nothing about transport health.
      final code = switch (error.reason) {
        WebRtcFailureReason.other => CallEngineErrorCode.observationUnavailable,
        WebRtcFailureReason.notReady => CallEngineErrorCode.notReady,
        WebRtcFailureReason.transportUnavailable =>
          CallEngineErrorCode.transportUnavailable,
        WebRtcFailureReason.configurationRejected =>
          CallEngineErrorCode.configurationRejected,
        WebRtcFailureReason.closed => CallEngineErrorCode.closed,
        WebRtcFailureReason.none => CallEngineErrorCode.other,
      };
      Error.throwWithStackTrace(CallEngineException(code), stackTrace);
    }
    _ensureOpen();
    if (snapshot.isClosed ||
        snapshot.connectionState == WebRtcConnectionState.closed) {
      throw const CallEngineException(CallEngineErrorCode.closed);
    }
    if (snapshot.connectionState == WebRtcConnectionState.failed) {
      throw const CallEngineException(CallEngineErrorCode.transportUnavailable);
    }
    final transport = _mapAdapterTransport(snapshot.transport);
    final relaySelectionProven = switch (transport) {
      CallTransportClass.relay ||
      CallTransportClass.turnUdp ||
      CallTransportClass.turnTcpTls => true,
      CallTransportClass.unknown || CallTransportClass.direct => false,
    };
    final relaySelectionUnproven =
        snapshot.selectedPairSucceeded &&
        snapshot.selectedPairNominated &&
        !relaySelectionProven;
    if (_transportPolicy == CallTransportPolicy.relayOnly &&
        (transport == CallTransportClass.direct || relaySelectionUnproven)) {
      throw const CallEngineException(CallEngineErrorCode.relayPolicyViolation);
    }
    return CallConnectionSnapshot(
      state: _mapAdapterConnectionState(snapshot.connectionState),
      transportPolicy: _transportPolicy ?? CallTransportPolicy.relayOnly,
      transport: transport,
      quality: _mapAdapterQuality(snapshot.quality),
      localAudioCaptureTrackCount: snapshot.localAudioCaptureTrackCount,
      localVideoCaptureTrackCount: snapshot.localVideoCaptureTrackCount,
      audioReceiveTransceiverCount: snapshot.audioReceiveTransceiverCount,
      videoTransceiverCount: snapshot.videoTransceiverCount,
      selectedPairSucceeded: snapshot.selectedPairSucceeded,
      selectedPairNominated: snapshot.selectedPairNominated,
      selectedRelayProtocol: _mapAdapterRelayProtocol(
        snapshot.selectedRelayProtocol,
      ),
      dtlsReady: snapshot.dtlsReady,
      audioSessionActive: _audioSessionActive,
      localAudioSenderAttached: snapshot.localAudioSenderAttached,
      localAudioTrackLive: snapshot.localAudioTrackLive,
      remoteAudioReceiverAttached: snapshot.remoteAudioReceiverAttached,
      remoteAudioTrackLive: snapshot.remoteAudioTrackLive,
      localAudioEnabled: snapshot.localAudioEnabled,
      inboundAudioRtpObserved: snapshot.inboundAudioRtpObserved,
      outboundAudioRtpObserved: snapshot.outboundAudioRtpObserved,
      outputRoute:
          _audioRoutePort?.selectedRoute ?? CallAudioOutputRoute.systemDefault,
    );
  }

  void _onLocalCandidate(CallIceCandidate candidate) {
    if (_closed || _localCandidates.isClosed) return;
    if (candidate.iceGeneration != _iceGeneration) return;
    if (_transportPolicy == CallTransportPolicy.relayOnly &&
        !_candidatePreservesLocalRelayPrivacy(candidate.value)) {
      return;
    }
    _localCandidates.add(candidate);
  }

  void _ensureOpen() {
    if (_closed) {
      throw const CallEngineException(CallEngineErrorCode.closed);
    }
  }

  void _requireConnectionCreated() {
    _ensureOpen();
    if (!_connectionCreated) {
      throw const CallEngineException(CallEngineErrorCode.notReady);
    }
  }

  static bool _validIceServers(List<CallIceServer> servers) {
    if (servers.length > 8) return false;
    final now = DateTime.now().toUtc();
    for (final server in servers) {
      if (server.urls.isEmpty || server.urls.length > 16) return false;
      if (server.urls.any(
        (url) =>
            !(url.startsWith('stun:') ||
                url.startsWith('turn:') ||
                url.startsWith('turns:')),
      )) {
        return false;
      }
      if (!server.expiresAt.isAfter(now)) return false;
      if (server.containsTurnUrl &&
          ((server.username?.isEmpty ?? true) ||
              (server.credential?.isEmpty ?? true))) {
        return false;
      }
    }
    return true;
  }

  static CallSessionDescription _withExtractedFingerprint(
    CallSessionDescription description,
  ) {
    final fingerprint = _extractFingerprint(description.value);
    return CallSessionDescription(
      type: description.type,
      value: description.value,
      fingerprint: fingerprint,
    );
  }

  Future<CallSessionDescription> _createLocalDescription(
    CallSessionDescriptionType expectedType,
  ) async {
    final raw = switch (expectedType) {
      CallSessionDescriptionType.offer => await _adapter.createOffer(),
      CallSessionDescriptionType.answer => await _adapter.createAnswer(),
    };
    _ensureOpen();
    if (raw.type != expectedType) {
      throw const CallEngineException(
        CallEngineErrorCode.configurationRejected,
      );
    }
    final description = _withExtractedFingerprint(raw);
    _validateDescription(description);
    _validateLocalDescriptionPrivacy(description);
    return description;
  }

  Future<void> _setRemoteDescriptionOnce(
    CallSessionDescription description,
  ) async {
    await _adapter.setRemoteDescription(description);
    _ensureOpen();
    _remoteDescription = description;
    _remoteDescriptionSet = true;
    await _drainDeferredCandidates();
  }

  Future<void> _drainDeferredCandidates() async {
    if (_deferredCandidates.isEmpty) return;
    final generation = _iceGeneration;
    final queued = List<CallIceCandidate>.unmodifiable(_deferredCandidates);
    await _adapter.addIceCandidates(queued);
    _ensureOpen();
    if (_iceGeneration != generation) return;
    _deferredCandidates.removeRange(0, queued.length);
  }

  void _resetDescriptions() {
    _remoteDescriptionSet = false;
    _createdOffer = null;
    _createdAnswer = null;
    _localDescription = null;
    _remoteDescription = null;
    _pendingLocalDescription = null;
    _pendingRemoteDescription = null;
  }

  static bool _sameDescription(
    CallSessionDescription? left,
    CallSessionDescription right,
  ) =>
      left?.type == right.type &&
      left?.value == right.value &&
      left?.fingerprint == right.fingerprint;

  void _validateDescription(CallSessionDescription description) {
    if (_containsVideoSection(description.value)) {
      throw const CallEngineException(
        CallEngineErrorCode.configurationRejected,
      );
    }
    final authenticated = _normalizeFingerprint(description.fingerprint);
    final inSdp = _extractFingerprint(description.value);
    if (authenticated != inSdp) {
      throw const CallEngineException(CallEngineErrorCode.fingerprintMismatch);
    }
    for (final rawLine in description.value.split(RegExp(r'\r?\n'))) {
      final line = rawLine.trim();
      if (_isCandidateAttribute(line) && _candidateTokens(line) == null) {
        throw const CallEngineException(
          CallEngineErrorCode.configurationRejected,
        );
      }
    }
  }

  // Egress defense in addition to native iceTransportPolicy=relay. Apply only
  // to our descriptions, including restart offers/answers, before signaling.
  // Do not rewrite SDP: the native agent must also restrict connectivity checks.
  void _validateLocalDescriptionPrivacy(CallSessionDescription description) {
    if (_transportPolicy != CallTransportPolicy.relayOnly) return;
    for (final rawLine in description.value.split(RegExp(r'\r?\n'))) {
      final line = rawLine.trim();
      if (_isCandidateAttribute(line) &&
          !_candidatePreservesLocalRelayPrivacy(line)) {
        throw const CallEngineException(
          CallEngineErrorCode.relayPolicyViolation,
        );
      }
    }
  }

  static String _extractFingerprint(String sdp) {
    final fingerprints = <String>{};
    for (final line in sdp.split(RegExp(r'\r?\n'))) {
      if (!line.startsWith('a=fingerprint:')) continue;
      fingerprints.add(
        _normalizeFingerprint(line.substring('a=fingerprint:'.length)),
      );
    }
    if (fingerprints.length != 1) {
      throw const CallEngineException(CallEngineErrorCode.malformedFingerprint);
    }
    return fingerprints.single;
  }

  static String _normalizeFingerprint(String? value) {
    final normalized = value?.trim() ?? '';
    final match = RegExp(
      r'^sha-256 ([0-9a-fA-F]{2})(:[0-9a-fA-F]{2}){31}$',
    ).firstMatch(normalized);
    if (match == null) {
      throw const CallEngineException(CallEngineErrorCode.malformedFingerprint);
    }
    return normalized.toUpperCase().replaceFirst('SHA-256', 'sha-256');
  }

  static bool _containsVideoSection(String sdp) =>
      sdp.split(RegExp(r'\r?\n')).any((line) => line.startsWith('m=video '));

  static bool _isCandidateAttribute(String line) =>
      RegExp(r'^a=candidate:', caseSensitive: false).hasMatch(line);

  static List<String>? _candidateTokens(String candidate) {
    if (candidate.contains('\r') || candidate.contains('\n')) return null;
    var normalized = candidate.trim();
    if (normalized.length >= 2 &&
        normalized.substring(0, 2).toLowerCase() == 'a=') {
      normalized = normalized.substring(2);
    }
    final tokens = normalized.split(RegExp(r'\s+'));
    if (tokens.length < 8 ||
        !tokens.first.toLowerCase().startsWith('candidate:') ||
        tokens[6].toLowerCase() != 'typ') {
      return null;
    }
    if (!const {
      'host',
      'srflx',
      'prflx',
      'relay',
    }.contains(tokens[7].toLowerCase())) {
      return null;
    }
    return tokens;
  }

  static bool _candidatePreservesLocalRelayPrivacy(String candidate) {
    final tokens = _candidateTokens(candidate);
    if (tokens == null || tokens[7].toLowerCase() != 'relay') return false;
    // libwebrtc's relay filter sanitizes TURN relatedAddress/relatedPort to
    // an unspecified address and zero. Refuse unsanitized native output before
    // egress, including a public reflexive address hidden in a relay candidate.
    for (var i = 8; i < tokens.length; i += 2) {
      if (i + 1 >= tokens.length) return false;
      final key = tokens[i].toLowerCase();
      final value = tokens[i + 1];
      if (key == 'raddr' && value != '0.0.0.0' && value != '::') return false;
      if (key == 'rport' && value != '0') return false;
    }
    return true;
  }

  void _onAdapterEvent(WebRtcPeerConnectionEvent event) {
    _emit(
      CallEngineEvent(
        type: _mapAdapterEventKind(event.kind),
        connectionState: _mapAdapterConnectionState(event.connectionState),
        transport: _mapAdapterTransport(event.transport),
        quality: _mapAdapterQuality(event.quality),
        failureReason: _mapAdapterFailureReason(event.failureReason),
      ),
    );
  }

  void _onAdapterError() {
    _emit(
      const CallEngineEvent(
        type: CallEngineEventType.state,
        connectionState: CallConnectionState.failed,
        transport: CallTransportClass.unknown,
        quality: CallQualityBand.unknown,
        failureReason: CallFailureReason.other,
      ),
    );
  }

  void _emit(CallEngineEvent event, {bool allowWhenClosed = false}) {
    if ((_closed && !allowWhenClosed) || _events.isClosed) return;
    // The executor consumes synchronously and coalesces its asynchronous work.
    // Retained history is bounded independently of lifetime delivery volume.
    _retain(event);
    _events.add(event);
  }

  void _retain(CallEngineEvent event) {
    if (_recentEvents.length == _eventBufferCapacity) {
      _recentEvents.removeAt(0);
    }
    _recentEvents.add(event);
  }

  @override
  Future<void> close() {
    final existing = _closeFuture;
    if (existing != null) return existing;
    _closed = true;
    final close = _runCloseAttempt();
    _closeFuture = close;
    return close;
  }

  Future<void> _runCloseAttempt() async {
    try {
      await _closeOnce();
    } catch (_) {
      _closeFuture = null;
      rethrow;
    }
  }

  Future<void> _closeOnce() async {
    var closeFailed = false;

    Future<void> attempt(
      bool completed,
      Future<void> Function() action,
      void Function() markCompleted,
    ) async {
      if (completed) return;
      try {
        await action();
        markCompleted();
      } catch (_) {
        closeFailed = true;
      }
    }

    // Fence routes and the peer immediately; either platform teardown may
    // suspend, so it must not delay the other resource's closed guard.
    final routePort = _audioRoutePort;
    final CallAudioRouteObserverLifecycle? routeLifecycle =
        routePort is CallAudioRouteObserverLifecycle
        ? routePort as CallAudioRouteObserverLifecycle
        : null;
    Future<void>? routeClose;
    if (routeLifecycle == null) {
      _audioRouteLifecycleClosed = true;
    } else {
      routeClose = attempt(
        _audioRouteLifecycleClosed,
        routeLifecycle.close,
        () => _audioRouteLifecycleClosed = true,
      );
    }
    await attempt(_adapterClosed, _adapter.close, () => _adapterClosed = true);
    if (routeClose != null) await routeClose;

    if (!_closeStateReset) {
      _connectionCreated = false;
      _audioSessionActive = false;
      _localAudioEnabled = false;
      _transportPolicy = null;
      _deferredCandidates.clear();
      _resetDescriptions();
      _closeStateReset = true;
    }
    if (!_closedEventEmitted) {
      _emit(
        const CallEngineEvent(
          type: CallEngineEventType.closed,
          connectionState: CallConnectionState.closed,
          transport: CallTransportClass.unknown,
          quality: CallQualityBand.unknown,
          failureReason: CallFailureReason.none,
        ),
        allowWhenClosed: true,
      );
      _closedEventEmitted = true;
    }
    final candidateSubscription = _candidateSubscription;
    if (candidateSubscription == null) {
      _candidateSubscriptionClosed = true;
    } else {
      await attempt(
        _candidateSubscriptionClosed,
        candidateSubscription.cancel,
        () => _candidateSubscriptionClosed = true,
      );
    }
    await attempt(
      _localCandidatesClosed,
      _localCandidates.close,
      () => _localCandidatesClosed = true,
    );
    await attempt(
      _adapterSubscriptionClosed,
      _adapterSubscription.cancel,
      () => _adapterSubscriptionClosed = true,
    );
    await attempt(_eventsClosed, _events.close, () => _eventsClosed = true);

    if (closeFailed) {
      throw const WebRtcAdapterException(WebRtcFailureReason.other);
    }
  }
}

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

WebRtcConnectionState _mapNullableConnectionState(
  webrtc.RTCPeerConnectionState? state,
) => state == null
    ? WebRtcConnectionState.newConnection
    : _mapConnectionState(state);

CallEngineEventType _mapAdapterEventKind(WebRtcPeerConnectionEventKind kind) {
  switch (kind) {
    case WebRtcPeerConnectionEventKind.state:
      return CallEngineEventType.state;
    case WebRtcPeerConnectionEventKind.statistics:
      return CallEngineEventType.statistics;
    case WebRtcPeerConnectionEventKind.overflow:
      return CallEngineEventType.overflow;
    case WebRtcPeerConnectionEventKind.closed:
      return CallEngineEventType.closed;
  }
}

CallConnectionState _mapAdapterConnectionState(WebRtcConnectionState state) {
  switch (state) {
    case WebRtcConnectionState.newConnection:
      return CallConnectionState.newConnection;
    case WebRtcConnectionState.connecting:
      return CallConnectionState.connecting;
    case WebRtcConnectionState.connected:
      return CallConnectionState.connected;
    case WebRtcConnectionState.disconnected:
      return CallConnectionState.disconnected;
    case WebRtcConnectionState.failed:
      return CallConnectionState.failed;
    case WebRtcConnectionState.closed:
      return CallConnectionState.closed;
  }
}

CallTransportClass _mapAdapterTransport(WebRtcTransportClass transport) {
  switch (transport) {
    case WebRtcTransportClass.unknown:
      return CallTransportClass.unknown;
    case WebRtcTransportClass.direct:
      return CallTransportClass.direct;
    case WebRtcTransportClass.relay:
      return CallTransportClass.relay;
    case WebRtcTransportClass.turnUdp:
      return CallTransportClass.turnUdp;
    case WebRtcTransportClass.turnTcpTls:
      return CallTransportClass.turnTcpTls;
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

CallRelayProtocol _mapAdapterRelayProtocol(WebRtcRelayProtocol protocol) {
  return switch (protocol) {
    WebRtcRelayProtocol.notRelay => CallRelayProtocol.notRelay,
    WebRtcRelayProtocol.unknown => CallRelayProtocol.unknown,
    WebRtcRelayProtocol.udp => CallRelayProtocol.udp,
    WebRtcRelayProtocol.tcp => CallRelayProtocol.tcp,
    WebRtcRelayProtocol.tls => CallRelayProtocol.tls,
  };
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

CallQualityBand _mapAdapterQuality(WebRtcQualityBand quality) {
  switch (quality) {
    case WebRtcQualityBand.unknown:
      return CallQualityBand.unknown;
    case WebRtcQualityBand.good:
      return CallQualityBand.good;
    case WebRtcQualityBand.degraded:
      return CallQualityBand.degraded;
    case WebRtcQualityBand.poor:
      return CallQualityBand.poor;
  }
}

CallFailureReason _mapAdapterFailureReason(WebRtcFailureReason reason) {
  switch (reason) {
    case WebRtcFailureReason.none:
      return CallFailureReason.none;
    case WebRtcFailureReason.transportUnavailable:
      return CallFailureReason.transportUnavailable;
    case WebRtcFailureReason.configurationRejected:
      return CallFailureReason.configurationRejected;
    case WebRtcFailureReason.notReady:
      return CallFailureReason.notReady;
    case WebRtcFailureReason.closed:
      return CallFailureReason.closed;
    case WebRtcFailureReason.other:
      return CallFailureReason.other;
  }
}
