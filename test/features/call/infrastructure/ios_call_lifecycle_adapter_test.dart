import 'dart:async';

import 'package:flutter_app/features/call/application/call_cleanup_coordinator.dart';
import 'package:flutter_app/features/call/application/call_coordinator.dart';
import 'package:flutter_app/features/call/application/call_history_projector.dart';
import 'package:flutter_app/features/call/application/handle_incoming_call_signal.dart';
import 'package:flutter_app/features/call/data/call_history_repository.dart';
import 'package:flutter_app/features/call/domain/call_engine.dart';
import 'package:flutter_app/features/call/domain/call_event.dart';
import 'package:flutter_app/features/call/domain/call_id.dart';
import 'package:flutter_app/features/call/domain/call_session_snapshot.dart';
import 'package:flutter_app/features/call/domain/call_state.dart';
import 'package:flutter_app/features/call/infrastructure/android_call_lifecycle_adapter.dart';
import 'package:flutter_app/features/call/infrastructure/ios_call_lifecycle_adapter.dart';
import 'package:flutter_test/flutter_test.dart';

const _nowMs = 2_000_000;
const _expiresAtMs = _nowMs + 45_000;
const _callHandle = '33333333-3333-4333-8333-333333333333';
const _wakeHandle = '223e4567e89b42d3a456426614174001';
final _callId = CallId.parse('22222222-2222-4222-8222-222222222222');
final _now = DateTime.fromMillisecondsSinceEpoch(_nowMs, isUtc: true);

