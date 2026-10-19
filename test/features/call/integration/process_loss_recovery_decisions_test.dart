import 'dart:async';
import 'dart:io';

import 'package:flutter_app/core/database/app_database_version.dart';
import 'package:flutter_app/core/database/production_migration_registry.dart';
import 'package:flutter_app/features/call/application/call_cleanup_coordinator.dart';
import 'package:flutter_app/features/call/application/call_control_effect_executor.dart';
import 'package:flutter_app/features/call/application/call_coordinator.dart';
import 'package:flutter_app/features/call/application/call_history_projector.dart';
import 'package:flutter_app/features/call/application/call_signaling_context_store.dart';
import 'package:flutter_app/features/call/application/handle_incoming_call_signal.dart';
import 'package:flutter_app/features/call/data/call_history_repository_impl.dart';
import 'package:flutter_app/features/call/domain/call_end_reason.dart';
import 'package:flutter_app/features/call/domain/call_event.dart';
import 'package:flutter_app/features/call/domain/call_id.dart';
import 'package:flutter_app/features/call/domain/call_session_snapshot.dart';
import 'package:flutter_app/features/call/domain/call_signal.dart';
import 'package:flutter_app/features/call/domain/call_state.dart';
import 'package:flutter_app/features/call/infrastructure/android_call_lifecycle_adapter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

final _now = DateTime.utc(2026, 10, 19, 20);
final _oldCall = CallId.parse('11111111-1111-4111-8111-111111111111');
final _nextCall = CallId.parse('22222222-2222-4222-8222-222222222222');
const _handle = '33333333-3333-4333-8333-333333333333';

Future<Database> _openDatabase(String path) {
  sqfliteFfiInit();
  return databaseFactoryFfiNoIsolate.openDatabase(
    path,
    options: OpenDatabaseOptions(
      version: currentIdentityDatabaseVersion,
      singleInstance: false,
      onCreate: runProductionOnCreate,
      onUpgrade: runProductionOnUpgrade,
    ),
  );
}

// The signaling port is the network boundary. It records real signals built
// by CallControlEffectExecutor; it does not decide call state or history.
final class _Wire implements CallControlSignalingPort {
  final sent = <CallSignal>[];
  @override
  Future<OutgoingCallSignalingPreparation> prepareOutgoingInvite(
    CallSessionSnapshot snapshot,
  ) async => const OutgoingCallSignalingPreparation(
    callHandle: _handle,
    remoteAccountPeerId: 'remote-account',
    remoteDevicePeerId: 'remote-device',
  );
  @override
  Future<CallControlSendResult> send({
    required CallSignal signal,
    required String callHandle,
  }) async {
    sent.add(signal);
    return CallControlSendResult(
      directAccepted: true,
      mailboxStored: false,
      mailboxStoreSettled: Future<void>.value(),
      directRoute: CallRouteClass.direct,
    );
  }
}

// Existing coordinator time seam: callbacks are fired at an explicit virtual
// clock instant. No wall-clock sleeps or live application timers.
final class _Timer implements CallTimerHandle {
  _Timer(this.delay, this.fire);
  final Duration delay;
  final Future<void> Function() fire;
  @override
  bool isActive = true;
  @override
  void cancel() => isActive = false;
}

final class _Timers implements CallTimerScheduler {
  final rows = <_Timer>[];
  @override
  CallTimerHandle schedule(Duration delay, Future<void> Function() callback) {
    final timer = _Timer(delay, callback);
    rows.add(timer);
    return timer;
  }
}

final class _Node {
  _Node(Database database, {List<CallCleanupStep> cleanup = const []}) {
    history = CallHistoryRepositoryImpl(database);
    coordinator = CallCoordinator(
      reducer: const CallReducer(),
      cleanupCoordinator: CallCleanupCoordinator(cleanup),
      historyProjector: CallHistoryProjector(history, clock: () => now),
      effectExecutor: CallControlEffectExecutor(
        contextStore: contexts,
        signalingPort: wire,
        clock: () => now,
        idSource: () => CallId.parse(
          '99999999-9999-4999-8999-${(++sequence).toString().padLeft(12, '0')}',
        ),
      ),
      clock: () => now,
      idSource: () => _nextCall,
      timerScheduler: timers,
    );
  }
  DateTime now = _now;
  int sequence = 0;
  final contexts = CallSignalingContextStore();
  final wire = _Wire();
  final timers = _Timers();
  late final CallHistoryRepositoryImpl history;
  late final CallCoordinator coordinator;

