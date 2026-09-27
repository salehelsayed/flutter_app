import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_app/features/call/application/call_cleanup_coordinator.dart';
import 'package:flutter_app/features/call/application/call_coordinator.dart';
import 'package:flutter_app/features/call/application/call_history_projector.dart';
import 'package:flutter_app/features/call/application/call_signaling_service.dart';
import 'package:flutter_app/features/call/data/call_history_repository.dart';
import 'package:flutter_app/features/call/domain/call_end_reason.dart';
import 'package:flutter_app/features/call/domain/call_event.dart';
import 'package:flutter_app/features/call/domain/call_id.dart';
import 'package:flutter_app/features/call/domain/call_session_snapshot.dart';
import 'package:flutter_app/features/call/domain/call_state.dart';
import 'package:flutter_test/flutter_test.dart';

// Beta 2026-09-25 (F3): the Android app was torn down during a connected
// call. The peer (iPhone) never got a terminate: it saw mediaLost 6 s later
// and ended with reconnectFailed after 21 s of dead air.
//
// Production bounds a terminal delivery to 500 ms
// (production_call_signaling_graph.dart, `terminalEffectTimeout`). A
// terminate re-resolves the peer endpoint and encodes the envelope before it
// reaches the direct/mailbox legs, and on the device that took about 320 ms
// on a quiet app. At teardown the 500 ms budget ran out, the graph then
// closed CallSignalingService (`signalingService.close()` right after
// `runtime.shutdown()`), and the still-running transmit hit its `_closed`
// check and was dropped. These tests replay that order with the production
// budget. `closed` mirrors CallSignalingService.close().

final _callId = CallId.parse('66666666-6666-4666-8666-666666666666');
final _now = DateTime.utc(2026, 9, 25, 17, 34, 40);

/// Endpoint resolution plus envelope encoding under teardown load.
const _slowPreLeg = Duration(milliseconds: 700);

void main() {
  test('engine teardown during a connected call delivers the appShutdown '
      'terminate before call signaling closes', () {
    fakeAsync((async) {
      final transport = _TeardownTransport(preLegDelay: _slowPreLeg);
      final coordinator = _productionCoordinator(transport);
      _connect(async, coordinator);

      // Engine detach: CallSignalingRuntime.shutdown -> coordinator.dispose,
      // then ProductionCallSignalingGraph.shutdown closes the signaling
      // service.
      var shutdownSettled = false;
      unawaited(
        coordinator.dispose().catchError((Object _) {}).whenComplete(() {
          transport.closed = true;
          shutdownSettled = true;
        }),
      );
      async.elapse(const Duration(seconds: 3));

      expect(shutdownSettled, isTrue);
      expect(transport.refused, isEmpty, reason: 'terminate was dropped');
      expect(transport.delivered, hasLength(1));
      expect(transport.delivered.single.endReason, CallEndReason.appShutdown);
    });
  });

  test('a native call end during teardown, then engine detach, still '
      'delivers the terminate before call signaling closes', () {
    fakeAsync((async) {
      final transport = _TeardownTransport(preLegDelay: _slowPreLeg);
      final coordinator = _productionCoordinator(transport);
      _connect(async, coordinator);

      // Native Telecom end (providerRemoved/explicit end) reaches Dart as a
      // native end action. Its terminal delivery outlives the 500 ms budget.
      unawaited(
        coordinator
            .dispatch(
              _event(
                CallEventType.nativeAction,
                nativeAction: CallNativeAction.end,
                endReason: CallEndReason.mediaFailed,
              ),
            )
            .then<void>((_) {}, onError: (Object _) {}),
      );
      async.elapse(const Duration(milliseconds: 600));
      expect(coordinator.lastSnapshot?.state, CallState.ended);
      expect(transport.delivered, isEmpty, reason: 'still resolving');

      var shutdownSettled = false;
      unawaited(
        coordinator.dispose().catchError((Object _) {}).whenComplete(() {
          transport.closed = true;
          shutdownSettled = true;
        }),
      );
      async.elapse(const Duration(seconds: 3));

      expect(shutdownSettled, isTrue);
      expect(transport.refused, isEmpty, reason: 'terminate was dropped');
      expect(transport.delivered, hasLength(1));
      expect(transport.delivered.single.endReason, CallEndReason.mediaFailed);
    });
  });

  test('a terminate that never settles cannot hold engine teardown past the '
      'call shutdown budget', () {
    fakeAsync((async) {
      final transport = _TeardownTransport(
        preLegDelay: const Duration(seconds: 30),
      );
      final coordinator = _productionCoordinator(transport);
      _connect(async, coordinator);

      var shutdownSettled = false;
      unawaited(
        coordinator
            .dispose()
            .catchError((Object _) {})
            .whenComplete(() => shutdownSettled = true),
      );
      // CanonicalRuntimeShutdownSequence gives call shutdown 2 s in total.
      async.elapse(const Duration(milliseconds: 1999));

      expect(shutdownSettled, isTrue);
      expect(transport.delivered, isEmpty);
    });
  });
}