void main() {
  test(
    'iOS forwards native route inventory changes and closes the stream',
    () async {
      final native = _LifecycleNative();
      final coordinator = _coordinator();
      final adapter = _adapter(native, coordinator);
      final CallAudioOutputRouteChangeSource source = adapter;
      final routes = <CallAudioOutputRoute>[];
      var closed = false;
      final subscription = source.outputRouteChanges.listen(
        routes.add,
        onDone: () => closed = true,
      );
      await _bindRinging(adapter, coordinator);
      await adapter.supportedOutputRoutes();
      expect(routes, [CallAudioOutputRoute.systemDefault]);

      native.audioState = <String, Object?>{
        'version': 1,
        'active': false,
        'muted': false,
        'route': 'system_default',
        'availableRoutes': <Object?>['system_default', 'speaker', 'bluetooth'],
      };
      native.emit('routeChanged');
      await _until(() => routes.length == 2);
      expect(
        await adapter.supportedOutputRoutes(),
        contains(CallAudioOutputRoute.bluetooth),
      );
      expect(routes, [
        CallAudioOutputRoute.systemDefault,
        CallAudioOutputRoute.systemDefault,
      ]);
      expect(native.callsOf('requestRoute'), isEmpty);

      await adapter.close();
      expect(closed, isTrue);
      await subscription.cancel();
      await coordinator.dispose();
      await native.events.close();
    },
  );

  test('iOS native authorization is default-off and requires every gate', () {
    const enabled = <String, bool>{
      'voice_call_capability_v1': true,
      'voice_call_incoming_enabled': true,
      'voice_call_turn_enabled': true,
      'voice_call_ios_native_enabled': true,
    };
    expect(isIosNativeCallCapabilityAuthorized(enabled), isTrue);
    for (final gate in enabled.keys) {
      expect(
        isIosNativeCallCapabilityAuthorized(<String, bool>{
          ...enabled,
          gate: false,
        }),
        isFalse,
        reason: gate,
      );
    }
    expect(
      IosCallLifecycleAdapter.methodChannelName,
      'mknoon/ios_call_lifecycle',
    );
    expect(
      IosCallLifecycleAdapter.eventChannelName,
      'mknoon/ios_call_lifecycle/events',
    );
  });

  test(
    'iOS default-off rollback is literal-true and platform scoped',
    () async {
      final calls = <_Invocation>[];
      Future<Object?> invoke(
        String method,
        Map<String, Object?> arguments,
      ) async {
        calls.add(_Invocation(method, arguments));
        return true;
      }

      await enforceIosCallCapabilityRollback(
        isIos: true,
        capabilityEnabled: false,
        invokeMethod: invoke,
      );
      await enforceIosCallCapabilityRollback(
        isIos: false,
        capabilityEnabled: false,
        invokeMethod: invoke,
      );
      await enforceIosCallCapabilityRollback(
        isIos: true,
        capabilityEnabled: true,
        invokeMethod: invoke,
      );

      expect(calls, hasLength(1));
      expect(calls.single.method, 'setCapabilityEnabled');
      expect(calls.single.arguments, <String, Object?>{
        'version': 1,
        'enabled': false,
      });
      await expectLater(
        enforceIosCallCapabilityRollback(
          isIos: true,
          capabilityEnabled: false,
          invokeMethod: (_, _) async => false,
        ),
        throwsA(
          isA<IosCallLifecycleException>().having(
            (error) => error.code,
            'code',
            IosCallLifecycleErrorCode.nativeFailure,
          ),
        ),
      );
    },
  );

  test(
    'runtime capability disable uses exact arguments and requires literal true',
    () async {
      final successNative = _LifecycleNative();
      final successCoordinator = _coordinator();
      final successAdapter = _adapter(successNative, successCoordinator);

      await successAdapter.disableCapability();

      expect(successNative.callsOf('setCapabilityEnabled').single.arguments, {
        'version': 1,
        'enabled': false,
      });

      final falseNative = _LifecycleNative()..disableCapabilityResult = false;
      final falseCoordinator = _coordinator();
      await expectLater(
        _adapter(falseNative, falseCoordinator).disableCapability(),
        throwsA(
          isA<IosCallLifecycleException>().having(
            (error) => error.code,
            'code',
            IosCallLifecycleErrorCode.nativeFailure,
          ),
        ),
      );

      final throwingNative = _LifecycleNative()
        ..disableCapabilityError = StateError('native details stay private');
      final throwingCoordinator = _coordinator();
      await expectLater(
        _adapter(throwingNative, throwingCoordinator).disableCapability(),
        throwsA(
          isA<IosCallLifecycleException>().having(
            (error) => error.code,
            'code',
            IosCallLifecycleErrorCode.nativeFailure,
          ),
        ),
      );

      await successCoordinator.dispose();
      await falseCoordinator.dispose();
      await throwingCoordinator.dispose();
      await successNative.events.close();
      await falseNative.events.close();
      await throwingNative.events.close();
    },
  );

  test(
    'provisional lifecycle routes use exact privacy-safe arguments',
    () async {
      final native = _LifecycleNative();
      final coordinator = _coordinator();
      final adapter = _adapter(native, coordinator);

      await adapter.authenticationFailed(_callHandle);
      await adapter.remoteCancel(_callHandle);
      await adapter.expire(_callHandle);
      await adapter.updateAuthenticatedContact(
        callHandle: _callHandle,
        displayName: 'Alice',
      );
      await adapter.revokeOpaqueContact(_callHandle);

      for (final method in <String>[
        'authenticationFailed',
        'remoteCancel',
        'expire',
        'revokeOpaqueContact',
      ]) {
        expect(native.callsOf(method).single.arguments, <String, Object?>{
          'version': 1,
          'callHandle': _callHandle,
        });
      }
      expect(
        native.callsOf('updateAuthenticatedContact').single.arguments,
        <String, Object?>{
          'version': 1,
          'callHandle': _callHandle,
          'displayName': 'Alice',
        },
      );
      await expectLater(
        adapter.authenticationFailed('not-a-call-handle'),
        throwsA(
          isA<IosCallLifecycleException>().having(
            (error) => error.code,
            'code',
            IosCallLifecycleErrorCode.unavailable,
          ),
        ),
      );
      expect(native.callsOf('authenticationFailed'), hasLength(1));

      await adapter.close();
      await coordinator.dispose();
      await native.events.close();
    },
  );

  test(
    'opaque contacts publish and revoke by strict wake handle without a call',
    () async {
      final native = _LifecycleNative();
      final coordinator = _coordinator();
      final adapter = _adapter(native, coordinator);

      await adapter.publishOpaqueContact(
        wakeHandle: _wakeHandle,
        displayName: 'Alice',
      );
      await adapter.revokeOpaqueContactHandle(_wakeHandle);

      expect(native.callsOf('publishOpaqueContact').single.arguments, {
        'version': 1,
        'wakeHandle': _wakeHandle,
        'displayName': 'Alice',
      });
      expect(native.callsOf('revokeOpaqueContactHandle').single.arguments, {
        'version': 1,
        'wakeHandle': _wakeHandle,
      });

      await adapter.publishOpaqueContact(
        wakeHandle: '223e4567-e89b-42d3-a456-426614174001',
        displayName: 'Alice Device',
      );
      expect(native.callsOf('publishOpaqueContact'), hasLength(2));

      for (final invalidHandle in <String>[
        '223E4567E89B42D3A456426614174001',
        '223e4567-e89b-12d3-a456-426614174001',
        '223e4567-e89b-42d3-c456-426614174001',
        'not-a-wake-handle',
      ]) {
        await expectLater(
          adapter.publishOpaqueContact(
            wakeHandle: invalidHandle,
            displayName: 'Alice',
          ),
          throwsA(
            isA<IosCallLifecycleException>()
                .having(
                  (error) => error.code,
                  'code',
                  IosCallLifecycleErrorCode.unavailable,
                )
                .having(
                  (error) => error.toString(),
                  'fixed shape',
                  'IosCallLifecycleException(unavailable)',
                ),
          ),
        );
      }
      for (final invalidName in <String>[
        '',
        ' Alice',
        'Alice\nInjected',
        'a' * 81,
      ]) {
        await expectLater(
          adapter.publishOpaqueContact(
            wakeHandle: _wakeHandle,
            displayName: invalidName,
          ),
          throwsA(
            isA<IosCallLifecycleException>().having(
              (error) => error.code,
              'code',
              IosCallLifecycleErrorCode.unavailable,
            ),
          ),
        );
      }
      await expectLater(
        adapter.revokeOpaqueContactHandle(
          '223e4567-e89b-42d3-7456-426614174001',
        ),
        throwsA(
          isA<IosCallLifecycleException>().having(
            (error) => error.code,
            'code',
            IosCallLifecycleErrorCode.unavailable,
          ),
        ),
      );
      expect(native.callsOf('publishOpaqueContact'), hasLength(2));
      expect(native.callsOf('revokeOpaqueContactHandle'), hasLength(1));

      await adapter.close();
      await coordinator.dispose();
      await native.events.close();
    },
  );

  test(
    'audio activation requires exact native adoption acknowledgement',
    () async {
      final native = _LifecycleNative()..attachResult = _emptyBatch();
      final coordinator = _coordinator();
      final adapter = _adapter(native, coordinator);

      await adapter.start();
      await _prepareIncoming(coordinator);
      expect(await adapter.present(_presentation()), isTrue);
      expect(native.callsOf('presentAuthenticated'), hasLength(1));

      await expectLater(
        adapter.activateAudio(),
        throwsA(
          isA<IosCallLifecycleException>().having(
            (error) => error.code,
            'code',
            IosCallLifecycleErrorCode.unavailable,
          ),
        ),
      );
      expect(native.callsOf('activateAudio'), isEmpty);
      expect(adapter.ownsSession, isFalse);

      await adapter.close();
      await coordinator.dispose();
      await native.events.close();
    },
  );

  test(
    'attaches, adopts, acknowledges in order, and terminal precedence wins',
    () async {
      final native = _LifecycleNative(terminalAtAttach: true);
      final coordinator = _coordinator();
      final adapter = _adapter(native, coordinator);

      await adapter.start();
      await _prepareIncoming(coordinator);

      expect(await adapter.present(_presentation()), isFalse);
      expect(native.callsOf('setCapabilityEnabled'), hasLength(1));
      expect(native.callsOf('attach'), hasLength(1));
      expect(native.callsOf('adopt'), isEmpty);
      expect(coordinator.lastSnapshot?.isTerminal, isTrue);
      expect(native.callsOf('acknowledge').single.arguments, <String, Object?>{
        'version': 1,
        'callHandle': _callHandle,
        'throughSequence': 2,
        'disposition': 'TERMINAL',
      });

      await adapter.close();
      await coordinator.dispose();
      await native.events.close();
    },
  );

  test(
    'answer is acknowledged while media still waits for didActivate',
    () async {
      final native = _LifecycleNative();
      final effects = _ActivatingEffects();
      final coordinator = _coordinator(effects: effects);
      final adapter = _adapter(native, coordinator);
      effects.adapter = adapter;
      await _bindRinging(adapter, coordinator);

      native.emit('answer');
      await _until(() => native.callsOf('activateAudio').isNotEmpty);
      await _until(
        () => native
            .callsOf('acknowledge')
            .any((call) => call.arguments['throughSequence'] == 2),
      );

      expect(effects.mediaStarts, 1);
      expect(
        effects.mediaReady,
        0,
        reason: 'answer alone cannot own AVAudioSession',
      );
      expect(
        native
            .callsOf('acknowledge')
            .any((call) => call.arguments['throughSequence'] == 2),
        isTrue,
      );

      native.didActivate();
      await _until(() => effects.mediaReady == 1);
      await _until(
        () => native
            .callsOf('acknowledge')
            .any((call) => call.arguments['throughSequence'] == 3),
      );

      expect(coordinator.activeSession?.state, CallState.accepted);
      expect(adapter.ownsSession, isTrue);

      await adapter.close();
      await coordinator.dispose();
      await native.events.close();
    },
  );

  test(
    'native End interrupts an acknowledged answer waiting for permission',
    () async {
      final permission = Completer<void>();
      final native = _LifecycleNative();
      final effects = _ActivatingEffects()
        ..beforeActivation = permission.future;
      final coordinator = _coordinator(effects: effects);
      final adapter = _adapter(native, coordinator);
      effects.adapter = adapter;
      await _bindRinging(adapter, coordinator);

      native.emit('answer');
      await _until(
        () => native
            .callsOf('acknowledge')
            .any((call) => call.arguments['throughSequence'] == 2),
      );
      expect(permission.isCompleted, isFalse);
      expect(effects.acceptSignals, 0);

      native.emit('end');
      await _until(() => coordinator.lastSnapshot?.isTerminal == true);
      await _until(
        () => native
            .callsOf('acknowledge')
            .any(
              (call) =>
                  call.arguments['throughSequence'] == 3 &&
                  call.arguments['disposition'] == 'TERMINAL',
            ),
      );
      expect(permission.isCompleted, isFalse);
      permission.complete();
      native.didActivate();
      await Future<void>.delayed(Duration.zero);
      expect(effects.acceptSignals, 0);
      expect(coordinator.activeSession, isNull);

      await adapter.close();
      await coordinator.dispose();
      await native.events.close();
    },
  );

  test('didActivate alone starts no media; later answer completes', () async {
    final native = _LifecycleNative();
    final effects = _ActivatingEffects();
    final coordinator = _coordinator(effects: effects);
    final adapter = _adapter(native, coordinator);
    effects.adapter = adapter;
    await _bindRinging(adapter, coordinator);

    native.didActivate();
    await _until(
      () => native
          .callsOf('acknowledge')
          .any((call) => call.arguments['throughSequence'] == 2),
    );
    expect(effects.mediaStarts, 0);
    expect(coordinator.activeSession?.state, CallState.ringing);

    native.emit('answer');
    await _until(() => effects.mediaReady == 1);
    await _until(
      () => native
          .callsOf('acknowledge')
          .any((call) => call.arguments['throughSequence'] == 3),
    );

    expect(effects.mediaStarts, 1);
    expect(coordinator.activeSession?.state, CallState.accepted);

    await adapter.close();
    await coordinator.dispose();
    await native.events.close();
  });

  test('audio activation retries bounded transient native readiness', () async {
    final native = _LifecycleNative()
      ..activationResults.addAll(<Object?>[false, true]);
    final coordinator = _coordinator();
    final retryDelays = <Duration>[];
    final adapter = _adapter(
      native,
      coordinator,
      audioActivationMaxAttempts: 3,
      audioActivationRetryInterval: const Duration(milliseconds: 50),
      audioActivationDelay: (delay) async => retryDelays.add(delay),
    );
    await _bindRinging(adapter, coordinator);

    native.emit('answer');
    await _until(() => coordinator.activeSession?.state == CallState.accepted);

    await adapter.activateAudio();

    expect(native.callsOf('activateAudio'), hasLength(2));
    expect(retryDelays, <Duration>[const Duration(milliseconds: 50)]);
    expect(adapter.ownsSession, isTrue);

    await adapter.close();
    await coordinator.dispose();
    await native.events.close();
  });

  test('audio activation readiness retry remains bounded', () async {
    final native = _LifecycleNative()
      ..activationResults.addAll(<Object?>[false, false, false]);
    final coordinator = _coordinator();
    final retryDelays = <Duration>[];
    final adapter = _adapter(
      native,
      coordinator,
      audioActivationMaxAttempts: 3,
      audioActivationRetryInterval: const Duration(milliseconds: 50),
      audioActivationDelay: (delay) async => retryDelays.add(delay),
    );
    await _bindRinging(adapter, coordinator);

    native.emit('answer');
    await _until(() => coordinator.activeSession?.state == CallState.accepted);

    await expectLater(
      adapter.activateAudio(),
      throwsA(
        isA<IosCallLifecycleException>().having(
          (error) => error.code,
          'code',
          IosCallLifecycleErrorCode.nativeFailure,
        ),
      ),
    );

    expect(native.callsOf('activateAudio'), hasLength(3));
    expect(retryDelays, hasLength(2));
    expect(adapter.ownsSession, isFalse);

    await adapter.close();
    await coordinator.dispose();
    await native.events.close();
  });

  test('forwards fixed-shape outgoing registration diagnostics', () async {
    final native = _LifecycleNative();
    final coordinator = _coordinator();
    final diagnostics =
        <
          (
            NativeOutgoingRegistrationStage,
            NativeOutgoingRegistrationStatus,
            NativeOutgoingRegistrationReason,
          )
        >[];
    final adapter = _adapter(
      native,
      coordinator,
      onOutgoingRegistrationResult: (stage, status, reason) {
        diagnostics.add((stage, status, reason));
      },
    );

    await adapter.start();
    await coordinator.placeCall(
      contactPeerId: 'remote-account',
      localAccountPeerId: 'local-account',
      localDeviceId: 'local-device',
    );
    expect(await adapter.registerOutgoing(_callId, expiresAt: _now), isFalse);
    expect(diagnostics, <Object?>[
      (
        NativeOutgoingRegistrationStage.preflight,
        NativeOutgoingRegistrationStatus.rejected,
        NativeOutgoingRegistrationReason.expired,
      ),
    ]);

    await adapter.close();
    await coordinator.dispose();
    await native.events.close();
  });

  test(
    'strict malformed native responses fail closed with iOS errors',
    () async {
      final malformedAttach = _LifecycleNative()
        ..attachResult = <String, Object?>{
          ..._emptyBatch(),
          'unexpected': true,
        };
      final attachCoordinator = _coordinator();
      final attachAdapter = _adapter(malformedAttach, attachCoordinator);

      await expectLater(
        attachAdapter.start(),
        throwsA(
          isA<IosCallLifecycleException>().having(
            (error) => error.code,
            'code',
            IosCallLifecycleErrorCode.malformedResponse,
          ),
        ),
      );
      expect(malformedAttach.callsOf('failClosed'), hasLength(1));

      await attachAdapter.close();
      await attachCoordinator.dispose();
      await malformedAttach.events.close();

      final malformedAudio = _LifecycleNative();
      final audioCoordinator = _coordinator();
      final audioAdapter = _adapter(malformedAudio, audioCoordinator);
      await _bindRinging(audioAdapter, audioCoordinator);
      malformedAudio.audioState = <String, Object?>{
        'version': 1,
        'active': false,
        'muted': false,
        'route': 'system_default',
        'availableRoutes': <Object?>['speaker', 'speaker'],
      };
      await expectLater(
        audioAdapter.readAudioState(),
        throwsA(
          isA<IosCallLifecycleException>().having(
            (error) => error.code,
            'code',
            IosCallLifecycleErrorCode.malformedResponse,
          ),
        ),
      );

      await audioAdapter.close();
      await audioCoordinator.dispose();
      await malformedAudio.events.close();
    },
  );

  test('a natively presented call observed before its invite adopts and '
      'activates audio', () async {
    final native = _LifecycleNative()..attachResult = _emptyBatch();
    final effects = _ActivatingEffects();
    final coordinator = _coordinator(effects: effects);
    final adapter = _adapter(native, coordinator);
    effects.adapter = adapter;
    await adapter.start();

    // PushKit reported the call; its journal reaches Dart before the
    // mailbox drain hands the invite to the coordinator.
    native.events.add(_batch(<Map<String, Object?>>[_event(1, 'presented')]));
    await _prepareIncoming(coordinator);
    expect(await adapter.present(_presentation()), isTrue);
    await coordinator.dispatch(
      CallEvent(
        type: CallEventType.systemUiPresented,
        eventId: 'system-ui-presented',
        occurredAt: _now,
        callId: _callId,
        contactPeerId: 'remote-account',
      ),
    );
    expect(coordinator.activeSession?.state, CallState.ringing);
    expect(native.callsOf('adopt'), hasLength(1));
    expect(
      native
          .callsOf('acknowledge')
          .any((call) => call.arguments['disposition'] == 'ADOPTED'),
      isTrue,
    );

    native.emit('answer');
    native.didActivate();
    await _until(() => effects.mediaReady == 1);
    expect(coordinator.activeSession?.state, CallState.accepted);
    expect(adapter.ownsSession, isTrue);

    await adapter.close();
    await coordinator.dispose();
    await native.events.close();
  });

  test('an invite handled before the native journal arrives still adopts and '
      'activates audio', () async {
    final native = _LifecycleNative()..attachResult = _emptyBatch();
    final effects = _ActivatingEffects();
    final coordinator = _coordinator(effects: effects);
    final adapter = _adapter(native, coordinator);
    effects.adapter = adapter;
    await adapter.start();

    await _prepareIncoming(coordinator);
    expect(await adapter.present(_presentation()), isTrue);
    // The PushKit journal for the same call lands after presentation.
    native.events.add(_batch(<Map<String, Object?>>[_event(1, 'presented')]));
    await coordinator.dispatch(
      CallEvent(
        type: CallEventType.systemUiPresented,
        eventId: 'system-ui-presented',
        occurredAt: _now,
        callId: _callId,
        contactPeerId: 'remote-account',
      ),
    );
    expect(coordinator.activeSession?.state, CallState.ringing);
    await _until(
      () => native
          .callsOf('acknowledge')
          .any((call) => call.arguments['disposition'] == 'ADOPTED'),
    );

    native.emit('answer');
    native.didActivate();
    await _until(() => effects.mediaReady == 1);
    expect(coordinator.activeSession?.state, CallState.accepted);
    expect(adapter.ownsSession, isTrue);

    await adapter.close();
    await coordinator.dispose();
    await native.events.close();
  });
}