  // Authenticated ingress is a precondition, not a native replay's authority.
  // These are the same event/context seams as the existing lifecycle tests.
  Future<void> admitIncoming() async {
    contexts.captureAuthenticated(
      signal: CallSignal.create(
        callId: _oldCall,
        messageId: '44444444-4444-4444-8444-444444444444',
        event: CallSignalType.invite,
        senderAccountPeerId: 'remote-account',
        senderDevicePeerId: 'remote-device',
        recipientAccountPeerId: 'local-account',
        recipientDevicePeerId: 'local-device',
        senderSequence: 1,
        iceGeneration: 0,
        createdAtMs: now.millisecondsSinceEpoch,
        expiresAtMs: now
            .add(const Duration(seconds: 45))
            .millisecondsSinceEpoch,
      ),
      callHandle: _handle,
    );
    await coordinator.dispatch(
      CallEvent(
        type: CallEventType.remoteInvite,
        eventId: 'authenticated-invite',
        occurredAt: now,
        callId: _oldCall,
        contactPeerId: 'remote-account',
        localAccountPeerId: 'local-account',
        localDeviceId: 'local-device',
        remoteAccountPeerId: 'remote-account',
        remoteDeviceId: 'remote-device',
        transportRoute: CallRouteClass.direct,
        expiresAt: now.add(const Duration(seconds: 45)),
      ),
    );
    await event(CallEventType.incomingValidated);
  }

  Future<void> event(CallEventType type) async {
    await coordinator.dispatch(
      CallEvent(
        type: type,
        eventId: 'event-${sequence++}-${type.name}',
        occurredAt: now,
        callId: _oldCall,
        contactPeerId: 'remote-account',
      ),
    );
  }

  Future<void> placeFreshCall() async {
    await coordinator.placeCall(
      contactPeerId: 'remote-account',
      localAccountPeerId: 'local-account',
      localDeviceId: 'local-device',
    );
  }
}

