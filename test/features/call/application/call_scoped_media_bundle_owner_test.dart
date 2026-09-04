import 'dart:async';

import 'package:flutter_app/core/permissions/mic_permission_gateway.dart';
import 'package:flutter_app/features/call/application/call_audio_controller.dart';
import 'package:flutter_app/features/call/application/call_coordinator.dart';
import 'package:flutter_app/features/call/application/call_scoped_media_bundle_owner.dart';
import 'package:flutter_app/features/call/domain/call_engine.dart';
import 'package:flutter_app/features/call/domain/call_event.dart';
import 'package:flutter_app/features/call/domain/call_id.dart';
import 'package:flutter_app/features/call/domain/call_session_snapshot.dart';
import 'package:flutter_app/features/call/domain/call_state.dart';
import 'package:flutter_test/flutter_test.dart';

final _firstCallId = CallId.parse('11111111-1111-4111-8111-111111111111');
final _secondCallId = CallId.parse('22222222-2222-4222-8222-222222222222');
final _now = DateTime.utc(2026, 8, 30, 12);

CallSessionSnapshot _snapshot(CallId callId) => CallSessionSnapshot.active(
  callId: callId,
  contactPeerId: 'contact',
  direction: CallDirection.outgoing,
  state: CallState.accepted,
  callerAccountPeerId: 'local-account',
  callerDeviceId: 'local-device',
  startedAt: _now,
  acceptedAt: _now,
);