/// The coordinator bounds production uses in ProductionCallSignalingGraph.
CallCoordinator _productionCoordinator(CallEffectExecutor executor) =>
    CallCoordinator(
      reducer: const CallReducer(),
      cleanupCoordinator: CallCleanupCoordinator(const <CallCleanupStep>[]),
      historyProjector: CallHistoryProjector(_MemoryHistoryRepository()),
      effectExecutor: executor,
      clock: () => _now,
      idSource: () => _callId,
      terminalEffectTimeout: const Duration(milliseconds: 500),
      terminalHistoryTimeout: const Duration(milliseconds: 250),
    );

void _connect(FakeAsync async, CallCoordinator coordinator) {
  for (final type in <CallEventType>[
    CallEventType.remoteInvite,
    CallEventType.incomingValidated,
    CallEventType.systemUiPresented,
    CallEventType.answer,
    CallEventType.negotiationReady,
    CallEventType.mediaConnected,
  ]) {
    var done = false;
    unawaited(
      coordinator
          .dispatch(
            _event(
              type,
              expiresAt: type == CallEventType.remoteInvite
                  ? _now.add(const Duration(seconds: 45))
                  : null,
            ),
          )
          .whenComplete(() => done = true),
    );
    async.flushMicrotasks();
    expect(done, isTrue, reason: type.name);
  }
  expect(coordinator.activeSession?.state, CallState.connected);
}

CallEvent _event(
  CallEventType type, {
  DateTime? expiresAt,
  CallNativeAction? nativeAction,
  CallEndReason? endReason,
}) => CallEvent(
  type: type,
  eventId: 'teardown-${type.name}',
  occurredAt: _now,
  callId: _callId,
  contactPeerId: 'remote-account',
  localAccountPeerId: 'local-account',
  localDeviceId: 'local-device',
  remoteAccountPeerId: 'remote-account',
  remoteDeviceId: 'remote-device',
  expiresAt: expiresAt,
  admission: IncomingCallAdmission.accepted,
  nativeAction: nativeAction,
  endReason: endReason,
);

/// Terminal sends shaped like CallSignalingService.transmit: the pre-leg work
/// (endpoint resolution and envelope encoding) runs first, then the send is
/// refused if the service was closed meanwhile.
final class _TeardownTransport implements CallEffectExecutor {
  _TeardownTransport({required this.preLegDelay});

  final Duration preLegDelay;
  bool closed = false;
  final List<CallSessionSnapshot> delivered = <CallSessionSnapshot>[];
  final List<CallSessionSnapshot> refused = <CallSessionSnapshot>[];

  @override
  Future<CallEvent?> execute(
    CallEffect effect,
    CallSessionSnapshot snapshot,
  ) async {
    if (effect.type != CallEffectType.sendTerminate) return null;
    await Future<void>.delayed(preLegDelay);
    if (closed) {
      refused.add(snapshot);
      throw const CallSignalingException(
        CallSignalingErrorCode.migrationPaused,
      );
    }
    delivered.add(snapshot);
    return null;
  }
}

final class _MemoryHistoryRepository implements CallHistoryRepository {
  final Map<CallId, CallHistoryEntry> rows = <CallId, CallHistoryEntry>{};

  @override
  Future<CallHistoryEntry?> getByCallId(CallId callId) async => rows[callId];

  @override
  Future<List<CallHistoryEntry>> listForContact(
    String contactAccountPeerId,
  ) async => rows.values.toList();

  @override
  Future<void> upsertTerminal(CallHistoryEntry entry) async {
    rows.putIfAbsent(entry.callId, () => entry);
  }
}