IosCallLifecycleAdapter _adapter(
  _LifecycleNative native,
  CallCoordinator coordinator, {
  int audioActivationMaxAttempts = 40,
  Duration audioActivationRetryInterval = const Duration(milliseconds: 50),
  Future<void> Function(Duration delay)? audioActivationDelay,
  NativeOutgoingRegistrationResultObserver? onOutgoingRegistrationResult,
}) {
  final adapter = IosCallLifecycleAdapter(
    invokeMethod: native.invoke,
    nativeEvents: native.events.stream,
    coordinator: coordinator,
    resolveAuthenticatedHandle: (callId) =>
        callId == _callId ? _callHandle : null,
    clock: () => _now,
    audioActivationMaxAttempts: audioActivationMaxAttempts,
    audioActivationRetryInterval: audioActivationRetryInterval,
    audioActivationDelay: audioActivationDelay,
    onOutgoingRegistrationResult: onOutgoingRegistrationResult,
  );
  adapter.bindNativeMuteApplier((_, _) async => true);
  return adapter;
}

Future<void> _bindRinging(
  IosCallLifecycleAdapter adapter,
  CallCoordinator coordinator,
) async {
  await adapter.start();
  await _prepareIncoming(coordinator);
  expect(await adapter.present(_presentation()), isTrue);
  await coordinator.dispatch(
    CallEvent(
      type: CallEventType.systemUiPresented,
      eventId: 'system-ui-presented',
      occurredAt: _now,
      callId: _callId,
      contactPeerId: 'remote-account',
    ),
  );
  expect(coordinator.activeSession?.state, CallState.ringing);
}

