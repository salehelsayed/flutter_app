import 'dart:async';

import 'package:flutter_app/core/permissions/mic_permission_gateway.dart';
import 'package:flutter_app/features/call/application/call_audio_controller.dart';
import 'package:flutter_app/features/call/application/call_route_diagnostics.dart';
import 'package:flutter_app/features/call/domain/call_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('VC2-03 foreground audio start', () {
    test(
      'does not request permission or touch media before local accept',
      () async {
        final harness = _Harness();

        final result = await harness.controller.start(
          locallyAccepted: false,
          configuration: _configuration(),
        );

        expect(result.status, CallAudioStartStatus.notLocallyAccepted);
        expect(harness.permission.requestCalls, 0);
        expect(harness.conflicts.acquireCalls, 0);
        expect(harness.session.activateCalls, 0);
        expect(harness.engine.createConnectionCalls, 0);
        expect(harness.engine.createOfferCalls, 0);
        expect(harness.engine.localAudioCaptureTrackCount, 0);
      },
    );

    test('permission denial creates no connection, track, or SDP', () async {
      final harness = _Harness(
        permissionStatus: MicPermissionStatus.permanentlyDenied,
      );

      final result = await harness.controller.start(
        locallyAccepted: true,
        configuration: _configuration(),
      );

      expect(result.status, CallAudioStartStatus.permissionDenied);
      expect(result.permissionStatus, MicPermissionStatus.permanentlyDenied);
      expect(result.state.failure, CallAudioFailure.permissionDenied);
      expect(result.state.messageKey, 'call.audio.permissionDenied');
      expect(harness.permission.requestCalls, 1);
      expect(harness.conflicts.acquireCalls, 0);
      expect(harness.session.activateCalls, 0);
      expect(harness.engine.createConnectionCalls, 0);
      expect(harness.engine.createOfferCalls, 0);
      expect(harness.engine.localAudioCaptureTrackCount, 0);
    });

    test(
      'after permission, resolves conflicts and activates session before capture',
      () async {
        final calls = <String>[];
        final harness = _Harness(calls: calls);

        final result = await harness.controller.start(
          locallyAccepted: true,
          configuration: _configuration(
            transportPolicy: CallTransportPolicy.all,
          ),
        );

        expect(result.status, CallAudioStartStatus.started);
        expect(calls.take(5), <String>[
          'permission.request',
          'conflicts.acquire',
          'session.activate',
          'engine.session:true',
          'engine.create',
        ]);
        expect(harness.engine.lastConfiguration?.captureAudio, isTrue);
        expect(harness.engine.lastConfiguration?.captureVideo, isFalse);
        expect(harness.engine.lastConfiguration?.receiveVideo, isFalse);
        expect(
          harness.engine.lastConfiguration?.transportPolicy,
          CallTransportPolicy.all,
        );
        expect(result.state.active, isTrue);
        expect(result.state.muted, isFalse);
        expect(result.state.supportedRoutes, <CallAudioOutputRoute>[
          CallAudioOutputRoute.systemDefault,
          CallAudioOutputRoute.speaker,
        ]);
      },
    );

    test(
      'start publishes known controls without a diagnostic snapshot',
      () async {
        final observed = <CallAudioEngineStartStage>[];
        final harness = _Harness(onEngineStartFailure: observed.add);
        final snapshotGate = Completer<void>();
        harness.engine
          ..failSnapshot = true
          ..snapshotGate = snapshotGate;

        final result = await harness.start().timeout(
          const Duration(seconds: 1),
        );

        expect(result.status, CallAudioStartStatus.started);
        expect(observed, isEmpty);
        expect(harness.engine.snapshotCalls, 0);
        expect(result.state.muted, isFalse);
        expect(result.state.selectedRoute, CallAudioOutputRoute.systemDefault);
        expect(result.state.supportedRoutes, <CallAudioOutputRoute>[
          CallAudioOutputRoute.systemDefault,
          CallAudioOutputRoute.speaker,
        ]);
        expect(result.state.active, isTrue);
        expect(result.state.failure, CallAudioFailure.none);
        expect(snapshotGate.isCompleted, isFalse);
        expect(harness.engine.closeCalls, 0);
        expect(harness.session.deactivateCalls, 0);
        expect(harness.conflicts.lease.releaseCalls, 0);

        snapshotGate.complete();
        await harness.controller.close();

        expect(harness.engine.closeCalls, 1);
        expect(harness.session.deactivateCalls, 1);
        expect(harness.conflicts.lease.releaseCalls, 1);
        expect(harness.controller.state.active, isFalse);
      },
    );

    test(
      'route inventory failure keeps an accepted audio connection alive',
      () async {
        final observed = <CallAudioEngineStartStage>[];
        final harness = _Harness(onEngineStartFailure: observed.add)
          ..engine.failSupportedRoutes = true;

        final result = await harness.start();

        expect(result.status, CallAudioStartStatus.started);
        expect(result.state.failure, CallAudioFailure.none);
        expect(result.state.active, isTrue);
        expect(result.state.selectedRoute, CallAudioOutputRoute.systemDefault);
        expect(result.state.supportedRoutes, const <CallAudioOutputRoute>[
          CallAudioOutputRoute.systemDefault,
        ]);
        expect(observed, isEmpty);
        expect(harness.engine.closeCalls, 0);
        expect(harness.session.deactivateCalls, 0);
        expect(harness.conflicts.lease.releaseCalls, 0);

        await harness.controller.close();
      },
    );

    test('reports only the fixed engine start substage that failed', () async {
      final scenarios =
          <
            ({
              CallAudioEngineStartStage stage,
              void Function(_FakeCallEngine engine) fail,
            })
          >[
            (
              stage: CallAudioEngineStartStage.setAudioSessionActive,
              fail: (engine) => engine.failSessionActivation = true,
            ),
            (
              stage: CallAudioEngineStartStage.createConnection,
              fail: (engine) => engine.failCreate = true,
            ),
          ];

      for (final scenario in scenarios) {
        final observed = <CallAudioEngineStartStage>[];
        final harness = _Harness(onEngineStartFailure: observed.add);
        scenario.fail(harness.engine);

        final result = await harness.start();

        expect(result.status, CallAudioStartStatus.engineFailed);
        expect(result.state.failure, CallAudioFailure.engineFailed);
        expect(observed, <CallAudioEngineStartStage>[scenario.stage]);
      }
    });

    test(
      'throwing engine start observer cannot change failure cleanup',
      () async {
        final harness = _Harness(
          onEngineStartFailure: (_) =>
              throw StateError('private diagnostic sink failure'),
        )..engine.failCreate = true;

        final result = await harness.start();

        expect(result.status, CallAudioStartStatus.engineFailed);
        expect(result.state.failure, CallAudioFailure.engineFailed);
        expect(harness.engine.closeCalls, 1);
        expect(harness.session.deactivateCalls, 1);
        expect(harness.conflicts.lease.releaseCalls, 1);
      },
    );

    test(
      'refused media conflict prevents audio-session and engine start',
      () async {
        final harness = _Harness()..conflicts.refuse = true;

        final result = await harness.controller.start(
          locallyAccepted: true,
          configuration: _configuration(),
        );

        expect(result.status, CallAudioStartStatus.mediaConflict);
        expect(result.state.failure, CallAudioFailure.mediaConflict);
        expect(harness.session.activateCalls, 0);
        expect(harness.engine.createConnectionCalls, 0);
      },
    );

    test(
      'rejects receive-only and every video configuration before permission',
      () async {
        final configurations = <CallConnectionConfiguration>[
          _configuration(captureAudio: false),
          _configuration(receiveVideo: true),
          _configuration(captureVideo: true),
        ];

        for (final configuration in configurations) {
          final harness = _Harness();
          final result = await harness.controller.start(
            locallyAccepted: true,
            configuration: configuration,
          );

          expect(result.status, CallAudioStartStatus.invalidConfiguration);
          expect(result.state.failure, CallAudioFailure.invalidConfiguration);
          expect(harness.permission.requestCalls, 0);
          expect(harness.engine.createConnectionCalls, 0);
        }
      },
    );
  });

  group('VC2-03 foreground audio controls', () {
    test('mute requested during startup waits for active audio', () async {
      final harness = _Harness();
      final supportedRoutesEntered = Completer<void>();
      final supportedRoutesGate = Completer<void>();
      harness.engine
        ..supportedRoutesEntered = supportedRoutesEntered
        ..supportedRoutesGate = supportedRoutesGate;

      final starting = harness.start();
      await supportedRoutesEntered.future;

      var muteCompleted = false;
      final muting = harness.controller.setMuted(false).whenComplete(() {
        muteCompleted = true;
      });
      await Future<void>.delayed(Duration.zero);

      expect(muteCompleted, isFalse);
      expect(harness.calls, isNot(contains('engine.muted:false')));

      supportedRoutesGate.complete();
      final startResult = await starting;
      final muteState = await muting;

      expect(startResult.status, CallAudioStartStatus.started);
      expect(muteState.active, isTrue);
      expect(muteState.failure, CallAudioFailure.none);
      expect(muteState.muted, isFalse);
      expect(harness.calls, contains('engine.muted:false'));
    });

    test('publishes only engine-refreshed control truth', () async {
      final harness = _Harness();
      final states = <CallAudioControlState>[];
      final subscription = harness.controller.stateChanges.listen(states.add);

      await harness.start();
      await harness.controller.setMuted(true);
      await harness.controller.selectOutputRoute(CallAudioOutputRoute.speaker);

      expect(states, hasLength(3));
      expect(states[0].active, isTrue);
      expect(states[0].muted, isFalse);
      expect(states[1].muted, isTrue);
      expect(states[1].selectedRoute, CallAudioOutputRoute.systemDefault);
      expect(states[2].muted, isTrue);
      expect(states[2].selectedRoute, CallAudioOutputRoute.speaker);
      await subscription.cancel();
    });

    test('device route changes refresh the active coarse projection', () async {
      final harness = _Harness();
      final states = <CallAudioControlState>[];
      final subscription = harness.controller.stateChanges.listen(states.add);
      await harness.start();
      await harness.controller.selectOutputRoute(CallAudioOutputRoute.speaker);
      expect(
        harness.controller.state.selectedRoute,
        CallAudioOutputRoute.speaker,
      );

      harness.engine.emitDeviceRouteChange();
      await harness.controller.settle();

      expect(
        harness.controller.state.selectedRoute,
        CallAudioOutputRoute.systemDefault,
      );
      expect(states.last.selectedRoute, CallAudioOutputRoute.systemDefault);
      expect(harness.engine.selectRouteCalls, 1);

      await harness.controller.selectOutputRoute(CallAudioOutputRoute.speaker);
      expect(
        harness.controller.state.selectedRoute,
        CallAudioOutputRoute.speaker,
      );
      await subscription.cancel();
    });

    test(
      'serializes rapid mute and route commands and projects snapshots',
      () async {
        final harness = _Harness();
        await harness.start();
        harness.engine.yieldDuringControls = true;

        final mute = harness.controller.setMuted(true);
        final speaker = harness.controller.selectOutputRoute(
          CallAudioOutputRoute.speaker,
        );
        final unmute = harness.controller.setMuted(false);
        final states = await Future.wait(<Future<CallAudioControlState>>[
          mute,
          speaker,
          unmute,
        ]);

        expect(harness.engine.controlsOverlapped, isFalse);
        expect(states[0].muted, isTrue);
        expect(states[1].selectedRoute, CallAudioOutputRoute.speaker);
        expect(states[2].muted, isFalse);
        expect(harness.controller.state.muted, isFalse);
        expect(
          harness.controller.state.selectedRoute,
          CallAudioOutputRoute.speaker,
        );
      },
    );

    test(
      'unsupported route reports stable failure and keeps actual route',
      () async {
        final harness = _Harness();
        await harness.start();

        final first = await harness.controller.selectOutputRoute(
          CallAudioOutputRoute.bluetooth,
        );
        final second = await harness.controller.selectOutputRoute(
          CallAudioOutputRoute.bluetooth,
        );

        expect(harness.engine.selectRouteCalls, 0);
        expect(first.selectedRoute, CallAudioOutputRoute.systemDefault);
        expect(second.selectedRoute, CallAudioOutputRoute.systemDefault);
        expect(first.failure, CallAudioFailure.unsupportedRoute);
        expect(second.failure, CallAudioFailure.unsupportedRoute);
        expect(first.messageKey, 'call.audio.routeUnsupported');
        expect(second.messageKey, first.messageKey);
      },
    );

    test(
      'interruption recovery is emitted only while session remains owned',
      () async {
        final harness = _Harness();
        await harness.start();
        final intents = <CallAudioInterruptionIntent>[];
        final subscription = harness.controller.interruptionIntents.listen(
          intents.add,
        );

        harness.session.emit(const CallAudioSessionInterruption.begin());
        await harness.controller.settle();
        expect(intents, <CallAudioInterruptionIntent>[
          CallAudioInterruptionIntent.pausedReconnect,
        ]);
        expect(harness.engine.audioSessionActive, isFalse);

        harness.session.ownsSession = false;
        harness.session.emit(const CallAudioSessionInterruption.end());
        await harness.controller.settle();
        expect(intents, <CallAudioInterruptionIntent>[
          CallAudioInterruptionIntent.pausedReconnect,
        ]);
        expect(harness.engine.audioSessionActive, isFalse);

        await subscription.cancel();
      },
    );

    test('owned interruption end emits recovery after reactivation', () async {
      final harness = _Harness();
      await harness.start();
      final intents = <CallAudioInterruptionIntent>[];
      final subscription = harness.controller.interruptionIntents.listen(
        intents.add,
      );

      harness.session.emit(const CallAudioSessionInterruption.begin());
      await harness.controller.settle();
      harness.session.emit(const CallAudioSessionInterruption.end());
      await harness.controller.settle();

      expect(intents, <CallAudioInterruptionIntent>[
        CallAudioInterruptionIntent.pausedReconnect,
        CallAudioInterruptionIntent.recover,
      ]);
      expect(harness.engine.audioSessionActive, isTrue);
      await subscription.cancel();
    });
  });

  group('VC2-03 foreground audio cleanup', () {
    test('publishes the final inactive state before closing changes', () async {
      final harness = _Harness();
      final states = <CallAudioControlState>[];
      var streamClosed = false;
      harness.controller.stateChanges.listen(
        states.add,
        onDone: () => streamClosed = true,
      );
      await harness.start();

      await harness.controller.close();

      expect(states.last.active, isFalse);
      expect(streamClosed, isTrue);
    });

    test('close is idempotent and releases each owned resource once', () async {
      final harness = _Harness();
      await harness.start();

      await Future.wait(<Future<void>>[
        harness.controller.close(),
        harness.controller.close(),
      ]);
      await harness.controller.close();

      expect(harness.engine.closeCalls, 1);
      expect(harness.session.deactivateCalls, 1);
      expect(harness.conflicts.lease.releaseCalls, 1);
      expect(harness.controller.state.active, isFalse);
    });

    test(
      'close during route enumeration cannot resurrect started authority',
      () async {
        final harness = _Harness();
        final supportedRoutesEntered = Completer<void>();
        final supportedRoutesGate = Completer<void>();
        harness.engine
          ..supportedRoutesEntered = supportedRoutesEntered
          ..supportedRoutesGate = supportedRoutesGate;

        final starting = harness.start();
        await supportedRoutesEntered.future;

        final closing = harness.controller.close();
        expect(harness.engine.closeCalls, 1);

        supportedRoutesGate.complete();
        final result = await starting;
        await closing;

        final unavailable = await harness.controller.setMuted(true);

        expect(result.status, CallAudioStartStatus.closed);
        expect(result.state.failure, CallAudioFailure.closed);
        expect(result.state.active, isFalse);
        expect(harness.controller.state.active, isFalse);
        expect(unavailable.active, isFalse);
        expect(unavailable.failure, CallAudioFailure.closed);
        expect(harness.engine.selectRouteCalls, 0);
        expect(harness.calls, isNot(contains('engine.muted:true')));
        expect(harness.engine.closeCalls, 1);
        expect(harness.session.deactivateCalls, 1);
        expect(harness.conflicts.lease.releaseCalls, 1);
        expect(
          harness.calls
              .where(
                <String>{
                  'engine.close',
                  'session.deactivate',
                  'conflicts.release',
                }.contains,
              )
              .toList(),
          <String>['engine.close', 'session.deactivate', 'conflicts.release'],
        );
      },
    );

    test('cleanup detaches the engine route-change projection', () async {
      final harness = _Harness();
      await harness.start();
      expect(harness.engine.hasRouteChangeListener, isTrue);

      await harness.controller.close();

      expect(harness.engine.hasRouteChangeListener, isFalse);
    });

    test('cleanup restores the system route before closing media', () async {
      final harness = _Harness();
      await harness.start();
      await harness.controller.selectOutputRoute(CallAudioOutputRoute.speaker);

      await harness.controller.close();

      expect(harness.engine.outputRoute, CallAudioOutputRoute.systemDefault);
      expect(harness.engine.calls, contains('engine.route:systemDefault'));
      expect(
        harness.engine.calls.indexOf('engine.route.request:systemDefault'),
        lessThan(harness.engine.calls.indexOf('engine.close')),
      );
    });

    test(
      'cleanup starts microphone close before a route reset can settle',
      () async {
        final harness = _Harness();
        await harness.start();
        await harness.controller.selectOutputRoute(
          CallAudioOutputRoute.speaker,
        );
        final routeResetGate = Completer<void>();
        harness.engine.systemRouteGate = routeResetGate;

        final closing = harness.controller.close();
        await Future<void>.delayed(Duration.zero);

        expect(harness.engine.selectRouteCalls, 2);
        expect(harness.engine.closeCalls, 1);

        routeResetGate.complete();
        await closing;
      },
    );

    test(
      'transient engine close retries while successful cleanup stays once',
      () async {
        final harness = _Harness();
        harness.engine.failCreate = true;
        harness.engine.failClose = true;

        final result = await harness.controller.start(
          locallyAccepted: true,
          configuration: _configuration(),
        );

        expect(result.status, CallAudioStartStatus.engineFailed);
        expect(result.state.failure, CallAudioFailure.cleanupFailed);
        expect(harness.engine.closeCalls, 1);
        expect(harness.session.deactivateCalls, 1);
        expect(harness.conflicts.lease.releaseCalls, 0);

        harness.engine.failClose = false;
        await Future.wait<void>(<Future<void>>[
          harness.controller.close(),
          harness.controller.close(),
        ]);
        expect(harness.engine.closeCalls, 2);
        expect(harness.session.deactivateCalls, 1);
        expect(harness.conflicts.lease.releaseCalls, 1);
        expect(harness.controller.state.failure, CallAudioFailure.engineFailed);

        await harness.controller.close();
        expect(harness.engine.closeCalls, 2);
        expect(harness.session.deactivateCalls, 1);
        expect(harness.conflicts.lease.releaseCalls, 1);
      },
    );

    test(
      'transient session cleanup retries without reclosing successful resources',
      () async {
        final harness = _Harness();
        await harness.start();
        harness.session.failDeactivate = true;

        await harness.controller.close();

        expect(
          harness.controller.state.failure,
          CallAudioFailure.cleanupFailed,
        );
        expect(harness.engine.closeCalls, 1);
        expect(harness.session.deactivateCalls, 1);
        expect(harness.conflicts.lease.releaseCalls, 1);

        harness.session.failDeactivate = false;
        await Future.wait<void>(<Future<void>>[
          harness.controller.close(),
          harness.controller.close(),
        ]);

        expect(harness.controller.state.failure, CallAudioFailure.none);
        expect(harness.controller.state.active, isFalse);
        expect(harness.engine.closeCalls, 1);
        expect(harness.session.deactivateCalls, 2);
        expect(harness.conflicts.lease.releaseCalls, 1);

        await harness.controller.close();
        expect(harness.engine.closeCalls, 1);
        expect(harness.session.deactivateCalls, 2);
        expect(harness.conflicts.lease.releaseCalls, 1);
      },
    );
  });

  test('route diagnostics expose only coarse transport class', () {
    expect(
      CallRouteDiagnostics.fromTransport(CallTransportClass.direct).route,
      CallRouteDiagnostic.direct,
    );
    expect(
      CallRouteDiagnostics.fromTransport(CallTransportClass.turnUdp).route,
      CallRouteDiagnostic.turnUdp,
    );
    expect(
      CallRouteDiagnostics.fromTransport(CallTransportClass.turnTcpTls).route,
      CallRouteDiagnostic.turnTcpTls,
    );
    final unknown = CallRouteDiagnostics.fromTransport(
      CallTransportClass.relay,
    );
    expect(unknown.route, CallRouteDiagnostic.unknown);
    expect(unknown.toDiagnosticMap(), <String, String>{'route': 'unknown'});
  });
}