void main() {
  test(
    'creates lazily and exposes audio only for the exact active call',
    () async {
      final bundles = <_BundleHarness>[];
      final owner = CallScopedMediaBundleOwner(
        createBundle: (callId) async {
          final bundle = _BundleHarness(callId);
          bundles.add(bundle);
          return bundle.value;
        },
      );
      addTearDown(owner.close);

      expect(
        await owner.execute(
          const CallEffect(CallEffectType.sendInvite),
          _snapshot(_firstCallId),
        ),
        isNull,
      );
      expect(bundles, isEmpty);
      expect(owner.currentAudioController(_firstCallId), isNull);
      expect(owner.currentAudioState(_firstCallId), isNull);

      await owner.execute(
        const CallEffect(CallEffectType.startNegotiation),
        _snapshot(_firstCallId),
      );
      await owner.execute(
        const CallEffect(CallEffectType.deliverAnswer),
        _snapshot(_firstCallId),
      );

      expect(bundles, hasLength(1));
      expect(bundles.single.executor.effects, <CallEffectType>[
        CallEffectType.startNegotiation,
        CallEffectType.deliverAnswer,
      ]);
      expect(
        owner.currentAudioController(_firstCallId),
        same(bundles.single.audioController),
      );
      expect(
        owner.currentAudioState(_firstCallId),
        same(bundles.single.audioController.state),
      );
      expect(owner.currentAudioController(_secondCallId), isNull);
      expect(owner.currentAudioState(_secondCallId), isNull);
    },
  );

  test(
    'publishes exact bundle availability for foreground audio binding',
    () async {
      late final _BundleHarness bundle;
      final owner = CallScopedMediaBundleOwner(
        createBundle: (callId) async {
          bundle = _BundleHarness(callId);
          return bundle.value;
        },
      );
      final changes = <CallScopedMediaBundle?>[];
      final subscription = owner.bundleChanges.listen(changes.add);
      addTearDown(subscription.cancel);
      addTearDown(owner.close);

      await owner.execute(
        const CallEffect(CallEffectType.startNegotiation),
        _snapshot(_firstCallId),
      );
      expect(changes, <CallScopedMediaBundle?>[bundle.value]);

      await owner.closeCall(_firstCallId);
      expect(changes, <CallScopedMediaBundle?>[bundle.value, null]);
    },
  );

  test(
    'fails closed with a redacted error while another call is creating',
    () async {
      final creationGate = Completer<void>();
      var factoryCalls = 0;
      final owner = CallScopedMediaBundleOwner(
        createBundle: (callId) async {
          factoryCalls++;
          await creationGate.future;
          return _BundleHarness(callId).value;
        },
      );
      addTearDown(owner.close);

      final firstExecution = owner.execute(
        const CallEffect(CallEffectType.startNegotiation),
        _snapshot(_firstCallId),
      );
      await Future<void>.delayed(Duration.zero);

      Object? mismatch;
      try {
        await owner.execute(
          const CallEffect(CallEffectType.startNegotiation),
          _snapshot(_secondCallId),
        );
      } catch (error) {
        mismatch = error;
      }
      expect(
        mismatch,
        isA<CallScopedMediaBundleOwnerException>().having(
          (error) => error.code,
          'code',
          CallScopedMediaBundleOwnerErrorCode.activeCallMismatch,
        ),
      );
      expect('$mismatch', isNot(contains(_firstCallId.value)));
      expect('$mismatch', isNot(contains(_secondCallId.value)));
      expect(factoryCalls, 1);

      creationGate.complete();
      await firstExecution;
    },
  );

  test(
    'cleans once, rejects stale effects, and creates a fresh next bundle',
    () async {
      final bundles = <_BundleHarness>[];
      final owner = CallScopedMediaBundleOwner(
        createBundle: (callId) async {
          final bundle = _BundleHarness(callId);
          bundles.add(bundle);
          return bundle.value;
        },
      );
      addTearDown(owner.close);

      await owner.execute(
        const CallEffect(CallEffectType.startNegotiation),
        _snapshot(_firstCallId),
      );
      await Future.wait<void>(<Future<void>>[
        owner.closeCall(_firstCallId),
        owner.closeCall(_firstCallId),
      ]);
      await owner.closeCall(_firstCallId);

      expect(bundles.single.closeCalls, 1);
      expect(owner.currentAudioController(_firstCallId), isNull);
      await expectLater(
        owner.execute(
          const CallEffect(CallEffectType.restartIce),
          _snapshot(_firstCallId),
        ),
        throwsA(
          isA<CallScopedMediaBundleOwnerException>().having(
            (error) => error.code,
            'code',
            CallScopedMediaBundleOwnerErrorCode.retiredCall,
          ),
        ),
      );
      expect(bundles, hasLength(1));

      await owner.execute(
        const CallEffect(CallEffectType.startNegotiation),
        _snapshot(_secondCallId),
      );
      expect(bundles, hasLength(2));
      expect(bundles[1].engine, isNot(same(bundles[0].engine)));
      expect(
        bundles[1].audioController,
        isNot(same(bundles[0].audioController)),
      );
      expect(bundles[1].executor, isNot(same(bundles[0].executor)));
      await owner.closeCall(_secondCallId);
      expect(bundles[1].closeCalls, 1);
    },
  );

  test(
    'creation failure retires that call without blocking a later call',
    () async {
      var factoryCalls = 0;
      final secondBundle = _BundleHarness(_secondCallId);
      final owner = CallScopedMediaBundleOwner(
        createBundle: (callId) async {
          factoryCalls++;
          if (callId == _firstCallId) throw StateError('factory failed');
          return secondBundle.value;
        },
      );
      addTearDown(owner.close);

      await expectLater(
        owner.execute(
          const CallEffect(CallEffectType.startNegotiation),
          _snapshot(_firstCallId),
        ),
        throwsStateError,
      );
      await owner.closeCall(_firstCallId);
      await owner.closeCall(_firstCallId);
      await expectLater(
        owner.execute(
          const CallEffect(CallEffectType.startNegotiation),
          _snapshot(_firstCallId),
        ),
        throwsA(isA<CallScopedMediaBundleOwnerException>()),
      );

      await owner.execute(
        const CallEffect(CallEffectType.startNegotiation),
        _snapshot(_secondCallId),
      );
      expect(factoryCalls, 2);
      expect(secondBundle.executor.effects, <CallEffectType>[
        CallEffectType.startNegotiation,
      ]);
    },
  );

  test(
    'close failure stays fenced, coalesces retry, and succeeds exactly once',
    () async {
      final retryGate = Completer<void>();
      final bundles = <_BundleHarness>[];
      final owner = CallScopedMediaBundleOwner(
        createBundle: (callId) async {
          final bundle = _BundleHarness(
            callId,
            onCloseAttempt: (attempt) async {
              if (callId != _firstCallId) return;
              if (attempt == 1) throw StateError('close failed');
              if (attempt == 2) await retryGate.future;
            },
          );
          bundles.add(bundle);
          return bundle.value;
        },
      );
      addTearDown(owner.close);

      await owner.execute(
        const CallEffect(CallEffectType.startNegotiation),
        _snapshot(_firstCallId),
      );
      await expectLater(owner.closeCall(_firstCallId), throwsStateError);
      expect(bundles.single.closeCalls, 1);
      await expectLater(
        owner.execute(
          const CallEffect(CallEffectType.restartIce),
          _snapshot(_firstCallId),
        ),
        throwsA(
          isA<CallScopedMediaBundleOwnerException>().having(
            (error) => error.code,
            'code',
            CallScopedMediaBundleOwnerErrorCode.retiredCall,
          ),
        ),
      );

      Object? retryFailure;
      var retryCompleted = false;
      final retries =
          Future.wait<void>(<Future<void>>[
            owner.closeCall(_firstCallId),
            owner.closeCall(_firstCallId),
          ]).then<void>(
            (_) => retryCompleted = true,
            onError: (Object error, StackTrace stackTrace) {
              retryFailure = error;
              retryCompleted = true;
            },
          );
      await Future<void>.delayed(Duration.zero);

      expect(bundles.single.closeCalls, 2);
      expect(retryCompleted, isFalse);
      retryGate.complete();
      await retries;
      expect(retryFailure, isNull);
      expect(retryCompleted, isTrue);

      await owner.closeCall(_firstCallId);
      expect(bundles.single.closeCalls, 2);

      await owner.execute(
        const CallEffect(CallEffectType.startNegotiation),
        _snapshot(_secondCallId),
      );
      expect(bundles, hasLength(2));
    },
  );

  test(
    'late-created bundle cleanup failure is never converted to success',
    () async {
      final creationGate = Completer<void>();
      final bundle = _BundleHarness(_firstCallId, failClose: true);
      final owner = CallScopedMediaBundleOwner(
        createBundle: (_) async {
          await creationGate.future;
          return bundle.value;
        },
      );
      addTearDown(owner.close);

      final execution = owner.execute(
        const CallEffect(CallEffectType.startNegotiation),
        _snapshot(_firstCallId),
      );
      await Future<void>.delayed(Duration.zero);
      final closing = owner.closeCall(_firstCallId);
      creationGate.complete();

      await expectLater(
        execution,
        throwsA(
          isA<CallScopedMediaBundleOwnerException>().having(
            (error) => error.code,
            'code',
            CallScopedMediaBundleOwnerErrorCode.cleanupFailed,
          ),
        ),
      );
      await expectLater(
        closing,
        throwsA(
          isA<CallScopedMediaBundleOwnerException>().having(
            (error) => error.code,
            'code',
            CallScopedMediaBundleOwnerErrorCode.cleanupFailed,
          ),
        ),
      );
      expect(bundle.closeCalls, 1);
    },
  );

  test('retired call tombstones stay at the fixed process bound', () async {
    final thirdCallId = CallId.parse('33333333-3333-4333-8333-333333333333');
    final bundles = <_BundleHarness>[];
    final owner = CallScopedMediaBundleOwner(
      retiredCallCapacity: 2,
      createBundle: (callId) async {
        final bundle = _BundleHarness(callId);
        bundles.add(bundle);
        return bundle.value;
      },
    );
    addTearDown(owner.close);

    for (final callId in <CallId>[_firstCallId, _secondCallId, thirdCallId]) {
      await owner.execute(
        const CallEffect(CallEffectType.startNegotiation),
        _snapshot(callId),
      );
      await owner.closeCall(callId);
    }

    await owner.execute(
      const CallEffect(CallEffectType.startNegotiation),
      _snapshot(_firstCallId),
    );
    expect(bundles, hasLength(4));
  });
}

