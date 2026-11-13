import 'dart:async';

import 'package:flutter_app/features/call/domain/call_engine.dart';
import 'package:flutter_app/features/call/domain/call_id.dart';
import 'package:flutter_app/features/call/domain/call_media.dart';
import 'package:flutter_app/features/call/infrastructure/flutter_webrtc_call_engine.dart';
import 'package:flutter_app/features/call/infrastructure/webrtc_types.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc;

const fingerprint =
    'sha-256 00:01:02:03:04:05:06:07:08:09:0A:0B:0C:0D:0E:0F:10:11:12:13:14:15:16:17:18:19:1A:1B:1C:1D:1E:1F';
String sdp({String? video}) =>
    'v=0\r\na=fingerprint:$fingerprint\r\nm=audio 9 UDP/TLS/RTP/SAVPF 111\r\na=sendrecv\r\n${video == null ? '' : 'm=video 9 UDP/TLS/RTP/SAVPF 96\r\na=$video\r\n'}';
CallSessionDescription description(
  CallSessionDescriptionType type, {
  String? video,
}) => CallSessionDescription(
  type: type,
  value: sdp(video: video),
  fingerprint: fingerprint,
);
Future<void> flush() async {
  for (var i = 0; i < 12; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

class Track implements rtc.MediaStreamTrack {
  Track(this.kind);
  @override
  final String kind;
  @override
  String get id => kind;
  @override
  bool enabled = true;
  int stops = 0;
  bool failStop = false;
  @override
  Map<String, dynamic> getSettings() => {'width': 640, 'height': 360};
  @override
  Future<void> stop() async {
    stops++;
    if (failStop) throw StateError('stop');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class StreamFake implements rtc.MediaStream {
  StreamFake(this.tracks);
  final List<rtc.MediaStreamTrack> tracks;
  int disposals = 0;
  Completer<void>? disposeGate;
  bool failDispose = false;
  @override
  List<rtc.MediaStreamTrack> getTracks() => tracks;
  @override
  Future<void> dispose() async {
    disposals++;
    await disposeGate?.future;
    if (failDispose) throw StateError('dispose');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class Sender implements rtc.RTCRtpSender {
  Sender([this.track]);
  @override
  rtc.MediaStreamTrack? track;
  final replacements = <rtc.MediaStreamTrack?>[];
  final streams = <rtc.MediaStream>[];
  @override
  rtc.RTCRtpParameters parameters = rtc.RTCRtpParameters(
    transactionId: 'native-transaction',
    encodings: [rtc.RTCRtpEncoding(ssrc: 42)],
  );
  final parameterWrites = <Map<String, dynamic>>[];
  Completer<bool>? parametersGate;
  bool acceptParameters = true;
  bool failParameters = false;
  void Function()? onParameters;
  @override
  Future<bool> setParameters(rtc.RTCRtpParameters value) async {
    parameterWrites.add(value.toMap());
    // The pinned SDK caches the requested value even when native returns false.
    parameters = value;
    onParameters?.call();
    if (failParameters) throw StateError('parameters');
    return parametersGate == null
        ? acceptParameters
        : await parametersGate!.future;
  }

  @override
  Future<void> setStreams(List<rtc.MediaStream> value) async {
    streams
      ..clear()
      ..addAll(value);
  }

  Completer<void>? gate;
  bool failDetach = false;
  @override
  Future<void> replaceTrack(rtc.MediaStreamTrack? next) async {
    replacements.add(next);
    await gate?.future;
    if (next == null && failDetach) throw StateError('detach');
    track = next;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class Receiver implements rtc.RTCRtpReceiver {
  Receiver(this.track);
  @override
  final rtc.MediaStreamTrack track;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class Transceiver implements rtc.RTCRtpTransceiver {
  Transceiver(String kind) : receiver = Receiver(Track(kind));
  @override
  final Sender sender = Sender();
  @override
  final Receiver receiver;
  rtc.TransceiverDirection direction = rtc.TransceiverDirection.Inactive;
  @override
  Future<void> setDirection(rtc.TransceiverDirection value) async {
    direction = value;
  }

  @override
  Future<rtc.TransceiverDirection> getDirection() async => direction;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class Peer implements rtc.RTCPeerConnection {
  final audio = Sender(Track('audio'));
  final nativeTransceivers = <Transceiver>[];
  final offers = <Map<String, dynamic>>[];
  final local = <rtc.RTCSessionDescription>[];
  final remote = <rtc.RTCSessionDescription>[];
  int closes = 0, restarts = 0, disposals = 0;
  Completer<void>? offerGate;
  bool failRollback = false;
  Future<rtc.RTCSignalingState?> Function()? probe;
  Future<void> Function(rtc.RTCSessionDescription, bool)? beforeApply;
  int probes = 0;
  int statsReads = 0;
  Future<List<rtc.StatsReport>> Function()? stats;
  @override
  Future<List<rtc.StatsReport>> getStats([rtc.MediaStreamTrack? track]) async {
    statsReads++;
    return stats == null ? [] : await stats!();
  }

  @override
  rtc.RTCSignalingState signalingState =
      rtc.RTCSignalingState.RTCSignalingStateStable;
  @override
  void Function(rtc.RTCTrackEvent)? onTrack;
  Transceiver get video =>
      nativeTransceivers.firstWhere((t) => t.receiver.track.kind == 'video');
  @override
  Future<rtc.RTCSignalingState?> getSignalingState() async {
    probes++;
    return probe == null ? signalingState : await probe!();
  }

  @override
  Future<rtc.RTCRtpTransceiver> addTransceiver({
    rtc.MediaStreamTrack? track,
    rtc.RTCRtpMediaType? kind,
    rtc.RTCRtpTransceiverInit? init,
  }) async {
    final t = Transceiver(
      kind == rtc.RTCRtpMediaType.RTCRtpMediaTypeVideo ? 'video' : 'audio',
    );
    t.direction = init?.direction ?? rtc.TransceiverDirection.Inactive;
    nativeTransceivers.add(t);
    return t;
  }

  String nativeSdp() {
    final videos = nativeTransceivers.where(
      (t) => t.receiver.track.kind == 'video',
    );
    return sdp(
      video: videos.isEmpty
          ? null
          : videos.single.direction == rtc.TransceiverDirection.Inactive
          ? 'inactive'
          : 'sendrecv',
    );
  }

  @override
  Future<rtc.RTCSessionDescription> createOffer([
    Map<String, dynamic>? constraints,
  ]) async {
    offers.add(constraints!);
    await offerGate?.future;
    return rtc.RTCSessionDescription(nativeSdp(), 'offer');
  }

  @override
  Future<rtc.RTCSessionDescription> createAnswer([
    Map<String, dynamic>? constraints,
  ]) async => rtc.RTCSessionDescription(nativeSdp(), 'answer');
  @override
  Future<void> setLocalDescription(rtc.RTCSessionDescription d) async {
    await beforeApply?.call(d, true);
    if (d.type == 'rollback' && failRollback) throw StateError('rollback');
    local.add(d);
    signalingState = d.type == 'offer'
        ? rtc.RTCSignalingState.RTCSignalingStateHaveLocalOffer
        : rtc.RTCSignalingState.RTCSignalingStateStable;
  }

  @override
  Future<void> setRemoteDescription(rtc.RTCSessionDescription d) async {
    await beforeApply?.call(d, false);
    if (d.type == 'rollback' && failRollback) throw StateError('rollback');
    remote.add(d);
    if (d.type == 'offer' &&
        d.sdp!.contains('m=video') &&
        !nativeTransceivers.any((t) => t.receiver.track.kind == 'video')) {
      nativeTransceivers.add(Transceiver('video'));
    }
    signalingState = d.type == 'offer'
        ? rtc.RTCSignalingState.RTCSignalingStateHaveRemoteOffer
        : rtc.RTCSignalingState.RTCSignalingStateStable;
  }

  @override
  Future<List<rtc.RTCRtpTransceiver>> getTransceivers() async =>
      nativeTransceivers;
  @override
  Future<rtc.RTCRtpSender> addTrack(
    rtc.MediaStreamTrack track, [
    rtc.MediaStream? stream,
  ]) async {
    audio.track = track;
    return audio;
  }

  @override
  Future<void> addCandidate(rtc.RTCIceCandidate c) async {}
  @override
  Future<void> close() async {
    closes++;
  }

  @override
  Future<void> dispose() async {
    disposals++;
  }

  @override
  Future<void> restartIce() async {
    restarts++;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.isSetter) return null;
    return super.noSuchMethod(invocation);
  }
}

class Renderer implements rtc.RTCVideoRenderer {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
  int binds = 0, disposals = 0;
  Completer<void>? gate;
  bool failDispose = false;
  bool failUnbind = false;
  @override
  Future<void> initialize() async {
    await gate?.future;
  }

  @override
  Future<void> setSrcObject({rtc.MediaStream? stream, String? trackId}) async {
    binds++;
    if (stream == null && failUnbind) throw StateError('unbind');
  }

  @override
  Future<void> dispose() async {
    disposals++;
    if (failDispose) throw StateError('renderer dispose');
  }

  @override
  int get textureId => texture;
  int texture = 42;
  @override
  Function? onResize;
  @override
  Function? onFirstFrameRendered;
  @override
  int get videoWidth => width;
  int width = 640;
  @override
  int get videoHeight => height;
  int height = 480;
}

class Fixture {
  final peer = Peer();
  final track = Track('video');
  late final stream = StreamFake([track]);
  final renderer = Renderer();
  final renderers = <Renderer>[];
  final association = StreamFake([]);
  late FlutterWebRtcCallEngine engine;
  late CallVideoSession session;
  bool current = true;
  int captures = 0;
  Duration qualityNow = Duration.zero;
  final captureResults = <rtc.MediaStream>[];
  Completer<rtc.MediaStream>? captureGate;
  Future<void> start({
    bool caller = true,
    bool bind = true,
    bool captureAudio = false,
    bool nativeVideoCapture = false,
    CallTransportPolicy policy = CallTransportPolicy.all,
  }) async {
    final adapter = FlutterWebRtcPeerConnectionAdapter(
      peerConnectionFactory: (_) async => peer,
      configureAndroidAudioFocus: () async {},
      videoCaptureFactory: nativeVideoCapture
          ? null
          : () async {
              captures++;
              if (captureResults.isNotEmpty) return captureResults.removeAt(0);
              return captureGate == null ? stream : await captureGate!.future;
            },
      videoQualityElapsed: () => qualityNow,
      videoRendererFactory: () =>
          renderers.isEmpty ? renderer : renderers.removeAt(0),
      videoStreamFactory: () async => association,
    );
    engine = FlutterWebRtcCallEngine(adapter: adapter);
    await engine.createConnection(
      CallConnectionConfiguration(
        transportPolicy: policy,
        receiveAudio: true,
        receiveVideo: false,
        captureAudio: captureAudio,
        captureVideo: false,
      ),
    );
    if (bind) {
      session = engine.bindV2Video(
        callId: CallId.parse('11111111-1111-4111-8111-111111111111'),
        localIsCaller: caller,
        wireVersion: CallWireVersion.v2,
        videoEnabled: true,
        canApply: () => current,
      );
    }
  }

  CallVideoNegotiation begin({
    CallMediaKind media = CallMediaKind.video,
    int revision = 1,
    String id = 'selected',
  }) => session.beginNegotiation(
    negotiationId: id,
    mediaRevision: revision,
    media: media,
    canApply: () => current,
  );
  Future<CallVideoNegotiation> committed() async {
    final t = begin();
    await session.applyLocal(t, await session.createOffer(t));
    await session.applyRemote(
      t,
      description(CallSessionDescriptionType.answer, video: 'sendrecv'),
    );
    await session.commit(t);
    return t;
  }

  CallLocalCameraGrant grant({
    bool consent = true,
    bool permission = true,
    bool agreed = true,
    bool Function()? fresh,
  }) => CallLocalCameraGrant(
    foregroundConsent: consent,
    permissionGranted: permission,
    videoAgreed: agreed,
    isCurrent: fresh ?? () => current,
  );
  void preserved() {
    expect(peer.audio.track!.enabled, isTrue);
    expect((peer.audio.track! as Track).stops, 0);
    expect(peer.closes, 0);
    expect(peer.restarts, 0);
    expect(engine.iceGeneration, 0);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('V2-view', () {
    const channel = MethodChannel('FlutterWebRTC.Method');
    void mockSwitch(Future<Object?> Function(MethodCall call) handler) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            if (call.method == 'initialize') return null;
            expect(call.method, 'mediaStreamTrackSwitchCamera');
            return handler(call);
          });
    }

    CallVideoPresentationSource source(Fixture f) {
      expect(f.session, isA<CallVideoPresentationSource>());
      return f.session as CallVideoPresentationSource;
    }

    CallVideoCameraSwitch camera(Fixture f) {
      expect(f.session, isA<CallVideoCameraSwitch>());
      return f.session as CallVideoCameraSwitch;
    }

    Track remote(Fixture f) {
      final track = Track('video');
      f.peer.onTrack!(
        rtc.RTCTrackEvent(
          track: track,
          streams: [
            StreamFake([track]),
          ],
        ),
      );
      return track;
    }

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });
    test('late remote track publishes availability without capture', () async {
      final f = Fixture();
      await f.start();
      final t = await f.committed();
      final p = source(f);
      final events = <CallVideoPresentationState>[];
      final subscription = p.presentationChanges.listen(events.add);
      expect(p.presentationFor(CallVideoRendererSlot.remote).hasTrack, isFalse);
      remote(f);
      await flush();
      expect(events.last.slot, CallVideoRendererSlot.remote);
      expect(events.last.hasTrack, isTrue);
      expect(events.last.view, isNull);
      await f.session.attachRenderer(t, CallVideoRendererSlot.remote);
      expect(
        p.presentationFor(CallVideoRendererSlot.remote).view?.textureId,
        42,
      );
      expect(f.captures, 0);
      f.preserved();
      await subscription.cancel();
    });
    test(
      'metadata updates and old renderer callbacks cannot replace current view',
      () async {
        final f = Fixture();
        await f.start();
        final t = await f.committed();
        final p = source(f);
        remote(f);
        await f.session.attachRenderer(t, CallVideoRendererSlot.remote);
        final oldCallback = f.renderer.onResize;
        expect(oldCallback, isNotNull);
        f.renderer.width = 900;
        f.renderer.onFirstFrameRendered!();
        expect(
          p.presentationFor(CallVideoRendererSlot.remote).view?.width,
          900,
        );
        final next = Renderer()..texture = 43;
        f.renderers.add(next);
        remote(f);
        expect(p.presentationFor(CallVideoRendererSlot.remote).view, isNull);
        await f.session.attachRenderer(t, CallVideoRendererSlot.remote);
        f.renderer.width = 1;
        oldCallback!();
        expect(
          p.presentationFor(CallVideoRendererSlot.remote).view?.textureId,
          43,
        );
        expect(
          p.presentationFor(CallVideoRendererSlot.remote).view?.width,
          640,
        );
        f.preserved();
      },
    );
    test(
      'local stop invalidates preview before cleanup and preserves remote',
      () async {
        final f = Fixture();
        await f.start();
        final t = await f.committed();
        final p = source(f);
        final track = remote(f);
        await f.session.attachRenderer(t, CallVideoRendererSlot.remote);
        final local = Renderer()..texture = 44;
        f.renderers.add(local);
        await f.session.setLocalCamera(t, f.grant());
        await f.session.attachRenderer(t, CallVideoRendererSlot.local);
        f.stream.disposeGate = Completer<void>();
        final stop = f.session.stopLocalCamera();
        expect(
          p.presentationFor(CallVideoRendererSlot.local).hasTrack,
          isFalse,
        );
        expect(p.presentationFor(CallVideoRendererSlot.local).view, isNull);
        expect(
          p.presentationFor(CallVideoRendererSlot.remote).view?.textureId,
          42,
        );
        expect(track.enabled, isTrue);
        f.stream.disposeGate!.complete();
        await stop;
        f.preserved();
      },
    );
    test(
      'retirement invalidates view even when renderer disposal fails',
      () async {
        final f = Fixture();
        await f.start();
        final t = await f.committed();
        final p = source(f);
        remote(f);
        await f.session.attachRenderer(t, CallVideoRendererSlot.remote);
        final callback = f.renderer.onResize!;
        f.renderer.failDispose = true;
        expect(await f.session.retireVideo(), isFalse);
        callback();
        expect(p.presentationFor(CallVideoRendererSlot.remote).view, isNull);
        expect(
          p.presentationFor(CallVideoRendererSlot.remote).hasTrack,
          isFalse,
        );
        expect(f.renderer.onResize, isNull);
        f.preserved();
        f.renderer.failDispose = false;
        await f.session.retryCleanup();
      },
    );
    test(
      'close publishes invalidation and completes presentation stream',
      () async {
        final f = Fixture();
        await f.start();
        final t = await f.committed();
        final p = source(f);
        remote(f);
        await f.session.attachRenderer(t, CallVideoRendererSlot.remote);
        final events = <CallVideoPresentationState>[];
        final done = Completer<void>();
        p.presentationChanges.listen(events.add, onDone: done.complete);
        await f.session.close();
        await done.future;
        expect(
          events.where((e) => e.slot == CallVideoRendererSlot.remote).last.view,
          isNull,
        );
        expect(
          p.presentationFor(CallVideoRendererSlot.remote).hasTrack,
          isFalse,
        );
      },
    );
    test('retired pending renderer never publishes a view', () async {
      final f = Fixture();
      await f.start();
      final t = await f.committed();
      final p = source(f);
      remote(f);
      final events = <CallVideoPresentationState>[];
      final sub = p.presentationChanges.listen(events.add);
      f.renderer.gate = Completer<void>();
      final attaching = f.session.attachRenderer(
        t,
        CallVideoRendererSlot.remote,
      );
      await flush();
      final retiring = f.session.retireVideo();
      f.renderer.gate!.complete();
      expect(await attaching, isNull);
      await retiring;
      expect(events.every((event) => event.view == null), isTrue);
      expect(f.renderer.onResize, isNull);
      f.preserved();
      await sub.cancel();
    });
    test(
      'presentation listener can stop capture without reentrant stream error',
      () async {
        final f = Fixture();
        await f.start();
        final t = await f.committed();
        final p = source(f);
        Future<bool>? stopping;
        final sub = p.presentationChanges.listen((event) {
          if (event.slot == CallVideoRendererSlot.local) {
            stopping = f.session.stopLocalCamera();
          }
        });
        expect(await f.session.setLocalCamera(t, f.grant()), isFalse);
        await stopping;
        expect(
          p.presentationFor(CallVideoRendererSlot.local).hasTrack,
          isFalse,
        );
        expect(f.track.enabled, isFalse);
        await sub.cancel();
        f.preserved();
      },
    );
    test(
      'switch rejects stale foreign and denied grants without native mutation',
      () async {
        final f = Fixture();
        await f.start();
        final t = await f.committed();
        final c = camera(f);
        final other = Fixture();
        await other.start();
        final foreign = await other.committed();
        await f.session.setLocalCamera(t, f.grant());
        var calls = 0;
        mockSwitch((_) async {
          calls++;
          return true;
        });
        for (final grant in [
          f.grant(consent: false),
          f.grant(permission: false),
          f.grant(agreed: false),
          f.grant(fresh: () => false),
        ]) {
          expect(await c.switchCamera(t, grant), isFalse);
        }
        expect(await c.switchCamera(foreign, f.grant()), isFalse);
        await f.session.retireVideo();
        expect(await c.switchCamera(t, f.grant()), isFalse);
        expect(calls, 0);
        f.preserved();
      },
    );
    test(
      'native rear-facing false is completed switch without new capture or signaling',
      () async {
        final f = Fixture();
        await f.start();
        final t = await f.committed();
        final c = camera(f);
        var calls = 0;
        mockSwitch((call) async {
          expect(call.method, 'mediaStreamTrackSwitchCamera');
          calls++;
          return false;
        });
        expect(await c.switchCamera(t, f.grant()), isFalse);
        await f.session.setLocalCamera(t, f.grant());
        final offers = f.peer.offers.length;
        final local = f.peer.local.length;
        final remote = f.peer.remote.length;
        expect(await c.switchCamera(t, f.grant()), isTrue);
        expect(calls, 1);
        expect(f.captures, 1);
        expect(f.track.enabled, isTrue);
        expect(f.peer.offers.length, offers);
        expect(f.peer.local.length, local);
        expect(f.peer.remote.length, remote);
        f.preserved();
      },
    );
    for (final retire in [false, true]) {
      test(
        'pending switch cannot revive ${retire ? "retired" : "stopped"} capture',
        () async {
          final f = Fixture();
          await f.start();
          final t = await f.committed();
          final c = camera(f);
          await f.session.setLocalCamera(t, f.grant());
          final gate = Completer<bool>();
          final entered = Completer<void>();
          mockSwitch((_) {
            entered.complete();
            return gate.future;
          });
          final switching = c.switchCamera(t, f.grant());
          await entered.future;
          final stopping = retire
              ? f.session.retireVideo()
              : f.session.stopLocalCamera();
          expect(f.track.enabled, isFalse);
          gate.complete(true);
          expect(await switching, isFalse);
          await stopping;
          expect(f.track.enabled, isFalse);
          expect(f.captures, 1);
          f.preserved();
        },
      );
    }
    test(
      'grant revoked during switch closes capture; native error preserves authorized capture',
      () async {
        final f = Fixture();
        await f.start();
        final t = await f.committed();
        final c = camera(f);
        await f.session.setLocalCamera(t, f.grant());
        mockSwitch((_) async {
          throw PlatformException(code: 'switch_failed');
        });
        expect(await c.switchCamera(t, f.grant()), isFalse);
        expect(f.track.enabled, isTrue);
        var fresh = true;
        mockSwitch((_) async {
          fresh = false;
          return true;
        });
        expect(await c.switchCamera(t, f.grant(fresh: () => fresh)), isFalse);
        expect(f.track.enabled, isFalse);
        expect(f.track.stops, 1);
        f.preserved();
      },
    );
  });
  test('default-off and v1 bindings reject before video mutation', () async {
    final f = Fixture();
    await f.start(bind: false);
    for (final version in CallWireVersion.values) {
      expect(
        () => f.engine.bindV2Video(
          callId: CallId.parse('11111111-1111-4111-8111-111111111111'),
          localIsCaller: true,
          wireVersion: version,
          canApply: () => true,
        ),
        throwsA(isA<CallEngineException>()),
      );
    }
    expect(
      f.peer.nativeTransceivers.where((t) => t.receiver.track.kind == 'video'),
      isEmpty,
    );
  });
  test(
    'initial v2 audio has no video section; later upgrade does not reuse v1 offer',
    () async {
      final f = Fixture();
      await f.start();
      final initial = await f.engine.createOffer();
      await f.engine.setLocalDescription(initial);
      await f.engine.setRemoteDescription(
        description(CallSessionDescriptionType.answer),
      );
      expect(initial.value, isNot(contains('m=video')));
      final t = await f.committed();
      expect((await f.session.createOffer(t)).value, contains('m=video'));
      expect(f.peer.offers, hasLength(2));
      expect(f.captures, 0);
      f.preserved();
    },
  );
  test('camera requires each fresh grant and committed video', () async {
    final f = Fixture();
    await f.start();
    final uncommitted = f.begin();
    expect(await f.session.setLocalCamera(uncommitted, f.grant()), isFalse);
    await f.session.applyLocal(
      uncommitted,
      await f.session.createOffer(uncommitted),
    );
    await f.session.applyRemote(
      uncommitted,
      description(CallSessionDescriptionType.answer, video: 'sendrecv'),
    );
    await f.session.commit(uncommitted);
    for (final grant in [
      f.grant(consent: false),
      f.grant(permission: false),
      f.grant(agreed: false),
      f.grant(fresh: () => false),
    ]) {
      expect(await f.session.setLocalCamera(uncommitted, grant), isFalse);
    }
    expect(f.captures, 0);
    expect(await f.session.setLocalCamera(uncommitted, f.grant()), isTrue);
    expect(f.track.enabled, isTrue);
    expect(f.peer.video.sender.track, same(f.track));
    f.preserved();
  });
  test(
    'late capture after off cleans its own track without sender attachment',
    () async {
      final f = Fixture();
      await f.start();
      final t = await f.committed();
      f.captureGate = Completer();
      final pending = f.session.setLocalCamera(t, f.grant());
      await flush();
      expect(f.captures, 1);
      await f.session.stopLocalCamera();
      f.captureGate!.complete(f.stream);
      expect(await pending, isFalse);
      expect(f.track.stops, 1);
      expect(f.stream.disposals, 1);
      expect(f.peer.video.sender.replacements, isEmpty);
      f.preserved();
    },
  );
  test('revoked permission after capture never attaches or sends', () async {
    final f = Fixture();
    await f.start();
    final t = await f.committed();
    var granted = true;
    f.captureGate = Completer();
    final pending = f.session.setLocalCamera(t, f.grant(fresh: () => granted));
    await flush();
    granted = false;
    f.captureGate!.complete(f.stream);
    expect(await pending, isFalse);
    expect(f.track.enabled, isFalse);
    expect(f.track.stops, 1);
    expect(f.peer.video.sender.replacements, isEmpty);
    f.preserved();
  });
  test(
    'off during sender replacement closes gate and detaches exact sender',
    () async {
      final f = Fixture();
      await f.start();
      final t = await f.committed();
      f.peer.video.sender.gate = Completer();
      final pending = f.session.setLocalCamera(t, f.grant());
      await flush();
      expect(f.track.enabled, isFalse);
      final stop = f.session.stopLocalCamera();
      f.peer.video.sender.gate!.complete();
      expect(await pending, isFalse);
      expect(await stop, isTrue);
      expect(f.peer.video.sender.track, isNull);
      expect(f.track.stops, 1);
      f.preserved();
    },
  );
  test(
    'capture cleanup retries failed stages without repeating successful stop',
    () async {
      final f = Fixture();
      await f.start();
      final t = await f.committed();
      expect(await f.session.setLocalCamera(t, f.grant()), isTrue);
      f.stream.failDispose = true;
      expect(await f.session.stopLocalCamera(), isFalse);
      expect(f.session.hasPendingCleanup, isTrue);
      expect(f.track.stops, 1);
      f.stream.failDispose = false;
      expect(await f.session.retryCleanup(), isTrue);
      expect(f.track.stops, 1);
      expect(f.stream.disposals, 2);
      expect(f.session.hasPendingCleanup, isFalse);
      f.preserved();
    },
  );
  test('local off preserves committed remote video reception', () async {
    final f = Fixture();
    await f.start();
    final t = await f.committed();
    final remote = Track('video');
    f.peer.onTrack!(
      rtc.RTCTrackEvent(
        track: remote,
        streams: [
          StreamFake([remote]),
        ],
      ),
    );
    expect(remote.enabled, isTrue);
    await f.session.setLocalCamera(t, f.grant());
    await f.session.stopLocalCamera();
    expect(remote.enabled, isTrue);
    expect(remote.stops, 0);
    expect(
      await f.session.attachRenderer(t, CallVideoRendererSlot.remote),
      isA<CallVideoView>(),
    );
    f.preserved();
  });
  test(
    'renderer pending during video retirement is never published and is disposed',
    () async {
      final f = Fixture();
      await f.start();
      final t = await f.committed();
      await f.session.setLocalCamera(t, f.grant());
      f.renderer.gate = Completer();
      final pending = f.session.attachRenderer(t, CallVideoRendererSlot.local);
      await flush();
      await f.session.retireVideo();
      f.renderer.gate!.complete();
      expect(await pending, isNull);
      expect(f.renderer.disposals, 1);
      f.preserved();
    },
  );
  test('renderer disposal failure remains retryable', () async {
    final f = Fixture();
    await f.start();
    final t = await f.committed();
    await f.session.setLocalCamera(t, f.grant());
    expect(
      (await f.session.attachRenderer(
        t,
        CallVideoRendererSlot.local,
      ))!.textureId,
      42,
    );
    f.renderer.failDispose = true;
    expect(
      await f.session.detachRenderer(CallVideoRendererSlot.local),
      isFalse,
    );
    expect(f.session.hasPendingCleanup, isTrue);
    f.renderer.failDispose = false;
    expect(await f.session.retryCleanup(), isTrue);
    expect(f.renderer.disposals, 2);
    f.preserved();
  });
  group('SDP-C close cancels state reads', () {
    Future<Object?> runProbe(
      Fixture f,
      CallVideoNegotiation token,
      String operation,
    ) async {
      try {
        if (operation == 'commit') {
          await f.session.commit(token);
          return null;
        }
        if (operation.startsWith('rollback')) {
          return await f.session.rollbackPending(token);
        }
        return await (f.session as CallVideoSdpReconciler).reconcilePending(
          token,
          canApply: () => true,
        );
      } catch (error) {
        return error;
      }
    }

    for (final operation in [
      'commit',
      'rollback-first',
      'rollback-final',
      'reconcile-first',
      'reconcile-final',
    ]) {
      for (final lateError in [false, true]) {
        test('$operation closes before probe; lateError=$lateError', () async {
          final f = Fixture();
          await f.start();
          final token = operation == 'commit' ? await f.committed() : f.begin();
          if (operation == 'commit') {
            await f.session.setLocalCamera(token, f.grant());
            await f.session.attachRenderer(token, CallVideoRendererSlot.local);
          } else {
            await f.session.applyLocal(
              token,
              await f.session.createOffer(token),
            );
          }
          final entered = Completer<void>();
          final native = Completer<rtc.RTCSignalingState?>();
          var reads = 0;
          f.peer.probe = () async {
            reads++;
            if (reads == (operation.endsWith('final') ? 2 : 1)) {
              entered.complete();
              return await native.future;
            }
            return f.peer.signalingState;
          };
          var settled = false;
          final result = runProbe(f, token, operation).then((value) {
            settled = true;
            return value;
          });
          await entered.future;
          final queued = expectLater(
            f.session.commit(token),
            throwsA(isA<CallEngineException>()),
          );
          var closed = false;
          final closing = f.session.close().then((value) {
            closed = true;
            return value;
          });
          final closingAgain = f.session.close();
          final localCount = f.peer.local.length;
          final remoteCount = f.peer.remote.length;
          try {
            await flush();
            expect(
              closed,
              isTrue,
              reason: 'close must not await a native read',
            );
            expect(settled, isTrue);
            expect(native.isCompleted, isFalse);
            expect(await closing, isTrue);
            expect(await closingAgain, isTrue);
            expect(
              await result,
              operation == 'commit'
                  ? isA<CallEngineException>()
                  : operation.startsWith('rollback')
                  ? isFalse
                  : CallVideoSdpReconciliationOutcome.unreconciled,
            );
          } finally {
            if (lateError) {
              native.completeError(StateError('late native probe'));
            } else {
              native.complete(rtc.RTCSignalingState.RTCSignalingStateStable);
            }
            await result;
            await closing;
            await closingAgain;
            await queued;
            await flush();
          }
          expect(f.peer.local, hasLength(localCount));
          expect(f.peer.remote, hasLength(remoteCount));
          if (operation == 'commit') {
            expect(f.track.enabled, isFalse);
            expect(f.track.stops, 1);
            expect(f.renderer.disposals, 1);
          }
          expect(f.session.hasPendingCleanup, isFalse);
          f.preserved();
        });
      }
    }

    for (final caller in [true, false]) {
      test('native rollback mutation still drains caller=$caller', () async {
        final f = Fixture();
        await f.start(caller: caller);
        final token = f.begin();
        if (caller) {
          await f.session.applyLocal(token, await f.session.createOffer(token));
        } else {
          await f.session.applyRemote(
            token,
            description(CallSessionDescriptionType.offer, video: 'sendrecv'),
          );
        }
        final entered = Completer<void>();
        final mutation = Completer<void>();
        f.peer.beforeApply = (description, _) async {
          if (description.type == 'rollback') {
            entered.complete();
            await mutation.future;
          }
        };
        final result = runProbe(f, token, 'reconcile-first');
        await entered.future;
        var closed = false;
        final closing = f.session.close().then((value) {
          closed = true;
          return value;
        });
        try {
          await flush();
          expect(closed, isFalse);
        } finally {
          mutation.complete();
          await closing;
        }
        expect(await result, CallVideoSdpReconciliationOutcome.unreconciled);
        expect((caller ? f.peer.local : f.peer.remote).last.type, 'rollback');
        f.preserved();
      });
    }

    for (final operation in ['commit', 'rollback-first']) {
      test('$operation preserves native errors before close', () async {
        final f = Fixture();
        await f.start();
        final token = operation == 'commit' ? await f.committed() : f.begin();
        if (operation != 'commit') {
          await f.session.applyLocal(token, await f.session.createOffer(token));
        }
        f.peer.probe = () async => throw StateError('native probe');
        expect(await runProbe(f, token, operation), isA<StateError>());
        await f.session.close();
        f.preserved();
      });
    }
  });
  group('SDP reconciliation', () {
    Future<CallVideoSdpReconciliationOutcome> reconcile(
      Fixture f,
      CallVideoNegotiation token, {
      bool Function()? canApply,
    }) => (f.session as CallVideoSdpReconciler).reconcilePending(
      token,
      canApply: canApply ?? () => true,
    );

    for (final answered in [false, true]) {
      test(
        'native stable proof with answered=$answered preserves audio',
        () async {
          final f = Fixture();
          await f.start();
          final token = answered ? await f.committed() : f.begin();
          if (answered) await f.session.setLocalCamera(token, f.grant());
          final probes = f.peer.probes;
          final result = reconcile(f, token);
          if (answered) expect(f.track.enabled, isFalse);
          expect(await result, CallVideoSdpReconciliationOutcome.alreadyStable);
          expect(f.peer.probes, probes + 1);
          expect(f.peer.local.where((d) => d.type == 'rollback'), isEmpty);
          expect(f.peer.remote.where((d) => d.type == 'rollback'), isEmpty);
          final repair = f.begin(media: CallMediaKind.audio, id: 'repair');
          await f.session.createOffer(repair);
          f.preserved();
        },
      );
    }

    for (final caller in [true, false]) {
      test(
        'owned pending offer caller=$caller proves stable after rollback',
        () async {
          final f = Fixture();
          await f.start(caller: caller);
          final token = f.begin();
          if (caller) {
            await f.session.applyLocal(
              token,
              await f.session.createOffer(token),
            );
          } else {
            await f.session.applyRemote(
              token,
              description(CallSessionDescriptionType.offer, video: 'sendrecv'),
            );
          }
          final probes = f.peer.probes;
          expect(
            await reconcile(f, token),
            CallVideoSdpReconciliationOutcome.rolledBack,
          );
          expect(f.peer.probes, probes + 2);
          expect((caller ? f.peer.local : f.peer.remote).last.type, 'rollback');
          f.begin(media: CallMediaKind.audio, id: 'repair');
          f.preserved();
        },
      );
      test(
        'retired pending native apply caller=$caller settles before reconciliation',
        () async {
          final f = Fixture();
          await f.start(caller: caller);
          final token = f.begin();
          final entered = Completer<void>();
          final gate = Completer<void>();
          f.peer.beforeApply = (description, _) async {
            if (description.type != 'rollback') {
              entered.complete();
              await gate.future;
            }
          };
          final pending = caller
              ? f.session.applyLocal(token, await f.session.createOffer(token))
              : f.session.applyRemote(
                  token,
                  description(
                    CallSessionDescriptionType.offer,
                    video: 'sendrecv',
                  ),
                );
          final stale = expectLater(
            pending,
            throwsA(isA<CallEngineException>()),
          );
          await entered.future;
          final result = reconcile(f, token);
          await flush();
          expect(f.peer.probes, 0);
          gate.complete();
          await stale;
          expect(await result, CallVideoSdpReconciliationOutcome.rolledBack);
          expect((caller ? f.peer.local : f.peer.remote).map((d) => d.type), [
            'offer',
            'rollback',
          ]);
          f.begin(media: CallMediaKind.audio, id: 'repair');
          f.preserved();
        },
      );
    }

    for (final boundary in ['probe', 'rollback', 'stable-recheck']) {
      test('expired budget during $boundary cannot authorize repair', () async {
        final f = Fixture();
        await f.start();
        final token = f.begin();
        await f.session.applyLocal(token, await f.session.createOffer(token));
        final entered = Completer<void>();
        final gate = Completer<void>();
        var allowed = true;
        var probeCount = 0;
        f.peer.probe = () async {
          probeCount++;
          if ((boundary == 'probe' && probeCount == 1) ||
              (boundary == 'stable-recheck' && probeCount == 2)) {
            entered.complete();
            await gate.future;
          }
          return f.peer.signalingState;
        };
        f.peer.beforeApply = (description, _) async {
          if (boundary == 'rollback' && description.type == 'rollback') {
            entered.complete();
            await gate.future;
          }
        };
        final result = reconcile(f, token, canApply: () => allowed);
        // A missing capability must fail causally rather than hang the fixture.
        await Future.any([entered.future, result.then((_) {})]);
        expect(entered.isCompleted, isTrue);
        allowed = false;
        gate.complete();
        expect(await result, CallVideoSdpReconciliationOutcome.unreconciled);
        expect(
          () => f.begin(media: CallMediaKind.audio, id: 'repair'),
          throwsA(isA<CallEngineException>()),
        );
        f.preserved();
      });
    }

    for (final invalid in ['false', 'throws', 'replaced']) {
      test(
        'invalid $invalid admission cannot probe or retire another owner',
        () async {
          final f = Fixture();
          await f.start();
          final token = f.begin();
          if (invalid == 'replaced') f.begin(id: 'replacement');
          expect(
            await reconcile(
              f,
              token,
              canApply: () {
                if (invalid == 'throws') throw StateError('expired');
                return invalid != 'false';
              },
            ),
            CallVideoSdpReconciliationOutcome.unreconciled,
          );
          expect(f.peer.probes, 0);
          f.preserved();
        },
      );
    }

    for (final failure in [
      'probe-error',
      'null',
      'unowned',
      'rollback-error',
      'not-stable',
    ]) {
      test('$failure remains unreconciled and preserves audio', () async {
        final f = Fixture();
        await f.start();
        final token = f.begin();
        if (failure == 'rollback-error' || failure == 'not-stable') {
          await f.session.applyLocal(token, await f.session.createOffer(token));
        }
        if (failure == 'probe-error') {
          f.peer.probe = () async => throw StateError('probe');
        }
        if (failure == 'null') f.peer.probe = () async => null;
        if (failure == 'unowned') {
          f.peer.signalingState =
              rtc.RTCSignalingState.RTCSignalingStateHaveRemoteOffer;
        }
        if (failure == 'rollback-error') f.peer.failRollback = true;
        if (failure == 'not-stable') {
          f.peer.probe = () async =>
              rtc.RTCSignalingState.RTCSignalingStateHaveLocalOffer;
        }
        expect(
          await reconcile(f, token),
          CallVideoSdpReconciliationOutcome.unreconciled,
        );
        f.preserved();
      });
    }

    for (final invalidation in ['session', 'close']) {
      test(
        '$invalidation during stable probe cannot certify retired token',
        () async {
          final f = Fixture();
          await f.start();
          final token = f.begin();
          final entered = Completer<void>();
          final gate = Completer<void>();
          f.peer.probe = () async {
            entered.complete();
            await gate.future;
            return rtc.RTCSignalingState.RTCSignalingStateStable;
          };
          final result = reconcile(f, token);
          await Future.any([entered.future, result.then((_) {})]);
          expect(entered.isCompleted, isTrue);
          Future<bool>? closing;
          if (invalidation == 'close') {
            closing = f.session.close();
          } else {
            f.current = false;
          }
          gate.complete();
          expect(await result, CallVideoSdpReconciliationOutcome.unreconciled);
          await closing;
          f.preserved();
        },
      );
    }
  });
  test(
    'caller offer rollback preserves audio and does not restart ICE',
    () async {
      final f = Fixture();
      await f.start();
      final t = f.begin();
      await f.session.applyLocal(t, await f.session.createOffer(t));
      expect(await f.session.rollbackPending(t), isTrue);
      expect(f.peer.local.last.type, 'rollback');
      f.preserved();
      final repair = f.begin(
        media: CallMediaKind.audio,
        revision: 1,
        id: 'repair',
      );
      expect(
        (await f.session.createOffer(repair)).value,
        contains('a=inactive'),
      );
      f.preserved();
    },
  );
  test(
    'callee answers and can roll back only its actual remote offer',
    () async {
      final f = Fixture();
      await f.start(caller: false);
      final t = f.begin();
      await expectLater(
        f.session.createOffer(t),
        throwsA(isA<CallEngineException>()),
      );
      await f.session.applyRemote(
        t,
        description(CallSessionDescriptionType.offer, video: 'sendrecv'),
      );
      expect(await f.session.rollbackPending(t), isTrue);
      expect(f.peer.remote.last.type, 'rollback');
      f.preserved();
    },
  );
  test(
    'stable answer cannot be rolled back; failed native rollback leaves audio',
    () async {
      final f = Fixture();
      await f.start();
      final t = await f.committed();
      expect(await f.session.rollbackPending(t), isFalse);
      expect(f.peer.local.where((d) => d.type == 'rollback'), isEmpty);
      final next = f.begin(revision: 2, id: 'next');
      await f.session.applyLocal(next, await f.session.createOffer(next));
      f.peer.failRollback = true;
      await expectLater(f.session.rollbackPending(next), throwsStateError);
      f.preserved();
    },
  );
  test('stale native SDP completion cannot be returned or applied', () async {
    final f = Fixture();
    await f.start();
    final t = f.begin();
    f.peer.offerGate = Completer();
    final pending = f.session.createOffer(t);
    final result = expectLater(pending, throwsA(isA<CallEngineException>()));
    await flush();
    f.current = false;
    f.peer.offerGate!.complete();
    await result;
    expect(f.peer.local, isEmpty);
    expect(f.captures, 0);
    f.preserved();
  });
  test(
    'v1 remains strict while audio downgrade permits only inactive video',
    () async {
      final f = Fixture();
      await f.start();
      await expectLater(
        Future.sync(
          () => f.engine.setRemoteDescription(
            description(CallSessionDescriptionType.offer, video: 'inactive'),
          ),
        ),
        throwsA(isA<CallEngineException>()),
      );
      final t = await f.committed();
      await f.session.retireVideo();
      final audio = f.begin(
        media: CallMediaKind.audio,
        revision: 2,
        id: 'audio',
      );
      await f.session.applyLocal(audio, await f.session.createOffer(audio));
      await expectLater(
        f.session.applyRemote(
          audio,
          description(CallSessionDescriptionType.answer, video: 'sendrecv'),
        ),
        throwsA(isA<CallEngineException>()),
      );
      await f.session.applyRemote(
        audio,
        description(CallSessionDescriptionType.answer, video: 'inactive'),
      );
      await f.session.commit(audio);
      expect(await f.session.setLocalCamera(audio, f.grant()), isFalse);
      await expectLater(
        f.session.createOffer(t),
        throwsA(isA<CallEngineException>()),
      );
      f.preserved();
    },
  );
  test('video SDP retains fingerprint authentication', () async {
    final f = Fixture();
    await f.start(caller: false);
    final t = f.begin();
    await expectLater(
      f.session.applyRemote(
        t,
        CallSessionDescription(
          type: CallSessionDescriptionType.offer,
          value: sdp(video: 'sendrecv'),
          fingerprint: fingerprint.replaceFirst('00:', 'FF:'),
        ),
      ),
      throwsA(
        isA<CallEngineException>().having(
          (e) => e.code,
          'code',
          CallEngineErrorCode.fingerprintMismatch,
        ),
      ),
    );
    expect(f.peer.remote, isEmpty);
    f.preserved();
  });
  test(
    'callee establishes a stream association before answering without capture',
    () async {
      final f = Fixture();
      await f.start(caller: false);
      final t = f.begin();
      await f.session.applyRemote(
        t,
        description(CallSessionDescriptionType.offer, video: 'sendrecv'),
      );
      final answer = await f.session.createAnswer(t);
      expect(f.peer.video.sender.streams, hasLength(1));
      expect(f.peer.video.sender.streams.single.getTracks(), isEmpty);
      await f.session.applyLocal(t, answer);
      await f.session.commit(t);
      expect(f.captures, 0);
      f.preserved();
    },
  );
  test(
    'renderer successful disposal discharges a failed unbind on retry',
    () async {
      final f = Fixture();
      await f.start();
      final t = await f.committed();
      await f.session.setLocalCamera(t, f.grant());
      await f.session.attachRenderer(t, CallVideoRendererSlot.local);
      f.renderer.failUnbind = true;
      expect(
        await f.session.detachRenderer(CallVideoRendererSlot.local),
        isFalse,
      );
      expect(await f.session.retryCleanup(), isTrue);
      expect(f.renderer.disposals, 1);
      f.preserved();
    },
  );
  test(
    'downgrade releases capture before audio SDP and never captures again',
    () async {
      final f = Fixture();
      await f.start();
      final t = await f.committed();
      await f.session.setLocalCamera(t, f.grant());
      final audio = f.begin(
        media: CallMediaKind.audio,
        revision: 2,
        id: 'audio',
      );
      expect(f.track.enabled, isFalse);
      await f.session.createOffer(audio);
      expect(f.track.stops, 1);
      expect(f.peer.video.sender.track, isNull);
      expect(f.captures, 1);
      f.preserved();
    },
  );
  test(
    'mixed capture is rejected and every acquired track is released',
    () async {
      final f = Fixture();
      await f.start();
      final t = await f.committed();
      final unexpected = Track('audio');
      f.stream.tracks.add(unexpected);
      expect(await f.session.setLocalCamera(t, f.grant()), isFalse);
      expect(f.track.stops, 1);
      expect(unexpected.stops, 1);
      expect(f.peer.video.sender.track, isNull);
      f.preserved();
    },
  );
  test('relay-only video SDP rejects local host candidate disclosure', () async {
    final f = Fixture();
    await f.start(policy: CallTransportPolicy.relayOnly);
    final t = f.begin();
    final unsafe = CallSessionDescription(
      type: CallSessionDescriptionType.offer,
      value:
          '${sdp(video: 'sendrecv')}a=candidate:1 1 UDP 1 192.0.2.1 9 typ host\r\n',
      fingerprint: fingerprint,
    );
    await expectLater(
      f.session.applyLocal(t, unsafe),
      throwsA(
        isA<CallEngineException>().having(
          (e) => e.code,
          'code',
          CallEngineErrorCode.relayPolicyViolation,
        ),
      ),
    );
    expect(f.peer.local, isEmpty);
    f.preserved();
  });
  test(
    'overlapping video close and cleanup coalesce association stream disposal',
    () async {
      final f = Fixture();
      await f.start();
      await f.committed();
      f.association.disposeGate = Completer();
      final first = f.session.close();
      await flush();
      final second = f.session.retryCleanup();
      await flush();
      expect(f.association.disposals, 1);
      f.association.disposeGate!.complete();
      expect(await first, isTrue);
      expect(await second, isTrue);
      expect(f.association.disposals, 1);
      f.preserved();
    },
  );
  test(
    'whole engine close releases audio and peer despite persistent video cleanup failure',
    () async {
      const channel = MethodChannel('FlutterWebRTC.Method');
      const events = MethodChannel('FlutterWebRTC.Event');
      final calls = <MethodCall>[];
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(events, (_) async => null);
      addTearDown(() => messenger.setMockMethodCallHandler(events, null));
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        if (call.method == 'getUserMedia') {
          return <String, Object>{
            'streamId': 'microphone-stream',
            'audioTracks': [
              <String, Object>{
                'id': 'microphone',
                'label': 'microphone',
                'kind': 'audio',
                'enabled': true,
              },
            ],
            'videoTracks': <Object>[],
          };
        }
        return null;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      final f = Fixture();
      await f.start(captureAudio: true);
      final token = await f.committed();
      expect(await f.session.setLocalCamera(token, f.grant()), isTrue);
      expect(
        await f.session.attachRenderer(token, CallVideoRendererSlot.local),
        isNotNull,
      );
      f.renderer.failDispose = true;
      await expectLater(
        f.engine.close(),
        throwsA(
          isA<WebRtcAdapterException>().having(
            (error) => error.reason,
            'reason',
            WebRtcFailureReason.other,
          ),
        ),
      );
      expect(f.session.hasPendingCleanup, isTrue);
      expect(
        calls.where(
          (call) =>
              call.method == 'trackDispose' &&
              call.arguments['trackId'] == 'microphone',
        ),
        hasLength(1),
      );
      expect(
        calls.where(
          (call) =>
              call.method == 'streamDispose' &&
              call.arguments['streamId'] == 'microphone-stream',
        ),
        hasLength(1),
      );
      expect(f.peer.closes, 1);
      expect(f.peer.disposals, 1);
      expect(f.track.stops, 1);
      expect(f.stream.disposals, 1);
      f.renderer.failDispose = false;
      await f.engine.close();
      expect(f.session.hasPendingCleanup, isFalse);
      expect(
        calls.where(
          (call) =>
              call.method == 'trackDispose' &&
              call.arguments['trackId'] == 'microphone',
        ),
        hasLength(1),
      );
      expect(
        calls.where(
          (call) =>
              call.method == 'streamDispose' &&
              call.arguments['streamId'] == 'microphone-stream',
        ),
        hasLength(1),
      );
      expect(f.peer.closes, 1);
      expect(f.peer.disposals, 1);
      expect(f.track.stops, 1);
      expect(f.stream.disposals, 1);
    },
  );
}
