import 'dart:async';

import 'package:flutter_webrtc/flutter_webrtc.dart' as webrtc;

import '../application/call_video_media_owner.dart';
import '../domain/call_engine.dart';
import '../domain/call_id.dart';
import '../domain/call_media.dart';
import 'webrtc_types.dart';

/// Injectable native boundaries; production defaults never request audio.
typedef CallVideoCaptureFactory = Future<webrtc.MediaStream> Function();
typedef CallVideoRendererFactory = webrtc.RTCVideoRenderer Function();
typedef CallVideoStreamFactory = Future<webrtc.MediaStream> Function();

final class _Negotiation implements CallVideoNegotiation {
  _Negotiation(
    this.callId,
    this.negotiationId,
    this.mediaRevision,
    this.media,
    this.canApply,
  );
  @override
  final CallId callId;
  @override
  final String negotiationId;
  @override
  final int mediaRevision;
  @override
  final CallMediaKind media;
  final bool Function() canApply;
  CallSessionDescription? local;
  CallSessionDescription? remote;
  CallSessionDescription? offer;
  CallSessionDescription? answer;
  bool committed = false;
  bool retired = false;
}

/// Concrete optional resources on an existing audio peer. No method owns the
/// microphone, audio route, ICE generation, or the peer connection lifetime.
final class FlutterWebRtcVideoSession
    implements
        CallVideoSession,
        CallVideoPresentationSource,
        CallVideoCameraSwitch {
  FlutterWebRtcVideoSession({
    required this.callId,
    required this.localIsCaller,
    required webrtc.RTCPeerConnection Function() connection,
    required bool Function() canApply,
    required CallVideoDescriptionValidator validateDescription,
    required Future<void> Function() remoteDescriptionApplied,
    CallVideoCaptureFactory? capture,
    CallVideoRendererFactory? renderer,
    CallVideoStreamFactory? videoStream,
  }) : _connection = connection,
       _canApply = canApply,
       _validateDescription = validateDescription,
       _remoteDescriptionApplied = remoteDescriptionApplied,
       _capture =
           capture ??
           (() => webrtc.navigator.mediaDevices.getUserMedia(<String, dynamic>{
             'audio': false,
             'video': true,
           })),
       _renderer = renderer ?? webrtc.RTCVideoRenderer.new,
       _videoStream =
           videoStream ?? (() => webrtc.createLocalMediaStream('call-video')) {
    _owner = CallVideoMediaOwner(
      callId: callId,
      closeLocalVideoSendGate: _closeSendGate,
    );
  }

  @override
  final CallId callId;
  final bool localIsCaller;
  final webrtc.RTCPeerConnection Function() _connection;
  final bool Function() _canApply;
  final CallVideoDescriptionValidator _validateDescription;
  final Future<void> Function() _remoteDescriptionApplied;
  final CallVideoCaptureFactory _capture;
  final CallVideoRendererFactory _renderer;
  final CallVideoStreamFactory _videoStream;
  webrtc.MediaStream? _sendStream;
  bool _streamDisposeFailed = false;
  Future<void>? _streamDisposal;
  late final CallVideoMediaOwner _owner;
  _Negotiation? _current;
  webrtc.RTCRtpTransceiver? _video;
  webrtc.MediaStreamTrack? _remoteTrack;
  webrtc.MediaStream? _remoteStream;
  final Set<_Capture> _captures = {};
  final Map<CallVideoRendererSlot, _Renderer> _views = {};
  _Capture? _senderCapture;
  CallVideoCaptureIntent? _captureIntent;
  bool _closed = false;
  bool _receiveOpen = false;
  int _operations = 0;
  Future<void> _tail = Future<void>.value();

  final _presentation = StreamController<CallVideoPresentationState>.broadcast(
    sync: true,
  );
  final _pendingPresentation = <CallVideoPresentationState>[];
  bool _publishing = false;
  final _lastPresentation =
      <CallVideoRendererSlot, CallVideoPresentationState>{};

  @override
  Stream<CallVideoPresentationState> get presentationChanges =>
      _presentation.stream;

  @override
  CallVideoPresentationState presentationFor(CallVideoRendererSlot slot) {
    final token = _current;
    final active =
        token != null &&
        _currentToken(token) &&
        token.committed &&
        token.media == CallMediaKind.video;
    final capture = _captureIntent == null
        ? null
        : _owner.captureFor(_captureIntent!)?.resource as _Capture?;
    final hasTrack =
        active &&
        (slot == CallVideoRendererSlot.remote
            ? _receiveOpen && _remoteTrack != null && _remoteStream != null
            : capture != null &&
                  capture.tracks.length == 1 &&
                  capture.tracks.single.enabled);
    final native = hasTrack ? _views[slot]?.native : null;
    final id = native?.textureId;
    return CallVideoPresentationState(
      callId: callId,
      negotiation: token != null && _currentToken(token) ? token : null,
      slot: slot,
      hasTrack: hasTrack,
      view: id == null
          ? null
          : CallVideoView(
              textureId: id,
              width: native!.videoWidth,
              height: native.videoHeight,
            ),
    );
  }

  void _publish(CallVideoRendererSlot slot) {
    if (_presentation.isClosed) return;
    final state = presentationFor(slot);
    final last = _lastPresentation[slot];
    if (last != null &&
        identical(last.negotiation, state.negotiation) &&
        last.hasTrack == state.hasTrack &&
        last.view?.textureId == state.view?.textureId &&
        last.view?.width == state.view?.width &&
        last.view?.height == state.view?.height) {
      return;
    }
    _lastPresentation[slot] = state;
    _pendingPresentation.add(state);
    if (_publishing) return;
    _publishing = true;
    try {
      while (_pendingPresentation.isNotEmpty && !_presentation.isClosed) {
        _presentation.add(_pendingPresentation.removeAt(0));
      }
    } finally {
      _publishing = false;
    }
  }

  void _invalidate(CallVideoRendererSlot slot) {
    final renderer = _views.remove(slot);
    renderer?.native.onResize = null;
    renderer?.native.onFirstFrameRendered = null;
    _publish(slot);
  }

  void _invalidateAll() {
    for (final slot in CallVideoRendererSlot.values) {
      _invalidate(slot);
    }
  }

  bool _allowed() {
    try {
      return !_closed && _canApply();
    } catch (_) {
      return false;
    }
  }

  bool _currentToken(_Negotiation token) {
    try {
      return _allowed() &&
          identical(_current, token) &&
          !token.retired &&
          token.canApply();
    } catch (_) {
      return false;
    }
  }

  Never _reject() =>
      throw const CallEngineException(CallEngineErrorCode.notReady);

  _Negotiation _check(CallVideoNegotiation token) {
    if (token is! _Negotiation || !_currentToken(token)) {
      if (identical(_current, token)) unawaited(retireVideo());
      _reject();
    }
    return token;
  }

  /// Serializes native mutations including replacement and cleanup. Retirement
  /// closes track gates synchronously even while a native operation is pending.
  Future<T> _serial<T>(Future<T> Function() operation) {
    _operations++;
    final result = _tail.then((_) => operation()).whenComplete(() {
      _operations--;
    });
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  @override
  bool get hasPendingCleanup =>
      _owner.hasPendingCleanup || _streamDisposeFailed;

  @override
  CallVideoNegotiation beginNegotiation({
    required String negotiationId,
    required int mediaRevision,
    required CallMediaKind media,
    required bool Function() canApply,
  }) {
    if (!_allowed() ||
        _operations != 0 ||
        negotiationId.isEmpty ||
        mediaRevision < 0) {
      _reject();
    }
    final previous = _current;
    if (previous != null &&
        (previous.negotiationId == negotiationId ||
            mediaRevision < previous.mediaRevision ||
            (previous.local?.type == CallSessionDescriptionType.offer &&
                previous.remote?.type != CallSessionDescriptionType.answer) ||
            (previous.remote?.type == CallSessionDescriptionType.offer &&
                previous.local?.type != CallSessionDescriptionType.answer))) {
      _reject();
    }
    final token = _Negotiation(
      callId,
      negotiationId,
      mediaRevision,
      media,
      canApply,
    );
    if (!_currentGrant(canApply)) _reject();
    previous?.retired = true;
    _captureIntent = null;
    _invalidateAll();
    unawaited(_owner.retireVideo());
    _closeSendGate();
    _receiveOpen = false;
    _remoteTrack?.enabled = false;
    return _current = token;
  }

  bool _currentGrant(bool Function() check) {
    try {
      return check();
    } catch (_) {
      return false;
    }
  }

  Future<void> _prepare(_Negotiation token) async {
    _check(token);
    var video = _video;
    if (video == null && token.media == CallMediaKind.video) {
      _sendStream ??= await _videoStream();
      _check(token);
      video = await _connection().addTransceiver(
        kind: webrtc.RTCRtpMediaType.RTCRtpMediaTypeVideo,
        init: webrtc.RTCRtpTransceiverInit(
          direction: webrtc.TransceiverDirection.Inactive,
          streams: [_sendStream!],
        ),
      );
      _video =
          video; // Retained even if the await was retired; never loses ownership.
      _check(token);
    }
    if (video == null) return;
    if (token.media == CallMediaKind.video) {
      _sendStream ??= await _videoStream();
      _check(token);
      await video.sender.setStreams([_sendStream!]);
      _check(token);
    }
    final direction = token.media == CallMediaKind.video
        ? webrtc.TransceiverDirection.SendRecv
        : webrtc.TransceiverDirection.Inactive;
    await video.setDirection(direction);
    _check(token);
    final actual = await video.getDirection();
    _check(token);
    if (actual != direction) _reject();
  }

  Future<CallSessionDescription> _create(
    CallVideoNegotiation raw,
    bool offer,
  ) => _serial(() async {
    final token = _check(raw);
    if (offer != localIsCaller) _reject();
    final cached = offer ? token.offer : token.answer;
    if (cached != null) return cached;
    if (!offer && token.remote?.type != CallSessionDescriptionType.offer) {
      _reject();
    }
    await _prepare(token);
    _check(token);
    final constraints = <String, dynamic>{
      'mandatory': <String, bool>{
        'OfferToReceiveAudio': true,
        'OfferToReceiveVideo': token.media == CallMediaKind.video,
      },
      'optional': <Map<String, dynamic>>[],
    };
    final native = offer
        ? await _connection().createOffer(constraints)
        : await _connection().createAnswer(constraints);
    _check(token);
    final type = offer
        ? CallSessionDescriptionType.offer
        : CallSessionDescriptionType.answer;
    if (native.type != type.name || native.sdp == null) _reject();
    final description = _validateDescription(
      CallSessionDescription(type: type, value: native.sdp!, fingerprint: ''),
      token.media,
      true,
    );
    if (offer) {
      token.offer = description;
    } else {
      token.answer = description;
    }
    return description;
  });

  @override
  Future<CallSessionDescription> createOffer(CallVideoNegotiation token) =>
      _create(token, true);
  @override
  Future<CallSessionDescription> createAnswer(CallVideoNegotiation token) =>
      _create(token, false);

  Future<void> _apply(
    CallVideoNegotiation raw,
    CallSessionDescription description,
    bool local,
  ) => _serial(() async {
    final token = _check(raw);
    final expectedOffer = local == localIsCaller;
    if ((description.type == CallSessionDescriptionType.offer) !=
        expectedOffer) {
      _reject();
    }
    final prior = local ? token.local : token.remote;
    if (prior != null) {
      if (prior.value == description.value &&
          prior.fingerprint == description.fingerprint) {
        return;
      }
      _reject();
    }
    if (!expectedOffer &&
        (local ? token.remote : token.local)?.type !=
            CallSessionDescriptionType.offer) {
      _reject();
    }
    _validateDescription(description, token.media, local);
    // The callee adopts the remote-created transceiver after remote offer.
    _check(token);
    final native = webrtc.RTCSessionDescription(
      description.value,
      description.type.name,
    );
    if (local) {
      await _connection().setLocalDescription(native);
      token.local = description;
    } else {
      await _connection().setRemoteDescription(native);
      token.remote = description;
    }
    _check(token);
    if (!local) {
      if (_video == null && token.media == CallMediaKind.video) {
        final transceivers = await _connection().getTransceivers();
        _check(token);
        for (final transceiver in transceivers) {
          if (transceiver.receiver.track?.kind == 'video') {
            _video = transceiver;
            transceiver.receiver.track?.enabled = false;
            break;
          }
        }
      }
      await _remoteDescriptionApplied();
      _check(token);
    }
  });

  @override
  Future<void> applyLocal(
    CallVideoNegotiation token,
    CallSessionDescription description,
  ) => _apply(token, description, true);
  @override
  Future<void> applyRemote(
    CallVideoNegotiation token,
    CallSessionDescription description,
  ) => _apply(token, description, false);

  @override
  Future<void> commit(CallVideoNegotiation raw) => _serial(() async {
    final token = _check(raw);
    if (token.local == null || token.remote == null) _reject();
    final state = await _connection().getSignalingState();
    _check(token);
    if (state != webrtc.RTCSignalingState.RTCSignalingStateStable) _reject();
    token.committed = true;
    _receiveOpen = token.media == CallMediaKind.video;
    _remoteTrack?.enabled = _receiveOpen;
    _publish(CallVideoRendererSlot.remote);
  });

  @override
  Future<bool> rollbackPending(CallVideoNegotiation raw) {
    if (raw is! _Negotiation || !identical(_current, raw)) {
      return Future.value(false);
    }
    raw.retired = true;
    _captureIntent = null;
    _invalidateAll();
    unawaited(_owner.retireVideo());
    _closeSendGate();
    _receiveOpen = false;
    _remoteTrack?.enabled = false;
    return _serial(() async {
      if (_closed || !identical(_current, raw)) return false;
      final connection = _connection();
      final state = await connection.getSignalingState();
      if (_closed || !identical(_current, raw)) return false;
      final localOffer = raw.local?.type == CallSessionDescriptionType.offer;
      final remoteOffer = raw.remote?.type == CallSessionDescriptionType.offer;
      if (state == webrtc.RTCSignalingState.RTCSignalingStateHaveLocalOffer &&
          localOffer) {
        await connection.setLocalDescription(
          webrtc.RTCSessionDescription('', 'rollback'),
        );
      } else if (state ==
              webrtc.RTCSignalingState.RTCSignalingStateHaveRemoteOffer &&
          remoteOffer) {
        await connection.setRemoteDescription(
          webrtc.RTCSessionDescription('', 'rollback'),
        );
      } else {
        return false;
      }
      if (_closed || !identical(_current, raw)) return false;
      final stable = await connection.getSignalingState();
      if (_closed ||
          !identical(_current, raw) ||
          stable != webrtc.RTCSignalingState.RTCSignalingStateStable) {
        return false;
      }
      raw.local = null;
      raw.remote = null;
      return true;
    });
  }

  bool _cameraAllowed(_Negotiation token, CallLocalCameraGrant grant) =>
      _currentToken(token) &&
      token.committed &&
      token.media == CallMediaKind.video &&
      grant.foregroundConsent &&
      grant.permissionGranted &&
      grant.videoAgreed &&
      _currentGrant(grant.isCurrent);

  @override
  Future<bool> setLocalCamera(
    CallVideoNegotiation raw,
    CallLocalCameraGrant grant,
  ) async {
    if (raw is! _Negotiation || !_cameraAllowed(raw, grant)) {
      if (identical(_current, raw)) await stopLocalCamera();
      return false;
    }
    await stopLocalCamera();
    if (!_cameraAllowed(raw, grant) || hasPendingCleanup) return false;
    final intent = _owner.beginGrantedCapture(callId);
    if (intent == null) return false;
    _captureIntent = intent;
    final adopted = await _owner.acquireCapture(intent, () async {
      if (!_cameraAllowed(raw, grant)) _reject();
      final stream = await _capture();
      final capture = _Capture(this, stream);
      _captures.add(capture);
      // Disable before any sender attachment, including stale returned capture.
      capture.closeGate();
      return CallVideoResource(
        callId: callId,
        resource: capture,
        dispose: capture.dispose,
      );
    });
    final resource = _owner.captureFor(intent);
    if (!adopted || resource == null) return false;
    final capture = resource.resource as _Capture;
    if (!_cameraAllowed(raw, grant) ||
        capture.tracks.length != 1 ||
        capture.tracks.single.kind != 'video') {
      if (identical(_captureIntent, intent)) await stopLocalCamera();
      return false;
    }
    try {
      return await _serial(() async {
        if (!_cameraAllowed(raw, grant) || _owner.captureFor(intent) == null) {
          return false;
        }
        final video = _video;
        if (video == null) return false;
        capture.sender = video.sender;
        _senderCapture = capture;
        await video.sender.replaceTrack(capture.tracks.single);
        if (!_cameraAllowed(raw, grant) || _owner.captureFor(intent) == null) {
          return false;
        }
        capture.tracks.single.enabled = true;
        _publish(CallVideoRendererSlot.local);
        return _cameraAllowed(raw, grant) && identical(_captureIntent, intent);
      });
    } catch (_) {
      return false;
    } finally {
      if ((!_cameraAllowed(raw, grant) || !capture.tracks.single.enabled) &&
          identical(_captureIntent, intent)) {
        await stopLocalCamera();
      }
    }
  }

  @override
  Future<bool> switchCamera(
    CallVideoNegotiation raw,
    CallLocalCameraGrant grant,
  ) async {
    if (raw is! _Negotiation || !_cameraAllowed(raw, grant)) return false;
    final intent = _captureIntent;
    if (intent == null) return false;
    final capture = _owner.captureFor(intent)?.resource as _Capture?;
    if (capture == null ||
        capture.tracks.length != 1 ||
        capture.tracks.single.kind != 'video') {
      return false;
    }
    bool valid() =>
        _cameraAllowed(raw, grant) &&
        identical(_captureIntent, intent) &&
        identical(_owner.captureFor(intent)?.resource, capture) &&
        capture.tracks.single.enabled;
    try {
      return await _serial(() async {
        if (!valid()) return false;
        // Native bool denotes front/rear facing, not success. Completion is success.
        await webrtc.Helper.switchCamera(capture.tracks.single);
        return valid();
      });
    } catch (_) {
      return false;
    } finally {
      if (!_cameraAllowed(raw, grant) && identical(_captureIntent, intent)) {
        await stopLocalCamera();
      }
    }
  }

  void _closeSendGate() {
    for (final capture in _captures) {
      capture.closeGate();
    }
  }

  @override
  Future<bool> stopLocalCamera() {
    _captureIntent = null;
    _closeSendGate();
    _invalidate(CallVideoRendererSlot.local);
    return _owner.stopCapture();
  }

  /// Called by the adapter's existing onTrack dispatcher. Audio is untouched.
  void onRemoteTrack(webrtc.RTCTrackEvent event) {
    if (event.track.kind != 'video') return;
    event.track.enabled = false;
    final token = _current;
    if (token == null ||
        !_currentToken(token) ||
        token.media != CallMediaKind.video) {
      return;
    }
    _remoteTrack?.enabled = false;
    _remoteTrack = event.track;
    _remoteStream = event.streams.isEmpty ? null : event.streams.first;
    event.track.enabled = _receiveOpen && token.committed;
    unawaited(detachRenderer(CallVideoRendererSlot.remote));
  }

  @override
  Future<CallVideoView?> attachRenderer(
    CallVideoNegotiation raw,
    CallVideoRendererSlot slot,
  ) async {
    if (raw is! _Negotiation ||
        !_currentToken(raw) ||
        !raw.committed ||
        raw.media != CallMediaKind.video) {
      return null;
    }
    final captureIntent = slot == CallVideoRendererSlot.local
        ? _captureIntent
        : null;
    final capture = captureIntent == null
        ? null
        : _owner.captureFor(captureIntent)?.resource as _Capture?;
    final stream = slot == CallVideoRendererSlot.local
        ? capture?.stream
        : _remoteStream;
    final track = slot == CallVideoRendererSlot.local
        ? capture?.tracks.single
        : _remoteTrack;
    if (stream == null ||
        track == null ||
        (slot == CallVideoRendererSlot.remote && !_receiveOpen)) {
      return null;
    }
    _invalidate(slot);
    final intent = _owner.beginRenderer(
      callId,
      slot,
      captureIntent: captureIntent,
    );
    if (intent == null) return null;
    _Renderer? prepared;
    final attached = await _owner.attachRenderer(intent, () async {
      final renderer = _Renderer(_renderer());
      prepared = renderer;
      final resource = CallVideoResource(
        callId: callId,
        resource: renderer,
        dispose: renderer.dispose,
      );
      try {
        await renderer.native.initialize();
        renderer.initialized = true;
        if (!_currentToken(raw)) {
          return CallVideoRendererBinding(
            resource: resource,
            attach: _reject,
            detach: () {},
          );
        }
        await renderer.native.setSrcObject(stream: stream, trackId: track.id);
        if (!_currentToken(raw)) {
          return CallVideoRendererBinding(
            resource: resource,
            attach: _reject,
            detach: () {},
          );
        }
        return CallVideoRendererBinding(
          resource: resource,
          attach: () {
            _check(raw);
            _views[slot] = renderer;
            void changed() {
              if (_currentToken(raw) && identical(_views[slot], renderer)) {
                _publish(slot);
              }
            }

            renderer.native.onResize = changed;
            renderer.native.onFirstFrameRendered = changed;
            _publish(slot);
          },
          detach: () {
            if (identical(_views[slot], renderer)) _invalidate(slot);
          },
        );
      } catch (_) {
        // Transfer failed preparations to the owner so failed release is retained.
        return CallVideoRendererBinding(
          resource: resource,
          attach: _reject,
          detach: () {},
        );
      }
    });
    if (!attached || prepared == null) return null;
    if (!_currentToken(raw)) {
      if (_owner.rendererFor(intent) != null) await _owner.detachRenderer(slot);
      return null;
    }
    final native = prepared!.native;
    final id = native.textureId;
    return id == null
        ? null
        : CallVideoView(
            textureId: id,
            width: native.videoWidth,
            height: native.videoHeight,
          );
  }

  @override
  Future<bool> detachRenderer(CallVideoRendererSlot slot) {
    _invalidate(slot);
    return _owner.detachRenderer(slot);
  }

  @override
  Future<bool> retireVideo() {
    _current?.retired = true;
    _receiveOpen = false;
    _remoteTrack?.enabled = false;
    _captureIntent = null;
    _closeSendGate();
    _invalidateAll();
    return _owner.retireVideo();
  }

  @override
  Future<bool> retryCleanup() async {
    final owned = await _owner.retryCleanup();
    if (_closed) await _disposeSendStream();
    return owned && !_streamDisposeFailed;
  }

  Future<void> _disposeSendStream() {
    final pending = _streamDisposal;
    if (pending != null) return pending;
    final operation = _disposeSendStreamOnce().whenComplete(() {
      _streamDisposal = null;
    });
    _streamDisposal = operation;
    return operation;
  }

  Future<void> _disposeSendStreamOnce() async {
    final stream = _sendStream;
    if (stream == null) return;
    try {
      await stream.dispose();
      _sendStream = null;
      _streamDisposeFailed = false;
    } catch (_) {
      _streamDisposeFailed = true;
    }
  }

  @override
  Future<bool> close() async {
    _closed = true;
    final cleanup = retireVideo();
    await _serial(() async {});
    final owned = await cleanup;
    await _owner.close();
    await _disposeSendStream();
    unawaited(_presentation.close());
    return owned && !hasPendingCleanup;
  }
}

final class _Capture {
  _Capture(this.session, this.stream) : tracks = stream.getTracks();
  final FlutterWebRtcVideoSession session;
  final webrtc.MediaStream stream;
  final List<webrtc.MediaStreamTrack> tracks;
  final Set<webrtc.MediaStreamTrack> stopped = {};
  webrtc.RTCRtpSender? sender;
  bool detached = false;
  bool disposed = false;
  void closeGate() {
    for (final track in tracks) {
      track.enabled = false;
    }
  }

  Future<void> dispose() async {
    closeGate();
    Object? failure;
    if (!detached) {
      try {
        await session._serial(() async {
          if (identical(session._senderCapture, this)) {
            await sender?.replaceTrack(null);
            if (identical(session._senderCapture, this)) {
              session._senderCapture = null;
            }
          }
          detached = true;
        });
      } catch (e) {
        failure = e;
      }
    }
    for (final track in tracks) {
      if (stopped.contains(track)) continue;
      try {
        await track.stop();
        stopped.add(track);
      } catch (e) {
        failure = e;
      }
    }
    if (!disposed) {
      try {
        await stream.dispose();
        disposed = true;
      } catch (e) {
        failure = e;
      }
    }
    if (failure != null) {
      throw const CallEngineException(CallEngineErrorCode.other);
    }
    session._captures.remove(this);
  }
}

final class _Renderer {
  _Renderer(this.native);
  final webrtc.RTCVideoRenderer native;
  bool initialized = false;
  bool unbound = false;
  bool disposed = false;
  Future<void> dispose() async {
    Object? failure;
    if (initialized && !unbound) {
      try {
        await native.setSrcObject();
        unbound = true;
      } catch (e) {
        failure = e;
      }
    }
    if (!disposed) {
      try {
        await native.dispose();
        disposed = true;
        unbound = true;
      } catch (e) {
        failure = e;
      }
    }
    if (failure != null) {
      throw const CallEngineException(CallEngineErrorCode.other);
    }
  }
}