IncomingCallPresentation _presentation() => IncomingCallPresentation(
  callId: _callId,
  callerAccountPeerId: 'remote-account',
  expiresAt: DateTime.fromMillisecondsSinceEpoch(_expiresAtMs, isUtc: true),
);

Future<void> _prepareIncoming(CallCoordinator coordinator) async {
  await coordinator.dispatch(
    CallEvent(
      type: CallEventType.remoteInvite,
      eventId: 'remote-invite',
      occurredAt: _now,
      callId: _callId,
      contactPeerId: 'remote-account',
      localAccountPeerId: 'local-account',
      localDeviceId: 'local-device',
      remoteAccountPeerId: 'remote-account',
      remoteDeviceId: 'remote-device',
      expiresAt: DateTime.fromMillisecondsSinceEpoch(_expiresAtMs, isUtc: true),
      transportRoute: CallRouteClass.direct,
    ),
  );
  await coordinator.dispatch(
    CallEvent(
      type: CallEventType.incomingValidated,
      eventId: 'incoming-validated',
      occurredAt: _now,
      callId: _callId,
      contactPeerId: 'remote-account',
    ),
  );
}

CallCoordinator _coordinator({_ActivatingEffects? effects}) => CallCoordinator(
  reducer: const CallReducer(),
  cleanupCoordinator: CallCleanupCoordinator(const <CallCleanupStep>[]),
  historyProjector: CallHistoryProjector(_History(), clock: () => _now),
  effectExecutor: effects ?? const NoopCallEffectExecutor(),
  clock: () => _now,
  idSource: () => _callId,
);