CallConnectionConfiguration _configuration({
  CallTransportPolicy transportPolicy = CallTransportPolicy.relayOnly,
  bool captureAudio = true,
  bool receiveVideo = false,
  bool captureVideo = false,
}) => CallConnectionConfiguration(
  transportPolicy: transportPolicy,
  receiveAudio: true,
  receiveVideo: receiveVideo,
  captureAudio: captureAudio,
  captureVideo: captureVideo,
  iceServers: <CallIceServer>[
    CallIceServer(
      urls: <String>['turns:relay.invalid'],
      username: 'opaque-user',
      credential: 'opaque-secret',
      expiresAt: DateTime.utc(2026, 8, 30, 18),
    ),
  ],
);

final class _Harness {
  _Harness({
    List<String>? calls,
    MicPermissionStatus permissionStatus = MicPermissionStatus.granted,
    CallAudioEngineStartFailureObserver? onEngineStartFailure,
  }) : calls = calls ?? <String>[] {
    engine = _FakeCallEngine(this.calls);
    permission = _FakePermission(this.calls, permissionStatus);
    conflicts = _FakeConflicts(this.calls);
    session = _FakeAudioSession(this.calls);
    controller = CallAudioController(
      engine: engine,
      microphonePermission: permission,
      mediaConflicts: conflicts,
      audioSession: session,
      onEngineStartFailure: onEngineStartFailure,
    );
  }

