import 'dart:async';

import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/features/call/application/call_audio_controller.dart';
import 'package:flutter_app/features/call/application/call_audio_negotiation_preparer.dart';
import 'package:flutter_app/features/call/application/call_cleanup_coordinator.dart';
import 'package:flutter_app/features/call/application/call_coordinator.dart';
import 'package:flutter_app/features/call/application/call_history_projector.dart';
import 'package:flutter_app/features/call/application/call_negotiation_effect_executor.dart';
import 'package:flutter_app/features/call/application/call_negotiation_material_store.dart';
import 'package:flutter_app/features/call/data/call_history_repository.dart';
import 'package:flutter_app/features/call/domain/call_end_reason.dart';
import 'package:flutter_app/features/call/domain/call_engine.dart';
import 'package:flutter_app/features/call/domain/call_event.dart';
import 'package:flutter_app/features/call/domain/call_id.dart';
import 'package:flutter_app/features/call/domain/call_session_snapshot.dart';
import 'package:flutter_app/features/call/domain/call_state.dart';
import 'package:flutter_app/features/call/infrastructure/bridge_call_ice_server_provider.dart';
import 'package:flutter_app/features/call/infrastructure/flutter_webrtc_call_engine.dart';
import 'package:flutter_app/features/call/infrastructure/webrtc_types.dart';
import 'package:flutter_test/flutter_test.dart';

final _epoch = DateTime.utc(2030);
final _first = CallId.parse('11111111-1111-4111-8111-111111111111');
final _next = CallId.parse('22222222-2222-4222-8222-222222222222');
const _outage = <String, dynamic>{
  'ok': false,
  'errorCode': 'TURN_CREDENTIALS_UNAVAILABLE',
};
final _stun = CallIceServer(
  urls: ['stun:approved.invalid:3478'],
  expiresAt: _epoch.add(const Duration(hours: 1)),
);
Map<String, dynamic> _valid(DateTime now) => {
  'ok': true,
  'urls': ['turn:relay.invalid:3478?transport=udp'],
  'username': 'fixture-user',
  'password': 'fixture-password',
  'expiresAtMs': now.add(const Duration(minutes: 5)).millisecondsSinceEpoch,
};

