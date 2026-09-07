import 'dart:async';

import 'package:flutter_app/features/call/application/call_cleanup_coordinator.dart';
import 'package:flutter_app/features/call/application/call_coordinator.dart';
import 'package:flutter_app/features/call/application/call_history_projector.dart';
import 'package:flutter_app/features/call/application/handle_incoming_call_signal.dart';
import 'package:flutter_app/features/call/data/call_history_repository.dart';
import 'package:flutter_app/features/call/domain/call_engine.dart';
import 'package:flutter_app/features/call/domain/call_end_reason.dart';
import 'package:flutter_app/features/call/domain/call_event.dart';
import 'package:flutter_app/features/call/domain/call_id.dart';
import 'package:flutter_app/features/call/domain/call_session_snapshot.dart';
import 'package:flutter_app/features/call/domain/call_state.dart';
import 'package:flutter_app/features/call/infrastructure/android_call_lifecycle_adapter.dart';
import 'package:flutter_app/features/call/infrastructure/call_audio_route_adapter.dart';
import 'package:flutter_app/features/call/infrastructure/flutter_webrtc_call_engine.dart';
import 'package:flutter_app/features/call/infrastructure/webrtc_types.dart';
import 'package:flutter_test/flutter_test.dart';

const _nowMs = 2_000_000;
const _expiresAtMs = _nowMs + 45_000;
const _callHandle = '33333333-3333-4333-8333-333333333333';
const _secondCallHandle = '44444444-4444-4444-8444-444444444444';
final _callId = CallId.parse('22222222-2222-4222-8222-222222222222');
final _secondCallId = CallId.parse('55555555-5555-4555-8555-555555555555');
final _now = DateTime.fromMillisecondsSinceEpoch(_nowMs, isUtc: true);