Map<String, Object?> _emptyBatch() => <String, Object?>{
  'version': 1,
  'descriptor': null,
  'events': <Object?>[],
  'nativeCallId': null,
  'highestSequence': 0,
};

Map<String, Object?> _batch(
  List<Map<String, Object?>> events, {
  String phase = 'preStart',
}) => <String, Object?>{
  'version': 1,
  'descriptor': <String, Object?>{
    'callHandle': _callHandle,
    'expiresAtMs': _expiresAtMs,
    'presented': true,
    'phase': phase,
    'direction': 'incoming',
  },
  'events': events,
  'nativeCallId': _callHandle,
  'highestSequence': events.isEmpty ? 0 : events.last['sequence'],
};

Map<String, Object?> _event(int sequence, String type) => <String, Object?>{
  'callHandle': _callHandle,
  'sequence': sequence,
  'eventId': '00000000-0000-4000-8000-${sequence.toString().padLeft(12, '0')}',
  'type': type,
  'occurredAtMs': _nowMs,
};

final class _Invocation {
  const _Invocation(this.method, this.arguments);

  final String method;
  final Map<String, Object?> arguments;
}

final class _LifecycleNative {
  _LifecycleNative({bool terminalAtAttach = false}) {
    if (terminalAtAttach) {
      _sequence = 2;
      attachResult = _batch(<Map<String, Object?>>[
        _event(1, 'presented'),
        _event(2, 'remoteCancelled'),
      ]);
    } else {
      _sequence = 1;
      attachResult = _batch(<Map<String, Object?>>[_event(1, 'presented')]);
    }
  }