void main() {
  for (final policy in CallTransportPolicy.values) {
    _testClock('valid TURN preserves $policy and approved STUN', (time) async {
      final h = _Harness(time, policy: policy)
        ..response = Future.value(_valid(_epoch));
      h.start();
      await time.settle();
      final b = h.current;
      expect(
        b.native.configurations.single.iceTransportPolicy,
        policy == CallTransportPolicy.all
            ? WebRtcIceTransportPolicy.all
            : WebRtcIceTransportPolicy.relayOnly,
      );
      expect(b.native.servers.first, same(_stun));
      expect(b.native.servers.last.containsTurnUrl, isTrue);
      // This models a selected TURN route when direct connectivity is absent.
      // Native route establishment itself requires the device campaign.
      b.native.connect(WebRtcTransportClass.turnUdp);
      await time.settle();
      expect(h.coordinator.activeSession?.state, CallState.connected);
      h.close();
      await time.settle();
    });

    for (final timeout in [false, true]) {
      _testClock(
        '$policy credential ${timeout ? 'timeout' : 'outage'} policy and setup deadline',
        (time) async {
          final pending = Completer<Map<String, dynamic>>();
          final h = _Harness(time, policy: policy)
            ..response = timeout ? pending.future : Future.value(_outage);
          h.start();
          await time.settle();
          final b = h.current;
          if (timeout) {
            await time.elapse(const Duration(milliseconds: 4999));
            expect(b.native.configurations, isEmpty);
            await time.elapse(const Duration(milliseconds: 1));
          }
          if (policy == CallTransportPolicy.relayOnly) {
            expect(b.native.configurations, isEmpty);
            expect(h.coordinator.activeSession, isNull);
          } else {
            expect(b.native.configurations, hasLength(1));
            expect(b.native.servers, [_stun]);
            expect(h.coordinator.activeSession?.state, CallState.negotiating);
            // The original 30s setup deadline is not reset by the credential wait.
            await time.elapse(const Duration(seconds: 30) - time.elapsed);
            await time.settle();
            expect(h.coordinator.activeSession, isNull);
            expect(
              h.coordinator.lastSnapshot?.endReason,
              CallEndReason.mediaFailed,
            );
          }
          expect(b.engine.isClosed, isTrue);
          pending.complete(_valid(h.now()));
          await time.settle();
          expect(
            b.native.configurations,
            hasLength(policy == CallTransportPolicy.all ? 1 : 0),
          );
          h.close();
          await time.settle();
        },
      );
    }
  }

  for (final failure in [
    'TURN_CREDENTIALS_UNAUTHORIZED',
    'TURN_CREDENTIALS_REJECTED',
    'TURN_CREDENTIALS_INVALID_RESPONSE',
    'TURN_CREDENTIALS_UNSUPPORTED',
    'UNKNOWN',
  ]) {
    _testClock('normal setup fails closed for $failure', (time) async {
      final h = _Harness(time)
        ..response = Future.value({'ok': false, 'errorCode': failure});
      h.start();
      await time.settle();
      expect(h.current.native.configurations, isEmpty);
      expect(h.coordinator.activeSession, isNull);
      h.close();
      await time.settle();
    });
  }

  for (final bad in [
    {..._valid(_epoch), 'expiresAtMs': _epoch.millisecondsSinceEpoch},
    {
      ..._valid(_epoch),
      'urls': ['turn:'],
    },
    {..._valid(_epoch), 'username': 'malformed\nprivate'},
  ]) {
    _testClock(
      'invalid bundle is never used: ${bad.keys.length}/${bad['urls']}',
      (time) async {
        final h = _Harness(time)..response = Future.value(bad);
        h.start();
        await time.settle();
        expect(h.current.native.configurations, isEmpty);
        expect(h.coordinator.activeSession, isNull);
        h.close();
        await time.settle();
      },
    );
  }

  for (final afterTimeout in [false, true]) {
    for (final completionFails in [false, true]) {
      _testClock(
        'late ${completionFails ? 'error' : 'success'} after hangup/replacement (timeout=$afterTimeout)',
        (time) async {
          final pending = Completer<Map<String, dynamic>>();
          final h = _Harness(time)..response = pending.future;
          h.start();
          await time.settle();
          final old = h.current;
          if (afterTimeout) await time.elapse(const Duration(seconds: 5));
          h.hangup();
          await time.settle();
          expect(old.engine.isClosed, isTrue);
          h.policy = CallTransportPolicy.relayOnly;
          h.response = Future.value(_valid(h.now()));
          h.start(id: _next);
          await time.settle();
          final next = h.current;
          if (completionFails) {
            pending.completeError(StateError('private'));
          } else {
            pending.complete(_valid(h.now()));
          }
          await time.settle();
          expect(h.coordinator.activeSession?.callId, _next);
          expect(
            next.native.configurations.single.iceTransportPolicy,
            WebRtcIceTransportPolicy.relayOnly,
          );
          expect(old.native.configurations, hasLength(afterTimeout ? 1 : 0));
          expect(next.native.configurations, hasLength(1));
          expect(next.native.restarts, 0);
          h.close();
          await time.settle();
        },
      );
    }
  }

  _testClock(
    'late TURN does not disrupt direct media; a later restart fetches fresh TURN with frozen policy',
    (time) async {
      final pending = Completer<Map<String, dynamic>>();
      final h = _Harness(time)..response = pending.future;
      h.start();
      await time.settle();
      await time.elapse(const Duration(seconds: 5));
      final b = h.current;
      b.native.connect(WebRtcTransportClass.direct);
      await time.settle();
      expect(h.coordinator.activeSession?.state, CallState.connected);
      pending.complete(_valid(h.now()));
      await time.settle();
      expect(b.native.restarts, 0);
      expect(b.native.servers, [_stun]);
      expect(h.fetches, 1);
      h.policy = CallTransportPolicy
          .relayOnly; // Preference change applies to a future call.
      h.response = Future.value(_valid(h.now()));
      b.native.disconnect();
      await time.settle();
      expect(b.native.restarts, 1);
      expect(h.fetches, 2);
      expect(b.native.servers.last.containsTurnUrl, isTrue);
      expect(
        b.native.configurations.single.iceTransportPolicy,
        WebRtcIceTransportPolicy.all,
      );
      b.native.connect(WebRtcTransportClass.turnUdp);
      await time.settle();
      expect(h.coordinator.activeSession?.state, CallState.connected);
      h.close();
      await time.settle();
    },
  );

  for (final policy in CallTransportPolicy.values) {
    _testClock(
      'restart reuses only current-call unexpired TURN under $policy',
      (time) async {
        final h = _Harness(time, policy: policy)
          ..response = Future.value(_valid(_epoch));
        h.start();
        await time.settle();
        final b = h.current;
        final original = b.native.servers.last;
        b.native.connect(WebRtcTransportClass.turnUdp);
        await time.settle();
        h.response = Future.value(_outage);
        b.native.disconnect();
        await time.settle();
        expect(b.native.restarts, 1);
        expect(b.native.servers.last, same(original));
        expect(
          b.native.configurations.single.iceTransportPolicy,
          policy == CallTransportPolicy.all
              ? WebRtcIceTransportPolicy.all
              : WebRtcIceTransportPolicy.relayOnly,
        );
        expect(h.fetches, 2);
        h.close();
        await time.settle();
      },
    );
  }

  _testClock(
    'restart outage clears previous TURN and remains bounded by reconnect deadline',
    (time) async {
      final h = _Harness(time)
        ..response = Future.value({
          ..._valid(_epoch),
          'expiresAtMs': _epoch
              .add(const Duration(seconds: 1))
              .millisecondsSinceEpoch,
        });
      h.start();
      await time.settle();
      final b = h.current;
      b.native.connect(WebRtcTransportClass.direct);
      await time.settle();
      h.response = Completer<Map<String, dynamic>>().future;
      b.native.disconnect();
      await time.settle();
      await time.elapse(const Duration(seconds: 5));
      expect(b.native.restarts, 1);
      expect(b.native.servers, [_stun]);
      await time.elapse(const Duration(seconds: 10));
      expect(h.coordinator.activeSession, isNull);
      expect(
        h.coordinator.lastSnapshot?.endReason,
        CallEndReason.reconnectFailed,
      );
      h.close();
      await time.settle();
    },
  );

  _testClock(
    'relay restart never falls back; late restart data cannot mutate a replacement',
    (time) async {
      final h = _Harness(time, policy: CallTransportPolicy.relayOnly)
        ..response = Future.value({
          ..._valid(_epoch),
          'expiresAtMs': _epoch
              .add(const Duration(seconds: 1))
              .millisecondsSinceEpoch,
        });
      h.start();
      await time.settle();
      final old = h.current;
      old.native.connect(WebRtcTransportClass.turnUdp);
      await time.settle();
      h.policy = CallTransportPolicy.all;
      final pending = Completer<Map<String, dynamic>>();
      h.response = pending.future;
      old.native.disconnect();
      await time.settle();
      await time.elapse(const Duration(seconds: 5));
      expect(old.native.restarts, 0);
      expect(h.coordinator.activeSession, isNull);
      h.response = Future.value(_valid(h.now()));
      h.start(id: _next);
      await time.settle();
      pending.complete(_valid(h.now()));
      await time.settle();
      expect(
        h.current.native.configurations.single.iceTransportPolicy,
        WebRtcIceTransportPolicy.all,
      );
      expect(old.native.restarts, 0);
      expect(h.current.native.restarts, 0);
      h.close();
      await time.settle();
    },
  );
}