final class _BundleHarness {
  _BundleHarness(this.callId, {this.failClose = false, this.onCloseAttempt}) {
    audioController = CallAudioController(
      engine: engine,
      microphonePermission: const _Permission(),
      mediaConflicts: const _MediaConflicts(),
      audioSession: const _AudioSession(),
    );
    value = CallScopedMediaBundle(
      callId: callId,
      engine: engine,
      audioController: audioController,
      negotiationExecutor: executor,
      close: () async {
        closeCalls++;
        await audioController.close();
        await onCloseAttempt?.call(closeCalls);
        if (failClose) throw StateError('close failed');
      },
    );
  }

  final CallId callId;
  final bool failClose;
  final Future<void> Function(int attempt)? onCloseAttempt;
  final _Engine engine = _Engine();
  final _RecordingExecutor executor = _RecordingExecutor();
  late final CallAudioController audioController;
  late final CallScopedMediaBundle value;
  int closeCalls = 0;
}

final class _RecordingExecutor implements CallEffectExecutor {
  final List<CallEffectType> effects = <CallEffectType>[];

  @override
  Future<CallEvent?> execute(
    CallEffect effect,
    CallSessionSnapshot snapshot,
  ) async {
    effects.add(effect.type);
    return null;
  }
}

final class _Permission implements CallMicrophonePermission {
  const _Permission();