void main() {
  test('Android native authorization requires every graph gate', () {
    const enabled = <String, bool>{
      'voice_call_capability_v1': true,
      'voice_call_incoming_enabled': true,
      'voice_call_turn_enabled': true,
      'voice_call_android_native_enabled': true,
    };
    expect(isAndroidNativeCallCapabilityAuthorized(enabled), isTrue);

    for (final gate in enabled.keys) {
      expect(
        isAndroidNativeCallCapabilityAuthorized(<String, bool>{
          ...enabled,
          gate: false,
        }),
        isFalse,
        reason: gate,
      );
    }
    expect(
      isAndroidNativeCallCapabilityAuthorized(const <String, bool>{}),
      isFalse,
    );
  });

  test(
    'Android default-off rollback writes false before graph creation',
    () async {
      final calls = <_NativeInvocation>[];
      Future<Object?> invoke(
        String method,
        Map<String, Object?> arguments,
      ) async {
        calls.add(_NativeInvocation(method, arguments));
        return true;
      }

      await enforceAndroidCallCapabilityRollback(
        isAndroid: true,
        capabilityEnabled: false,
        invokeMethod: invoke,
      );
      await enforceAndroidCallCapabilityRollback(
        isAndroid: true,
        capabilityEnabled: true,
        invokeMethod: invoke,
      );
      await enforceAndroidCallCapabilityRollback(
        isAndroid: false,
        capabilityEnabled: false,
        invokeMethod: invoke,
      );

      expect(calls, hasLength(1));
      expect(calls.single.method, 'setCapabilityEnabled');
      expect(calls.single.arguments, <String, Object?>{
        'version': 1,
        'enabled': false,
      });
    },
  );

  test('Android default-off rollback fails closed on native refusal', () async {
    for (final result in <Object?>[false, null]) {
      await expectLater(
        enforceAndroidCallCapabilityRollback(
          isAndroid: true,
          capabilityEnabled: false,
          invokeMethod: (_, _) async => result,
        ),
        throwsA(isA<AndroidCallLifecycleException>()),
      );
    }
    await expectLater(
      enforceAndroidCallCapabilityRollback(
        isAndroid: true,
        capabilityEnabled: false,
        invokeMethod: (_, _) async => throw StateError('private failure'),
      ),
      throwsA(isA<AndroidCallLifecycleException>()),
    );
  });

  test(
    'subscribes before attach and authenticates a new native presentation',
    () async {
      final native = _NativeHarness()..attachResult = _emptyBatch();
      final coordinator = _coordinator();
      var subscribedBeforeAttach = false;
      var resolverCalls = 0;
      native.onAttach = () {
        subscribedBeforeAttach = native.events.hasListener;
      };
      final adapter = AndroidCallLifecycleAdapter(
        invokeMethod: native.invoke,
        nativeEvents: native.events.stream,
        coordinator: coordinator,
        resolveAuthenticatedHandle: (callId) {
          resolverCalls++;
          return callId == _callId ? _callHandle : null;
        },
        clock: () => _now,
      );

      await adapter.start();

      expect(adapter, isA<IncomingCallPresenter>());
      expect(subscribedBeforeAttach, isTrue);
      expect(native.calls.take(2).map((call) => call.method), <String>[
        'setCapabilityEnabled',
        'attach',
      ]);
      expect(native.callsOf('setCapabilityEnabled').single.arguments, {
        'version': 1,
        'enabled': true,
      });
      expect(resolverCalls, 0, reason: 'attach must not guess call authority');
      expect(await adapter.present(_presentation()), isTrue);
      expect(resolverCalls, 1);
      expect(native.callsOf('presentAuthenticated'), hasLength(1));
      expect(native.callsOf('presentAuthenticated').single.arguments, {
        'version': 1,
        'callHandle': _callHandle,
        'expiresAtMs': _expiresAtMs,
      });

      await adapter.close();
      await coordinator.dispose();
      await native.events.close();
    },
  );

  test('does not attach when native capability enable is not true', () async {
    final native = _NativeHarness()
      ..attachResult = _emptyBatch()
      ..results['setCapabilityEnabled'] = false;
    final coordinator = _coordinator();
    final adapter = _adapter(native, coordinator, const <CallId, String>{});

    await expectLater(
      adapter.start(),
      throwsA(isA<AndroidCallLifecycleException>()),
    );

    expect(native.callsOf('setCapabilityEnabled'), hasLength(1));
    expect(native.callsOf('attach'), isEmpty);

    await adapter.close();
    await coordinator.dispose();
    await native.events.close();
  });

  test(
    'authenticated outgoing registration binds Telecom before audio activation',
    () async {
      final native = _NativeHarness()
        ..attachResult = _emptyBatch()
        ..audioState = <String, Object?>{
          'version': 1,
          'active': false,
          'muted': false,
          'route': 'system_default',
          'availableRoutes': <Object?>['system_default', 'speaker'],
        };
      final coordinator = _coordinator();
      final adapter = _adapter(native, coordinator, <CallId, String>{
        _callId: _callHandle,
      });
      native.onInvoke = (method) {
        if (method != 'registerOutgoingAuthenticated') return;
        native.events.add(
          _batch(<Map<String, Object?>>[
            _event(1, 'outgoing-native-presented', 'presented'),
          ], direction: 'outgoing'),
        );
      };

      await adapter.start();
      final placed = await coordinator.placeCall(
        contactPeerId: 'remote-account',
        localAccountPeerId: 'local-account',
        localDeviceId: 'local-device',
      );
      expect(placed.decision, CallEventDecision.applied);

      expect(
        await adapter.registerOutgoing(
          _callId,
          expiresAt: DateTime.fromMillisecondsSinceEpoch(
            _expiresAtMs,
            isUtc: true,
          ),
        ),
        isTrue,
      );
      await _until(
        () => native
            .callsOf('acknowledge')
            .any((call) => call.arguments['disposition'] == 'ADOPTED'),
      );
      await adapter.activateAudio();

      expect(adapter.isBoundTo(_callId), isTrue);
      expect(
        native.callsOf('registerOutgoingAuthenticated').single.arguments,
        <String, Object?>{
          'version': 1,
          'callHandle': _callHandle,
          'expiresAtMs': _expiresAtMs,
        },
      );
      expect(
        native.calls.indexOf(
          native.callsOf('registerOutgoingAuthenticated').single,
        ),
        lessThan(native.calls.indexOf(native.callsOf('activateAudio').single)),
      );

      await adapter.close();
      await coordinator.dispose();
      await native.events.close();
    },
  );

  test(
    'fresh outgoing registration waits for durable ADOPTED acknowledgement',
    () async {
      final adoptionAcknowledgement = Completer<Object?>();
      final native = _NativeHarness()
        ..attachResult = _emptyBatch()
        ..results['acknowledge'] = adoptionAcknowledgement.future;
      final coordinator = _coordinator();
      final adapter = _adapter(native, coordinator, <CallId, String>{
        _callId: _callHandle,
      });
      native.onInvoke = (method) {
        if (method != 'registerOutgoingAuthenticated') return;
        native.events.add(
          _batch(<Map<String, Object?>>[
            _event(1, 'outgoing-adoption-barrier', 'presented'),
          ], direction: 'outgoing'),
        );
      };

      await adapter.start();
      await coordinator.placeCall(
        contactPeerId: 'remote-account',
        localAccountPeerId: 'local-account',
        localDeviceId: 'local-device',
      );

      var registrationCompleted = false;
      final registration = adapter
          .registerOutgoing(
            _callId,
            expiresAt: DateTime.fromMillisecondsSinceEpoch(
              _expiresAtMs,
              isUtc: true,
            ),
          )
          .then((registered) {
            registrationCompleted = true;
            return registered;
          });
      await _until(() => native.callsOf('acknowledge').isNotEmpty);
      final completedBeforeAcknowledgement = registrationCompleted;

      adoptionAcknowledgement.complete(true);
      final registered = await registration;

      expect(registered, isTrue);
      expect(completedBeforeAcknowledgement, isFalse);
      expect(native.callsOf('acknowledge').single.arguments, {
        'version': 1,
        'callHandle': _callHandle,
        'throughSequence': 1,
        'disposition': 'ADOPTED',
      });

      await adapter.close();
      await coordinator.dispose();
      await native.events.close();
    },
  );

  test(
    'outgoing registration reconciles durable replay when stream delivery lags',
    () async {
      final native = _NativeHarness()..attachResult = _emptyBatch();
      final coordinator = _coordinator();
      final adapter = _adapter(native, coordinator, <CallId, String>{
        _callId: _callHandle,
      });
      final delayedPresentedReplay = _batch(<Map<String, Object?>>[
        _event(1, 'outgoing-delayed-stream-presented', 'presented'),
      ], direction: 'outgoing');
      native.onInvoke = (method) {
        if (method != 'registerOutgoingAuthenticated') return;
        native.attachResult = delayedPresentedReplay;
      };

      await adapter.start();
      await coordinator.placeCall(
        contactPeerId: 'remote-account',
        localAccountPeerId: 'local-account',
        localDeviceId: 'local-device',
      );

      expect(
        await adapter.registerOutgoing(
          _callId,
          expiresAt: DateTime.fromMillisecondsSinceEpoch(
            _expiresAtMs,
            isUtc: true,
          ),
        ),
        isTrue,
      );
      expect(native.callsOf('attach'), hasLength(2));
      expect(native.callsOf('acknowledge').single.arguments, {
        'version': 1,
        'callHandle': _callHandle,
        'throughSequence': 1,
        'disposition': 'ADOPTED',
      });
      expect(native.callsOf('failClosed'), isEmpty);
      expect(adapter.isBoundTo(_callId), isTrue);

      native.events.add(delayedPresentedReplay);
      await _settle();
      expect(
        native.callsOf('failClosed'),
        isEmpty,
        reason: 'the exact pre-ACK stream envelope is a stale duplicate',
      );
      expect(adapter.isBoundTo(_callId), isTrue);

      native.events.add(
        _batch(
          <Map<String, Object?>>[
            _event(1, 'outgoing-delayed-stream-presented', 'presented'),
          ],
          direction: 'outgoing',
          expiresAtMs: _expiresAtMs - 1,
        ),
      );
      await _until(() => native.callsOf('failClosed').isNotEmpty);
      expect(
        adapter.isBoundTo(_callId),
        isFalse,
        reason: 'a descriptor mutation must retain the fail-closed fence',
      );

      await adapter.close();
      await coordinator.dispose();
      await native.events.close();
    },
  );

  test(
    'outgoing registration diagnostics distinguish invalid and descriptor guards',
    () async {
      final invalidNative = _NativeHarness()..attachResult = _emptyBatch();
      final invalidCoordinator = _coordinator();
      final invalidDiagnostics =
          <
            (
              NativeOutgoingRegistrationStage,
              NativeOutgoingRegistrationStatus,
              NativeOutgoingRegistrationReason,
            )
          >[];
      final invalidAdapter = _adapter(
        invalidNative,
        invalidCoordinator,
        <CallId, String>{_callId: _callHandle},
        onOutgoingRegistrationResult: (stage, status, reason) {
          invalidDiagnostics.add((stage, status, reason));
        },
      );

      await invalidAdapter.start();
      await invalidCoordinator.placeCall(
        contactPeerId: 'remote-account',
        localAccountPeerId: 'local-account',
        localDeviceId: 'local-device',
      );
      expect(
        await invalidAdapter.registerOutgoing(
          _callId,
          expiresAt: DateTime.fromMillisecondsSinceEpoch(
            _expiresAtMs,
            isUtc: true,
          ),
        ),
        isFalse,
      );
      invalidDiagnostics.clear();
      expect(
        await invalidAdapter.registerOutgoing(
          _callId,
          expiresAt: DateTime.fromMillisecondsSinceEpoch(
            _expiresAtMs,
            isUtc: true,
          ),
        ),
        isFalse,
      );
      expect(invalidDiagnostics, <Object?>[
        (
          NativeOutgoingRegistrationStage.preflight,
          NativeOutgoingRegistrationStatus.rejected,
          NativeOutgoingRegistrationReason.invalidLatched,
        ),
      ]);

      await invalidAdapter.close();
      await invalidCoordinator.dispose();
      await invalidNative.events.close();

      final conflictNative = _NativeHarness()
        ..attachResult = _batch(<Map<String, Object?>>[
          _event(1, 'conflicting-outgoing-descriptor', 'presented'),
        ]);
      final conflictCoordinator = _coordinator();
      final conflictDiagnostics =
          <
            (
              NativeOutgoingRegistrationStage,
              NativeOutgoingRegistrationStatus,
              NativeOutgoingRegistrationReason,
            )
          >[];
      final conflictAdapter = _adapter(
        conflictNative,
        conflictCoordinator,
        <CallId, String>{_callId: _callHandle},
        onOutgoingRegistrationResult: (stage, status, reason) {
          conflictDiagnostics.add((stage, status, reason));
        },
      );

      await conflictCoordinator.placeCall(
        contactPeerId: 'remote-account',
        localAccountPeerId: 'local-account',
        localDeviceId: 'local-device',
      );
      await conflictAdapter.start();
      expect(
        await conflictAdapter.registerOutgoing(
          _callId,
          expiresAt: DateTime.fromMillisecondsSinceEpoch(
            _expiresAtMs,
            isUtc: true,
          ),
        ),
        isFalse,
      );
      expect(conflictDiagnostics, <Object?>[
        (
          NativeOutgoingRegistrationStage.descriptorValidation,
          NativeOutgoingRegistrationStatus.rejected,
          NativeOutgoingRegistrationReason.descriptorConflict,
        ),
      ]);
      expect(
        conflictNative.callsOf('registerOutgoingAuthenticated'),
        isEmpty,
        reason: 'an active mismatched descriptor remains fail closed',
      );

      await conflictAdapter.close();
      await conflictCoordinator.dispose();
      await conflictNative.events.close();
    },
  );

  test(
    'outgoing registration diagnostics separate native false from throw',
    () async {
      for (final throws in <bool>[false, true]) {
        final native = _NativeHarness()
          ..attachResult = _emptyBatch()
          ..results['registerOutgoingAuthenticated'] = false;
        if (throws) {
          native.onInvoke = (method) {
            if (method == 'registerOutgoingAuthenticated') {
              throw StateError('injected native failure');
            }
          };
        }
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
          <CallId, String>{_callId: _callHandle},
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
        expect(
          await adapter.registerOutgoing(
            _callId,
            expiresAt: DateTime.fromMillisecondsSinceEpoch(
              _expiresAtMs,
              isUtc: true,
            ),
          ),
          isFalse,
          reason: throws ? 'throw' : 'false',
        );
        expect(diagnostics, <Object?>[
          (
            NativeOutgoingRegistrationStage.nativeRegistration,
            throws
                ? NativeOutgoingRegistrationStatus.error
                : NativeOutgoingRegistrationStatus.rejected,
            throws
                ? NativeOutgoingRegistrationReason.nativeInvocationFailed
                : NativeOutgoingRegistrationReason.nativeRejected,
          ),
        ]);

        await adapter.close();
        await coordinator.dispose();
        await native.events.close();
      }
    },
  );

  test(
    'outgoing registration diagnostic reports adoption completion once',
    () async {
      final native = _NativeHarness()..attachResult = _emptyBatch();
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
        <CallId, String>{_callId: _callHandle},
        onOutgoingRegistrationResult: (stage, status, reason) {
          diagnostics.add((stage, status, reason));
        },
      );
      native.onInvoke = (method) {
        if (method != 'registerOutgoingAuthenticated') return;
        native.events.add(
          _batch(<Map<String, Object?>>[
            _event(1, 'diagnostic-outgoing-presented', 'presented'),
          ], direction: 'outgoing'),
        );
      };

      await adapter.start();
      await coordinator.placeCall(
        contactPeerId: 'remote-account',
        localAccountPeerId: 'local-account',
        localDeviceId: 'local-device',
      );
      expect(
        await adapter.registerOutgoing(
          _callId,
          expiresAt: DateTime.fromMillisecondsSinceEpoch(
            _expiresAtMs,
            isUtc: true,
          ),
        ),
        isTrue,
      );
      expect(diagnostics, <Object?>[
        (
          NativeOutgoingRegistrationStage.adoptionCompletion,
          NativeOutgoingRegistrationStatus.success,
          NativeOutgoingRegistrationReason.none,
        ),
      ]);

      await adapter.close();
      await coordinator.dispose();
      await native.events.close();
    },
  );

  test(
    'fresh outgoing registration fails closed without an exact adopted replay',
    () async {
      for (final replay in <String>['missing', 'mismatched', 'ack-refused']) {
        final native = _NativeHarness()..attachResult = _emptyBatch();
        if (replay == 'ack-refused') {
          native.results['acknowledge'] = false;
        }
        final coordinator = _coordinator();
        final adapter = _adapter(native, coordinator, <CallId, String>{
          _callId: _callHandle,
        });
        native.onInvoke = (method) {
          if (method != 'registerOutgoingAuthenticated' ||
              replay == 'missing') {
            return;
          }
          native.events.add(
            _batch(<Map<String, Object?>>[
              _event(1, 'outgoing-$replay', 'presented'),
            ], direction: replay == 'mismatched' ? 'incoming' : 'outgoing'),
          );
        };

        await adapter.start();
        await coordinator.placeCall(
          contactPeerId: 'remote-account',
          localAccountPeerId: 'local-account',
          localDeviceId: 'local-device',
        );

        expect(
          await adapter.registerOutgoing(
            _callId,
            expiresAt: DateTime.fromMillisecondsSinceEpoch(
              _expiresAtMs,
              isUtc: true,
            ),
          ),
          isFalse,
          reason: replay,
        );
        expect(native.callsOf('failClosed'), hasLength(1), reason: replay);
        expect(adapter.isBoundTo(_callId), isFalse, reason: replay);

        await adapter.close();
        await coordinator.dispose();
        await native.events.close();
      }
    },
  );

  test('outgoing replay adoption refusal fails closed', () async {
    final native = _NativeHarness()
      ..attachResult = _batch(<Map<String, Object?>>[
        _event(1, 'outgoing-adopt-refused', 'presented'),
      ], direction: 'outgoing')
      ..results['adopt'] = false;
    final coordinator = _coordinator();
    final adapter = _adapter(native, coordinator, <CallId, String>{
      _callId: _callHandle,
    });

    await coordinator.placeCall(
      contactPeerId: 'remote-account',
      localAccountPeerId: 'local-account',
      localDeviceId: 'local-device',
    );
    await adapter.start();

    expect(
      await adapter.registerOutgoing(
        _callId,
        expiresAt: DateTime.fromMillisecondsSinceEpoch(
          _expiresAtMs,
          isUtc: true,
        ),
      ),
      isFalse,
    );
    expect(native.callsOf('adopt'), hasLength(1));
    expect(native.callsOf('acknowledge'), isEmpty);
    expect(native.callsOf('failClosed'), hasLength(1));
    expect(adapter.isBoundTo(_callId), isFalse);

    await adapter.close();
    await coordinator.dispose();
    await native.events.close();
  });

  test(
    'new authenticated incoming presentation acknowledges native adoption',
    () async {
      final native = _NativeHarness()..attachResult = _emptyBatch();
      final coordinator = _coordinator();
      final adapter = _adapter(native, coordinator, <CallId, String>{
        _callId: _callHandle,
      });
      native.onInvoke = (method) {
        if (method != 'presentAuthenticated') return;
        native.events.add(
          _batch(<Map<String, Object?>>[
            _event(1, 'incoming-native-presented', 'presented'),
          ]),
        );
      };

      await adapter.start();
      await _prepareIncoming(coordinator);
      expect(await adapter.present(_presentation()), isTrue);
      await _until(
        () => native
            .callsOf('acknowledge')
            .any((call) => call.arguments['disposition'] == 'ADOPTED'),
      );

      expect(native.callsOf('adopt'), isEmpty);
      expect(
        native.callsOf('acknowledge').single.arguments['throughSequence'],
        1,
      );

      await adapter.close();
      await coordinator.dispose();
      await native.events.close();
    },
  );

  test(
    'recreated outgoing descriptor adopts without a second Telecom call',
    () async {
      final native = _NativeHarness()
        ..attachResult = _batch(<Map<String, Object?>>[
          _event(1, 'recreated-outgoing-presented', 'presented'),
        ], direction: 'outgoing');
      final coordinator = _coordinator();
      final adapter = _adapter(native, coordinator, <CallId, String>{
        _callId: _callHandle,
      });

      await coordinator.placeCall(
        contactPeerId: 'remote-account',
        localAccountPeerId: 'local-account',
        localDeviceId: 'local-device',
      );
      await adapter.start();

      expect(
        await adapter.registerOutgoing(
          _callId,
          expiresAt: DateTime.fromMillisecondsSinceEpoch(
            _expiresAtMs,
            isUtc: true,
          ),
        ),
        isTrue,
      );
      expect(native.callsOf('adopt'), hasLength(1));
      expect(native.callsOf('registerOutgoingAuthenticated'), isEmpty);
      expect(
        native.callsOf('acknowledge').single.arguments['disposition'],
        'ADOPTED',
      );

      await adapter.close();
      await coordinator.dispose();
      await native.events.close();
    },
  );

  test('false presentation and adoption results stay fail closed', () async {
    final directNative = _NativeHarness()
      ..attachResult = _emptyBatch()
      ..results['presentAuthenticated'] = false
      ..results['detach'] = false;
    final directCoordinator = _coordinator();
    final directAdapter = _adapter(
      directNative,
      directCoordinator,
      <CallId, String>{_callId: _callHandle},
    );

    await directAdapter.start();
    expect(await directAdapter.present(_presentation()), isFalse);
    await directAdapter.close();
    expect(directNative.callsOf('detach'), hasLength(1));
    await directCoordinator.dispose();
    await directNative.events.close();

    final adoptedNative = _NativeHarness()
      ..attachResult = _batch(<Map<String, Object?>>[
        _event(1, 'presented-1', 'presented'),
      ])
      ..results['adopt'] = false;
    final adoptedCoordinator = _coordinator();
    final adoptedAdapter = _adapter(
      adoptedNative,
      adoptedCoordinator,
      <CallId, String>{_callId: _callHandle},
    );

    await adoptedAdapter.start();
    expect(await adoptedAdapter.present(_presentation()), isFalse);
    expect(adoptedNative.callsOf('acknowledge'), isEmpty);
    await adoptedAdapter.close();
    await adoptedCoordinator.dispose();
    await adoptedNative.events.close();
  });

  test(
    'adopts a pre-start answer but dispatches it only after ringing',
    () async {
      final native = _NativeHarness()..attachResult = _emptyBatch();
      native.onAttach = () => native.events.add(
        _batch(<Map<String, Object?>>[
          _event(1, 'native-presented-1', 'presented'),
          _event(2, 'native-answer-2', 'answer'),
        ]),
      );
      final coordinator = _coordinator();
      final handles = <CallId, String>{};
      final adapter = _adapter(native, coordinator, handles);

      await adapter.start();
      await _prepareIncoming(coordinator);
      handles[_callId] = _callHandle;

      expect(await adapter.present(_presentation()), isTrue);
      expect(coordinator.activeSession?.state, CallState.incomingValidating);
      expect(
        coordinator.activeSession?.recentEventIds,
        isNot(contains(_nativeEventId('native-answer-2'))),
      );
      expect(native.callsOf('adopt'), hasLength(1));
      expect(
        native.callsOf('acknowledge').map((call) => call.arguments),
        contains(
          equals(<String, Object?>{
            'version': 1,
            'callHandle': _callHandle,
            'throughSequence': 1,
            'disposition': 'ADOPTED',
          }),
        ),
      );

      await _showSystemUi(coordinator);
      await _until(
        () => coordinator.activeSession?.state == CallState.accepted,
      );
      await _until(
        () => native
            .callsOf('acknowledge')
            .any((call) => call.arguments['throughSequence'] == 2),
      );

      expect(
        coordinator.activeSession?.recentEventIds,
        contains(_nativeEventId('native-answer-2')),
      );
      expect(native.callsOf('acknowledge').last.arguments, {
        'version': 1,
        'callHandle': _callHandle,
        'throughSequence': 2,
        'disposition': 'NONE',
      });
      expect(
        native.callsOf('project').map((call) => call.arguments['state']),
        containsAllInOrder(<String>['ringing', 'accepted']),
      );

      native.events.add(
        _batch(<Map<String, Object?>>[
          _event(1, 'native-presented-1', 'presented'),
          _event(2, 'native-answer-2', 'answer'),
        ], phase: 'journal'),
      );
      await _settle();
      expect(
        coordinator.activeSession?.recentEventIds.where(
          (id) => id == _nativeEventId('native-answer-2'),
        ),
        hasLength(1),
      );
      expect(
        native
            .callsOf('acknowledge')
            .where((call) => call.arguments['throughSequence'] == 2),
        hasLength(1),
      );

      await adapter.close();
      await coordinator.dispose();
      await native.events.close();
    },
  );

  test(
    'accepts the durable pre-start to journal transition only after adoption',
    () async {
      final native = _NativeHarness()
        ..attachResult = _batch(<Map<String, Object?>>[
          _event(1, 'native-presented-before-adoption', 'presented'),
        ])
        ..audioState = <String, Object?>{
          'version': 1,
          'active': false,
          'muted': false,
          'route': 'speaker',
          'availableRoutes': <Object?>['speaker'],
        };
      final coordinator = _coordinator();
      final adapter = _adapter(native, coordinator, <CallId, String>{
        _callId: _callHandle,
      });

      await adapter.start();
      await _prepareIncoming(coordinator);
      expect(await adapter.present(_presentation()), isTrue);

      native.events.add(
        _batch(<Map<String, Object?>>[
          _event(2, 'native-route-after-adoption', 'routeChanged'),
        ], phase: 'journal'),
      );
      await _until(
        () => native
            .callsOf('acknowledge')
            .any((call) => call.arguments['throughSequence'] == 2),
      );

      expect(native.callsOf('detach'), isEmpty);
      expect(adapter.selectedRoute, CallAudioOutputRoute.speaker);

      await adapter.close();
      await coordinator.dispose();
      await native.events.close();
    },
  );

  test(
    'every coordinator-owned terminal path ends and acknowledges native once',
    () async {
      final cases =
          <
            ({
              CallEventType type,
              CallTimeoutKind? timeoutKind,
              bool answerFirst,
            })
          >[
            (
              type: CallEventType.decline,
              timeoutKind: null,
              answerFirst: false,
            ),
            (
              type: CallEventType.remoteTerminate,
              timeoutKind: null,
              answerFirst: false,
            ),
            (
              type: CallEventType.timeout,
              timeoutKind: CallTimeoutKind.noAnswer,
              answerFirst: false,
            ),
            (type: CallEventType.end, timeoutKind: null, answerFirst: true),
          ];

      for (final testCase in cases) {
        final native = _NativeHarness()..attachResult = _emptyBatch();
        final coordinator = _coordinator();
        final adapter = _adapter(native, coordinator, <CallId, String>{
          _callId: _callHandle,
        });
        native.onInvoke = (method) {
          if (method != 'end') return;
          native.events.add(
            _batch(<Map<String, Object?>>[
              _event(1, 'dart-terminal-presented', 'presented'),
              _event(2, 'dart-terminal-end', 'end'),
            ], phase: 'journal'),
          );
        };

        await adapter.start();
        await _prepareIncoming(coordinator);
        expect(await adapter.present(_presentation()), isTrue);
        await _showSystemUi(coordinator);
        if (testCase.answerFirst) {
          await coordinator.dispatch(
            CallEvent(
              type: CallEventType.answer,
              eventId: 'answer-before-dart-end',
              occurredAt: _now,
              callId: _callId,
              contactPeerId: 'remote-account',
            ),
          );
        }

        await coordinator.dispatch(
          CallEvent(
            type: testCase.type,
            eventId: 'dart-terminal-${testCase.type.name}',
            occurredAt: _now,
            callId: _callId,
            contactPeerId: 'remote-account',
            timeoutKind: testCase.timeoutKind,
          ),
        );

        await _until(() => native.callsOf('end').isNotEmpty);
        await _until(
          () => native
              .callsOf('acknowledge')
              .any((call) => call.arguments['disposition'] == 'TERMINAL'),
        );
        expect(native.callsOf('end'), hasLength(1), reason: testCase.type.name);
        expect(
          native
              .callsOf('acknowledge')
              .where((call) => call.arguments['disposition'] == 'TERMINAL'),
          hasLength(1),
          reason: testCase.type.name,
        );
        expect(coordinator.activeSession, isNull);

        await adapter.close();
        await coordinator.dispose();
        await native.events.close();
      }
    },
  );

  test(
    'terminal batch suppresses presentation and answer before returning false',
    () async {
      final native = _NativeHarness()
        ..attachResult = _batch(<Map<String, Object?>>[
          _event(1, 'native-presented-1', 'presented'),
          _event(2, 'native-answer-2', 'answer'),
          _event(3, 'native-decline-3', 'decline'),
        ]);
      final coordinator = _coordinator();
      final handles = <CallId, String>{_callId: _callHandle};
      final adapter = _adapter(native, coordinator, handles);

      await adapter.start();
      await _prepareIncoming(coordinator);

      expect(await adapter.present(_presentation()), isFalse);
      expect(coordinator.lastSnapshot?.state, CallState.ended);
      expect(
        coordinator.lastSnapshot?.recentEventIds,
        contains(_nativeEventId('native-decline-3')),
      );
      expect(
        coordinator.lastSnapshot?.recentEventIds,
        isNot(contains(_nativeEventId('native-answer-2'))),
      );
      expect(native.callsOf('adopt'), isEmpty);
      expect(native.callsOf('presentAuthenticated'), isEmpty);
      expect(native.callsOf('acknowledge').last.arguments, {
        'version': 1,
        'callHandle': _callHandle,
        'throughSequence': 3,
        'disposition': 'TERMINAL',
      });

      await adapter.close();
      await coordinator.dispose();
      await native.events.close();
    },
  );

  test(
    'fresh process establishes a contiguous replay baseline above one',
    () async {
      final native = _NativeHarness()
        ..attachResult = _batch(<Map<String, Object?>>[
          _event(7, 'native-presented-7', 'presented'),
          _event(8, 'native-answer-8', 'answer'),
        ]);
      final coordinator = _coordinator();
      final adapter = _adapter(native, coordinator, <CallId, String>{
        _callId: _callHandle,
      });

      await adapter.start();
      await _prepareIncoming(coordinator);
      expect(await adapter.present(_presentation()), isTrue);
      expect(
        native.callsOf('acknowledge').last.arguments['throughSequence'],
        7,
      );

      await _showSystemUi(coordinator);
      await _until(
        () => coordinator.activeSession?.state == CallState.accepted,
      );
      await _until(
        () =>
            native.callsOf('acknowledge').last.arguments['throughSequence'] ==
            8,
      );

      expect(
        coordinator.activeSession?.recentEventIds,
        contains(_nativeEventId('native-answer-8')),
      );

      await adapter.close();
      await coordinator.dispose();
      await native.events.close();
    },
  );

  test(
    'post-adoption journal remains consumable after the invite expiry',
    () async {
      final native = _NativeHarness()
        ..attachResult = _batch(
          <Map<String, Object?>>[
            _event(7, 'provider-removed-7', 'providerRemoved'),
          ],
          phase: 'journal',
          expiresAtMs: _nowMs - 1,
        );
      final coordinator = _coordinator();
      final adapter = _adapter(native, coordinator, <CallId, String>{
        _callId: _callHandle,
      });

      await adapter.start();
      await _prepareIncoming(coordinator);

      expect(await adapter.present(_presentation()), isFalse);
      expect(native.callsOf('acknowledge').single.arguments, <String, Object?>{
        'version': 1,
        'callHandle': _callHandle,
        'throughSequence': 7,
        'disposition': 'TERMINAL',
      });
      expect(coordinator.activeSession, isNull);

      await adapter.close();
      await coordinator.dispose();
      await native.events.close();
    },
  );

  test(
    'empty journal replay restores its high watermark before later events',
    () async {
      final native = _NativeHarness()
        ..attachResult = _batch(
          const <Map<String, Object?>>[],
          phase: 'journal',
          highestSequence: 6,
        );
      final coordinator = _coordinator();
      final adapter = _adapter(native, coordinator, <CallId, String>{
        _callId: _callHandle,
      });

      await adapter.start();
      await _prepareIncoming(coordinator);
      expect(await adapter.present(_presentation()), isTrue);

      native.events.add(
        _batch(<Map<String, Object?>>[
          _event(7, 'provider-removed-after-empty-7', 'providerRemoved'),
        ], phase: 'journal'),
      );
      await _until(
        () => native
            .callsOf('acknowledge')
            .any((call) => call.arguments['throughSequence'] == 7),
      );

      expect(
        native.callsOf('acknowledge').last.arguments['disposition'],
        'TERMINAL',
      );

      await adapter.close();
      await coordinator.dispose();
      await native.events.close();
    },
  );

  test('expanded terminal wire events all dominate presentation', () async {
    const expectedReasons = <String, CallEndReason>{
      'remoteCancelled': CallEndReason.callerCancelled,
      'expired': CallEndReason.expired,
      'providerRemoved': CallEndReason.mediaFailed,
      'nativeFailure': CallEndReason.mediaFailed,
    };
    for (final entry in expectedReasons.entries) {
      final terminalType = entry.key;
      final native = _NativeHarness()
        ..attachResult = _batch(<Map<String, Object?>>[
          _event(1, '$terminalType-presented', 'presented'),
          _event(2, '$terminalType-terminal', terminalType),
        ]);
      final coordinator = _coordinator();
      final adapter = _adapter(native, coordinator, <CallId, String>{
        _callId: _callHandle,
      });

      await adapter.start();
      await _prepareIncoming(coordinator);

      expect(await adapter.present(_presentation()), isFalse);
      expect(coordinator.lastSnapshot?.isTerminal, isTrue);
      expect(coordinator.lastSnapshot?.endReason, entry.value);
      expect(
        coordinator.lastSnapshot?.recentEventIds,
        contains(_nativeEventId('$terminalType-terminal')),
      );
      expect(native.callsOf('acknowledge').last.arguments, {
        'version': 1,
        'callHandle': _callHandle,
        'throughSequence': 2,
        'disposition': 'TERMINAL',
      });

      await adapter.close();
      await coordinator.dispose();
      await native.events.close();
    }
  });

  test(
    'native end maps to local hangup, sends terminate, and ACKs terminal',
    () async {
      final native = _NativeHarness()..attachResult = _emptyBatch();
      final effects = _Effects();
      final coordinator = _coordinator(effects: effects);
      final adapter = _adapter(native, coordinator, <CallId, String>{
        _callId: _callHandle,
      });

      await adapter.start();
      await _prepareIncoming(coordinator);
      expect(await adapter.present(_presentation()), isTrue);

      native.events.add(
        _batch(<Map<String, Object?>>[
          _event(1, 'telecom-end-presented', 'presented'),
          _event(2, 'telecom-end-requested', 'end'),
        ], phase: 'journal'),
      );
      await _until(
        () => native
            .callsOf('acknowledge')
            .any((call) => call.arguments['disposition'] == 'TERMINAL'),
      );

      expect(coordinator.lastSnapshot?.endReason, CallEndReason.localHangup);
      expect(
        effects.executed.where(
          (effect) => effect.type == CallEffectType.sendTerminate,
        ),
        hasLength(1),
      );
      final terminalAck = native
          .callsOf('acknowledge')
          .lastWhere((call) => call.arguments['disposition'] == 'TERMINAL');
      expect(terminalAck.arguments['throughSequence'], 2);

      await adapter.close();
      await coordinator.dispose();
      await native.events.close();
    },
  );

  test(
    'a durable terminal ACK releases all binding before the next call',
    () async {
      final native = _NativeHarness()
        ..attachResult = _batch(<Map<String, Object?>>[
          _event(1, 'first-presented', 'presented'),
          _event(2, 'first-cancelled', 'remoteCancelled'),
        ]);
      final coordinator = _coordinator();
      final adapter = _adapter(native, coordinator, <CallId, String>{
        _callId: _callHandle,
        _secondCallId: _secondCallHandle,
      });

      await adapter.start();
      await _prepareIncoming(coordinator);
      expect(await adapter.present(_presentation()), isFalse);
      expect(coordinator.activeSession, isNull);

      native.events.add(
        _batch(<Map<String, Object?>>[
          _event(1, 'first-presented', 'presented'),
          _event(2, 'first-cancelled', 'remoteCancelled'),
        ]),
      );
      native.events.add(
        _batch(<Map<String, Object?>>[
          _event(
            1,
            'second-presented',
            'presented',
            callHandle: _secondCallHandle,
          ),
        ], callHandle: _secondCallHandle),
      );
      await _prepareIncomingFor(
        coordinator,
        callId: _secondCallId,
        eventSuffix: 'second',
      );

      expect(
        await adapter.present(
          IncomingCallPresentation(
            callId: _secondCallId,
            callerAccountPeerId: 'remote-account',
            expiresAt: DateTime.fromMillisecondsSinceEpoch(
              _expiresAtMs,
              isUtc: true,
            ),
          ),
        ),
        isTrue,
      );
      expect(native.callsOf('detach'), isEmpty);
      expect(
        native.callsOf('adopt').last.arguments['callHandle'],
        _secondCallHandle,
      );

      await adapter.close();
      await coordinator.dispose();
      await native.events.close();
    },
  );

  test(
    'next incoming presentation ACKs a cleanup-ready retained terminal first',
    () async {
      final retainedSnapshotAck = Completer<Object?>();
      final firstBatch = _batch(<Map<String, Object?>>[
        _event(1, 'incoming-rearm-first-presented', 'presented'),
        _event(2, 'incoming-rearm-first-cancelled', 'remoteCancelled'),
      ]);
      final native = _NativeHarness()
        ..attachResult = firstBatch
        ..queuedResults['acknowledge'] = <Object?>[
          false,
          retainedSnapshotAck.future,
        ];
      final coordinator = _coordinator();
      final adapter = _adapter(native, coordinator, <CallId, String>{
        _callId: _callHandle,
        _secondCallId: _secondCallHandle,
      });

      await adapter.start();
      await _prepareIncoming(coordinator);
      expect(await adapter.present(_presentation()), isFalse);
      expect(coordinator.activeSession, isNull);
      expect(coordinator.terminalCleanupAckReady(_callId), isTrue);
      expect(adapter.isBoundTo(_callId), isTrue);

      native.events.add(firstBatch);
      await _until(
        () =>
            native
                .callsOf('acknowledge')
                .where((call) => call.arguments['disposition'] == 'TERMINAL')
                .length >=
            2,
      );
      retainedSnapshotAck.complete(false);
      await _prepareIncomingFor(
        coordinator,
        callId: _secondCallId,
        eventSuffix: 'incoming-rearm-second',
      );

      expect(
        await adapter.present(
          IncomingCallPresentation(
            callId: _secondCallId,
            callerAccountPeerId: 'remote-account',
            expiresAt: DateTime.fromMillisecondsSinceEpoch(
              _expiresAtMs,
              isUtc: true,
            ),
          ),
        ),
        isTrue,
      );
      expect(adapter.isBoundTo(_secondCallId), isTrue);
      expect(
        native
            .callsOf('acknowledge')
            .where((call) => call.arguments['disposition'] == 'TERMINAL'),
        hasLength(3),
      );
      expect(
        native.callsOf('presentAuthenticated').single.arguments['callHandle'],
        _secondCallHandle,
      );
      final terminalAckIndex = native.calls.lastIndexWhere(
        (call) =>
            call.method == 'acknowledge' &&
            call.arguments['disposition'] == 'TERMINAL',
      );
      final presentationIndex = native.calls.indexWhere(
        (call) => call.method == 'presentAuthenticated',
      );
      expect(terminalAckIndex, lessThan(presentationIndex));

      await adapter.close();
      await coordinator.dispose();
      await native.events.close();
    },
  );

  test(
    'next incoming presentation retains the prior call when terminal ACK refuses',
    () async {
      final retainedSnapshotAck = Completer<Object?>();
      final firstBatch = _batch(<Map<String, Object?>>[
        _event(1, 'incoming-rearm-refused-presented', 'presented'),
        _event(2, 'incoming-rearm-refused-cancelled', 'remoteCancelled'),
      ]);
      final native = _NativeHarness()
        ..attachResult = firstBatch
        ..queuedResults['acknowledge'] = <Object?>[
          false,
          retainedSnapshotAck.future,
        ];
      final coordinator = _coordinator();
      final adapter = _adapter(native, coordinator, <CallId, String>{
        _callId: _callHandle,
        _secondCallId: _secondCallHandle,
      });

      await adapter.start();
      await _prepareIncoming(coordinator);
      expect(await adapter.present(_presentation()), isFalse);
      expect(coordinator.terminalCleanupAckReady(_callId), isTrue);
      native.events.add(firstBatch);
      await _until(
        () =>
            native
                .callsOf('acknowledge')
                .where((call) => call.arguments['disposition'] == 'TERMINAL')
                .length >=
            2,
      );
      retainedSnapshotAck.complete(false);
      native.results['acknowledge'] = false;
      await _prepareIncomingFor(
        coordinator,
        callId: _secondCallId,
        eventSuffix: 'incoming-rearm-refused-second',
      );
      final terminalAcksBeforeSecondPresentation = native
          .callsOf('acknowledge')
          .where((call) => call.arguments['disposition'] == 'TERMINAL')
          .length;

      expect(
        await adapter.present(
          IncomingCallPresentation(
            callId: _secondCallId,
            callerAccountPeerId: 'remote-account',
            expiresAt: DateTime.fromMillisecondsSinceEpoch(
              _expiresAtMs,
              isUtc: true,
            ),
          ),
        ),
        isFalse,
      );
      expect(adapter.isBoundTo(_callId), isTrue);
      expect(native.callsOf('presentAuthenticated'), isEmpty);
      expect(
        native
            .callsOf('acknowledge')
            .where((call) => call.arguments['disposition'] == 'TERMINAL'),
        hasLength(terminalAcksBeforeSecondPresentation + 1),
      );

      await adapter.close();
      await coordinator.dispose();
      await native.events.close();
    },
  );

  test(
    'terminal projection reconciles delayed replay before next outgoing call',
    () async {
      final callIds = <CallId>[_callId, _secondCallId].iterator;
      final native = _NativeHarness()..attachResult = _emptyBatch();
      final coordinator = _coordinator(
        idSource: () {
          expect(callIds.moveNext(), isTrue);
          return callIds.current;
        },
      );
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
        <CallId, String>{
          _callId: _callHandle,
          _secondCallId: _secondCallHandle,
        },
        projectTerminalBeforeEnd: true,
        onOutgoingRegistrationResult: (stage, status, reason) {
          diagnostics.add((stage, status, reason));
        },
      );
      var outgoingRegistrations = 0;
      native.onInvokeWithArguments = (method, arguments) {
        if (method == 'registerOutgoingAuthenticated') {
          final first = outgoingRegistrations++ == 0;
          final handle = first ? _callHandle : _secondCallHandle;
          native.events.add(
            _batch(
              <Map<String, Object?>>[
                _event(
                  1,
                  first
                      ? 'first-outgoing-presented'
                      : 'second-outgoing-presented',
                  'presented',
                  callHandle: handle,
                ),
              ],
              callHandle: handle,
              direction: 'outgoing',
            ),
          );
          return;
        }
        if (method == 'project' && arguments['state'] == 'ended') {
          native.attachResult = _batch(
            <Map<String, Object?>>[
              _event(1, 'first-outgoing-presented', 'presented'),
              _event(2, 'first-outgoing-remote-end', 'end'),
            ],
            phase: 'journal',
            direction: 'outgoing',
          );
          native.results['acknowledge'] = false;
        }
      };

      await adapter.start();
      final firstPlaced = await coordinator.placeCall(
        contactPeerId: 'remote-account',
        localAccountPeerId: 'local-account',
        localDeviceId: 'local-device',
      );
      expect(firstPlaced.snapshot.callId, _callId);
      expect(
        await adapter.registerOutgoing(
          _callId,
          expiresAt: DateTime.fromMillisecondsSinceEpoch(
            _expiresAtMs,
            isUtc: true,
          ),
        ),
        isTrue,
      );
      for (final type in <CallEventType>[
        CallEventType.outgoingInviteReady,
        CallEventType.remoteAccept,
        CallEventType.negotiationReady,
        CallEventType.mediaConnected,
      ]) {
        await coordinator.dispatch(
          CallEvent(
            type: type,
            eventId: 'first-${type.name}',
            occurredAt: _now,
            callId: _callId,
            contactPeerId: 'remote-account',
          ),
        );
      }
      expect(coordinator.activeSession?.state, CallState.connected);

      await coordinator.dispatch(
        CallEvent(
          type: CallEventType.remoteTerminate,
          eventId: 'first-remote-terminate',
          occurredAt: _now,
          callId: _callId,
          contactPeerId: 'remote-account',
        ),
      );
      await _until(
        () => native
            .callsOf('acknowledge')
            .any((call) => call.arguments['disposition'] == 'TERMINAL'),
      );
      expect(coordinator.activeSession, isNull);
      expect(coordinator.terminalCleanupAckReady(_callId), isTrue);
      expect(
        adapter.isBoundTo(_callId),
        isTrue,
        reason: 'a refused terminal ACK must retain the exact replay binding',
      );
      final secondPlaced = await coordinator.placeCall(
        contactPeerId: 'remote-account',
        localAccountPeerId: 'local-account',
        localDeviceId: 'local-device',
      );
      expect(secondPlaced.snapshot.callId, _secondCallId);
      expect(
        await adapter.registerOutgoing(
          _secondCallId,
          expiresAt: DateTime.fromMillisecondsSinceEpoch(
            _expiresAtMs,
            isUtc: true,
          ),
        ),
        isFalse,
      );
      expect(adapter.isBoundTo(_callId), isTrue);
      expect(native.callsOf('registerOutgoingAuthenticated'), hasLength(1));
      expect(diagnostics.last, (
        NativeOutgoingRegistrationStage.terminalReplay,
        NativeOutgoingRegistrationStatus.rejected,
        NativeOutgoingRegistrationReason.terminalPending,
      ));

      native.results['acknowledge'] = true;
      expect(
        await adapter.registerOutgoing(
          _secondCallId,
          expiresAt: DateTime.fromMillisecondsSinceEpoch(
            _expiresAtMs,
            isUtc: true,
          ),
        ),
        isTrue,
      );
      expect(adapter.isBoundTo(_secondCallId), isTrue);
      expect(native.callsOf('attach'), hasLength(2));
      expect(native.callsOf('registerOutgoingAuthenticated'), hasLength(2));
      expect(diagnostics.last, (
        NativeOutgoingRegistrationStage.adoptionCompletion,
        NativeOutgoingRegistrationStatus.success,
        NativeOutgoingRegistrationReason.none,
      ));

      native.events.add(
        _batch(
          <Map<String, Object?>>[
            _event(1, 'first-outgoing-presented', 'presented'),
            _event(2, 'first-outgoing-remote-end', 'end'),
          ],
          phase: 'journal',
          direction: 'outgoing',
        ),
      );
      await _settle();
      expect(adapter.isBoundTo(_secondCallId), isTrue);
      expect(native.callsOf('failClosed'), isEmpty);
      expect(
        native
            .callsOf('acknowledge')
            .where((call) => call.arguments['disposition'] == 'TERMINAL'),
        hasLength(3),
      );

      await adapter.close();
      await coordinator.dispose();
      await native.events.close();
    },
  );

  test(
    'pre-outgoing reconciliation retries retained cleanup before placement',
    () async {
      var cleanupAllowed = false;
      var cleanupRuns = 0;
      final cleanup = CallCleanupCoordinator(<CallCleanupStep>[
        CallCleanupStep('call_media', (_) async {
          cleanupRuns++;
          if (!cleanupAllowed) throw StateError('private cleanup failure');
        }, requiredForTerminalAck: true),
      ]);
      final native = _NativeHarness()
        ..attachResult = _batch(<Map<String, Object?>>[
          _event(1, 'preflight-old-presented', 'presented'),
          _event(2, 'preflight-old-terminal', 'remoteCancelled'),
        ]);
      final coordinator = _coordinator(
        cleanupCoordinator: cleanup,
        idSource: () => _secondCallId,
      );
      final adapter = _adapter(native, coordinator, <CallId, String>{
        _callId: _callHandle,
        _secondCallId: _secondCallHandle,
      });

      await adapter.start();
      await _prepareIncoming(coordinator);
      expect(await adapter.present(_presentation()), isFalse);
      await _until(() => cleanupRuns >= 2);
      expect(adapter.isBoundTo(_callId), isTrue);

      expect(await adapter.reconcileBeforeOutgoing(), isFalse);
      expect(adapter.isBoundTo(_callId), isTrue);
      expect(
        native
            .callsOf('acknowledge')
            .where((call) => call.arguments['disposition'] == 'TERMINAL'),
        isEmpty,
      );

      cleanupAllowed = true;
      native.results['acknowledge'] = false;
      expect(await adapter.reconcileBeforeOutgoing(), isFalse);
      expect(coordinator.terminalCleanupAckReady(_callId), isTrue);
      expect(adapter.isBoundTo(_callId), isTrue);
      expect(
        native
            .callsOf('acknowledge')
            .where((call) => call.arguments['disposition'] == 'TERMINAL'),
        hasLength(1),
      );

      native.results['acknowledge'] = true;
      expect(await adapter.reconcileBeforeOutgoing(), isTrue);
      expect(adapter.isBoundTo(_callId), isFalse);
      expect(
        native
            .callsOf('acknowledge')
            .where((call) => call.arguments['disposition'] == 'TERMINAL'),
        hasLength(2),
      );

      native.onInvokeWithArguments = (method, _) {
        if (method != 'registerOutgoingAuthenticated') return;
        native.events.add(
          _batch(
            <Map<String, Object?>>[
              _event(
                1,
                'preflight-new-presented',
                'presented',
                callHandle: _secondCallHandle,
              ),
            ],
            callHandle: _secondCallHandle,
            direction: 'outgoing',
          ),
        );
      };
      final placed = await coordinator.placeCall(
        contactPeerId: 'remote-account',
        localAccountPeerId: 'local-account',
        localDeviceId: 'local-device',
      );
      expect(placed.snapshot.callId, _secondCallId);
      expect(
        await adapter.registerOutgoing(
          _secondCallId,
          expiresAt: DateTime.fromMillisecondsSinceEpoch(
            _expiresAtMs,
            isUtc: true,
          ),
        ),
        isTrue,
      );
      expect(adapter.isBoundTo(_secondCallId), isTrue);

      await adapter.close();
      await coordinator.dispose();
      await native.events.close();
    },
  );

  test(
    'next outgoing registration retries retained terminal without stream replay',
    () async {
      var cleanupAllowed = false;
      var cleanupRuns = 0;
      final cleanup = CallCleanupCoordinator(<CallCleanupStep>[
        CallCleanupStep('call_media', (_) async {
          cleanupRuns++;
          if (!cleanupAllowed) throw StateError('private cleanup failure');
        }, requiredForTerminalAck: true),
      ]);
      final callIds = <CallId>[_callId, _secondCallId].iterator;
      final native = _NativeHarness()..attachResult = _emptyBatch();
      final coordinator = _coordinator(
        cleanupCoordinator: cleanup,
        idSource: () {
          expect(callIds.moveNext(), isTrue);
          return callIds.current;
        },
      );
      final adapter = _adapter(native, coordinator, <CallId, String>{
        _callId: _callHandle,
        _secondCallId: _secondCallHandle,
      }, projectTerminalBeforeEnd: true);
      var outgoingRegistrations = 0;
      native.onInvokeWithArguments = (method, arguments) {
        if (method == 'registerOutgoingAuthenticated') {
          final first = outgoingRegistrations++ == 0;
          final handle = first ? _callHandle : _secondCallHandle;
          native.events.add(
            _batch(
              <Map<String, Object?>>[
                _event(
                  1,
                  first
                      ? 'cleanup-first-outgoing-presented'
                      : 'cleanup-second-outgoing-presented',
                  'presented',
                  callHandle: handle,
                ),
              ],
              callHandle: handle,
              direction: 'outgoing',
            ),
          );
          return;
        }
        if (method == 'project' && arguments['state'] == 'ended') {
          native.attachResult = _batch(
            <Map<String, Object?>>[
              _event(1, 'cleanup-first-outgoing-presented', 'presented'),
              _event(2, 'cleanup-first-outgoing-remote-end', 'end'),
            ],
            phase: 'journal',
            direction: 'outgoing',
          );
        }
      };

      await adapter.start();
      await coordinator.placeCall(
        contactPeerId: 'remote-account',
        localAccountPeerId: 'local-account',
        localDeviceId: 'local-device',
      );
      expect(
        await adapter.registerOutgoing(
          _callId,
          expiresAt: DateTime.fromMillisecondsSinceEpoch(
            _expiresAtMs,
            isUtc: true,
          ),
        ),
        isTrue,
      );
      for (final type in <CallEventType>[
        CallEventType.outgoingInviteReady,
        CallEventType.remoteAccept,
        CallEventType.negotiationReady,
        CallEventType.mediaConnected,
      ]) {
        await coordinator.dispatch(
          CallEvent(
            type: type,
            eventId: 'cleanup-first-${type.name}',
            occurredAt: _now,
            callId: _callId,
            contactPeerId: 'remote-account',
          ),
        );
      }

      await coordinator.dispatch(
        CallEvent(
          type: CallEventType.remoteTerminate,
          eventId: 'cleanup-first-remote-terminate',
          occurredAt: _now,
          callId: _callId,
          contactPeerId: 'remote-account',
        ),
      );
      await _until(() => cleanupRuns >= 2);
      expect(adapter.isBoundTo(_callId), isTrue);
      expect(
        native
            .callsOf('acknowledge')
            .where((call) => call.arguments['disposition'] == 'TERMINAL'),
        isEmpty,
      );

      await coordinator.placeCall(
        contactPeerId: 'remote-account',
        localAccountPeerId: 'local-account',
        localDeviceId: 'local-device',
      );
      expect(
        await adapter.registerOutgoing(
          _secondCallId,
          expiresAt: DateTime.fromMillisecondsSinceEpoch(
            _expiresAtMs,
            isUtc: true,
          ),
        ),
        isFalse,
      );
      expect(cleanupRuns, 2);
      expect(adapter.isBoundTo(_callId), isTrue);
      expect(native.callsOf('registerOutgoingAuthenticated'), hasLength(1));

      cleanupAllowed = true;
      expect(await coordinator.retryTerminalCleanup(_callId), isTrue);
      expect(cleanupRuns, 3);
      expect(
        await adapter.registerOutgoing(
          _secondCallId,
          expiresAt: DateTime.fromMillisecondsSinceEpoch(
            _expiresAtMs,
            isUtc: true,
          ),
        ),
        isTrue,
      );
      expect(
        native
            .callsOf('acknowledge')
            .where((call) => call.arguments['disposition'] == 'TERMINAL'),
        hasLength(1),
      );
      expect(native.callsOf('registerOutgoingAuthenticated'), hasLength(2));

      await adapter.close();
      await coordinator.dispose();
      await native.events.close();
    },
  );

  test(
    'effect-tail outgoing registration ACKs cleanup-ready terminal without dispatch',
    () async {
      final effects = _Effects();
      final retainedSnapshotAck = Completer<Object?>();
      final native = _NativeHarness()
        ..attachResult = _batch(<Map<String, Object?>>[
          _event(1, 'reentrant-old-presented', 'presented'),
          _event(2, 'reentrant-old-terminal', 'remoteCancelled'),
        ])
        ..queuedResults['acknowledge'] = <Object?>[
          false,
          retainedSnapshotAck.future,
        ];
      final coordinator = _coordinator(
        effects: effects,
        idSource: () => _secondCallId,
      );
      final adapter = _adapter(native, coordinator, <CallId, String>{
        _callId: _callHandle,
        _secondCallId: _secondCallHandle,
      });

      await adapter.start();
      await _prepareIncoming(coordinator);
      expect(await adapter.present(_presentation()), isFalse);
      expect(coordinator.activeSession, isNull);
      expect(coordinator.terminalCleanupAckReady(_callId), isTrue);
      expect(adapter.isBoundTo(_callId), isTrue);
      await _until(
        () =>
            native
                .callsOf('acknowledge')
                .where((call) => call.arguments['disposition'] == 'TERMINAL')
                .length >=
            2,
      );
      retainedSnapshotAck.complete(false);

      native.onInvokeWithArguments = (method, _) {
        if (method != 'registerOutgoingAuthenticated') return;
        native.events.add(
          _batch(
            <Map<String, Object?>>[
              _event(
                1,
                'reentrant-new-presented',
                'presented',
                callHandle: _secondCallHandle,
              ),
            ],
            callHandle: _secondCallHandle,
            direction: 'outgoing',
          ),
        );
      };
      final registrationStarted = Completer<void>();
      effects.onPrepareOutgoingInvite = (snapshot) async {
        registrationStarted.complete();
        final registered = await adapter.registerOutgoing(
          snapshot.callId!,
          expiresAt: DateTime.fromMillisecondsSinceEpoch(
            _expiresAtMs,
            isUtc: true,
          ),
        );
        if (!registered) return null;
        return CallEvent(
          type: CallEventType.outgoingInviteReady,
          eventId: 'reentrant-outgoing-ready',
          occurredAt: _now,
          callId: snapshot.callId,
          contactPeerId: snapshot.contactPeerId,
        );
      };

      final placement = coordinator.placeCall(
        contactPeerId: 'remote-account',
        localAccountPeerId: 'local-account',
        localDeviceId: 'local-device',
      );
      await registrationStarted.future;
      await _until(
        () => native.callsOf('registerOutgoingAuthenticated').isNotEmpty,
      );
      final placed = await placement;

      expect(placed.snapshot.callId, _secondCallId);
      expect(placed.snapshot.state, CallState.preparing);
      expect(adapter.isBoundTo(_secondCallId), isTrue);
      expect(native.callsOf('registerOutgoingAuthenticated'), hasLength(1));
      expect(
        native
            .callsOf('acknowledge')
            .where((call) => call.arguments['disposition'] == 'TERMINAL'),
        hasLength(3),
      );

      await adapter.close();
      await coordinator.dispose();
      await native.events.close();
    },
  );

  test(
    'terminal media cleanup does not reenter the native journal tail',
    () async {
      late AndroidCallLifecycleAdapter adapter;
      Future<void>? mediaClose;
      var engineClosed = false;
      var microphoneLeaseReleased = false;
      final cleanup = CallCleanupCoordinator(<CallCleanupStep>[
        CallCleanupStep(
          'call_media',
          (_) => mediaClose ??= () async {
            var releaseFailed = false;
            try {
              await adapter.selectOutputRoute(
                CallAudioOutputRoute.systemDefault,
              );
            } catch (_) {
              releaseFailed = true;
            }
            try {
              await adapter.deactivate();
            } catch (_) {
              releaseFailed = true;
            }
            engineClosed = true;
            microphoneLeaseReleased = true;
            if (releaseFailed) throw StateError('private release failure');
          }(),
          requiredForTerminalAck: true,
        ),
      ], stepTimeout: const Duration(milliseconds: 20));
      final native = _NativeHarness()
        ..attachResult = _emptyBatch()
        ..results['requestRoute'] = false
        ..results['deactivateAudio'] = false;
      final coordinator = _coordinator(cleanupCoordinator: cleanup);
      adapter = _adapter(native, coordinator, <CallId, String>{
        _callId: _callHandle,
      });

      await adapter.start();
      await _prepareIncoming(coordinator);
      expect(await adapter.present(_presentation()), isTrue);
      await adapter.activateAudio();
      expect(adapter.ownsSession, isTrue);

      native.events.add(
        _batch(<Map<String, Object?>>[
          _event(1, 'terminal-cleanup-presented', 'presented'),
          _event(2, 'terminal-cleanup-ended', 'remoteCancelled'),
        ]),
      );
      await _until(() => coordinator.activeSession == null);
      await _until(() => coordinator.terminalCleanupAckReady(_callId));

      expect(engineClosed, isTrue);
      expect(microphoneLeaseReleased, isTrue);
      expect(adapter.ownsSession, isFalse);
      expect(native.callsOf('requestRoute'), isEmpty);
      expect(native.callsOf('deactivateAudio'), isEmpty);
      expect(
        native
            .callsOf('acknowledge')
            .where((call) => call.arguments['disposition'] == 'TERMINAL'),
        hasLength(1),
      );

      await adapter.close();
      await coordinator.dispose();
      await native.events.close();
    },
  );

  test(
    'terminal ACK waits for exact critical cleanup and coalesces retry',
    () async {
      var cleanupRuns = 0;
      final cleanup = CallCleanupCoordinator(<CallCleanupStep>[
        CallCleanupStep('call_media', (_) async {
          cleanupRuns++;
          if (cleanupRuns == 1) throw StateError('private cleanup failure');
        }, requiredForTerminalAck: true),
      ]);
      final native = _NativeHarness()
        ..attachResult = _batch(<Map<String, Object?>>[
          _event(1, 'cleanup-presented', 'presented'),
          _event(2, 'cleanup-cancelled', 'remoteCancelled'),
        ]);
      final coordinator = _coordinator(cleanupCoordinator: cleanup);
      final adapter = _adapter(native, coordinator, <CallId, String>{
        _callId: _callHandle,
      });

      await adapter.start();
      await _prepareIncoming(coordinator);
      expect(await adapter.present(_presentation()), isFalse);
      expect(cleanupRuns, 1);
      expect(
        native
            .callsOf('acknowledge')
            .where((call) => call.arguments['disposition'] == 'TERMINAL'),
        isEmpty,
      );

      final duplicate = _batch(<Map<String, Object?>>[
        _event(1, 'cleanup-presented', 'presented'),
        _event(2, 'cleanup-cancelled', 'remoteCancelled'),
      ]);
      native.events.add(duplicate);
      native.events.add(duplicate);
      await _until(
        () => native
            .callsOf('acknowledge')
            .any((call) => call.arguments['disposition'] == 'TERMINAL'),
      );

      expect(cleanupRuns, 2);
      expect(
        native
            .callsOf('acknowledge')
            .where((call) => call.arguments['disposition'] == 'TERMINAL'),
        hasLength(1),
      );

      await adapter.close();
      await coordinator.dispose();
      await native.events.close();
    },
  );

  test('terminal delivery timeout leaves margin for native ACK', () async {
    final effects = _Effects()..hangTerminal = true;
    final native = _NativeHarness()
      ..attachResult = _batch(<Map<String, Object?>>[
        _event(1, 'bounded-terminal-presented', 'presented'),
      ]);
    final coordinator = _coordinator(
      effects: effects,
      terminalEffectTimeout: const Duration(milliseconds: 20),
    );
    final adapter = _adapter(native, coordinator, <CallId, String>{
      _callId: _callHandle,
    });

    await adapter.start();
    await _prepareIncoming(coordinator);
    expect(await adapter.present(_presentation()), isTrue);
    await _showSystemUi(coordinator);
    final stopwatch = Stopwatch()..start();
    native.events.add(
      _batch(<Map<String, Object?>>[
        _event(2, 'bounded-terminal-decline', 'decline'),
      ], phase: 'journal'),
    );
    for (
      var attempt = 0;
      attempt < 500 &&
          !native
              .callsOf('acknowledge')
              .any((call) => call.arguments['disposition'] == 'TERMINAL');
      attempt++
    ) {
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
    stopwatch.stop();

    expect(
      native
          .callsOf('acknowledge')
          .where((call) => call.arguments['disposition'] == 'TERMINAL'),
      hasLength(1),
    );
    expect(stopwatch.elapsed, lessThan(const Duration(seconds: 1)));

    await adapter.close();
    await coordinator.dispose();
    await native.events.close();
  });

  test('terminal history timeout leaves margin for native ACK', () async {
    final never = Completer<void>();
    final native = _NativeHarness()
      ..attachResult = _batch(<Map<String, Object?>>[
        _event(1, 'bounded-history-presented', 'presented'),
      ]);
    final coordinator = _coordinator(
      history: _History(writeGate: never.future),
      terminalHistoryTimeout: const Duration(milliseconds: 20),
    );
    final adapter = _adapter(native, coordinator, <CallId, String>{
      _callId: _callHandle,
    });

    await adapter.start();
    await _prepareIncoming(coordinator);
    expect(await adapter.present(_presentation()), isTrue);
    await _showSystemUi(coordinator);
    final stopwatch = Stopwatch()..start();
    native.events.add(
      _batch(<Map<String, Object?>>[
        _event(2, 'bounded-history-decline', 'decline'),
      ], phase: 'journal'),
    );
    for (
      var attempt = 0;
      attempt < 500 &&
          !native
              .callsOf('acknowledge')
              .any((call) => call.arguments['disposition'] == 'TERMINAL');
      attempt++
    ) {
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
    stopwatch.stop();

    expect(
      native
          .callsOf('acknowledge')
          .where((call) => call.arguments['disposition'] == 'TERMINAL'),
      hasLength(1),
    );
    expect(stopwatch.elapsed, lessThan(const Duration(seconds: 1)));

    await adapter.close();
    await coordinator.dispose();
    await native.events.close();
  });

  test(
    'lifecycle invalidations refresh coarse audio and ACK monotonically',
    () async {
      final native = _NativeHarness()
        ..attachResult = _batch(<Map<String, Object?>>[
          _event(1, 'presented-1', 'presented'),
          _event(2, 'muted-2', 'muteChanged'),
          _event(3, 'route-3', 'routeChanged'),
          _event(4, 'active-4', 'audioActivated'),
          _event(5, 'inactive-5', 'audioDeactivated'),
        ])
        ..audioState = <String, Object?>{
          'version': 1,
          'active': false,
          'muted': true,
          'route': 'speaker',
          'availableRoutes': <Object?>['earpiece', 'speaker'],
        };
      final coordinator = _coordinator();
      final adapter = _adapter(native, coordinator, <CallId, String>{
        _callId: _callHandle,
      });

      await adapter.start();
      await _prepareIncoming(coordinator);
      expect(await adapter.present(_presentation()), isTrue);
      await _until(
        () =>
            native.callsOf('acknowledge').last.arguments['throughSequence'] ==
            5,
      );

      expect(
        native
            .callsOf('acknowledge')
            .map((call) => call.arguments['throughSequence']),
        <int>[1, 2, 3, 4, 5],
      );
      expect(adapter.ownsSession, isFalse);
      expect(adapter.selectedRoute, CallAudioOutputRoute.speaker);
      expect(native.callsOf('readAudioState'), hasLength(4));
      final lifecycleIds = <String>{
        _nativeEventId('muted-2'),
        _nativeEventId('route-3'),
        _nativeEventId('active-4'),
        _nativeEventId('inactive-5'),
      };
      expect(
        coordinator.activeSession?.recentEventIds.where(lifecycleIds.contains),
        isEmpty,
      );

      await adapter.close();
      await coordinator.dispose();
      await native.events.close();
    },
  );

  test(
    'native active transitions emit interruptions without command echoes',
    () async {
      final inactive = <String, Object?>{
        'version': 1,
        'active': false,
        'muted': false,
        'route': 'earpiece',
        'availableRoutes': <Object?>['earpiece', 'speaker'],
      };
      final active = <String, Object?>{...inactive, 'active': true};
      final native = _NativeHarness()
        ..attachResult = _emptyBatch()
        ..queuedResults['readAudioState'] = <Object?>[active, inactive, active];
      final coordinator = _coordinator();
      final adapter = _adapter(native, coordinator, <CallId, String>{
        _callId: _callHandle,
      });
      final interruptions = <bool>[];
      final interruptionSubscription = adapter.interruptions.listen(
        (event) => interruptions.add(event.isBeginning),
      );

      await adapter.start();
      expect(await adapter.present(_presentation()), isTrue);
      await adapter.readAudioState();

      native.events.add(
        _batch(<Map<String, Object?>>[
          _event(1, 'inactive-1', 'audioDeactivated'),
        ]),
      );
      await _until(
        () => native
            .callsOf('acknowledge')
            .any((call) => call.arguments['throughSequence'] == 1),
      );
      native.events.add(
        _batch(<Map<String, Object?>>[_event(2, 'active-2', 'audioActivated')]),
      );
      await _until(
        () => native
            .callsOf('acknowledge')
            .any((call) => call.arguments['throughSequence'] == 2),
      );

      expect(interruptions, <bool>[true, false]);

      native.onInvoke = (method) {
        switch (method) {
          case 'activateAudio':
            native.audioState = active;
            native.events.add(
              _batch(<Map<String, Object?>>[
                _event(3, 'command-active-3', 'audioActivated'),
              ]),
            );
          case 'deactivateAudio':
            native.audioState = inactive;
            native.events.add(
              _batch(<Map<String, Object?>>[
                _event(4, 'command-inactive-4', 'audioDeactivated'),
              ]),
            );
        }
      };
      await adapter.activateAudio();
      await adapter.deactivateAudio();
      await _until(
        () => native
            .callsOf('acknowledge')
            .any((call) => call.arguments['throughSequence'] == 4),
      );

      expect(interruptions, <bool>[
        true,
        false,
      ], reason: 'serialized Dart commands must not echo as interruptions');

      await adapter.close();
      await interruptionSubscription.cancel();
      await coordinator.dispose();
      await native.events.close();
    },
  );

  test(
    'native mute observations emit once and suppress duplicate state',
    () async {
      Map<String, Object?> audioState(bool muted) => <String, Object?>{
        'version': 1,
        'active': false,
        'muted': muted,
        'route': 'earpiece',
        'availableRoutes': <Object?>['earpiece', 'speaker'],
      };

      final native = _NativeHarness()
        ..attachResult = _emptyBatch()
        ..queuedResults['readAudioState'] = <Object?>[
          audioState(true),
          audioState(true),
          audioState(false),
        ];
      final coordinator = _coordinator();
      final adapter = _adapter(native, coordinator, <CallId, String>{
        _callId: _callHandle,
      });
      final muteChanges = <bool>[];
      final muteSubscription = adapter.muteChanges.listen(muteChanges.add);

      await adapter.start();
      expect(await adapter.present(_presentation()), isTrue);
      native.events.add(
        _batch(<Map<String, Object?>>[
          _event(1, 'muted-1', 'muteChanged'),
          _event(2, 'muted-duplicate-2', 'muteChanged'),
          _event(3, 'unmuted-3', 'muteChanged'),
        ]),
      );
      await _until(
        () => native
            .callsOf('acknowledge')
            .any((call) => call.arguments['throughSequence'] == 3),
      );

      expect(muteChanges, <bool>[true, false]);
      expect(native.callsOf('readAudioState'), hasLength(3));

      await adapter.close();
      await muteSubscription.cancel();
      await coordinator.dispose();
      await native.events.close();
    },
  );

  test('native mute is ACKed only after the audio track applies it', () async {
    final native = _NativeHarness()
      ..attachResult = _batch(<Map<String, Object?>>[
        _event(1, 'mute-commit-presented', 'presented'),
      ])
      ..audioState = <String, Object?>{
        'version': 1,
        'active': true,
        'muted': true,
        'route': 'earpiece',
        'availableRoutes': <Object?>['earpiece'],
      };
    final coordinator = _coordinator();
    final releaseCommit = Completer<void>();
    final requested = <bool>[];
    final adapter = _adapter(
      native,
      coordinator,
      <CallId, String>{_callId: _callHandle},
      nativeMuteApplier: (callId, muted) async {
        expect(callId, _callId);
        requested.add(muted);
        await releaseCommit.future;
        return true;
      },
    );

    await adapter.start();
    await _prepareIncoming(coordinator);
    expect(await adapter.present(_presentation()), isTrue);
    native.events.add(
      _batch(<Map<String, Object?>>[
        _event(2, 'mute-commit-event', 'muteChanged'),
      ], phase: 'journal'),
    );
    await _until(() => requested.isNotEmpty);

    expect(requested, <bool>[true]);
    expect(
      native
          .callsOf('acknowledge')
          .where((call) => call.arguments['throughSequence'] == 2),
      isEmpty,
    );

    releaseCommit.complete();
    await _until(
      () => native
          .callsOf('acknowledge')
          .any((call) => call.arguments['throughSequence'] == 2),
    );

    await adapter.close();
    await coordinator.dispose();
    await native.events.close();
  });

  test(
    'native mute waits unacked for media readiness and retries without ending',
    () async {
      final native = _NativeHarness()
        ..attachResult = _batch(<Map<String, Object?>>[
          _event(1, 'mute-not-ready-presented', 'presented'),
        ])
        ..audioState = <String, Object?>{
          'version': 1,
          'active': true,
          'muted': false,
          'route': 'earpiece',
          'availableRoutes': <Object?>['earpiece'],
        };
      final coordinator = _coordinator();
      var mediaReady = false;
      final requested = <bool>[];
      final adapter = _adapter(
        native,
        coordinator,
        <CallId, String>{_callId: _callHandle},
        nativeMuteApplier: (callId, muted) async {
          expect(callId, _callId);
          requested.add(muted);
          return mediaReady;
        },
      );

      await adapter.start();
      await _prepareIncoming(coordinator);
      expect(await adapter.present(_presentation()), isTrue);
      native.events.add(
        _batch(<Map<String, Object?>>[
          _event(2, 'mute-not-ready-event', 'muteChanged'),
        ], phase: 'journal'),
      );
      await _until(() => requested.length == 1);

      expect(requested, <bool>[false]);
      expect(
        native
            .callsOf('acknowledge')
            .where((call) => call.arguments['throughSequence'] == 2),
        isEmpty,
      );
      expect(native.callsOf('end'), isEmpty);

      mediaReady = true;
      adapter.notifyNativeMuteTargetReady(_callId);
      await _until(
        () => native
            .callsOf('acknowledge')
            .any((call) => call.arguments['throughSequence'] == 2),
      );

      expect(requested, <bool>[false, false]);
      expect(native.callsOf('end'), isEmpty);

      await adapter.close();
      await coordinator.dispose();
      await native.events.close();
    },
  );

  test(
    'failed native mute application terminates without ACKing mute',
    () async {
      final native = _NativeHarness()
        ..attachResult = _batch(<Map<String, Object?>>[
          _event(1, 'mute-failure-presented', 'presented'),
        ])
        ..audioState = <String, Object?>{
          'version': 1,
          'active': true,
          'muted': true,
          'route': 'earpiece',
          'availableRoutes': <Object?>['earpiece'],
        };
      final coordinator = _coordinator();
      final adapter = _adapter(
        native,
        coordinator,
        <CallId, String>{_callId: _callHandle},
        nativeMuteApplier: (_, _) async {
          throw StateError('private audio failure');
        },
      );

      await adapter.start();
      await _prepareIncoming(coordinator);
      expect(await adapter.present(_presentation()), isTrue);
      await _showSystemUi(coordinator);
      native.events.add(
        _batch(<Map<String, Object?>>[
          _event(2, 'mute-failure-event', 'muteChanged'),
        ], phase: 'journal'),
      );
      await _until(() => native.callsOf('end').isNotEmpty);
      await _until(() => coordinator.activeSession == null);

      expect(
        native
            .callsOf('acknowledge')
            .where((call) => call.arguments['throughSequence'] == 2),
        isEmpty,
      );
      expect(native.callsOf('end'), hasLength(1));

      await adapter.close();
      await coordinator.dispose();
      await native.events.close();
    },
  );

  test(
    'direct audio read does not consume the next native mute publication',
    () async {
      Map<String, Object?> audioState(bool muted) => <String, Object?>{
        'version': 1,
        'active': false,
        'muted': muted,
        'route': 'earpiece',
        'availableRoutes': <Object?>['earpiece', 'speaker'],
      };

      final native = _NativeHarness()
        ..attachResult = _emptyBatch()
        ..queuedResults['readAudioState'] = <Object?>[
          audioState(true),
          audioState(true),
        ];
      final coordinator = _coordinator();
      final adapter = _adapter(native, coordinator, <CallId, String>{
        _callId: _callHandle,
      });
      final muteChanges = <bool>[];
      final muteSubscription = adapter.muteChanges.listen(muteChanges.add);

      await adapter.start();
      expect(await adapter.present(_presentation()), isTrue);
      expect((await adapter.readAudioState()).muted, isTrue);

      native.events.add(
        _batch(<Map<String, Object?>>[
          _event(1, 'muted-after-read-1', 'muteChanged'),
        ]),
      );
      await _until(
        () => native
            .callsOf('acknowledge')
            .any((call) => call.arguments['throughSequence'] == 1),
      );

      expect(muteChanges, <bool>[true]);

      await adapter.close();
      await muteSubscription.cancel();
      await coordinator.dispose();
      await native.events.close();
    },
  );

  test(
    'acknowledges an admitted answer even when media subsequently fails',
    () async {
      final native = _NativeHarness()
        ..attachResult = _batch(<Map<String, Object?>>[
          _event(1, 'native-presented-1', 'presented'),
          _event(2, 'native-answer-2', 'answer'),
        ]);
      final effects = _Effects();
      final coordinator = _coordinator(effects: effects);
      final adapter = _adapter(native, coordinator, <CallId, String>{
        _callId: _callHandle,
      });

      await adapter.start();
      await _prepareIncoming(coordinator);
      expect(await adapter.present(_presentation()), isTrue);
      effects.failOn = CallEffectType.prepareAcceptedMedia;

      await _showSystemUi(coordinator);
      await _until(() => coordinator.lastSnapshot?.isTerminal == true);
      await _until(
        () => native
            .callsOf('acknowledge')
            .any((call) => call.arguments['throughSequence'] == 2),
      );

      expect(
        native
            .callsOf('acknowledge')
            .any((call) => call.arguments['throughSequence'] == 2),
        isTrue,
      );

      await adapter.close();
      await coordinator.dispose();
      await native.events.close();
    },
  );

  test(
    'answer coordinator effect can read supported routes without self-waiting',
    () async {
      final native = _NativeHarness()
        ..attachResult = _batch(<Map<String, Object?>>[
          _event(1, 'route-read-presented-1', 'presented'),
          _event(2, 'route-read-answer-2', 'answer'),
        ])
        ..audioState = <String, Object?>{
          'version': 1,
          'active': true,
          'muted': false,
          'route': 'earpiece',
          'availableRoutes': <Object?>['earpiece', 'speaker'],
        };
      final effects = _Effects();
      final coordinator = _coordinator(effects: effects);
      late final AndroidCallLifecycleAdapter adapter;
      final routeRead = Completer<List<CallAudioOutputRoute>>();
      effects.onPrepareAcceptedMedia = (_) async {
        final routes = await adapter.supportedOutputRoutes();
        routeRead.complete(routes);
        return null;
      };
      adapter = _adapter(native, coordinator, <CallId, String>{
        _callId: _callHandle,
      });

      await adapter.start();
      await _prepareIncoming(coordinator);
      expect(await adapter.present(_presentation()), isTrue);
      await _showSystemUi(coordinator);

      expect(
        await routeRead.future.timeout(const Duration(milliseconds: 100)),
        <CallAudioOutputRoute>[
          CallAudioOutputRoute.earpiece,
          CallAudioOutputRoute.speaker,
        ],
      );
      await _until(
        () => coordinator.activeSession?.state == CallState.accepted,
      );
      expect(native.callsOf('readAudioState'), hasLength(1));

      await adapter.close();
      await coordinator.dispose();
      await native.events.close();
    },
  );

  test(
    'false adoption ACK does not advance or dispatch the buffered answer',
    () async {
      final native = _NativeHarness()
        ..attachResult = _batch(<Map<String, Object?>>[
          _event(1, 'native-presented-1', 'presented'),
          _event(2, 'native-answer-2', 'answer'),
        ])
        ..results['acknowledge'] = false;
      final coordinator = _coordinator();
      final adapter = _adapter(native, coordinator, <CallId, String>{
        _callId: _callHandle,
      });

      await adapter.start();
      await _prepareIncoming(coordinator);
      expect(await adapter.present(_presentation()), isTrue);
      await _showSystemUi(coordinator);
      await _settle();

      expect(coordinator.activeSession?.state, CallState.ringing);
      expect(
        coordinator.activeSession?.recentEventIds,
        isNot(contains(_nativeEventId('native-answer-2'))),
      );

      native.results['acknowledge'] = true;
      native.events.add(
        _batch(<Map<String, Object?>>[
          _event(1, 'native-presented-1', 'presented'),
          _event(2, 'native-answer-2', 'answer'),
        ]),
      );
      await _until(
        () => coordinator.activeSession?.state == CallState.accepted,
      );
      expect(
        native.callsOf('acknowledge').last.arguments['throughSequence'],
        2,
      );

      await adapter.close();
      await coordinator.dispose();
      await native.events.close();
    },
  );

  test(
    'rejects malformed, unknown, unordered, and oversized batches',
    () async {
      final invalid = <({String name, Object? batch, int maxEvents})>[
        (
          name: 'unknown top-level key',
          batch: <String, Object?>{..._emptyBatch(), 'peerId': 'secret'},
          maxEvents: 8,
        ),
        (
          name: 'duplicate sequence',
          batch: _batch(<Map<String, Object?>>[
            _event(1, 'first', 'presented'),
            _event(1, 'second', 'answer'),
          ]),
          maxEvents: 8,
        ),
        (
          name: 'out of order',
          batch: _batch(<Map<String, Object?>>[
            _event(2, 'second', 'answer'),
            _event(1, 'first', 'presented'),
          ]),
          maxEvents: 8,
        ),
        (
          name: 'unknown event',
          batch: _batch(<Map<String, Object?>>[
            _event(1, 'unknown', 'openChat'),
          ]),
          maxEvents: 8,
        ),
        (
          name: 'malformed event',
          batch: _batch(<Map<String, Object?>>[
            <String, Object?>{
              'callHandle': _callHandle,
              'sequence': 1,
              'eventId': 7,
              'type': 'answer',
              'occurredAtMs': _nowMs,
            },
          ]),
          maxEvents: 8,
        ),
        (
          name: 'noncanonical event id',
          batch: _batch(<Map<String, Object?>>[
            <String, Object?>{
              ..._event(1, 'canonical-source', 'answer'),
              'eventId': 'not-a-canonical-event-id',
            },
          ]),
          maxEvents: 8,
        ),
        (
          name: 'oversized batch',
          batch: _batch(<Map<String, Object?>>[
            _event(1, 'one', 'presented'),
            _event(2, 'two', 'presented'),
            _event(3, 'three', 'presented'),
          ]),
          maxEvents: 2,
        ),
      ];

      for (final scenario in invalid) {
        final native = _NativeHarness()..attachResult = scenario.batch;
        final coordinator = _coordinator();
        final adapter = AndroidCallLifecycleAdapter(
          invokeMethod: native.invoke,
          nativeEvents: native.events.stream,
          coordinator: coordinator,
          resolveAuthenticatedHandle: (_) => _callHandle,
          clock: () => _now,
          maxEventsPerBatch: scenario.maxEvents,
        );

        await adapter.start();

        expect(
          await adapter.present(_presentation()),
          isFalse,
          reason: scenario.name,
        );
        expect(native.callsOf('adopt'), isEmpty, reason: scenario.name);
        expect(
          native.callsOf('presentAuthenticated'),
          isEmpty,
          reason: scenario.name,
        );
        expect(native.callsOf('acknowledge'), isEmpty, reason: scenario.name);
        await _until(() => native.callsOf('failClosed').isNotEmpty);
        expect(native.callsOf('failClosed').single.arguments, <String, Object?>{
          'version': 1,
        }, reason: scenario.name);
        expect(native.callsOf('detach'), isEmpty, reason: scenario.name);

        await adapter.close();
        expect(native.callsOf('detach'), hasLength(1), reason: scenario.name);
        await coordinator.dispose();
        await native.events.close();
      }
    },
  );

  test(
    'malformed adopted event cleans canonical call before native fail-closed',
    () async {
      for (final cleanupFails in <bool>[false, true]) {
        final order = <String>[];
        final native = _NativeHarness()
          ..attachResult = _batch(<Map<String, Object?>>[
            _event(1, 'malformed-adopted-presented', 'presented'),
          ])
          ..onInvoke = (method) {
            if (method == 'failClosed') order.add('native_fail_closed');
          };
        final cleanup = CallCleanupCoordinator(<CallCleanupStep>[
          CallCleanupStep('call_media', (_) async {
            order.add('call_media');
            if (cleanupFails) throw StateError('injected cleanup failure');
          }, requiredForTerminalAck: true),
        ]);
        final coordinator = _coordinator(cleanupCoordinator: cleanup);
        final adapter = _adapter(native, coordinator, <CallId, String>{
          _callId: _callHandle,
        });

        await adapter.start();
        await _prepareIncoming(coordinator);
        expect(await adapter.present(_presentation()), isTrue);
        await _showSystemUi(coordinator);

        native.events.add(<String, Object?>{
          ..._batch(<Map<String, Object?>>[
            _event(1, 'malformed-adopted-presented', 'presented'),
          ], phase: 'journal'),
          'unknown': true,
        });

        await _until(() => native.callsOf('failClosed').isNotEmpty);
        expect(order, <String>[
          'call_media',
          'native_fail_closed',
        ], reason: 'cleanupFails=$cleanupFails');
        expect(coordinator.lastSnapshot?.isTerminal, isTrue);
        expect(coordinator.activeSession, isNull);
        expect(coordinator.terminalCleanupAckReady(_callId), !cleanupFails);
        expect(
          native
              .callsOf('acknowledge')
              .where((call) => call.arguments['disposition'] == 'TERMINAL'),
          isEmpty,
          reason: 'fail-closed teardown is replayed before terminal ACK',
        );
        expect(native.callsOf('failClosed').single.arguments, {'version': 1});

        await adapter.close();
        await coordinator.dispose();
        await native.events.close();
      }
    },
  );

  test(
    'close fences a pending capability result before native attach',
    () async {
      for (final outcome in <String>['enabled', 'refused', 'error']) {
        final capability = Completer<Object?>();
        final native = _NativeHarness()
          ..attachResult = _emptyBatch()
          ..results['setCapabilityEnabled'] = capability.future;
        final coordinator = _coordinator();
        final adapter = _adapter(native, coordinator, const <CallId, String>{});

        final start = adapter.start();
        await _until(() => native.callsOf('setCapabilityEnabled').isNotEmpty);
        final close = adapter.close();
        await _until(() => native.callsOf('detach').isNotEmpty);
        if (outcome == 'enabled') {
          capability.complete(true);
        } else if (outcome == 'refused') {
          capability.complete(false);
        } else {
          capability.completeError(StateError('injected capability failure'));
        }

        await start;
        await close;
        expect(native.callsOf('attach'), isEmpty, reason: outcome);
        expect(native.callsOf('failClosed'), isEmpty, reason: outcome);
        expect(native.callsOf('detach'), hasLength(1), reason: outcome);

        await coordinator.dispose();
        await native.events.close();
      }
    },
  );

  test(
    'native routes and inventory changes reach the engine and close with the adapter',
    () async {
      Map<String, Object?> audioState(String route, List<String> routes) => {
        'version': 1,
        'active': true,
        'muted': false,
        'route': route,
        'availableRoutes': routes,
      };
      final native = _NativeHarness()
        ..attachResult = _emptyBatch()
        ..audioState = audioState('earpiece', ['earpiece', 'speaker']);
      final coordinator = _coordinator();
      final adapter = _adapter(native, coordinator, {_callId: _callHandle});
      final engine = FlutterWebRtcCallEngine(
        adapter: _RouteProjectionWebRtcAdapter(),
        audioRoutePort: adapter,
      );
      final changes = <CallAudioOutputRoute>[];
      var closed = false;
      final subscription = engine.outputRouteChanges.listen(
        changes.add,
        onDone: () => closed = true,
      );

      await adapter.start();
      expect(await adapter.present(_presentation()), isTrue);
      expect(await engine.supportedOutputRoutes(), [
        CallAudioOutputRoute.earpiece,
        CallAudioOutputRoute.speaker,
      ]);
      expect(changes, [CallAudioOutputRoute.earpiece]);

      Future<void> emitRoute(int sequence) async {
        native.events.add(
          _batch([_event(sequence, 'native-route-$sequence', 'routeChanged')]),
        );
        await _until(
          () => native
              .callsOf('acknowledge')
              .any((call) => call.arguments['throughSequence'] == sequence),
        );
      }

      native.audioState = audioState('bluetooth', ['bluetooth', 'speaker']);
      await emitRoute(1);
      expect(changes.last, CallAudioOutputRoute.bluetooth);
      expect(adapter.selectedRoute, CallAudioOutputRoute.bluetooth);

      // A headset becomes selectable without changing the current output.
      native.audioState = audioState('bluetooth', [
        'bluetooth',
        'speaker',
        'wired_headset',
      ]);
      await emitRoute(2);
      expect(changes, [
        CallAudioOutputRoute.earpiece,
        CallAudioOutputRoute.bluetooth,
        CallAudioOutputRoute.bluetooth,
      ]);
      expect(
        await engine.supportedOutputRoutes(),
        contains(CallAudioOutputRoute.wiredHeadset),
      );

      await emitRoute(3);
      expect(changes, hasLength(3), reason: 'unchanged reads must not loop');
      native.audioState = audioState('earpiece', ['earpiece', 'speaker']);
      await emitRoute(4);
      expect(changes.last, CallAudioOutputRoute.earpiece);
      expect(native.callsOf('requestRoute'), isEmpty);

      await engine.close();
      expect(closed, isFalse, reason: 'native adapter is process-owned');
      await adapter.close();
      expect(closed, isTrue);
      await subscription.cancel();
      await coordinator.dispose();
      await native.events.close();
    },
  );

  test(
    'audio, route, end, and close stay coarse and delegate exactly once',
    () async {
      final native = _NativeHarness()
        ..attachResult = _emptyBatch()
        ..audioState = <String, Object?>{
          'version': 1,
          'active': true,
          'muted': false,
          'route': 'bluetooth',
          'availableRoutes': <Object?>['bluetooth', 'speaker'],
        };
      final coordinator = _coordinator();
      final adapter = _adapter(native, coordinator, <CallId, String>{
        _callId: _callHandle,
      });

      await adapter.start();
      expect(await adapter.present(_presentation()), isTrue);
      expect(await adapter.supportedOutputRoutes(), <CallAudioOutputRoute>[
        CallAudioOutputRoute.bluetooth,
        CallAudioOutputRoute.speaker,
      ]);
      final audio = await adapter.readAudioState();
      expect(audio.active, isTrue);
      expect(audio.muted, isFalse);
      expect(audio.route, CallAudioOutputRoute.bluetooth);

      await adapter.requestRoute(CallAudioOutputRoute.speaker);
      await adapter.activateAudio();
      await adapter.deactivateAudio();
      await adapter.dismiss(_presentation());

      expect(
        native.callsOf('requestRoute').single.arguments['route'],
        'speaker',
      );
      expect(native.callsOf('activateAudio'), hasLength(1));
      expect(native.callsOf('deactivateAudio'), hasLength(1));
      expect(native.callsOf('end'), hasLength(1));
      for (final method in <String>[
        'requestRoute',
        'activateAudio',
        'deactivateAudio',
        'end',
      ]) {
        expect(
          native.callsOf(method).single.arguments['callHandle'],
          _callHandle,
        );
      }

      await Future.wait(<Future<void>>[adapter.close(), adapter.close()]);
      expect(native.events.hasListener, isFalse);
      expect(native.callsOf('detach'), hasLength(1));

      final callCount = native.calls.length;
      native.events.add(
        _batch(<Map<String, Object?>>[_event(1, 'late-end', 'end')]),
      );
      await _settle();
      expect(native.calls, hasLength(callCount));

      await coordinator.dispose();
      await native.events.close();
    },
  );

  test(
    'close fences a native activation that completes after teardown',
    () async {
      final activation = Completer<Object?>();
      final native = _NativeHarness()
        ..attachResult = _emptyBatch()
        ..results['activateAudio'] = activation.future;
      final coordinator = _coordinator();
      final adapter = _adapter(native, coordinator, <CallId, String>{
        _callId: _callHandle,
      });

      await adapter.start();
      expect(await adapter.present(_presentation()), isTrue);
      final activating = adapter.activateAudio();
      await _until(() => native.callsOf('activateAudio').isNotEmpty);
      final activationFailure = expectLater(
        activating,
        throwsA(
          isA<AndroidCallLifecycleException>().having(
            (error) => error.code,
            'code',
            AndroidCallLifecycleErrorCode.closed,
          ),
        ),
      );

      final closing = adapter.close();
      activation.complete(true);
      await activationFailure;
      await closing;

      expect(adapter.ownsSession, isFalse);
      expect(
        native.callsOf('deactivateAudio').single.arguments['callHandle'],
        _callHandle,
      );
      await coordinator.dispose();
      await native.events.close();
    },
  );

  test(
    'direct audio-state read preserves ordering with audio commands',
    () async {
      final readResult = Completer<Object?>();
      final native = _NativeHarness()
        ..attachResult = _emptyBatch()
        ..results['readAudioState'] = readResult.future;
      final coordinator = _coordinator();
      final adapter = _adapter(native, coordinator, <CallId, String>{
        _callId: _callHandle,
      });

      await adapter.start();
      expect(await adapter.present(_presentation()), isTrue);
      final reading = adapter.readAudioState();
      await _until(() => native.callsOf('readAudioState').isNotEmpty);
      final deactivating = adapter.deactivateAudio();
      await _settle();

      expect(native.callsOf('deactivateAudio'), isEmpty);

      readResult.complete(<String, Object?>{
        'version': 1,
        'active': true,
        'muted': false,
        'route': 'earpiece',
        'availableRoutes': <Object?>['earpiece', 'speaker'],
      });
      await reading;
      await deactivating;

      expect(
        native.calls.indexOf(native.callsOf('readAudioState').single),
        lessThan(
          native.calls.indexOf(native.callsOf('deactivateAudio').single),
        ),
      );
      expect(adapter.ownsSession, isFalse);

      await adapter.close();
      await coordinator.dispose();
      await native.events.close();
    },
  );

  test('direct audio-state read respects the adoption fence', () async {
    final native = _NativeHarness()
      ..attachResult = _emptyBatch()
      ..audioState = <String, Object?>{
        'version': 1,
        'active': true,
        'muted': false,
        'route': 'earpiece',
        'availableRoutes': <Object?>['earpiece'],
      };
    final coordinator = _coordinator();
    final adapter = _adapter(native, coordinator, <CallId, String>{
      _callId: _callHandle,
    }, requireAdoptionForAudio: true);

    await adapter.start();
    expect(await adapter.present(_presentation()), isTrue);

    await expectLater(
      adapter.readAudioState(),
      throwsA(
        isA<AndroidCallLifecycleException>().having(
          (error) => error.code,
          'code',
          AndroidCallLifecycleErrorCode.unavailable,
        ),
      ),
    );
    expect(native.callsOf('readAudioState'), isEmpty);

    await adapter.close();
    await coordinator.dispose();
    await native.events.close();
  });

  test(
    'terminal A and rebound B fence A activation after the native await',
    () async {
      final activation = Completer<Object?>();
      final native = _NativeHarness()
        ..attachResult = _emptyBatch()
        ..results['activateAudio'] = activation.future;
      final coordinator = _coordinator();
      final adapter = _adapter(native, coordinator, <CallId, String>{
        _callId: _callHandle,
        _secondCallId: _secondCallHandle,
      });

      await adapter.start();
      await _prepareIncoming(coordinator);
      expect(await adapter.present(_presentation()), isTrue);
      await _showSystemUi(coordinator);
      final activating = adapter.activateAudio();
      await _until(() => native.callsOf('activateAudio').isNotEmpty);

      native.events.add(
        _batch(<Map<String, Object?>>[
          _event(1, 'first-terminal-during-activation', 'remoteCancelled'),
        ]),
      );
      await _until(() => coordinator.activeSession == null);

      native.events.add(
        _batch(<Map<String, Object?>>[
          _event(
            1,
            'second-presented-after-activation',
            'presented',
            callHandle: _secondCallHandle,
          ),
        ], callHandle: _secondCallHandle),
      );
      await _prepareIncomingFor(
        coordinator,
        callId: _secondCallId,
        eventSuffix: 'second-after-activation',
      );
      expect(
        await adapter.present(
          IncomingCallPresentation(
            callId: _secondCallId,
            callerAccountPeerId: 'remote-account',
            expiresAt: DateTime.fromMillisecondsSinceEpoch(
              _expiresAtMs,
              isUtc: true,
            ),
          ),
        ),
        isTrue,
      );

      final activationFailure = expectLater(
        activating,
        throwsA(
          isA<AndroidCallLifecycleException>().having(
            (error) => error.code,
            'code',
            AndroidCallLifecycleErrorCode.unavailable,
          ),
        ),
      );
      activation.complete(true);
      await activationFailure;

      expect(adapter.isBoundTo(_secondCallId), isTrue);
      expect(adapter.ownsSession, isFalse);
      expect(
        native.callsOf('deactivateAudio').single.arguments['callHandle'],
        _callHandle,
      );

      await adapter.close();
      await coordinator.dispose();
      await native.events.close();
    },
  );

  test(
    'terminal A and rebound B fence A audio-state after the native await',
    () async {
      final readResult = Completer<Object?>();
      final native = _NativeHarness()
        ..attachResult = _emptyBatch()
        ..results['readAudioState'] = readResult.future;
      final coordinator = _coordinator();
      final adapter = _adapter(native, coordinator, <CallId, String>{
        _callId: _callHandle,
        _secondCallId: _secondCallHandle,
      });

      await adapter.start();
      await _prepareIncoming(coordinator);
      expect(await adapter.present(_presentation()), isTrue);
      await _showSystemUi(coordinator);
      final reading = adapter.readAudioState();
      await _until(() => native.callsOf('readAudioState').isNotEmpty);

      native.events.add(
        _batch(<Map<String, Object?>>[
          _event(1, 'first-terminal-during-audio-read', 'remoteCancelled'),
        ]),
      );
      await _until(() => coordinator.activeSession == null);

      native.events.add(
        _batch(<Map<String, Object?>>[
          _event(
            1,
            'second-presented-after-audio-read',
            'presented',
            callHandle: _secondCallHandle,
          ),
        ], callHandle: _secondCallHandle),
      );
      await _prepareIncomingFor(
        coordinator,
        callId: _secondCallId,
        eventSuffix: 'second-after-audio-read',
      );
      expect(
        await adapter.present(
          IncomingCallPresentation(
            callId: _secondCallId,
            callerAccountPeerId: 'remote-account',
            expiresAt: DateTime.fromMillisecondsSinceEpoch(
              _expiresAtMs,
              isUtc: true,
            ),
          ),
        ),
        isTrue,
      );

      final readFailure = expectLater(
        reading,
        throwsA(
          isA<AndroidCallLifecycleException>().having(
            (error) => error.code,
            'code',
            AndroidCallLifecycleErrorCode.unavailable,
          ),
        ),
      );
      readResult.complete(<String, Object?>{
        'version': 1,
        'active': true,
        'muted': false,
        'route': 'speaker',
        'availableRoutes': <Object?>['speaker'],
      });
      await readFailure;

      expect(adapter.isBoundTo(_secondCallId), isTrue);
      expect(adapter.ownsSession, isFalse);
      expect(adapter.selectedRoute, CallAudioOutputRoute.systemDefault);
      expect(
        native.callsOf('readAudioState').single.arguments['callHandle'],
        _callHandle,
      );

      await adapter.close();
      await coordinator.dispose();
      await native.events.close();
    },
  );

  test(
    'false native booleans never mutate audio route or end cursors',
    () async {
      final native = _NativeHarness()
        ..attachResult = _emptyBatch()
        ..audioState = <String, Object?>{
          'version': 1,
          'active': false,
          'muted': false,
          'route': 'earpiece',
          'availableRoutes': <Object?>['earpiece', 'speaker'],
        };
      final coordinator = _coordinator();
      final adapter = _adapter(native, coordinator, <CallId, String>{
        _callId: _callHandle,
      });

      await adapter.start();
      expect(await adapter.present(_presentation()), isTrue);
      await adapter.readAudioState();

      native.results['activateAudio'] = false;
      await expectLater(
        adapter.activateAudio(),
        throwsA(isA<AndroidCallLifecycleException>()),
      );
      expect(adapter.ownsSession, isFalse);

      native.results['activateAudio'] = true;
      await adapter.activateAudio();
      expect(adapter.ownsSession, isTrue);

      native.results['deactivateAudio'] = false;
      await expectLater(
        adapter.deactivateAudio(),
        throwsA(isA<AndroidCallLifecycleException>()),
      );
      expect(adapter.ownsSession, isTrue);

      native.results['requestRoute'] = false;
      await expectLater(
        adapter.requestRoute(CallAudioOutputRoute.speaker),
        throwsA(isA<CallAudioRouteException>()),
      );
      expect(adapter.selectedRoute, CallAudioOutputRoute.earpiece);

      native.queuedResults['end'] = <Object?>[false, true];
      await adapter.dismiss(_presentation());
      await adapter.dismiss(_presentation());
      expect(native.callsOf('end'), hasLength(2));

      await adapter.close();
      await coordinator.dispose();
      await native.events.close();
    },
  );

  test(
    'audio route inventory is bounded, unique, coarse, and may be empty',
    () async {
      final native = _NativeHarness()
        ..attachResult = _emptyBatch()
        ..audioState = <String, Object?>{
          'version': 1,
          'active': false,
          'muted': false,
          'route': 'system_default',
          'availableRoutes': <Object?>[],
        };
      final coordinator = _coordinator();
      final adapter = _adapter(native, coordinator, <CallId, String>{
        _callId: _callHandle,
      });

      await adapter.start();
      expect(await adapter.present(_presentation()), isTrue);
      expect(await adapter.supportedOutputRoutes(), isEmpty);

      native.audioState = <String, Object?>{
        'version': 1,
        'active': false,
        'muted': false,
        'route': 'system_default',
        'availableRoutes': <Object?>['speaker', 'speaker'],
      };
      await expectLater(
        adapter.readAudioState(),
        throwsA(
          isA<AndroidCallLifecycleException>().having(
            (error) => error.code,
            'code',
            AndroidCallLifecycleErrorCode.malformedResponse,
          ),
        ),
      );
      expect(adapter.selectedRoute, CallAudioOutputRoute.systemDefault);

      await adapter.close();
      await coordinator.dispose();
      await native.events.close();
    },
  );

  test(
    'system-default route reset after the native call ended is a no-op success',
    () async {
      late AndroidCallLifecycleAdapter adapter;
      final native = _NativeHarness()
        ..attachResult = _emptyBatch()
        ..results['requestRoute'] = false
        ..results['deactivateAudio'] = false
        ..audioState = <String, Object?>{
          'version': 1,
          'active': true,
          'muted': false,
          'route': 'system_default',
          'availableRoutes': <Object?>['system_default', 'speaker'],
        };
      final routeReset = Completer<Object?>();
      final speakerAfterEnd = Completer<Object?>();
      final deactivateAfterEnd = Completer<Object?>();
      var routeRequestsAfterReset = -1;
      final cleanup = CallCleanupCoordinator(<CallCleanupStep>[
        CallCleanupStep('call_media', (_) async {
          // The adapter's own terminal path must have ended the native handle
          // before media cleanup resets the route (TC-400-01 fixture rule).
          await _until(() => native.callsOf('end').length == 1);
          try {
            await adapter.selectOutputRoute(CallAudioOutputRoute.systemDefault);
            routeReset.complete(null);
          } catch (error) {
            routeReset.complete(error);
          }
          routeRequestsAfterReset = native.callsOf('requestRoute').length;
          try {
            await adapter.requestRoute(CallAudioOutputRoute.speaker);
            speakerAfterEnd.complete(null);
          } catch (error) {
            speakerAfterEnd.complete(error);
          }
          try {
            await adapter.deactivate();
            deactivateAfterEnd.complete(null);
          } catch (error) {
            deactivateAfterEnd.complete(error);
          }
        }, requiredForTerminalAck: true),
      ], stepTimeout: const Duration(seconds: 2));
      final coordinator = _coordinator(cleanupCoordinator: cleanup);
      adapter = _adapter(native, coordinator, <CallId, String>{
        _callId: _callHandle,
      });

      await adapter.start();
      await _prepareIncoming(coordinator);
      expect(await adapter.present(_presentation()), isTrue);
      await adapter.activateAudio();
      expect(adapter.ownsSession, isTrue);

      // Dart-originated terminal: the adapter ends the native handle itself
      // and the committed terminal replay carries no terminal event yet.
      await coordinator.dispatch(
        CallEvent(
          type: CallEventType.remoteTerminate,
          eventId: 'remote-terminate-before-route-reset',
          occurredAt: _now,
          callId: _callId,
          contactPeerId: 'remote-account',
        ),
      );

      expect(await routeReset.future, isNull);
      expect(native.callsOf('end'), hasLength(1));
      expect(routeRequestsAfterReset, 0);
      expect(
        await speakerAfterEnd.future,
        isA<CallAudioRouteException>().having(
          (error) => error.code,
          'code',
          CallAudioRouteErrorCode.selectionFailed,
        ),
      );
      expect(native.callsOf('requestRoute'), hasLength(1));
      expect(await deactivateAfterEnd.future, isNull);
      expect(native.callsOf('deactivateAudio'), isEmpty);
      expect(adapter.ownsSession, isFalse);
      await _until(() => coordinator.terminalCleanupAckReady(_callId));

      await adapter.close();
      await coordinator.dispose();
      await native.events.close();
    },
  );

  test('system-default route reset after a native terminal event is released '
      'without a native call', () async {
    late AndroidCallLifecycleAdapter adapter;
    final native = _NativeHarness()
      ..attachResult = _emptyBatch()
      ..results['requestRoute'] = false
      ..audioState = <String, Object?>{
        'version': 1,
        'active': true,
        'muted': false,
        'route': 'system_default',
        'availableRoutes': <Object?>['system_default', 'speaker'],
      };
    final routeReset = Completer<Object?>();
    final cleanup = CallCleanupCoordinator(<CallCleanupStep>[
      CallCleanupStep('call_media', (_) async {
        try {
          await adapter.selectOutputRoute(CallAudioOutputRoute.systemDefault);
          routeReset.complete(null);
        } catch (error) {
          routeReset.complete(error);
        }
      }, requiredForTerminalAck: true),
    ], stepTimeout: const Duration(seconds: 2));
    final coordinator = _coordinator(cleanupCoordinator: cleanup);
    adapter = _adapter(native, coordinator, <CallId, String>{
      _callId: _callHandle,
    });

    await adapter.start();
    await _prepareIncoming(coordinator);
    expect(await adapter.present(_presentation()), isTrue);
    await adapter.activateAudio();
    expect(adapter.ownsSession, isTrue);

    // Native-originated terminal: the retained terminal short-circuit owns
    // the release, so no route request reaches the ended native call.
    native.events.add(
      _batch(<Map<String, Object?>>[
        _event(1, 'native-terminal-presented', 'presented'),
        _event(2, 'native-terminal-ended', 'remoteCancelled'),
      ]),
    );

    expect(await routeReset.future, isNull);
    expect(native.callsOf('requestRoute'), isEmpty);
    expect(adapter.ownsSession, isFalse);
    expect(adapter.selectedRoute, CallAudioOutputRoute.systemDefault);
    await _until(() => coordinator.terminalCleanupAckReady(_callId));

    await adapter.close();
    await coordinator.dispose();
    await native.events.close();
  });
}

AndroidCallLifecycleAdapter _adapter(
  _NativeHarness native,
  CallCoordinator coordinator,
  Map<CallId, String> handles, {
  AndroidNativeMuteApplier? nativeMuteApplier,
  NativeOutgoingRegistrationResultObserver? onOutgoingRegistrationResult,
  bool projectTerminalBeforeEnd = false,
  bool requireAdoptionForAudio = false,
}) {
  final adapter = AndroidCallLifecycleAdapter(
    invokeMethod: native.invoke,
    nativeEvents: native.events.stream,
    coordinator: coordinator,
    resolveAuthenticatedHandle: (callId) => handles[callId],
    clock: () => _now,
    onOutgoingRegistrationResult: onOutgoingRegistrationResult,
    projectTerminalBeforeEnd: projectTerminalBeforeEnd,
    requireAdoptionForAudio: requireAdoptionForAudio,
  );
  adapter.bindNativeMuteApplier(nativeMuteApplier ?? (_, _) async => true);
  return adapter;
}

IncomingCallPresentation _presentation() => IncomingCallPresentation(
  callId: _callId,
  callerAccountPeerId: 'remote-account',
  expiresAt: DateTime.fromMillisecondsSinceEpoch(_expiresAtMs, isUtc: true),
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
  String callHandle = _callHandle,
  String? nativeCallId,
  String phase = 'preStart',
  String direction = 'incoming',
  int expiresAtMs = _expiresAtMs,
  int? highestSequence,
}) => <String, Object?>{
  'version': 1,
  'descriptor': <String, Object?>{
    'callHandle': callHandle,
    'expiresAtMs': expiresAtMs,
    'presented': true,
    'phase': phase,
    'direction': direction,
  },
  'events': events,
  'nativeCallId': nativeCallId ?? callHandle,
  'highestSequence':
      highestSequence ?? (events.isEmpty ? 0 : events.last['sequence']),
};