// WidgetTester owns a fake clock while allowing already-completed stream
// cancellation futures to settle across their original zone.
void _testClock(String name, Future<void> Function(_Clock) body) {
  testWidgets(name, (tester) async {
    await body(_Clock(tester));
  });
}

final class _Clock {
  _Clock(this.tester) : startedAt = tester.binding.clock.now();
  final WidgetTester tester;
  final DateTime startedAt;
  Duration get elapsed => tester.binding.clock.now().difference(startedAt);
  Future<void> settle() async {
    // Stream cancellation can return an already-created root-zone future.
    // Drain that work without advancing the virtual credential/deadline clock.
    for (var i = 0; i < 4; i++) {
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump();
    }
  }

  Future<void> elapse(Duration duration) async {
    await tester.pump(duration);
    await settle();
  }
}

final class _Harness implements CallEffectExecutor {
  _Harness(this.time, {this.policy = CallTransportPolicy.all}) {
    coordinator = CallCoordinator(
      reducer: const CallReducer(),
      cleanupCoordinator: CallCleanupCoordinator([
        CallCleanupStep('media', (s) {
          bundles[s.callId]!.provider.close();
          return bundles[s.callId]!.executor.close();
        }),
      ]),
      historyProjector: CallHistoryProjector(_History(), clock: now),
      effectExecutor: this,
      clock: now,
      idSource: () => current.id,
    );
  }
  final _Clock time;
  CallTransportPolicy policy;
  late Future<Map<String, dynamic>> response;
  late final CallCoordinator coordinator;
  late _Bundle current;
  final bundles = <CallId, _Bundle>{};
  int fetches = 0;
  int sequence = 0;
  DateTime now() => _epoch.add(time.elapsed);
  void start({CallId? id}) {
    current = _Bundle(this, id ?? _first);
    bundles[current.id] = current;
    unawaited(() async {
      await coordinator.placeCall(
        contactPeerId: 'remote',
        localAccountPeerId: 'local',
        localDeviceId: 'device',
      );
      await coordinator.dispatch(event(CallEventType.outgoingInviteReady));
      await coordinator.dispatch(event(CallEventType.remoteAccept));
    }());
  }