  final List<String> calls;
  late final _FakeCallEngine engine;
  late final _FakePermission permission;
  late final _FakeConflicts conflicts;
  late final _FakeAudioSession session;
  late final CallAudioController controller;

  Future<CallAudioStartResult> start() =>
      controller.start(locallyAccepted: true, configuration: _configuration());
}

final class _FakePermission implements CallMicrophonePermission {
  _FakePermission(this.calls, this.status);

  final List<String> calls;
  final MicPermissionStatus status;
  int requestCalls = 0;

  @override
  Future<MicPermissionStatus> request() async {
    requestCalls++;
    calls.add('permission.request');
    return status;
  }
}

final class _FakeLease implements CallMediaConflictLease {
  _FakeLease(this.calls);

  final List<String> calls;
  int releaseCalls = 0;

  @override
  Future<void> release() async {
    releaseCalls++;
    calls.add('conflicts.release');
  }
}

final class _FakeConflicts implements CallMediaConflictPort {
  _FakeConflicts(this.calls) : lease = _FakeLease(calls);

  final List<String> calls;
  final _FakeLease lease;
  bool refuse = false;
  int acquireCalls = 0;

  @override
  Future<CallMediaConflictLease> acquireForCall() async {
    acquireCalls++;
    calls.add('conflicts.acquire');
    if (refuse) throw const CallMediaConflictRefused();
    return lease;
  }
}