  final StreamController<Object?> events = StreamController<Object?>.broadcast(
    sync: true,
  );
  final List<_Invocation> calls = <_Invocation>[];
  Object? attachResult;
  Object? audioState = <String, Object?>{
    'version': 1,
    'active': false,
    'muted': false,
    'route': 'system_default',
    'availableRoutes': <Object?>['system_default', 'speaker'],
  };
  late int _sequence;
  bool _answer = false;
  bool _didActivate = false;
  final Completer<Object?> _activation = Completer<Object?>();
  Object? disableCapabilityResult = true;
  Object? disableCapabilityError;
  final List<Object?> activationResults = <Object?>[];

  void emit(String type) {
    _sequence++;
    if (type == 'answer') _answer = true;
    _completeActivationIfReady();
    events.add(
      _batch(<Map<String, Object?>>[_event(_sequence, type)], phase: 'journal'),
    );
  }

  void didActivate() {
    _didActivate = true;
    audioState = <String, Object?>{
      'version': 1,
      'active': true,
      'muted': false,
      'route': 'system_default',
      'availableRoutes': <Object?>['system_default', 'speaker'],
    };
    _completeActivationIfReady();
    emit('audioActivated');
  }

  void _completeActivationIfReady() {
    if (_answer && _didActivate && !_activation.isCompleted) {
      _activation.complete(true);
    }
  }