  CallEvent event(CallEventType type) => CallEvent(
    type: type,
    eventId: 'test-${sequence++}',
    callId: current.id,
    occurredAt: now(),
  );
  void hangup() => unawaited(coordinator.dispatch(event(CallEventType.end)));
  void close() => unawaited(coordinator.dispose());
  @override
  Future<CallEvent?> execute(CallEffect effect, CallSessionSnapshot snapshot) =>
      bundles[snapshot.callId]!.executor.execute(effect, snapshot);
}

final class _Bundle {
  _Bundle(_Harness h, this.id) {
    provider = BridgeCallIceServerProvider(
      bridge: _Bridge(),
      clock: h.now,
      fetch: (_) {
        h.fetches++;
        return h.response;
      },
    );
    engine = FlutterWebRtcCallEngine(adapter: native);
    final preparer = CallAudioNegotiationPreparer(
      isCurrentCall: (callId) =>
          callId == id &&
          !engine.isClosed &&
          h.coordinator.activeSession?.callId == id &&
          h.coordinator.activeSession?.isTerminal == false,
      readInitialIceServers: provider.read,
      clock: h.now,
      startAudio: ({required locallyAccepted, required configuration}) async {
        await engine.setAudioSessionActive(true);
        await engine.createConnection(configuration);
        return CallAudioStartResult(
          status: CallAudioStartStatus.started,
          state: CallAudioControlState.idle,
        );
      },
    );
    executor = CallNegotiationEffectExecutor(
      engine: engine,
      materialStore: CallNegotiationMaterialStore(),
      mediaPreparer: preparer,
      signaling: _Signaling(),
      configuration: CallConnectionConfiguration(
        transportPolicy: h.policy,
        receiveAudio: true,
        receiveVideo: false,
        captureAudio: true,
        captureVideo: false,
        iceServers: [_stun],
      ),
      dispatchEvent: (e) async {
        await h.coordinator.dispatch(e);
      },
      readActiveSnapshot: () => h.coordinator.activeSession,
      readStagedIceServers: provider.read,
      clock: h.now,
    );
  }
  final CallId id;
  final native = _Native();
  late final BridgeCallIceServerProvider provider;
  late final FlutterWebRtcCallEngine engine;
  late final CallNegotiationEffectExecutor executor;
}