// A retained journal SUPPLIED by the native boundary. This does not implement
// or certify native storage, OS process loss, or physical capture release.
final class _NativeJournal {
  final events = StreamController<Object?>.broadcast(sync: true);
  final calls = <(String, Map<String, Object?>)>[];
  Map<String, Object?> replay = {
    'version': 1,
    'descriptor': {
      'callHandle': _handle,
      'presented': true,
      'phase': 'journal',
      'direction': 'incoming',
      'expiresAtMs': _now
          .add(const Duration(seconds: 45))
          .millisecondsSinceEpoch,
    },
    'nativeCallId': _handle,
    'highestSequence': 8,
    'events': [
      {
        'callHandle': _handle,
        'sequence': 6,
        'eventId': '66666666-6666-4666-8666-666666666666',
        'type': 'presented',
        'occurredAtMs': _now.millisecondsSinceEpoch,
      },
      {
        'callHandle': _handle,
        'sequence': 7,
        'eventId': '77777777-7777-4777-8777-777777777777',
        'type': 'answer',
        'occurredAtMs': _now.millisecondsSinceEpoch,
      },
      {
        'callHandle': _handle,
        'sequence': 8,
        'eventId': '88888888-8888-4888-8888-888888888888',
        'type': 'providerRemoved',
        'occurredAtMs': _now.millisecondsSinceEpoch,
      },
    ],
  };
  Future<Object?> invoke(String method, Map<String, Object?> arguments) async {
    calls.add((method, Map.of(arguments)));
    if (method == 'attach') return replay;
    return true;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('VC-026 Dart recovery decisions; actual process death is device-only', () {
    test(
      'fresh Dart owner reconciles supplied native terminal replay without re-ringing; SQL survives reopen',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'astra-call-history-',
        );
        addTearDown(() => directory.delete(recursive: true));
        final path = '${directory.path}/account.sqlite';
        var db = await _openDatabase(path);
        addTearDown(() async {
          if (db.isOpen) await db.close();
        });
        await db.close();
        db = await _openDatabase(
          path,
        ); // A fresh SQL handle, not an in-memory map.
        final native = _NativeJournal();
        addTearDown(native.events.close);
        late final AndroidCallLifecycleAdapter adapter;
        final node = _Node(
          db,
          cleanup: [
            CallCleanupStep(
              'call_media',
              (_) => adapter.deactivate(),
              requiredForTerminalAck: true,
            ),
          ],
        );
        addTearDown(node.coordinator.dispose);
        adapter = AndroidCallLifecycleAdapter(
          invokeMethod: native.invoke,
          nativeEvents: native.events.stream,
          coordinator: node.coordinator,
          resolveAuthenticatedHandle: (id) => id == _oldCall ? _handle : null,
          clock: () => node.now,
        );
        addTearDown(adapter.close);
        await adapter.start();
        await node.admitIncoming();
        final presentation = IncomingCallPresentation(
          callId: _oldCall,
          callerAccountPeerId: 'remote-account',
          expiresAt: node.now.add(const Duration(seconds: 45)),
        );
        expect(await adapter.present(presentation), isFalse);
        expect(node.coordinator.activeSession, isNull);
        expect(
          node.coordinator.lastSnapshot?.endReason,
          CallEndReason.mediaFailed,
        );
        expect(node.coordinator.terminalCleanupAckReady(_oldCall), isTrue);
        expect(adapter.isBoundTo(_oldCall), isFalse);
        expect(
          native.calls.where((c) => c.$1 == 'presentAuthenticated'),
          isEmpty,
        );
        expect(native.calls.where((c) => c.$1 == 'adopt'), isEmpty);
        expect(native.calls.where((c) => c.$1 == 'activateAudio'), isEmpty);
        expect(native.calls.where((c) => c.$1 == 'acknowledge').single.$2, {
          'version': 1,
          'callHandle': _handle,
          'throughSequence': 8,
          'disposition': 'TERMINAL',
        });
        expect(
          node.wire.sent
              .where((s) => s.event == CallSignalType.terminate)
              .single
              .payload,
          {'reason': 'media_failed'},
        );
        expect(
          (await node.history.getByCallId(_oldCall))?.terminalReason,
          CallEndReason.mediaFailed,
        );
        // A repeated journal cannot replay its answer or create a second row.
        native.events.add(native.replay);
        expect(
          await adapter.reconcileBeforeOutgoing(),
          isTrue,
        ); // Queued-work barrier.
        expect(node.coordinator.activeSession, isNull);
        expect((await node.history.listForContact('remote-account')).length, 1);
        expect(
          node.wire.sent
              .where((s) => s.event == CallSignalType.terminate)
              .length,
          1,
        );
        await adapter.close();
        await node.coordinator.dispose();
        await db.close();
        db = await _openDatabase(path);
        final restarted = _Node(db);
        addTearDown(restarted.coordinator.dispose);
        expect(
          (await restarted.history.getByCallId(_oldCall))?.terminalReason,
          CallEndReason.mediaFailed,
        );
        await restarted.placeFreshCall();
        expect(restarted.coordinator.activeSession?.callId, _nextCall);
        expect(restarted.coordinator.activeSession?.state, CallState.inviting);
      },
    );

    test(
      'surviving peer given media loss ends at its original 15-second deadline and can place a fresh call',
      () async {
        final db = await _openDatabase(inMemoryDatabasePath);
        addTearDown(db.close);
        var nativeReleases = 0;
        final node = _Node(
          db,
          cleanup: [
            CallCleanupStep('call_media', (_) async {
              nativeReleases++;
            }, requiredForTerminalAck: true),
          ],
        );
        addTearDown(node.coordinator.dispose);
        await node.admitIncoming();
        // These are supplied native/negotiation observations, not real audio.
        for (final type in [
          CallEventType.systemUiPresented,
          CallEventType.answer,
          CallEventType.negotiationReady,
          CallEventType.mediaConnected,
        ]) {
          await node.event(type);
        }
        expect(node.coordinator.activeSession?.state, CallState.connected);
        await node.event(CallEventType.mediaLost);
        expect(node.coordinator.activeSession?.state, CallState.reconnecting);
        final deadline = node.timers.rows.singleWhere(
          (t) => t.isActive && t.delay == const Duration(seconds: 15),
        );
        node.now = _now.add(const Duration(seconds: 14));
        expect(node.coordinator.activeSession?.state, CallState.reconnecting);
        expect(await node.history.getByCallId(_oldCall), isNull);
        node.now = _now.add(const Duration(seconds: 15));
        await deadline.fire();
        expect(node.coordinator.activeSession, isNull);
        expect(
          node.coordinator.lastSnapshot?.endReason,
          CallEndReason.reconnectFailed,
        );
        expect(nativeReleases, 1);
        expect(node.coordinator.terminalCleanupAckReady(_oldCall), isTrue);
        expect(
          node.wire.sent
              .where((s) => s.event == CallSignalType.terminate)
              .single
              .payload,
          {'reason': 'reconnect_failed'},
        );
        final row = (await node.history.getByCallId(_oldCall))!;
        expect(row.terminalReason, CallEndReason.reconnectFailed);
        expect(row.endedAt, DateTime.utc(2026, 10, 19, 20, 0, 15));
        await node.placeFreshCall();
        expect(node.coordinator.activeSession?.callId, _nextCall);
        expect(node.coordinator.activeSession?.state, CallState.inviting);
      },
    );
  });
}
