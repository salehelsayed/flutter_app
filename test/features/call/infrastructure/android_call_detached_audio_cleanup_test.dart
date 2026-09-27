import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_app/features/call/application/call_cleanup_coordinator.dart';
import 'package:flutter_app/features/call/application/call_coordinator.dart';
import 'package:flutter_app/features/call/application/call_history_projector.dart';
import 'package:flutter_app/features/call/application/handle_incoming_call_signal.dart';
import 'package:flutter_app/features/call/data/call_history_repository.dart';
import 'package:flutter_app/features/call/domain/call_event.dart';
import 'package:flutter_app/features/call/domain/call_id.dart';
import 'package:flutter_app/features/call/domain/call_session_snapshot.dart';
import 'package:flutter_app/features/call/domain/call_state.dart';
import 'package:flutter_app/features/call/infrastructure/android_call_lifecycle_adapter.dart';
import 'package:flutter_test/flutter_test.dart';

// Beta 2026-09-24 (F4): an Android Back press finished MainActivity during a
// connected call. MainActivity.onDestroy disposed the native call bridge first
// (its controller detach ended the Telecom call and removed the method
// handler), then Dart saw `detached` and ended the call with appShutdown.
// Every later native audio command failed, so the audio controller reported
// cleanupFailed and terminal cleanup stayed `blocked reason=callMedia`.

const _nowMs = 2_000_000;
const _expiresAtMs = _nowMs + 45_000;
const _callHandle = '33333333-3333-4333-8333-333333333333';
final _callId = CallId.parse('22222222-2222-4222-8222-222222222222');
final _now = DateTime.fromMillisecondsSinceEpoch(_nowMs, isUtc: true);

void main() {
  test(
    'appShutdown after the native bridge detached releases audio and cleanup '
    'reaches ready',
    () async {
      late AndroidCallLifecycleAdapter adapter;
      final native = _NativeHarness()..attachResult = _emptyBatch();
      final deactivateResult = Completer<Object?>();
      final cleanup = CallCleanupCoordinator(<CallCleanupStep>[
        CallCleanupStep('call_media', (_) async {
          await _until(() => native.callsOf('end').isNotEmpty);
          try {
            await adapter.deactivate();
            if (!deactivateResult.isCompleted) deactivateResult.complete(null);
          } catch (error) {
            if (!deactivateResult.isCompleted) deactivateResult.complete(error);
            rethrow;
          }
        }, requiredForTerminalAck: true),
      ], stepTimeout: const Duration(seconds: 2));
      final coordinator = _coordinator(cleanupCoordinator: cleanup);
      adapter = _adapter(native, coordinator);

      await adapter.start();
      await _prepareIncoming(coordinator);
      expect(await adapter.present(_presentation()), isTrue);
      await adapter.activateAudio();
      expect(adapter.ownsSession, isTrue);

      // The activity is gone: every native method now has no handler.
      native.detached = true;
      await coordinator.dispatch(
        CallEvent(
          type: CallEventType.appShutdown,
          eventId: 'app-shutdown-after-native-detach',
          occurredAt: _now,
          callId: _callId,
          contactPeerId: 'remote-account',
        ),
      );

      expect(await deactivateResult.future, isNull);
      expect(adapter.ownsSession, isFalse);
      await _until(() => coordinator.terminalCleanupAckReady(_callId));

      await adapter.close();
      await coordinator.dispose();
      await native.events.close();
    },
  );

  test('deactivate after the adapter closed is a released no-op', () async {
    final native = _NativeHarness()..attachResult = _emptyBatch();
    final coordinator = _coordinator();
    final adapter = _adapter(native, coordinator);

    await adapter.start();
    await _prepareIncoming(coordinator);
    expect(await adapter.present(_presentation()), isTrue);
    await adapter.activateAudio();
    await adapter.close();
    final deactivateCallsBefore = native.callsOf('deactivateAudio').length;

    await adapter.deactivate();

    expect(adapter.ownsSession, isFalse);
    expect(native.callsOf('deactivateAudio'), hasLength(deactivateCallsBefore));
    await coordinator.dispose();
    await native.events.close();
  });

  test('a live native refusal to deactivate still fails closed', () async {
    final native = _NativeHarness()..attachResult = _emptyBatch();
    final coordinator = _coordinator();
    final adapter = _adapter(native, coordinator);

    await adapter.start();
    await _prepareIncoming(coordinator);
    expect(await adapter.present(_presentation()), isTrue);
    await adapter.activateAudio();

    native.results['deactivateAudio'] = false;
    await expectLater(
      adapter.deactivate(),
      throwsA(isA<AndroidCallLifecycleException>()),
    );
    expect(adapter.ownsSession, isTrue);

    await adapter.close();
    await coordinator.dispose();
    await native.events.close();
  });
}