  @override
  Future<MicPermissionStatus> request() async => MicPermissionStatus.granted;
}

final class _Lease implements CallMediaConflictLease {
  const _Lease();

  @override
  Future<void> release() async {}
}

final class _MediaConflicts implements CallMediaConflictPort {
  const _MediaConflicts();

  @override
  Future<CallMediaConflictLease> acquireForCall() async => const _Lease();
}

final class _AudioSession implements CallForegroundAudioSession {
  const _AudioSession();

  @override
  Stream<CallAudioSessionInterruption> get interruptions =>
      const Stream<CallAudioSessionInterruption>.empty();

  @override
  bool get ownsSession => false;

  @override
  Future<void> activate() async {}

  @override
  Future<void> deactivate() async {}
}

final class _Engine implements CallEngine {
  var closeCalls = 0;

  @override
  Stream<CallEngineEvent> get events => const Stream<CallEngineEvent>.empty();

  @override
  Stream<CallIceCandidate> get localCandidates =>
      const Stream<CallIceCandidate>.empty();

  @override
  List<CallEngineEvent> get recentEvents => const <CallEngineEvent>[];

  @override
  bool get isClosed => closeCalls > 0;

  @override
  int get iceGeneration => 0;

  @override
  Future<void> createConnection(
    CallConnectionConfiguration configuration,
  ) async {}

  @override
  Future<CallSessionDescription> createOffer() => throw UnimplementedError();

  @override
  Future<CallSessionDescription> createAnswer() => throw UnimplementedError();

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
  Future<void> setLocalAudioEnabled(bool enabled) async {}

  @override
  Future<void> setAudioSessionActive(bool active) async {}

  @override
  Future<List<CallAudioOutputRoute>> supportedOutputRoutes() async =>
      const <CallAudioOutputRoute>[CallAudioOutputRoute.systemDefault];

  @override
  Future<void> selectOutputRoute(CallAudioOutputRoute route) async {}

  @override
  Future<CallConnectionSnapshot> snapshot() async =>
      const CallConnectionSnapshot(
        state: CallConnectionState.newConnection,
        transportPolicy: CallTransportPolicy.relayOnly,
        transport: CallTransportClass.unknown,
        quality: CallQualityBand.unknown,
        localAudioCaptureTrackCount: 0,
        localVideoCaptureTrackCount: 0,
        audioReceiveTransceiverCount: 0,
        videoTransceiverCount: 0,
      );

  @override
  Future<void> close() async {
    closeCalls++;
  }
}