final class _FakeAudioSession implements CallForegroundAudioSession {
  _FakeAudioSession(this.calls);

  final List<String> calls;
  final StreamController<CallAudioSessionInterruption> _interruptions =
      StreamController<CallAudioSessionInterruption>.broadcast(sync: true);
  int activateCalls = 0;
  int deactivateCalls = 0;
  bool failDeactivate = false;

  @override
  bool ownsSession = false;

  @override
  Stream<CallAudioSessionInterruption> get interruptions =>
      _interruptions.stream;

  @override
  Future<void> activate() async {
    activateCalls++;
    calls.add('session.activate');
    ownsSession = true;
  }

  @override
  Future<void> deactivate() async {
    deactivateCalls++;
    calls.add('session.deactivate');
    ownsSession = false;
    if (failDeactivate) throw StateError('private platform failure');
  }

  void emit(CallAudioSessionInterruption interruption) {
    _interruptions.add(interruption);
  }
}

final class _FakeCallEngine
    implements CallEngine, CallAudioOutputRouteChangeSource {
  _FakeCallEngine(this.calls);

  final List<String> calls;
  final StreamController<CallEngineEvent> _events =
      StreamController<CallEngineEvent>.broadcast();
  final StreamController<CallIceCandidate> _candidates =
      StreamController<CallIceCandidate>.broadcast();
  final StreamController<CallAudioOutputRoute> _outputRouteChanges =
      StreamController<CallAudioOutputRoute>.broadcast(sync: true);

  int createConnectionCalls = 0;
  int createOfferCalls = 0;
  int selectRouteCalls = 0;
  int snapshotCalls = 0;
  int closeCalls = 0;
  int localAudioCaptureTrackCount = 0;
  bool failSessionActivation = false;
  bool failCreate = false;
  bool failSupportedRoutes = false;
  bool failSnapshot = false;
  bool failClose = false;
  bool yieldDuringControls = false;
  bool controlsOverlapped = false;
  bool _controlInFlight = false;
  bool audioSessionActive = false;
  bool localAudioEnabled = false;
  CallAudioOutputRoute outputRoute = CallAudioOutputRoute.systemDefault;
  Completer<void>? snapshotGate;
  Completer<void>? supportedRoutesEntered;
  Completer<void>? supportedRoutesGate;
  Completer<void>? systemRouteGate;
  CallConnectionConfiguration? lastConfiguration;

  @override
  Stream<CallEngineEvent> get events => _events.stream;

  @override
  Stream<CallIceCandidate> get localCandidates => _candidates.stream;

  @override
  Stream<CallAudioOutputRoute> get outputRouteChanges =>
      _outputRouteChanges.stream;

  bool get hasRouteChangeListener => _outputRouteChanges.hasListener;

  @override
  List<CallEngineEvent> get recentEvents => const <CallEngineEvent>[];

  @override
  bool get isClosed => closeCalls > 0;

  @override
  int get iceGeneration => 0;

  @override
  Future<void> createConnection(
    CallConnectionConfiguration configuration,
  ) async {
    createConnectionCalls++;
    calls.add('engine.create');
    lastConfiguration = configuration;
    if (failCreate) throw const CallEngineException(CallEngineErrorCode.other);
    localAudioCaptureTrackCount = configuration.captureAudio ? 1 : 0;
    localAudioEnabled = configuration.captureAudio;
  }

  @override
  Future<CallSessionDescription> createOffer() async {
    createOfferCalls++;
    return const CallSessionDescription(
      type: CallSessionDescriptionType.offer,
      value: 'opaque',
    );
  }

  @override
  Future<CallSessionDescription> createAnswer() async =>
      const CallSessionDescription(
        type: CallSessionDescriptionType.answer,
        value: 'opaque',
      );

  @override
  Future<void> setLocalDescription(CallSessionDescription description) async {}

  @override
  Future<void> setRemoteDescription(CallSessionDescription description) async {}

  @override
  Future<void> addIceCandidates(List<CallIceCandidate> candidates) async {}

  @override
  Future<int> restartIce({List<CallIceServer> iceServers = const []}) async =>
      1;

  @override
  Future<void> setLocalAudioEnabled(bool enabled) async {
    await _beginControl();
    calls.add('engine.muted:${!enabled}');
    localAudioEnabled = enabled;
    _endControl();
  }

  @override
  Future<void> setAudioSessionActive(bool active) async {
    calls.add('engine.session:$active');
    if (active && failSessionActivation) {
      throw const CallEngineException(CallEngineErrorCode.other);
    }
    audioSessionActive = active;
  }

  @override
  Future<List<CallAudioOutputRoute>> supportedOutputRoutes() async {
    final entered = supportedRoutesEntered;
    if (entered != null && !entered.isCompleted) entered.complete();
    await supportedRoutesGate?.future;
    if (failSupportedRoutes) {
      throw const CallEngineException(CallEngineErrorCode.other);
    }
    return const <CallAudioOutputRoute>[
      CallAudioOutputRoute.systemDefault,
      CallAudioOutputRoute.speaker,
    ];
  }

  @override
  Future<void> selectOutputRoute(CallAudioOutputRoute route) async {
    calls.add('engine.route.request:${route.name}');
    await _beginControl();
    selectRouteCalls++;
    calls.add('engine.route:${route.name}');
    if (route == CallAudioOutputRoute.systemDefault) {
      await systemRouteGate?.future;
    }
    outputRoute = route;
    _endControl();
  }

  void emitDeviceRouteChange() {
    outputRoute = CallAudioOutputRoute.systemDefault;
    _outputRouteChanges.add(CallAudioOutputRoute.systemDefault);
  }

  @override
  Future<CallConnectionSnapshot> snapshot() async {
    snapshotCalls++;
    await snapshotGate?.future;
    if (failSnapshot) {
      throw const CallEngineException(CallEngineErrorCode.other);
    }
    return CallConnectionSnapshot(
      state: CallConnectionState.connected,
      transportPolicy:
          lastConfiguration?.transportPolicy ?? CallTransportPolicy.relayOnly,
      transport: CallTransportClass.turnTcpTls,
      quality: CallQualityBand.good,
      localAudioCaptureTrackCount: localAudioCaptureTrackCount,
      localVideoCaptureTrackCount: 0,
      audioReceiveTransceiverCount: 1,
      videoTransceiverCount: 0,
      selectedPairSucceeded: true,
      selectedPairNominated: true,
      dtlsReady: true,
      audioSessionActive: audioSessionActive,
      localAudioSenderAttached: localAudioCaptureTrackCount == 1,
      localAudioTrackLive: localAudioCaptureTrackCount == 1,
      remoteAudioReceiverAttached: true,
      remoteAudioTrackLive: true,
      localAudioEnabled: localAudioEnabled,
      outputRoute: outputRoute,
    );
  }

  @override
  Future<void> close() async {
    closeCalls++;
    calls.add('engine.close');
    if (failClose) throw const CallEngineException(CallEngineErrorCode.other);
  }

  Future<void> _beginControl() async {
    if (_controlInFlight) controlsOverlapped = true;
    _controlInFlight = true;
    if (yieldDuringControls) await Future<void>.delayed(Duration.zero);
  }

  void _endControl() {
    _controlInFlight = false;
  }
}