AndroidCallLifecycleAdapter _adapter(
  _NativeHarness native,
  CallCoordinator coordinator,
) {
  final adapter = AndroidCallLifecycleAdapter(
    invokeMethod: native.invoke,
    nativeEvents: native.events.stream,
    coordinator: coordinator,
    resolveAuthenticatedHandle: (callId) =>
        callId == _callId ? _callHandle : null,
    clock: () => _now,
  );
  adapter.bindNativeMuteApplier((_, _) async => true);
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

Future<void> _prepareIncoming(CallCoordinator coordinator) async {
  await coordinator.dispatch(
    CallEvent(
      type: CallEventType.remoteInvite,
      eventId: 'remote-invite-first',
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
      eventId: 'incoming-validated-first',
      occurredAt: _now,
      callId: _callId,
      contactPeerId: 'remote-account',
    ),
  );
}

CallCoordinator _coordinator({CallCleanupCoordinator? cleanupCoordinator}) =>
    CallCoordinator(
      reducer: const CallReducer(),
      cleanupCoordinator:
          cleanupCoordinator ??
          CallCleanupCoordinator(const <CallCleanupStep>[]),
      historyProjector: CallHistoryProjector(_History(), clock: () => _now),
      effectExecutor: _Effects(),
      clock: () => _now,
      idSource: () => _callId,
      terminalEffectTimeout: const Duration(seconds: 5),
      terminalHistoryTimeout: const Duration(seconds: 5),
    );

Future<void> _until(bool Function() predicate) async {
  for (var attempt = 0; attempt < 200 && !predicate(); attempt++) {
    await Future<void>.delayed(Duration.zero);
  }
  expect(predicate(), isTrue);
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
  Object? attachResult;

  /// Mirrors MknoonCallNativeBridge.dispose: the method handler is removed,
  /// so the platform channel answers every call with MissingPluginException.
  bool detached = false;

  Future<Object?> invoke(String method, Map<String, Object?> arguments) async {
    calls.add(_NativeInvocation(method, Map<String, Object?>.of(arguments)));
    if (detached) {
      throw MissingPluginException('No implementation found for $method');
    }
    if (results.containsKey(method)) return results[method];
    switch (method) {
      case 'attach':
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
      default:
        return null;
    }
  }

  List<_NativeInvocation> callsOf(String method) =>
      calls.where((call) => call.method == method).toList(growable: false);
}

final class _Effects implements CallEffectExecutor {
  @override
  Future<CallEvent?> execute(
    CallEffect effect,
    CallSessionSnapshot snapshot,
  ) async => null;
}

final class _History implements CallHistoryRepository {
  final Map<CallId, CallHistoryEntry> entries = <CallId, CallHistoryEntry>{};

  @override
  Future<CallHistoryEntry?> getByCallId(CallId callId) async => entries[callId];

  @override
  Future<List<CallHistoryEntry>> listForContact(
    String contactAccountPeerId,
  ) async => const <CallHistoryEntry>[];

  @override
  Future<void> upsertTerminal(CallHistoryEntry entry) async {
    entries.putIfAbsent(entry.callId, () => entry);
  }
}