  Future<Object?> invoke(String method, Map<String, Object?> arguments) async {
    calls.add(_Invocation(method, Map<String, Object?>.of(arguments)));
    switch (method) {
      case 'attach':
        return attachResult;
      case 'activateAudio':
        if (activationResults.isNotEmpty) {
          return activationResults.removeAt(0);
        }
        _completeActivationIfReady();
        return _activation.future;
      case 'readAudioState':
        return audioState;
      case 'presentAuthenticated':
      case 'registerOutgoingAuthenticated':
      case 'adopt':
      case 'acknowledge':
      case 'deactivateAudio':
      case 'requestRoute':
      case 'end':
      case 'failClosed':
      case 'detach':
      case 'project':
      case 'authenticationFailed':
      case 'remoteCancel':
      case 'expire':
      case 'updateAuthenticatedContact':
      case 'revokeOpaqueContact':
      case 'publishOpaqueContact':
      case 'revokeOpaqueContactHandle':
        return true;
      case 'setCapabilityEnabled':
        if (arguments['enabled'] == false) {
          final error = disableCapabilityError;
          if (error != null) throw error;
          return disableCapabilityResult;
        }
        return true;
      default:
        return null;
    }
  }

  List<_Invocation> callsOf(String method) =>
      calls.where((call) => call.method == method).toList(growable: false);
}

final class _ActivatingEffects implements CallEffectExecutor {
  late IosCallLifecycleAdapter adapter;
  Future<void>? beforeActivation;
  int mediaStarts = 0;
  int mediaReady = 0;
  int acceptSignals = 0;

  @override
  Future<CallEvent?> execute(
    CallEffect effect,
    CallSessionSnapshot snapshot,
  ) async {
    if (effect.type == CallEffectType.prepareAcceptedMedia) {
      mediaStarts++;
      await beforeActivation;
      await adapter.activateAudio();
      mediaReady++;
    }
    if (effect.type == CallEffectType.sendAccept) acceptSignals++;
    return null;
  }
}

final class _History implements CallHistoryRepository {
  @override
  Future<CallHistoryEntry?> getByCallId(CallId callId) async => null;

  @override
  Future<List<CallHistoryEntry>> listForContact(
    String contactAccountPeerId,
  ) async => const <CallHistoryEntry>[];

  @override
  Future<void> upsertTerminal(CallHistoryEntry entry) async {}
}

Future<void> _until(bool Function() predicate) async {
  for (var attempt = 0; attempt < 200; attempt++) {
    if (predicate()) return;
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
  fail('condition was not reached');
}