Map<String, Object?> _event(
  int sequence,
  String eventId,
  String type, {
  String callHandle = _callHandle,
}) => <String, Object?>{
  'callHandle': callHandle,
  'sequence': sequence,
  'eventId': _nativeEventId(eventId),
  'type': type,
  'occurredAtMs': _nowMs,
};

String _nativeEventId(String label) {
  var hash = 0xcbf29ce484222325;
  for (final unit in label.codeUnits) {
    hash = ((hash ^ unit) * 0x100000001b3) & 0xffffffffffff;
  }
  return '00000000-0000-4000-8000-${hash.toRadixString(16).padLeft(12, '0')}';
}

Future<void> _prepareIncoming(CallCoordinator coordinator) =>
    _prepareIncomingFor(coordinator, callId: _callId, eventSuffix: 'first');

Future<void> _prepareIncomingFor(
  CallCoordinator coordinator, {
  required CallId callId,
  required String eventSuffix,
}) async {
  await coordinator.dispatch(
    CallEvent(
      type: CallEventType.remoteInvite,
      eventId: 'remote-invite-$eventSuffix',
      occurredAt: _now,
      callId: callId,
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
      eventId: 'incoming-validated-$eventSuffix',
      occurredAt: _now,
      callId: callId,
      contactPeerId: 'remote-account',
    ),
  );
}