final class _Bridge implements Bridge {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _History implements CallHistoryRepository {
  @override
  Future<CallHistoryEntry?> getByCallId(CallId id) async => null;
  @override
  Future<void> upsertTerminal(CallHistoryEntry entry) async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _Signaling implements CallNegotiationSignalingPort {
  @override
  Future<void> sendDescription({
    required CallId callId,
    required CallSessionDescription description,
    required int iceGeneration,
  }) async {}
  @override
  Future<void> sendIceRestart({
    required CallId callId,
    required int iceGeneration,
  }) async {}
  @override
  Future<void> sendCandidates({
    required CallId callId,
    required List<CallIceCandidate> candidates,
  }) async {}
}

final class _Native
    implements WebRtcPeerConnectionAdapter, WebRtcIceServerUpdater {
  final configurations = <WebRtcPeerConnectionConfiguration>[];
  List<CallIceServer> servers = [];
  final controller = StreamController<WebRtcPeerConnectionEvent>.broadcast(
    sync: true,
  );
  var state = WebRtcConnectionState.connecting;
  var transport = WebRtcTransportClass.unknown;
  int restarts = 0;
  @override
  bool isClosed = false;
  @override
  Stream<WebRtcPeerConnectionEvent> get events => controller.stream;
  @override
  Future<void> create(WebRtcPeerConnectionConfiguration configuration) async {
    configurations.add(configuration);
    servers = configuration.iceServers;
  }

  @override
  Future<void> updateIceServers(List<CallIceServer> iceServers) async {
    servers = iceServers;
  }

  @override
  Future<void> restartIce() async {
    restarts++;
  }

  @override
  Future<CallSessionDescription> createOffer() async => CallSessionDescription(
    type: CallSessionDescriptionType.offer,
    value:
        'v=0\r\na=fingerprint:sha-256 ${List.filled(32, 'AA').join(':')}\r\nm=audio 9 UDP/TLS/RTP/SAVPF 111\r\n',
  );
  @override
  Future<void> setLocalDescription(CallSessionDescription description) async {}
  void connect(WebRtcTransportClass route) {
    transport = route;
    state = WebRtcConnectionState.connected;
    emit();
  }

  void disconnect() {
    state = WebRtcConnectionState.disconnected;
    emit();
  }

  void emit() => controller.add(
    WebRtcPeerConnectionEvent(
      kind: WebRtcPeerConnectionEventKind.state,
      connectionState: state,
      transport: transport,
      quality: WebRtcQualityBand.good,
      failureReason: WebRtcFailureReason.none,
    ),
  );
  @override
  Future<WebRtcPeerConnectionSnapshot> snapshot() async =>
      WebRtcPeerConnectionSnapshot(
        isClosed: isClosed,
        iceTransportPolicy: configurations.single.iceTransportPolicy,
        localAudioCaptureTrackCount: 1,
        localVideoCaptureTrackCount: 0,
        audioReceiveTransceiverCount: 1,
        videoTransceiverCount: 0,
        connectionState: state,
        transport: transport,
        quality: WebRtcQualityBand.good,
        selectedPairSucceeded: true,
        selectedPairNominated: true,
        dtlsReady: true,
        localAudioSenderAttached: true,
        localAudioTrackLive: true,
        remoteAudioReceiverAttached: true,
        remoteAudioTrackLive: true,
      );
  @override
  Future<void> close() async {
    isClosed = true;
    await controller.close();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