Future<void> _showSystemUi(CallCoordinator coordinator) => coordinator
    .dispatch(
      CallEvent(
        type: CallEventType.systemUiPresented,
        eventId: 'system-ui-presented',
        occurredAt: _now,
        callId: _callId,
        contactPeerId: 'remote-account',
      ),
    )
    .then<void>((_) {});

CallCoordinator _coordinator({
  _Effects? effects,
  CallCleanupCoordinator? cleanupCoordinator,
  Duration terminalEffectTimeout = const Duration(seconds: 5),
  Duration terminalHistoryTimeout = const Duration(seconds: 5),
  _History? history,
  CallId Function()? idSource,
}) => CallCoordinator(
  reducer: const CallReducer(),
  cleanupCoordinator:
      cleanupCoordinator ?? CallCleanupCoordinator(const <CallCleanupStep>[]),
  historyProjector: CallHistoryProjector(
    history ?? _History(),
    clock: () => _now,
  ),
  effectExecutor: effects ?? _Effects(),
  clock: () => _now,
  idSource: idSource ?? () => _callId,
  terminalEffectTimeout: terminalEffectTimeout,
  terminalHistoryTimeout: terminalHistoryTimeout,
);

Future<void> _until(bool Function() predicate) async {
  for (var attempt = 0; attempt < 100 && !predicate(); attempt++) {
    await Future<void>.delayed(Duration.zero);
  }
  expect(predicate(), isTrue);
}

Future<void> _settle() async {
  for (var turn = 0; turn < 8; turn++) {
    await Future<void>.delayed(Duration.zero);
  }
}

final class _RouteProjectionWebRtcAdapter
    implements WebRtcPeerConnectionAdapter {
  @override
  Stream<WebRtcPeerConnectionEvent> get events => const Stream.empty();

  @override
  Future<void> close() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _NativeInvocation {
  const _NativeInvocation(this.method, this.arguments);

  final String method;
  final Map<String, Object?> arguments;
}

final class _NativeHarness {
  final StreamController<Object?> events = StreamController<Object?>.broadcast(
    sync: true,
  );
  final List<_NativeInvocation> calls = <_NativeInvocation>[];
  final Map<String, Object?> results = <String, Object?>{};
  final Map<String, List<Object?>> queuedResults = <String, List<Object?>>{};
  Object? attachResult;
  Object? audioState;
  void Function()? onAttach;
  void Function(String method)? onInvoke;
  void Function(String method, Map<String, Object?> arguments)?
  onInvokeWithArguments;

  Future<Object?> invoke(String method, Map<String, Object?> arguments) async {
    calls.add(_NativeInvocation(method, Map<String, Object?>.of(arguments)));
    onInvoke?.call(method);
    onInvokeWithArguments?.call(method, arguments);
    final queued = queuedResults[method];
    if (queued != null && queued.isNotEmpty) return queued.removeAt(0);
    if (results.containsKey(method)) return results[method];
    switch (method) {
      case 'attach':
        onAttach?.call();
        return attachResult;
      case 'presentAuthenticated':
      case 'registerOutgoingAuthenticated':
      case 'adopt':
      case 'setCapabilityEnabled':
      case 'acknowledge':
      case 'activateAudio':
      case 'deactivateAudio':
      case 'requestRoute':
      case 'end':
      case 'failClosed':
      case 'detach':
        return true;
      case 'readAudioState':
        return audioState;
      default:
        return null;
    }
  }

  List<_NativeInvocation> callsOf(String method) =>
      calls.where((call) => call.method == method).toList(growable: false);
}

final class _Effects implements CallEffectExecutor {
  final List<CallEffect> executed = <CallEffect>[];
  CallEffectType? failOn;
  bool hangTerminal = false;
  Future<CallEvent?> Function(CallSessionSnapshot snapshot)?
  onPrepareOutgoingInvite;
  Future<CallEvent?> Function(CallSessionSnapshot snapshot)?
  onPrepareAcceptedMedia;

  @override
  Future<CallEvent?> execute(
    CallEffect effect,
    CallSessionSnapshot snapshot,
  ) async {
    executed.add(effect);
    final prepareOutgoing = onPrepareOutgoingInvite;
    if (effect.type == CallEffectType.prepareOutgoingInvite &&
        prepareOutgoing != null) {
      return prepareOutgoing(snapshot);
    }
    final prepareAcceptedMedia = onPrepareAcceptedMedia;
    if (effect.type == CallEffectType.prepareAcceptedMedia &&
        prepareAcceptedMedia != null) {
      return prepareAcceptedMedia(snapshot);
    }
    if (hangTerminal && snapshot.isTerminal) {
      return Completer<CallEvent?>().future;
    }
    if (effect.type == failOn) throw StateError('injected dispatch failure');
    return null;
  }
}

final class _History implements CallHistoryRepository {
  _History({this.writeGate});

  final Future<void>? writeGate;
  final Map<CallId, CallHistoryEntry> entries = <CallId, CallHistoryEntry>{};

  @override
  Future<CallHistoryEntry?> getByCallId(CallId callId) async => entries[callId];

  @override
  Future<List<CallHistoryEntry>> listForContact(
    String contactAccountPeerId,
  ) async => const <CallHistoryEntry>[];

  @override
  Future<void> upsertTerminal(CallHistoryEntry entry) async {
    final gate = writeGate;
    if (gate != null) await gate;
    entries.putIfAbsent(entry.callId, () => entry);
  }
}
